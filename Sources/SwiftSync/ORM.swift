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
    /// Test database in package directory's hidden .test-data folder
    case test(String)
    
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
        case .test(let name):
            // Find the package root by looking for Package.swift
            let currentPath = FileManager.default.currentDirectoryPath
            var packageRoot = currentPath
            
            // Traverse up to find Package.swift
            while !FileManager.default.fileExists(atPath: "\(packageRoot)/Package.swift") {
                let parentPath = URL(fileURLWithPath: packageRoot).deletingLastPathComponent().path
                if parentPath == packageRoot {
                    // Reached filesystem root without finding Package.swift, fallback to current directory
                    packageRoot = currentPath
                    break
                }
                packageRoot = parentPath
            }
            
            let testDataDir = "\(packageRoot)/.test-data"
            
            // Create test data directory if it doesn't exist
            try? FileManager.default.createDirectory(atPath: testDataDir, withIntermediateDirectories: true)
            
            let filename = name.hasSuffix(".sqlite") ? name : "\(name).sqlite"
            return "\(testDataDir)/\(filename)"
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
    
    /// Model limit manager for enforcing storage limits
    public let modelLimitManager: ModelLimitManager
    
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
        
        // Initialize model limit manager
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            self.modelLimitManager = ModelLimitManager(database: database, diskStorageManager: diskStorageManager, changeNotifier: changeNotifier)
        } else {
            self.modelLimitManager = ModelLimitManager(database: database, diskStorageManager: diskStorageManager, changeNotifier: nil)
        }
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
        
        // Initialize model limit manager
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            self.modelLimitManager = ModelLimitManager(database: database, diskStorageManager: diskStorageManager, changeNotifier: changeNotifier)
        } else {
            self.modelLimitManager = ModelLimitManager(database: database, diskStorageManager: diskStorageManager, changeNotifier: nil)
        }
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
            repository = Repository<T>(database: database, changeNotifier: changeNotifier, diskStorageManager: diskStorageManager, relationshipManager: relManager, modelLimitManager: modelLimitManager)
        } else {
            // For older platforms, create a dummy change notifier
            repository = Repository<T>(database: database, changeNotifier: ChangeNotifier(), diskStorageManager: diskStorageManager, relationshipManager: relManager, modelLimitManager: modelLimitManager)
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
    
    // MARK: - Multi-Model Soft Sync
    
    /// Results from multi-model soft sync operation
    public struct MultiModelSyncResults: Sendable {
        public let modelResults: [String: ModelSyncResult]
        
        public init(modelResults: [String: ModelSyncResult]) {
            self.modelResults = modelResults
        }
    }
    
    /// Result for a single model type sync
    public struct ModelSyncResult: Sendable {
        public let insertedCount: Int
        public let updatedCount: Int
        public let removedCount: Int
        public let conflictsCount: Int
        public let totalChanges: Int
        
        public init(insertedCount: Int, updatedCount: Int, removedCount: Int, conflictsCount: Int) {
            self.insertedCount = insertedCount
            self.updatedCount = updatedCount
            self.removedCount = removedCount
            self.conflictsCount = conflictsCount
            self.totalChanges = insertedCount + updatedCount
        }
    }
    
    /// Soft sync multiple model types from a Codable container
    /// Note: This is a placeholder implementation to demonstrate the API design.
    /// For now, use individual model softSync calls for each model type.
    /// - Parameters:
    ///   - container: Codable object containing nested model arrays
    ///   - modelTypes: Array of model types to sync (must match container properties)
    ///   - conflictResolution: How to handle conflicts (default: .serverWins)
    /// - Returns: Dictionary mapping model type names to their sync changes
    public func softSync<Container: Codable>(
        from container: Container,
        modelTypes: [any ORMTable.Type],
        conflictResolution: ConflictResolution = .serverWins
    ) async -> Result<MultiModelSyncResults, Error> {
        
        var results: [String: ModelSyncResult] = [:]
        let mirror = Mirror(reflecting: container)
        
        // Process each requested model type
        for modelType in modelTypes {
            let typeName = String(describing: modelType)
            
            do {
                // Find and sync the model type from the container
                let syncResult = try await findAndSyncModelType(
                    mirror: mirror,
                    modelType: modelType,
                    conflictResolution: conflictResolution
                )
                results[typeName] = syncResult
            } catch {
                // If sync fails for a model type, record empty result
                results[typeName] = ModelSyncResult(
                    insertedCount: 0,
                    updatedCount: 0,
                    removedCount: 0,
                    conflictsCount: 0
                )
            }
        }
        
        return .success(MultiModelSyncResults(modelResults: results))
    }
    
    /// Find and sync a specific model type from the container
    private func findAndSyncModelType(
        mirror: Mirror,
        modelType: any ORMTable.Type,
        conflictResolution: ConflictResolution
    ) async throws -> ModelSyncResult {
        
        // Try to find a property that contains this model type
        for child in mirror.children {
            guard child.label != nil else { continue }
            
            let value = child.value
            
            // Check if this property contains an array of the target model type
            if await isArrayOfModelType(value, modelType: modelType) {
                // Found matching property, extract data and sync
                return try await syncModelsFromValue(value, modelType: modelType, conflictResolution: conflictResolution)
            }
            
            // Check if this property contains a single instance of the target model type
            if await isSingleInstanceOfModelType(value, modelType: modelType) {
                // Found single instance, wrap in array and sync
                return try await syncModelsFromValue([value], modelType: modelType, conflictResolution: conflictResolution)
            }
        }
        
        // If we didn't find the model type, return empty result
        return ModelSyncResult(insertedCount: 0, updatedCount: 0, removedCount: 0, conflictsCount: 0)
    }
    
    /// Check if a value is an array of the specified model type
    private func isArrayOfModelType(_ value: Any, modelType: any ORMTable.Type) async -> Bool {
        let mirror = Mirror(reflecting: value)
        
        // Check if this is an array
        guard mirror.displayStyle == .collection else { return false }
        
        // For empty arrays, check the type name
        if mirror.children.isEmpty {
            let typeName = String(describing: type(of: value))
            let modelTypeName = String(describing: modelType)
            return typeName.contains(modelTypeName)
        }
        
        // Get the first element to check the type
        for child in mirror.children {
            let childType = type(of: child.value)
            return String(describing: childType) == String(describing: modelType)
        }
        
        return false
    }
    
    /// Check if a value is a single instance of the specified model type
    private func isSingleInstanceOfModelType(_ value: Any, modelType: any ORMTable.Type) async -> Bool {
        let valueType = type(of: value)
        let modelTypeName = String(describing: modelType)
        let valueTypeName = String(describing: valueType)
        return valueTypeName == modelTypeName
    }
    
    /// Sync models from extracted value using type erasure
    private func syncModelsFromValue(
        _ value: Any,
        modelType: any ORMTable.Type,
        conflictResolution: ConflictResolution
    ) async throws -> ModelSyncResult {
        
        // Use type erasure to dispatch to the correct softSync method
        // This is done through protocol conformance and runtime dispatch
        
        // Convert value to the expected array type for the model
        guard let models = extractModelsFromValue(value, modelType: modelType) else {
            throw SyncError.invalidDataType
        }
        
        // Here we need to use dynamic dispatch to call the correct softSync method
        // Since we can't use generics at runtime, we'll use a protocol-based approach
        return try await performTypedSoftSync(models: models, modelType: modelType, conflictResolution: conflictResolution)
    }
    
    /// Extract models from Any value - convert to proper array type
    private func extractModelsFromValue(_ value: Any, modelType: any ORMTable.Type) -> [any ORMTable]? {
        
        // Handle array case
        if let array = value as? [any ORMTable] {
            return array
        }
        
        // Handle single item case
        if let single = value as? any ORMTable {
            return [single]
        }
        
        // Try to extract using reflection
        let mirror = Mirror(reflecting: value)
        
        if mirror.displayStyle == .collection {
            var extractedModels: [any ORMTable] = []
            
            for child in mirror.children {
                if let model = child.value as? any ORMTable {
                    extractedModels.append(model)
                }
            }
            
            return extractedModels.isEmpty ? nil : extractedModels
        }
        
        return nil
    }
    
    /// Perform typed soft sync using protocol dispatch
    private func performTypedSoftSync(
        models: [any ORMTable],
        modelType: any ORMTable.Type,
        conflictResolution: ConflictResolution
    ) async throws -> ModelSyncResult {
        
        // Use direct database queries since we can't use generic repositories at runtime
        let tableName = modelType.tableName
        
        // Get existing local data using raw SQL
        let sql = "SELECT * FROM \(tableName)"
        let result = await database.query(sql, bindings: [])
        
        guard case .success(let rows) = result else {
            throw SyncError.localDataError
        }
        
        // Perform manual soft sync logic
        var insertedCount = 0
        var updatedCount = 0  
        var conflictsCount = 0
        
        // Create ID lookup for local data based on raw rows
        var localIDSet: Set<String> = []
        var dirtyLocalIDs: Set<String> = []
        
        for row in rows {
            if let id = row["id"] {
                let idString = String(describing: id)
                localIDSet.insert(idString)
                
                // Check if local model is dirty
                if let isDirty = row["isDirty"] as? Int, isDirty == 1 {
                    dirtyLocalIDs.insert(idString)
                }
            }
        }
        
        // Process each server model
        for serverModel in models {
            let serverIDString = String(describing: serverModel.id)
            
            if localIDSet.contains(serverIDString) {
                // Model exists locally - check for conflicts
                if dirtyLocalIDs.contains(serverIDString) {
                    // Has conflict
                    switch conflictResolution {
                    case .localWins:
                        // Keep local version, no update needed
                        break
                    default:
                        // Server wins or other resolution
                        conflictsCount += 1
                        updatedCount += 1
                    }
                } else {
                    // No conflict, can update
                    updatedCount += 1
                }
            } else {
                // New model from server
                insertedCount += 1
            }
        }
        
        return ModelSyncResult(
            insertedCount: insertedCount,
            updatedCount: updatedCount,
            removedCount: 0, // Soft sync never removes
            conflictsCount: conflictsCount
        )
    }
    
    /// Perform type-erased soft sync using runtime dispatch
    private func performTypeErasedSoftSync(
        value: Any,
        modelType: any ORMTable.Type,
        conflictResolution: ConflictResolution
    ) async -> Result<Any, Error> {
        
        // This is where we handle the type erasure challenge
        // We'll use a protocol-based approach with runtime dispatch
        switch modelType {
        default:
            // For now, we'll use reflection to extract the models and perform a manual sync
            // This is a fallback that works with any ORMTable type
            return await performReflectionBasedSync(value: value, modelType: modelType, conflictResolution: conflictResolution)
        }
    }
    
    /// Perform sync using reflection (fallback method)
    private func performReflectionBasedSync(
        value: Any,
        modelType: any ORMTable.Type,
        conflictResolution: ConflictResolution
    ) async -> Result<Any, Error> {
        
        // Extract array elements using reflection
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .collection else {
            return .failure(ORMError.invalidOperation(reason: "Value is not a collection"))
        }
        
        var models: [any ORMTable] = []
        for child in mirror.children {
            if let model = child.value as? any ORMTable {
                models.append(model)
            }
        }
        
        if models.isEmpty {
            // Return empty sync changes
            return .success(createEmptySyncChanges())
        }
        
        // Perform the sync operation through the repository
        // This requires type-specific handling, so we'll create a basic result
        return await performGenericSync(models: models, modelType: modelType, conflictResolution: conflictResolution)
    }
    
    /// Create empty sync changes for any model type
    private func createEmptySyncChanges() -> [String: Any] {
        return [
            "inserted": Array<[String: Any]>(),
            "updated": Array<[String: Any]>(),
            "removed": Array<[String: Any]>(),
            "conflicts": 0,
            "totalChanges": 0
        ]
    }
    
    /// Perform generic sync using manual database operations
    private func performGenericSync(
        models: [any ORMTable],
        modelType: any ORMTable.Type,
        conflictResolution: ConflictResolution
    ) async -> Result<Any, Error> {
        
        // For now, we'll return a placeholder since full type-erased sync is complex
        // In a real implementation, this would manually construct SQL and perform the sync
        _ = modelType.tableName  // Acknowledge we have the table name for future use
        
        var insertedCount = 0
        let updatedCount = 0
        let conflictsCount = 0
        
        for _ in models {
            // This is a simplified version - in reality we'd need to:
            // 1. Check if the model exists locally
            // 2. Handle conflicts based on the resolution strategy
            // 3. Perform insert or update
            
            // For now, we'll just count them as insertions
            insertedCount += 1
        }
        
        let result: [String: Any] = [
            "inserted": Array(repeating: [String: Any](), count: insertedCount),
            "updated": Array(repeating: [String: Any](), count: updatedCount),
            "removed": Array<[String: Any]>(),
            "conflicts": conflictsCount,
            "totalChanges": insertedCount + updatedCount
        ]
        
        return .success(result)
    }
    
    // MARK: - Model Limit Management
    
    /// Configure model limit for a specific model type
    /// - Parameters:
    ///   - modelType: The model type to configure
    ///   - limit: The model limit configuration
    public func setModelLimit<T: ORMTable>(for modelType: T.Type, limit: ModelLimit) async {
        await modelLimitManager.setModelLimit(for: modelType, limit: limit)
    }
    
    /// Get model limit configuration for a specific model type
    /// - Parameter modelType: The model type
    /// - Returns: Model limit configuration or nil if not set
    public func getModelLimit<T: ORMTable>(for modelType: T.Type) async -> ModelLimit? {
        return await modelLimitManager.getModelLimit(for: modelType)
    }
    
    /// Remove model limit configuration for a specific model type
    /// - Parameter modelType: The model type
    public func removeModelLimit<T: ORMTable>(for modelType: T.Type) async {
        await modelLimitManager.removeModelLimit(for: modelType)
    }
    
    /// Manually enforce model limits for a specific model type
    /// - Parameter modelType: The model type
    /// - Returns: Result indicating success or failure
    public func enforceLimits<T: ORMTable>(for modelType: T.Type) async -> ORMResult<Void> {
        return await modelLimitManager.enforceLimits(for: modelType)
    }
    
    /// Get statistics about all configured model limits
    /// - Returns: Dictionary of table names to their statistics
    public func getModelLimitStatistics() async -> [String: ModelLimitStatistics] {
        return await modelLimitManager.getStatistics()
    }
    
    /// Cleanup access tracking data for better memory management
    /// - Parameter olderThan: Time interval to consider entries as old (default: 30 days)
    public func cleanupAccessTracking(olderThan timeInterval: TimeInterval = 30 * 24 * 60 * 60) async {
        await modelLimitManager.cleanupAccessTracking(olderThan: timeInterval)
    }
    
    /// Set global removal callback for all model types
    /// - Parameter callback: Callback to execute when models are removed due to limits
    public func setGlobalModelRemovalCallback(_ callback: ModelRemovalCallback?) async {
        await modelLimitManager.setGlobalRemovalCallback(callback)
    }
    
    /// Set removal callback for a specific model type
    /// - Parameters:
    ///   - modelType: The model type
    ///   - callback: Callback to execute when models of this type are removed due to limits
    public func setModelRemovalCallback<T: ORMTable>(for modelType: T.Type, callback: ModelRemovalCallback?) async {
        await modelLimitManager.setRemovalCallback(for: modelType, callback: callback)
    }
    
    /// Manually enforce model limits for a specific model type
    /// - Parameters:
    ///   - modelType: The model type
    ///   - reason: The reason for enforcement
    /// - Returns: Result indicating success or failure
    public func manuallyEnforceLimits<T: ORMTable>(
        for modelType: T.Type,
        reason: ModelRemovalReason = .manualEnforcement
    ) async -> ORMResult<Void> {
        return await modelLimitManager.manuallyEnforceLimits(for: modelType, reason: reason)
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

/// Create a new ORM instance with test database in package's hidden .test-data directory
/// - Parameters:
///   - filename: Database filename (will auto-add .sqlite extension if needed)
///   - enableDiskStorage: Whether to enable disk storage for large objects
/// - Returns: Configured ORM instance for testing
public func createTestORM(filename: String, enableDiskStorage: Bool = true) -> ORM {
    ORM(.test(filename), enableDiskStorage: enableDiskStorage)
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

/// Create a new ORM instance and set up tables in one step (test database)
/// - Parameters:
///   - filename: Database filename (will auto-add .sqlite extension if needed)
///   - enableDiskStorage: Whether to enable disk storage for large objects
///   - models: Variable number of model types to create tables for
/// - Returns: Configured and ready-to-use ORM instance for testing
/// 
/// Example usage:
/// ```swift
/// let orm = await createTestORMWithTables("test_db", User.self, Post.self)
/// ```
public func createTestORMWithTables(_ filename: String, enableDiskStorage: Bool = true, _ models: any ORMTable.Type...) async -> ORMResult<ORM> {
    let orm = createTestORM(filename: filename, enableDiskStorage: enableDiskStorage)
    let result = await orm.openAndCreateTables(for: models)
    
    switch result {
    case .success:
        return .success(orm)
    case .failure(let error):
        return .failure(error)
    }
}