import Foundation

/// Main ORM manager that provides access to all database operations
/// Uses actor pattern for thread-safe concurrent access
public actor ORM {
    /// The database connection
    private let database: SQLiteDatabase
    
    /// Migration manager
    public let migrations: MigrationManager
    
    /// Repository cache
    private var repositories: [String: Any] = [:]
    
    /// Initialize ORM with database path
    /// - Parameters:
    ///   - path: Path to database file (use ":memory:" for in-memory database)
    ///   - configuration: Database configuration
    public init(path: String, configuration: DatabaseConfiguration = .default) {
        self.database = SQLiteDatabase(path: path, configuration: configuration)
        self.migrations = MigrationManager(database: database)
    }
    
    /// Open database connection
    /// - Returns: Result indicating success or failure
    public func open() async -> ORMResult<Void> {
        await database.open()
    }
    
    /// Close database connection
    /// - Returns: Result indicating success or failure
    public func close() async -> ORMResult<Void> {
        await database.close()
    }
    
    /// Get or create a repository for the specified model type
    /// - Parameter type: The model type
    /// - Returns: Repository instance for the model
    public func repository<T: Model>(for type: T.Type) -> Repository<T> {
        let key = String(describing: type)
        
        if let cached = repositories[key] as? Repository<T> {
            return cached
        }
        
        let repository = Repository<T>(database: database)
        repositories[key] = repository
        return repository
    }
    
    /// Execute a transaction
    /// - Parameter block: The transaction block
    /// - Returns: Result of the transaction
    public func transaction<T: Sendable>(_ block: @Sendable () async throws -> ORMResult<T>) async -> ORMResult<T> {
        await database.transaction(block)
    }
    
    /// Execute raw SQL that doesn't return results
    /// - Parameters:
    ///   - sql: SQL statement to execute
    ///   - bindings: Parameter bindings
    /// - Returns: Result with number of affected rows
    public func execute(_ sql: String, bindings: [SQLiteConvertible] = []) async -> ORMResult<Int> {
        await database.execute(sql, bindings: bindings.map { $0.sqliteValue })
    }
    
    /// Execute raw SQL query that returns results
    /// - Parameters:
    ///   - sql: SQL query to execute
    ///   - bindings: Parameter bindings
    /// - Returns: Result with array of row dictionaries
    public func query(_ sql: String, bindings: [SQLiteConvertible] = []) async -> ORMResult<[[String: SQLiteValue]]> {
        await database.query(sql, bindings: bindings.map { $0.sqliteValue })
    }
    
    /// Create all tables for registered models
    /// - Parameter models: Array of model types to create tables for
    /// - Returns: Result indicating success or failure
    public func createTables(for models: [any Model.Type]) async -> ORMResult<Void> {
        for modelType in models {
            let result = await createTable(for: modelType)
            if case .failure(let error) = result {
                return .failure(error)
            }
        }
        return .success(())
    }
    
    /// Create table for a specific model type
    /// - Parameter type: The model type
    /// - Returns: Result indicating success or failure
    private func createTable(for type: any Model.Type) async -> ORMResult<Void> {
        // Create table
        let createTableSQL = SchemaBuilder.createTable(for: type)
        let tableResult = await database.execute(createTableSQL)
        
        guard case .success = tableResult else {
            return tableResult.map { _ in () }
        }
        
        // Create indexes
        let indexStatements = SchemaBuilder.createIndexes(for: type)
        for indexSQL in indexStatements {
            let indexResult = await database.execute(indexSQL)
            if case .failure(let error) = indexResult {
                return .failure(error)
            }
        }
        
        return .success(())
    }
}

/// Global convenience functions for common operations

/// Create a new ORM instance with in-memory database
/// - Returns: Configured ORM instance
public func createInMemoryORM() -> ORM {
    ORM(path: ":memory:")
}

/// Create a new ORM instance with file-based database
/// - Parameters:
///   - filename: Database filename
///   - directory: Directory path (defaults to documents directory)
/// - Returns: Configured ORM instance
public func createFileORM(filename: String, directory: URL? = nil) -> ORM {
    let dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let path = dir.appendingPathComponent(filename).path
    return ORM(path: path)
}