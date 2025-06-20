import Foundation
@preconcurrency import Combine

/// Repository pattern implementation for database operations
/// Provides high-level, type-safe methods for CRUD operations
public actor Repository<T: ORMTable> {
    /// The database connection
    private let database: SQLiteDatabase
    
    /// The model encoder for converting models to database values
    private let encoder = ModelEncoder()
    
    /// The model decoder for converting database values to models
    private let decoder = ModelDecoder()
    
    /// The change notifier for reactive subscriptions
    private let changeNotifier: ChangeNotifier
    
    /// Optional disk storage manager for large data objects
    private let diskStorageManager: DiskStorageManager?
    
    /// Optional relationship manager for lazy loading
    private let relationshipManager: RelationshipManager?
    
    /// Model limit manager for enforcing storage limits
    private let modelLimitManager: ModelLimitManager
    
    /// Initialize a new repository
    /// - Parameters:
    ///   - database: The database connection to use
    ///   - changeNotifier: The change notification system
    ///   - diskStorageManager: Optional disk storage manager for large objects
    ///   - relationshipManager: Optional relationship manager for lazy loading
    ///   - modelLimitManager: Model limit manager for enforcing storage limits
    public init(database: SQLiteDatabase, changeNotifier: ChangeNotifier, diskStorageManager: DiskStorageManager? = nil, relationshipManager: RelationshipManager? = nil, modelLimitManager: ModelLimitManager) {
        self.database = database
        self.changeNotifier = changeNotifier
        self.diskStorageManager = diskStorageManager
        self.relationshipManager = relationshipManager
        self.modelLimitManager = modelLimitManager
    }
    
    /// Find a model by its ID
    /// - Parameter id: The ID to search for
    /// - Returns: Result containing the model or error
    public func find(id: T.IDType) async -> ORMResult<T?> {
        let query = QueryBuilder<T>()
            .where("id", .equal, id as? SQLiteConvertible)
            .limit(1)
        
        let (sql, bindings) = query.buildSelect()
        
        let queryResult = await database.query(sql, bindings: bindings)
        switch queryResult {
        case .success(let rows):
            guard let row = rows.first else {
                return .success(nil)
            }
            
            do {
                var model = try decoder.decode(T.self, from: row)
                try await loadDiskStoredProperties(for: &model, from: row)
                
                // Track access for LRU/MRU strategies
                await modelLimitManager.trackAccess(for: T.self, id: model.id)
                
                return .success(model)
            } catch {
                return .failure(.invalidData(reason: error.localizedDescription))
            }
        case .failure(let error):
            return .failure(error)
        }
    }
    
    /// Find all models matching the query
    /// - Parameter query: The query builder (optional)
    /// - Returns: Result containing array of models or error
    public func findAll(query: QueryBuilder<T>? = nil) async -> ORMResult<[T]> {
        let queryBuilder = query ?? QueryBuilder<T>()
        let (sql, bindings) = queryBuilder.buildSelect()
        
        let queryResult = await database.query(sql, bindings: bindings)
        switch queryResult {
        case .success(let rows):
            do {
                var models: [T] = []
                models.reserveCapacity(rows.count)
                
                for row in rows {
                    var model = try decoder.decode(T.self, from: row)
                    try await loadDiskStoredProperties(for: &model, from: row)
                    
                    // Track access for LRU/MRU strategies
                    await modelLimitManager.trackAccess(for: T.self, id: model.id)
                    
                    models.append(model)
                }
                
                return .success(models)
            } catch {
                return .failure(.invalidData(reason: error.localizedDescription))
            }
        case .failure(let error):
            return .failure(error)
        }
    }
    
    /// Find the first model matching the query
    /// - Parameter query: The query builder
    /// - Returns: Result containing the model or nil
    public func findFirst(query: QueryBuilder<T>) async -> ORMResult<T?> {
        let limitedQuery = query.limit(1)
        
        return await findAll(query: limitedQuery).map { models in
            models.first
        }
    }
    
    /// Count models matching the query
    /// - Parameter query: The query builder (optional)
    /// - Returns: Result containing the count
    public func count(query: QueryBuilder<T>? = nil) async -> ORMResult<Int> {
        let baseQuery = query ?? QueryBuilder<T>()
        let countQuery = baseQuery.select("COUNT(*) as count")
        let (sql, bindings) = countQuery.buildSelect()
        
        return await database.query(sql, bindings: bindings).flatMap { rows in
            guard let row = rows.first,
                  case .integer(let count) = row["count"] else {
                return .failure(.invalidData(reason: "Failed to get count"))
            }
            return .success(Int(count))
        }
    }
    
    /// Insert a new model into the database
    /// - Parameter model: The model to insert
    /// - Returns: Result containing the inserted model with updated ID
    public func insert(_ model: inout T) async -> ORMResult<T> {
        do {
            // Handle disk storage before encoding
            var processedModel = model
            try await processDiskStorageForInsert(&processedModel)
            
            let values = try encoder.encode(processedModel)
            
            // Remove id if it's 0 or default value to use auto-increment
            var insertValues = values
            if let idValue = values["id"],
               case .integer(let id) = idValue,
               id == 0 {
                insertValues.removeValue(forKey: "id")
            }
            
            let sortedKeys = insertValues.keys.sorted()
            let columns = sortedKeys.joined(separator: ", ")
            let placeholders = Array(repeating: "?", count: sortedKeys.count).joined(separator: ", ")
            let sql = "INSERT INTO \(T.tableName) (\(columns)) VALUES (\(placeholders))"
            let bindings = sortedKeys.map { insertValues[$0]! }
            
            let executeResult = await database.execute(sql, bindings: bindings)
            switch executeResult {
            case .success:
                // Update model with the new ID
                let newId = await database.lastInsertRowID
                
                // Convert Int64 to model's ID type
                if let convertedId = T.IDType(String(newId)) {
                    processedModel.id = convertedId
                    model = processedModel
                    
                    // Notify subscribers of the change
                    await changeNotifier.notifyChange(for: T.tableName)
                    
                    // Enforce model limits after successful insertion
                    let limitResult = await modelLimitManager.enforceLimits(for: T.self)
                    if case .failure(let limitError) = limitResult {
                        // Log the error but don't fail the insert operation
                        print("Warning: Failed to enforce model limits for \(T.tableName): \(limitError)")
                    }
                    
                    return .success(processedModel)
                } else {
                    return .failure(.invalidData(reason: "Failed to convert inserted ID"))
                }
            case .failure(let error):
                return .failure(error)
            }
        } catch {
            return .failure(.invalidData(reason: error.localizedDescription))
        }
    }
    
    /// Update an existing model in the database
    /// - Parameter model: The model to update
    /// - Returns: Result indicating success or failure
    public func update(_ model: T) async -> ORMResult<T> {
        do {
            let values = try encoder.encode(model)
            
            // Remove id from update values
            var updateValues = values
            updateValues.removeValue(forKey: "id")
            
            // Convert to SQLiteConvertible dictionary
            var updates: [String: SQLiteConvertible] = [:]
            for (key, value) in updateValues {
                updates[key] = SQLiteValueConvertible(sqliteValue: value)
            }
            
            let query = QueryBuilder<T>().where("id", .equal, model.id as? SQLiteConvertible)
            let (sql, bindings) = query.buildUpdate(updates)
            
            let result = await database.execute(sql, bindings: bindings)
            switch result {
            case .success(let rowsAffected):
                if rowsAffected > 0 {
                    // Notify subscribers of the change
                    await changeNotifier.notifyChange(for: T.tableName)
                }
                return .success(model)
            case .failure(let error):
                return .failure(error)
            }
        } catch {
            return .failure(.invalidData(reason: error.localizedDescription))
        }
    }
    
    /// Save a model (insert if new, update if existing)
    /// - Parameter model: The model to save
    /// - Returns: Result containing the saved model
    public func save(_ model: inout T) async -> ORMResult<T> {
        // Check if model exists
        if let idValue = model.id as? SQLiteConvertible,
           case .integer(let id) = idValue.sqliteValue,
           id > 0 {
            // Try to find existing model
            let findResult = await find(id: model.id)
            switch findResult {
            case .success(let existingModel):
                if existingModel != nil {
                    return await update(model)
                } else {
                    return await insert(&model)
                }
            case .failure:
                return await insert(&model)
            }
        } else {
            return await insert(&model)
        }
    }
    
    /// Delete a model by ID
    /// - Parameter id: The ID of the model to delete
    /// - Returns: Result with number of rows deleted
    public func delete(id: T.IDType) async -> ORMResult<Int> {
        let query = QueryBuilder<T>().where("id", .equal, id as? SQLiteConvertible)
        let (sql, bindings) = query.buildDelete()
        
        let result = await database.execute(sql, bindings: bindings)
        switch result {
        case .success(let rowsAffected):
            if rowsAffected > 0 {
                // Notify subscribers of the change
                await changeNotifier.notifyChange(for: T.tableName)
            }
            return .success(rowsAffected)
        case .failure(let error):
            return .failure(error)
        }
    }
    
    /// Delete models matching the query
    /// - Parameter query: The query builder
    /// - Returns: Result with number of rows deleted
    public func deleteWhere(query: QueryBuilder<T>) async -> ORMResult<Int> {
        let (sql, bindings) = query.buildDelete()
        let result = await database.execute(sql, bindings: bindings)
        switch result {
        case .success(let rowsAffected):
            if rowsAffected > 0 {
                // Notify subscribers of the change
                await changeNotifier.notifyChange(for: T.tableName)
            }
            return .success(rowsAffected)
        case .failure(let error):
            return .failure(error)
        }
    }
    
    /// Delete all models in the table
    /// - Returns: Result with number of rows deleted
    public func deleteAll() async -> ORMResult<Int> {
        let sql = "DELETE FROM \(T.tableName)"
        let result = await database.execute(sql, bindings: [])
        switch result {
        case .success(let rowsAffected):
            if rowsAffected > 0 {
                // Notify subscribers of the change
                await changeNotifier.notifyChange(for: T.tableName)
            }
            return .success(rowsAffected)
        case .failure(let error):
            return .failure(error)
        }
    }
    
    /// Insert or update a model based on its primary key
    /// If a model with the same ID exists, it will be updated; otherwise, it will be inserted
    /// - Parameter model: The model to upsert
    /// - Returns: Result containing the upserted model
    public func upsert(_ model: inout T) async -> ORMResult<T> {
        // Check if model exists
        let findResult = await find(id: model.id)
        switch findResult {
        case .success(let existingModel):
            if existingModel != nil {
                // Model exists, update it
                return await update(model)
            } else {
                // Model doesn't exist, insert it
                return await insert(&model)
            }
        case .failure(let error):
            // If it's a not found error, try to insert
            if case .notFound = error {
                return await insert(&model)
            }
            // For other errors, return the error
            return .failure(error)
        }
    }
    
    /// Execute a raw SQL query
    /// - Parameters:
    ///   - sql: The SQL query
    ///   - bindings: Parameter bindings
    /// - Returns: Result containing array of models
    public func raw(_ sql: String, bindings: [SQLiteConvertible] = []) async -> ORMResult<[T]> {
        let sqliteBindings = bindings.map { $0.sqliteValue }
        
        return await database.query(sql, bindings: sqliteBindings).flatMap { rows in
            do {
                let models = try rows.map { row in
                    try decoder.decode(T.self, from: row)
                }
                return .success(models)
            } catch {
                return .failure(.invalidData(reason: error.localizedDescription))
            }
        }
    }
    
    /// Execute a raw count query
    /// - Parameters:
    ///   - sql: The SQL query (should return a single integer)
    ///   - bindings: Parameter bindings
    /// - Returns: Result containing the count
    public func rawCount(_ sql: String, bindings: [SQLiteConvertible] = []) async -> ORMResult<Int> {
        let sqliteBindings = bindings.map { $0.sqliteValue }
        
        return await database.query(sql, bindings: sqliteBindings).flatMap { rows in
            guard let row = rows.first,
                  let firstValue = row.values.first,
                  case .integer(let count) = firstValue else {
                return .failure(.invalidData(reason: "Failed to get count"))
            }
            return .success(Int(count))
        }
    }
    
    /// Create the table for this model if it doesn't exist
    /// - Returns: Result indicating success or failure
    public func createTable() async -> ORMResult<Void> {
        let schema = SchemaBuilder.createTable(for: T.self)
        return await database.execute(schema).map { _ in () }
    }
    
    /// Drop the table for this model
    /// - Returns: Result indicating success or failure
    public func dropTable() async -> ORMResult<Void> {
        let sql = "DROP TABLE IF EXISTS \(T.tableName)"
        return await database.execute(sql).map { _ in () }
    }
    
    /// Create a QueryBuilder with this repository context for fluent subscription chaining
    /// - Returns: A QueryBuilder that can be used for subscriptions
    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    public func query() -> QueryBuilderWithRepository<T> {
        return QueryBuilderWithRepository(repository: self)
    }
}

// MARK: - Combine Subscriptions
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension Repository {
    
    /// Subscribe to changes for all models in this repository
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Returns: An observable object that provides updated results when data changes
    public nonisolated func subscribe() -> SimpleQuerySubscription<T> {
        return SimpleQuerySubscription(repository: self, query: nil, changeNotifier: changeNotifier)
    }
    
    /// Subscribe to changes for models matching a specific query
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Parameter query: The query builder to filter results
    /// - Returns: An observable object that provides updated query results when data changes
    public nonisolated func subscribe(query: ORMQueryBuilder<T>) -> SimpleQuerySubscription<T> {
        return SimpleQuerySubscription(repository: self, query: query, changeNotifier: changeNotifier)
    }
    
    /// Subscribe to changes for a single model by ID
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Parameter id: The ID of the model to monitor
    /// - Returns: An observable object that provides the updated model when it changes
    public nonisolated func subscribe(id: T.IDType) -> SimpleSingleQuerySubscription<T> {
        let query = ORMQueryBuilder<T>().where("id", .equal, id as? SQLiteConvertible)
        return SimpleSingleQuerySubscription(repository: self, query: query, changeNotifier: changeNotifier)
    }
    
    /// Subscribe to changes for the first model matching a query
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Parameter query: The query builder to find the model
    /// - Returns: An observable object that provides the updated model when it changes
    public nonisolated func subscribeFirst(query: ORMQueryBuilder<T>) -> SimpleSingleQuerySubscription<T> {
        return SimpleSingleQuerySubscription(repository: self, query: query.limit(1), changeNotifier: changeNotifier)
    }
    
    /// Subscribe to the count of models matching a query
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Parameter query: Optional query builder to filter the count
    /// - Returns: An observable object that provides updated count when data changes
    public nonisolated func subscribeCount(query: ORMQueryBuilder<T>? = nil) -> SimpleCountSubscription<T> {
        return SimpleCountSubscription(repository: self, query: query, changeNotifier: changeNotifier)
    }
    
    // MARK: - Alternative Subscription API (Different Return Types)
    
    /// Subscribe to changes for all models in this repository
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Returns: An observable object that provides updated results when data changes
    public nonisolated func subscribeQuery() -> QuerySubscription<T> {
        return QuerySubscription(repository: self, query: nil, changeNotifier: changeNotifier)
    }
    
    /// Subscribe to changes for models matching a specific query
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Parameter query: The query builder to filter results
    /// - Returns: An observable object that provides updated query results when data changes
    public nonisolated func subscribeQuery(query: ORMQueryBuilder<T>) -> QuerySubscription<T> {
        return QuerySubscription(repository: self, query: query, changeNotifier: changeNotifier)
    }
    
    /// Subscribe to changes for a single model by ID
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Parameter id: The ID of the model to monitor
    /// - Returns: An observable object that provides the updated model when it changes
    public nonisolated func subscribeSingle(id: T.IDType) -> SingleQuerySubscription<T> {
        return SingleQuerySubscription(repository: self, id: id, changeNotifier: changeNotifier)
    }
    
    /// Subscribe to changes for the first model matching a query
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Parameter query: The query builder to find the model
    /// - Returns: An observable object that provides the updated model when it changes
    public nonisolated func subscribeSingle(query: ORMQueryBuilder<T>) -> SingleQuerySubscription<T> {
        return SingleQuerySubscription(repository: self, query: query.limit(1), changeNotifier: changeNotifier)
    }
    
    /// Subscribe to the count of models matching a query
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Parameter query: Optional query builder to filter the count
    /// - Returns: An observable object that provides updated count when data changes
    public nonisolated func subscribeCountQuery(query: ORMQueryBuilder<T>? = nil) -> CountSubscription<T> {
        return CountSubscription(repository: self, query: query, changeNotifier: changeNotifier)
    }
    
    // MARK: - Convenient Subscription Methods
    
    /// Subscribe to whether any models exist matching a query
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Parameter query: Optional query builder to filter the existence check
    /// - Returns: A subscription that emits true/false when existence changes
    public nonisolated func subscribeExists(query: ORMQueryBuilder<T>? = nil) -> ExistsSubscription<T> {
        return ExistsSubscription(repository: self, query: query, changeNotifier: changeNotifier)
    }
    
    /// Subscribe to whether a specific model exists by ID
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Parameter id: The ID to check for existence
    /// - Returns: A subscription that emits true/false when the model's existence changes
    public nonisolated func subscribeExists(id: T.IDType) -> ExistsSubscription<T> {
        let query = ORMQueryBuilder<T>().where("id", .equal, id as? SQLiteConvertible)
        return ExistsSubscription(repository: self, query: query, changeNotifier: changeNotifier)
    }
    
    /// Subscribe to the latest (most recently created/updated) model
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Parameter orderBy: Column to order by (defaults to "id" for latest by ID)
    /// - Returns: A subscription that emits the latest model when data changes
    public nonisolated func subscribeLatest(orderBy column: String = "id") -> SingleQuerySubscription<T> {
        let query = ORMQueryBuilder<T>().orderBy(column, ascending: false).limit(1)
        return SingleQuerySubscription(repository: self, query: query, changeNotifier: changeNotifier)
    }
    
    /// Subscribe to the oldest (first created) model
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Parameter orderBy: Column to order by (defaults to "id" for oldest by ID)
    /// - Returns: A subscription that emits the oldest model when data changes
    public nonisolated func subscribeOldest(orderBy column: String = "id") -> SingleQuerySubscription<T> {
        let query = ORMQueryBuilder<T>().orderBy(column, ascending: true).limit(1)
        return SingleQuerySubscription(repository: self, query: query, changeNotifier: changeNotifier)
    }
    
    /// Subscribe to models where a specific column matches a value
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Parameters:
    ///   - column: The column name to filter by
    ///   - value: The value to match
    /// - Returns: A subscription that emits matching models when data changes
    public nonisolated func subscribeWhere(_ column: String, equals value: SQLiteConvertible) -> QuerySubscription<T> {
        let query = ORMQueryBuilder<T>().where(column, .equal, value)
        return QuerySubscription(repository: self, query: query, changeNotifier: changeNotifier)
    }
    
    /// Subscribe to models where a specific column contains a value (LIKE search)
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Parameters:
    ///   - column: The column name to search in
    ///   - pattern: The LIKE pattern to match
    /// - Returns: A subscription that emits matching models when data changes
    public nonisolated func subscribeWhere(_ column: String, contains pattern: String) -> QuerySubscription<T> {
        let query = ORMQueryBuilder<T>().where(column, .like, "%\(pattern)%")
        return QuerySubscription(repository: self, query: query, changeNotifier: changeNotifier)
    }
    
    // MARK: - Relationship-Aware Subscription Methods
    
    /// Subscribe to related models via a foreign key relationship
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Parameters:
    ///   - relatedType: The type of related models to subscribe to
    ///   - foreignKey: The foreign key column name in the related table
    ///   - value: The value to match against the foreign key
    /// - Returns: A subscription that emits related models when data changes
    public nonisolated func subscribeRelated<Related: ORMTable>(
        _ relatedType: Related.Type,
        foreignKey: String,
        value: SQLiteConvertible
    ) -> QuerySubscription<Related> {
        let relatedRepository = Repository<Related>(
            database: database,
            changeNotifier: changeNotifier,
            diskStorageManager: diskStorageManager,
            relationshipManager: relationshipManager,
            modelLimitManager: modelLimitManager
        )
        let query = ORMQueryBuilder<Related>().where(foreignKey, .equal, value)
        return QuerySubscription(repository: relatedRepository, query: query, changeNotifier: changeNotifier)
    }
    
    /// Subscribe to related models for a specific parent model instance
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Parameters:
    ///   - relatedType: The type of related models to subscribe to
    ///   - foreignKey: The foreign key column name in the related table
    ///   - parentId: The parent model's ID
    /// - Returns: A subscription that emits related models when data changes
    public nonisolated func subscribeRelated<Related: ORMTable>(
        _ relatedType: Related.Type,
        foreignKey: String,
        parentId: T.IDType
    ) -> QuerySubscription<Related> {
        return subscribeRelated(relatedType, foreignKey: foreignKey, value: parentId as! SQLiteConvertible)
    }
    
    /// Subscribe to the count of related models
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Parameters:
    ///   - relatedType: The type of related models to count
    ///   - foreignKey: The foreign key column name in the related table
    ///   - parentId: The parent model's ID
    /// - Returns: A subscription that emits the count of related models when data changes
    public nonisolated func subscribeRelatedCount<Related: ORMTable>(
        _ relatedType: Related.Type,
        foreignKey: String,
        parentId: T.IDType
    ) -> CountSubscription<Related> {
        let relatedRepository = Repository<Related>(
            database: database,
            changeNotifier: changeNotifier,
            diskStorageManager: diskStorageManager,
            relationshipManager: relationshipManager,
            modelLimitManager: modelLimitManager
        )
        let query = ORMQueryBuilder<Related>().where(foreignKey, .equal, parentId as! SQLiteConvertible)
        return CountSubscription(repository: relatedRepository, query: query, changeNotifier: changeNotifier)
    }
}

/// Helper struct to wrap SQLiteValue for SQLiteConvertible conformance
private struct SQLiteValueConvertible: SQLiteConvertible {
    let value: SQLiteValue
    
    init?(sqliteValue: SQLiteValue) {
        self.value = sqliteValue
    }
    
    var sqliteValue: SQLiteValue {
        value
    }
}

// MARK: - Disk Storage Support
extension Repository {
    
    /// Process disk storage for model insertion
    private func processDiskStorageForInsert(_ model: inout T) async throws {
        // For now, skip disk storage processing as it requires more integration
        // This feature will be fully implemented in a future update
        return
    }
    
    /// Load disk-stored properties for a model
    private func loadDiskStoredProperties(for model: inout T, from row: [String: SQLiteValue]) async throws {
        // For now, skip disk storage loading as it requires more integration
        // This feature will be fully implemented in a future update
        return
    }
}

// MARK: - Relationship Methods

extension Repository {
    /// Load a belongs-to relationship for a model
    /// - Parameters:
    ///   - model: The model instance
    ///   - config: The relationship configuration
    /// - Returns: Result containing the related model or error
    public func loadBelongsTo<Related: ORMTable>(
        for model: T,
        config: BelongsToConfig<Related>
    ) async -> ORMResult<Related?> {
        guard let manager = relationshipManager else {
            return .failure(.notFound(entity: "RelationshipManager", id: ""))
        }
        
        return await manager.loadBelongsTo(for: model, config: config)
    }
    
    /// Load a has-many relationship for a model
    /// - Parameters:
    ///   - model: The model instance
    ///   - config: The relationship configuration
    /// - Returns: Result containing the related models or error
    public func loadHasMany<Related: ORMTable>(
        for model: T,
        config: HasManyConfig<Related>
    ) async -> ORMResult<[Related]> {
        guard let manager = relationshipManager else {
            return .failure(.notFound(entity: "RelationshipManager", id: ""))
        }
        
        return await manager.loadHasMany(for: model, config: config)
    }
    
    /// Load a has-one relationship for a model
    /// - Parameters:
    ///   - model: The model instance
    ///   - config: The relationship configuration
    /// - Returns: Result containing the related model or error
    public func loadHasOne<Related: ORMTable>(
        for model: T,
        config: HasOneConfig<Related>
    ) async -> ORMResult<Related?> {
        guard let manager = relationshipManager else {
            return .failure(.notFound(entity: "RelationshipManager", id: ""))
        }
        
        return await manager.loadHasOne(for: model, config: config)
    }
    
    /// Load a many-to-many relationship for a model
    /// - Parameters:
    ///   - model: The model instance
    ///   - config: The relationship configuration
    /// - Returns: Result containing the related models or error
    public func loadManyToMany<Related: ORMTable>(
        for model: T,
        config: ManyToManyConfig<Related>
    ) async -> ORMResult<[Related]> {
        guard let manager = relationshipManager else {
            return .failure(.notFound(entity: "RelationshipManager", id: ""))
        }
        
        return await manager.loadManyToMany(for: model, config: config)
    }
    
    /// Find related models using a foreign key
    /// - Parameters:
    ///   - relatedType: The type of related models to find
    ///   - foreignKey: The foreign key column name
    ///   - value: The value to match
    /// - Returns: Result containing the related models or error
    public func findRelated<Related: ORMTable>(
        _ relatedType: Related.Type,
        foreignKey: String,
        value: T.IDType
    ) async -> ORMResult<[Related]> {
        let relatedRepository = Repository<Related>(
            database: database,
            changeNotifier: changeNotifier,
            diskStorageManager: diskStorageManager,
            relationshipManager: relationshipManager,
            modelLimitManager: modelLimitManager
        )
        
        let query = QueryBuilder<Related>()
            .where(foreignKey, .equal, value as? SQLiteConvertible)
        
        return await relatedRepository.findAll(query: query)
    }
    
    /// Find a single related model using a foreign key
    /// - Parameters:
    ///   - relatedType: The type of related model to find
    ///   - foreignKey: The foreign key column name
    ///   - value: The value to match
    /// - Returns: Result containing the related model or error
    public func findRelatedSingle<Related: ORMTable>(
        _ relatedType: Related.Type,
        foreignKey: String,
        value: T.IDType
    ) async -> ORMResult<Related?> {
        let relatedRepository = Repository<Related>(
            database: database,
            changeNotifier: changeNotifier,
            diskStorageManager: diskStorageManager,
            relationshipManager: relationshipManager,
            modelLimitManager: modelLimitManager
        )
        
        let query = QueryBuilder<Related>()
            .where(foreignKey, .equal, value as? SQLiteConvertible)
            .limit(1)
        
        let result = await relatedRepository.findAll(query: query)
        return result.map { $0.first }
    }
}

// MARK: - Model Limit Management

extension Repository {
    
    /// Configure model limit for this repository's model type
    /// - Parameter limit: The model limit configuration
    public func setModelLimit(_ limit: ModelLimit) async {
        await modelLimitManager.setModelLimit(for: T.self, limit: limit)
    }
    
    /// Get current model limit configuration for this repository's model type
    /// - Returns: Model limit configuration or nil if not set
    public func getModelLimit() async -> ModelLimit? {
        return await modelLimitManager.getModelLimit(for: T.self)
    }
    
    /// Remove model limit configuration for this repository's model type
    public func removeModelLimit() async {
        await modelLimitManager.removeModelLimit(for: T.self)
    }
    
    /// Manually enforce model limits for this repository's model type
    /// - Parameters:
    ///   - reason: The reason for enforcement (default: manualEnforcement)
    /// - Returns: Result indicating success or failure
    public func enforceLimits(reason: ModelRemovalReason = .manualEnforcement) async -> ORMResult<Void> {
        return await modelLimitManager.manuallyEnforceLimits(for: T.self, reason: reason)
    }
    
    /// Get statistics about model limits for this repository's model type
    /// - Returns: Model limit statistics or nil if no limit is configured
    public func getModelLimitStatistics() async -> ModelLimitStatistics? {
        let allStats = await modelLimitManager.getStatistics()
        return allStats[T.tableName]
    }
    
    /// Set removal callback for this repository's model type
    /// - Parameter callback: Callback to execute when models are removed due to limits
    public func setModelRemovalCallback(_ callback: ModelRemovalCallback?) async {
        await modelLimitManager.setRemovalCallback(for: T.self, callback: callback)
    }
}

