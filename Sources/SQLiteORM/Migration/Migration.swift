import Foundation

/// Protocol for database migrations
public protocol Migration: Sendable {
    /// Unique identifier for this migration
    var id: String { get }
    
    /// Timestamp when this migration was created
    var timestamp: Date { get }
    
    /// Apply the migration
    /// - Parameter database: The database to apply migration to
    /// - Returns: Result indicating success or failure
    func up(database: SQLiteDatabase) async -> ORMResult<Void>
    
    /// Rollback the migration
    /// - Parameter database: The database to rollback migration from
    /// - Returns: Result indicating success or failure
    func down(database: SQLiteDatabase) async -> ORMResult<Void>
}

/// Migration manager handles applying and tracking migrations
public actor MigrationManager {
    /// The database connection
    private let database: SQLiteDatabase
    
    /// Table name for tracking migrations
    private let migrationsTable = "schema_migrations"
    
    /// Initialize migration manager
    /// - Parameter database: The database connection
    public init(database: SQLiteDatabase) {
        self.database = database
    }
    
    /// Setup the migrations tracking table
    /// - Returns: Result indicating success or failure
    public func setup() async -> ORMResult<Void> {
        let sql = """
            CREATE TABLE IF NOT EXISTS \(migrationsTable) (
                id TEXT PRIMARY KEY,
                applied_at REAL NOT NULL
            )
            """
        
        return await database.execute(sql).map { _ in () }
    }
    
    /// Run all pending migrations
    /// - Parameter migrations: Array of migrations to run
    /// - Returns: Result with number of migrations applied
    public func migrate(_ migrations: [Migration]) async -> ORMResult<Int> {
        // Ensure migrations table exists
        let setupResult = await setup()
        guard case .success = setupResult else {
            return setupResult.map { _ in 0 }
        }
        
        // Get applied migrations
        let appliedResult = await getAppliedMigrations()
        guard case .success(let applied) = appliedResult else {
            return appliedResult.map { _ in 0 }
        }
        
        let appliedIds = Set(applied)
        
        // Sort migrations by timestamp
        let sortedMigrations = migrations.sorted { $0.timestamp < $1.timestamp }
        
        var migrationsApplied = 0
        
        for migration in sortedMigrations {
            if !appliedIds.contains(migration.id) {
                let result = await applyMigration(migration)
                switch result {
                case .success:
                    migrationsApplied += 1
                case .failure(let error):
                    return .failure(.migrationFailed(version: migrationsApplied, reason: error.description))
                }
            }
        }
        
        return .success(migrationsApplied)
    }
    
    /// Rollback the last n migrations
    /// - Parameters:
    ///   - migrations: Array of all migrations
    ///   - count: Number of migrations to rollback (default: 1)
    /// - Returns: Result with number of migrations rolled back
    public func rollback(_ migrations: [Migration], count: Int = 1) async -> ORMResult<Int> {
        // Get applied migrations in reverse order
        let appliedResult = await getAppliedMigrations()
        guard case .success(let applied) = appliedResult else {
            return appliedResult.map { _ in 0 }
        }
        
        let migrationMap = Dictionary(uniqueKeysWithValues: migrations.map { ($0.id, $0) })
        
        // Get migrations to rollback
        let toRollback = applied.reversed().prefix(count)
        
        var migrationsRolledBack = 0
        
        for migrationId in toRollback {
            guard let migration = migrationMap[migrationId] else {
                continue
            }
            
            let result = await rollbackMigration(migration)
            switch result {
            case .success:
                migrationsRolledBack += 1
            case .failure(let error):
                return .failure(.migrationFailed(version: migrationsRolledBack, reason: error.description))
            }
        }
        
        return .success(migrationsRolledBack)
    }
    
    /// Apply a single migration
    private func applyMigration(_ migration: Migration) async -> ORMResult<Void> {
        // Run migration in a transaction
        return await database.transaction {
            // Apply the migration
            let upResult = await migration.up(database: self.database)
            guard case .success = upResult else {
                return upResult
            }
            
            // Record the migration
            let sql = "INSERT INTO \(self.migrationsTable) (id, applied_at) VALUES (?, ?)"
            return await self.database.execute(sql, bindings: [.text(migration.id), .real(Date().timeIntervalSince1970)])
                .map { _ in () }
        }
    }
    
    /// Rollback a single migration
    private func rollbackMigration(_ migration: Migration) async -> ORMResult<Void> {
        // Run rollback in a transaction
        return await database.transaction {
            // Rollback the migration
            let downResult = await migration.down(database: self.database)
            guard case .success = downResult else {
                return downResult
            }
            
            // Remove migration record
            let sql = "DELETE FROM \(self.migrationsTable) WHERE id = ?"
            return await self.database.execute(sql, bindings: [.text(migration.id)])
                .map { _ in () }
        }
    }
    
    /// Get list of applied migration IDs
    private func getAppliedMigrations() async -> ORMResult<[String]> {
        let sql = "SELECT id FROM \(migrationsTable) ORDER BY applied_at"
        
        return await database.query(sql).map { rows in
            rows.compactMap { row in
                guard case .text(let id) = row["id"] else { return nil }
                return id
            }
        }
    }
}

/// Base class for creating migrations
open class BaseMigration: Migration, @unchecked Sendable {
    public let id: String
    public let timestamp: Date
    
    /// Initialize with automatic ID generation
    public init() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        
        self.timestamp = Date()
        self.id = formatter.string(from: timestamp) + "_" + String(describing: type(of: self))
    }
    
    /// Initialize with custom ID
    public init(id: String, timestamp: Date = Date()) {
        self.id = id
        self.timestamp = timestamp
    }
    
    /// Override in subclasses to implement migration
    open func up(database: SQLiteDatabase) async -> ORMResult<Void> {
        fatalError("up() must be overridden in subclasses")
    }
    
    /// Override in subclasses to implement rollback
    open func down(database: SQLiteDatabase) async -> ORMResult<Void> {
        fatalError("down() must be overridden in subclasses")
    }
}

/// Helper for creating simple SQL migrations
public final class SQLMigration: BaseMigration, @unchecked Sendable {
    private let upSQL: String
    private let downSQL: String
    
    public init(id: String? = nil, up: String, down: String) {
        self.upSQL = up
        self.downSQL = down
        
        if let id = id {
            super.init(id: id)
        } else {
            super.init()
        }
    }
    
    public override func up(database: SQLiteDatabase) async -> ORMResult<Void> {
        await database.execute(upSQL).map { _ in () }
    }
    
    public override func down(database: SQLiteDatabase) async -> ORMResult<Void> {
        await database.execute(downSQL).map { _ in () }
    }
}