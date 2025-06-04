import Foundation

/// Repository pattern implementation for database operations
/// Provides high-level, type-safe methods for CRUD operations
public actor Repository<T: Model> {
    /// The database connection
    private let database: SQLiteDatabase
    
    /// The model encoder for converting models to database values
    private let encoder = ModelEncoder()
    
    /// The model decoder for converting database values to models
    private let decoder = ModelDecoder()
    
    /// Initialize a new repository
    /// - Parameter database: The database connection to use
    public init(database: SQLiteDatabase) {
        self.database = database
    }
    
    /// Find a model by its ID
    /// - Parameter id: The ID to search for
    /// - Returns: Result containing the model or error
    public func find(id: T.IDType) async -> ORMResult<T?> {
        let query = QueryBuilder<T>()
            .where("id", .equal, id as? SQLiteConvertible)
            .limit(1)
        
        let (sql, bindings) = query.buildSelect()
        
        return await database.query(sql, bindings: bindings).flatMap { rows in
            guard let row = rows.first else {
                return .success(nil)
            }
            
            do {
                let model = try decoder.decode(T.self, from: row)
                return .success(model)
            } catch {
                return .failure(.invalidData(reason: error.localizedDescription))
            }
        }
    }
    
    /// Find all models matching the query
    /// - Parameter query: The query builder (optional)
    /// - Returns: Result containing array of models or error
    public func findAll(query: QueryBuilder<T>? = nil) async -> ORMResult<[T]> {
        let queryBuilder = query ?? QueryBuilder<T>()
        let (sql, bindings) = queryBuilder.buildSelect()
        
        return await database.query(sql, bindings: bindings).flatMap { rows in
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
            let values = try encoder.encode(model)
            
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
                    model.id = convertedId
                    return .success(model)
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
            
            return await database.execute(sql, bindings: bindings).map { rowsAffected in
                if rowsAffected == 0 {
                    return model  // No rows updated, but not an error
                }
                return model
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
        
        return await database.execute(sql, bindings: bindings)
    }
    
    /// Delete models matching the query
    /// - Parameter query: The query builder
    /// - Returns: Result with number of rows deleted
    public func deleteWhere(query: QueryBuilder<T>) async -> ORMResult<Int> {
        let (sql, bindings) = query.buildDelete()
        return await database.execute(sql, bindings: bindings)
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