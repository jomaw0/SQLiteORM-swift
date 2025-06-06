import Foundation
import SQLite3

/// Actor-based SQLite database connection manager
/// Ensures thread-safe database operations using Swift's actor model
public actor SQLiteDatabase {
    /// The SQLite database handle
    private var db: OpaquePointer?
    
    /// The database file path
    private let path: String
    
    /// Current transaction state
    private var isInTransaction = false
    
    /// Configuration for the database
    private let configuration: DatabaseConfiguration
    
    /// Initialize a new database connection
    /// - Parameters:
    ///   - path: Path to the database file (use ":memory:" for in-memory database)
    ///   - configuration: Database configuration options
    public init(path: String, configuration: DatabaseConfiguration = .default) {
        self.path = path
        self.configuration = configuration
    }
    
    /// Open the database connection
    /// - Returns: Result indicating success or failure
    public func open() -> ORMResult<Void> {
        guard db == nil else {
            return .success(())
        }
        
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        
        if sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK {
            // Apply configuration
            let _ = execute("PRAGMA foreign_keys = ON")
            
            if configuration.enableWAL {
                let _ = execute("PRAGMA journal_mode = WAL")
            }
            
            if let busyTimeout = configuration.busyTimeout {
                sqlite3_busy_timeout(db, Int32(busyTimeout))
            }
            
            return .success(())
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            db = nil
            return .failure(.connectionFailed(reason: errorMessage))
        }
    }
    
    /// Close the database connection
    /// - Returns: Result indicating success or failure
    public func close() -> ORMResult<Void> {
        guard let database = db else {
            return .success(())
        }
        
        if sqlite3_close(database) == SQLITE_OK {
            db = nil
            return .success(())
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            return .failure(.connectionFailed(reason: "Failed to close database: \(errorMessage)"))
        }
    }
    
    /// Execute a SQL statement that doesn't return results
    /// - Parameter sql: The SQL statement to execute
    /// - Parameter bindings: Parameter bindings for the statement
    /// - Returns: Result with the number of affected rows
    public func execute(_ sql: String, bindings: [SQLiteValue] = []) -> ORMResult<Int> {
        guard let database = db else {
            return .failure(.databaseNotOpen)
        }
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            return .failure(.invalidSQL(query: sql + " - " + errorMessage))
        }
        
        defer { sqlite3_finalize(statement) }
        
        // Bind parameters
        for (index, value) in bindings.enumerated() {
            let bindResult = value.bind(to: statement, at: Int32(index + 1))
            if bindResult != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                return .failure(.sqlExecutionFailed(query: sql, reason: "Binding failed: \(errorMessage)"))
            }
        }
        
        let result = sqlite3_step(statement)
        
        if result == SQLITE_DONE {
            let rowsAffected = Int(sqlite3_changes(database))
            return .success(rowsAffected)
        } else if result == SQLITE_CONSTRAINT {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            return .failure(.constraintViolation(constraint: errorMessage))
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            return .failure(.sqlExecutionFailed(query: sql, reason: errorMessage))
        }
    }
    
    /// Execute a SQL query that returns results
    /// - Parameter sql: The SQL query to execute
    /// - Parameter bindings: Parameter bindings for the query
    /// - Returns: Result with an array of rows
    public func query(_ sql: String, bindings: [SQLiteValue] = []) -> ORMResult<[[String: SQLiteValue]]> {
        guard let database = db else {
            return .failure(.databaseNotOpen)
        }
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            return .failure(.invalidSQL(query: sql + " - " + errorMessage))
        }
        
        defer { sqlite3_finalize(statement) }
        
        // Bind parameters
        for (index, value) in bindings.enumerated() {
            let bindResult = value.bind(to: statement, at: Int32(index + 1))
            if bindResult != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(database))
                return .failure(.sqlExecutionFailed(query: sql, reason: "Binding failed: \(errorMessage)"))
            }
        }
        
        var rows: [[String: SQLiteValue]] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: SQLiteValue] = [:]
            let columnCount = sqlite3_column_count(statement)
            
            for i in 0..<columnCount {
                let columnName = String(cString: sqlite3_column_name(statement, i))
                let value = SQLiteValue.fromColumn(statement: statement, index: i)
                row[columnName] = value
            }
            
            rows.append(row)
        }
        
        return .success(rows)
    }
    
    /// Begin a database transaction
    /// - Returns: Result indicating success or failure
    public func beginTransaction() -> ORMResult<Void> {
        guard !isInTransaction else {
            return .failure(.invalidOperation(reason: "Transaction already in progress"))
        }
        
        return execute("BEGIN TRANSACTION").map { _ in
            self.isInTransaction = true
        }
    }
    
    /// Commit the current transaction
    /// - Returns: Result indicating success or failure
    public func commitTransaction() -> ORMResult<Void> {
        guard isInTransaction else {
            return .failure(.transactionNotActive)
        }
        
        return execute("COMMIT").map { _ in
            self.isInTransaction = false
        }
    }
    
    /// Rollback the current transaction
    /// - Returns: Result indicating success or failure
    public func rollbackTransaction() -> ORMResult<Void> {
        guard isInTransaction else {
            return .failure(.transactionNotActive)
        }
        
        return execute("ROLLBACK").map { _ in
            self.isInTransaction = false
        }
    }
    
    /// Execute a block within a transaction
    /// - Parameter block: The block to execute
    /// - Returns: Result of the block execution
    public func transaction<T: Sendable>(_ block: @Sendable () async throws -> ORMResult<T>) async -> ORMResult<T> {
        let beginResult = beginTransaction()
        guard case .success = beginResult else {
            return beginResult.map { _ in fatalError("Unreachable") }
        }
        
        do {
            let result = try await block()
            switch result {
            case .success(let value):
                let commitResult = commitTransaction()
                switch commitResult {
                case .success:
                    return .success(value)
                case .failure(let error):
                    let _ = rollbackTransaction()
                    return .failure(error)
                }
            case .failure(let error):
                let _ = rollbackTransaction()
                return .failure(error)
            }
        } catch {
            let _ = rollbackTransaction()
            return .failure(.transactionFailed(reason: error.localizedDescription))
        }
    }
    
    /// Get the last inserted row ID
    public var lastInsertRowID: Int64 {
        guard let database = db else { return 0 }
        return sqlite3_last_insert_rowid(database)
    }
}

/// Database configuration options
public struct DatabaseConfiguration: Sendable {
    /// Enable Write-Ahead Logging
    public let enableWAL: Bool
    
    /// Busy timeout in milliseconds
    public let busyTimeout: Int?
    
    /// Default configuration
    public static let `default` = DatabaseConfiguration(
        enableWAL: true,
        busyTimeout: 5000
    )
    
    public init(enableWAL: Bool = true, busyTimeout: Int? = 5000) {
        self.enableWAL = enableWAL
        self.busyTimeout = busyTimeout
    }
}