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
    
    /// Initialize a new repository
    /// - Parameters:
    ///   - database: The database connection to use
    ///   - changeNotifier: The change notification system
    ///   - diskStorageManager: Optional disk storage manager for large objects
    ///   - relationshipManager: Optional relationship manager for lazy loading
    public init(database: SQLiteDatabase, changeNotifier: ChangeNotifier, diskStorageManager: DiskStorageManager? = nil, relationshipManager: RelationshipManager? = nil) {
        self.database = database
        self.changeNotifier = changeNotifier
        self.diskStorageManager = diskStorageManager
        self.relationshipManager = relationshipManager
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
            relationshipManager: relationshipManager
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
            relationshipManager: relationshipManager
        )
        
        let query = QueryBuilder<Related>()
            .where(foreignKey, .equal, value as? SQLiteConvertible)
            .limit(1)
        
        let result = await relatedRepository.findAll(query: query)
        return result.map { $0.first }
    }
}

