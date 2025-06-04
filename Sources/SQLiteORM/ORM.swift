import Foundation
@preconcurrency import Combine

/// Database path configuration enum for easy ORM initialization
public enum DatabasePath {
    /// Relative path to documents directory
    case relative(String)
    /// In-memory database
    case memory
    /// Default database in documents directory with name "app.sqlite"
    case `default`
    
    /// Returns the resolved absolute path for the database
    var resolvedPath: String {
        switch self {
        case .relative(let name):
            let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, 
                                                                   .userDomainMask, 
                                                                   true).first!
            let filename = name.hasSuffix(".sqlite") ? name : "\(name).sqlite"
            return "\(documentsPath)/\(filename)"
        case .memory:
            return ":memory:"
        case .default:
            let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, 
                                                                   .userDomainMask, 
                                                                   true).first!
            return "\(documentsPath)/app.sqlite"
        }
    }
}

/// Main ORM manager that provides access to all database operations
/// Uses actor pattern for thread-safe concurrent access
public actor ORM {
    /// The database connection
    private let database: SQLiteDatabase
    
    /// Migration manager
    public let migrations: MigrationManager
    
    /// Repository cache
    private var repositories: [String: Any] = [:]
    
    /// Change notifier for reactive subscriptions
    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    public let changeNotifier = ChangeNotifier()
    
    /// Disk storage manager for large data objects
    public nonisolated let diskStorageManager: DiskStorageManager?
    
    /// Relationship manager for lazy loading
    private var relationshipManager: RelationshipManager?
    
    /// Initialize ORM with default database name in documents directory
    /// - Parameters:
    ///   - configuration: Database configuration
    ///   - enableDiskStorage: Whether to enable disk storage for large objects
    public init(configuration: DatabaseConfiguration = .default, enableDiskStorage: Bool = true) {
        let resolvedPath = DatabasePath.default.resolvedPath
        self.database = SQLiteDatabase(path: resolvedPath, configuration: configuration)
        self.migrations = MigrationManager(database: database)
        
        // Initialize disk storage if enabled and not using in-memory database
        if enableDiskStorage && resolvedPath != ":memory:" {
            do {
                self.diskStorageManager = try DiskStorageManager(databasePath: resolvedPath)
            } catch {
                self.diskStorageManager = nil
            }
        } else {
            self.diskStorageManager = nil
        }
        
        // Relationship manager will be initialized on first use
        self.relationshipManager = nil
    }
    
    /// Initialize ORM with database path configuration
    /// - Parameters:
    ///   - databasePath: Database path configuration
    ///   - configuration: Database configuration
    ///   - enableDiskStorage: Whether to enable disk storage for large objects
    public init(_ databasePath: DatabasePath, configuration: DatabaseConfiguration = .default, enableDiskStorage: Bool = true) {
        let resolvedPath = databasePath.resolvedPath
        self.database = SQLiteDatabase(path: resolvedPath, configuration: configuration)
        self.migrations = MigrationManager(database: database)
        
        // Initialize disk storage if enabled and not using in-memory database
        if enableDiskStorage && resolvedPath != ":memory:" {
            do {
                self.diskStorageManager = try DiskStorageManager(databasePath: resolvedPath)
            } catch {
                self.diskStorageManager = nil
            }
        } else {
            self.diskStorageManager = nil
        }
        
        // Relationship manager will be initialized on first use
        self.relationshipManager = nil
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
    
    /// Get the relationship manager, creating it if needed
    private func getRelationshipManager() -> RelationshipManager {
        if let manager = relationshipManager {
            return manager
        }
        
        let manager = RelationshipManager(orm: self)
        relationshipManager = manager
        return manager
    }
    
    /// Get or create a repository for the specified model type
    /// - Parameter type: The model type
    /// - Returns: Repository instance for the model
    public func repository<T: ORMTable>(for type: T.Type) -> Repository<T> {
        let key = String(describing: type)
        
        if let cached = repositories[key] as? Repository<T> {
            return cached
        }
        
        let relManager = getRelationshipManager()
        let repository: Repository<T>
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            repository = Repository<T>(database: database, changeNotifier: changeNotifier, diskStorageManager: diskStorageManager, relationshipManager: relManager)
        } else {
            // For older platforms, create a dummy change notifier
            repository = Repository<T>(database: database, changeNotifier: ChangeNotifier(), diskStorageManager: diskStorageManager, relationshipManager: relManager)
        }
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
    public func createTables(for models: [any ORMTable.Type]) async -> ORMResult<Void> {
        for modelType in models {
            let result = await createTable(for: modelType)
            if case .failure(let error) = result {
                return .failure(error)
            }
        }
        return .success(())
    }
    
    /// Create tables for multiple model types (variadic convenience method)
    /// - Parameter models: Variable number of model types to create tables for
    /// - Returns: Result indicating success or failure
    /// 
    /// Example usage:
    /// ```swift
    /// await orm.createTables(User.self, Post.self, Comment.self)
    /// ```
    public func createTables(_ models: any ORMTable.Type...) async -> ORMResult<Void> {
        return await createTables(for: models)
    }
    
    /// Open database and create tables in one step (array version)
    /// - Parameter models: Array of model types to create tables for
    /// - Returns: Result indicating success or failure
    public func openAndCreateTables(for models: [any ORMTable.Type]) async -> ORMResult<Void> {
        let openResult = await open()
        guard case .success = openResult else {
            return openResult
        }
        
        return await createTables(for: models)
    }
    
    /// Open database and create tables in one step (variadic convenience method)
    /// - Parameter models: Variable number of model types to create tables for
    /// - Returns: Result indicating success or failure
    /// 
    /// Example usage:
    /// ```swift
    /// await orm.openAndCreateTables(User.self, Post.self, Comment.self)
    /// ```
    public func openAndCreateTables(_ models: any ORMTable.Type...) async -> ORMResult<Void> {
        return await openAndCreateTables(for: models)
    }
    
    /// Create table for a specific model type
    /// - Parameter type: The model type
    /// - Returns: Result indicating success or failure
    private func createTable(for type: any ORMTable.Type) async -> ORMResult<Void> {
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
    ORM(.memory)
}

/// Create a new ORM instance with file-based database using new enum system
/// - Parameters:
///   - filename: Database filename (will auto-add .sqlite extension if needed)
///   - enableDiskStorage: Whether to enable disk storage for large objects
/// - Returns: Configured ORM instance
public func createFileORM(filename: String, enableDiskStorage: Bool = true) -> ORM {
    ORM(.relative(filename), enableDiskStorage: enableDiskStorage)
}


/// Create a new ORM instance and set up tables in one step (in-memory)
/// - Parameter models: Variable number of model types to create tables for
/// - Returns: Configured and ready-to-use ORM instance
/// 
/// Example usage:
/// ```swift
/// let orm = await createInMemoryORMWithTables(User.self, Post.self)
/// ```
public func createInMemoryORMWithTables(_ models: any ORMTable.Type...) async -> ORMResult<ORM> {
    let orm = createInMemoryORM()
    let result = await orm.openAndCreateTables(for: models)
    
    switch result {
    case .success:
        return .success(orm)
    case .failure(let error):
        return .failure(error)
    }
}

/// Create a new ORM instance and set up tables in one step (file-based)
/// - Parameters:
///   - filename: Database filename (will auto-add .sqlite extension if needed)
///   - enableDiskStorage: Whether to enable disk storage for large objects
///   - models: Variable number of model types to create tables for
/// - Returns: Configured and ready-to-use ORM instance
/// 
/// Example usage:
/// ```swift
/// let orm = await createFileORMWithTables("myapp", User.self, Post.self)
/// ```
public func createFileORMWithTables(_ filename: String, enableDiskStorage: Bool = true, _ models: any ORMTable.Type...) async -> ORMResult<ORM> {
    let orm = createFileORM(filename: filename, enableDiskStorage: enableDiskStorage)
    let result = await orm.openAndCreateTables(for: models)
    
    switch result {
    case .success:
        return .success(orm)
    case .failure(let error):
        return .failure(error)
    }
}