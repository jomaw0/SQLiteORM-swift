import Foundation

/// Custom Result type for SQLiteORM operations
/// Provides a clear success/failure pattern for all database operations
public typealias ORMResult<T> = Result<T, ORMError>

/// Comprehensive error types for SQLiteORM operations
public enum ORMError: Error, CustomStringConvertible {
    /// Database connection errors
    case connectionFailed(reason: String)
    case databaseNotOpen
    case databaseLocked
    
    /// SQL execution errors
    case sqlExecutionFailed(query: String, reason: String)
    case invalidSQL(query: String)
    case constraintViolation(constraint: String)
    
    /// Data mapping errors
    case typeMismatch(column: String, expectedType: String, actualType: String)
    case missingColumn(name: String)
    case invalidData(reason: String)
    
    /// Migration errors
    case migrationFailed(version: Int, reason: String)
    case incompatibleSchema(reason: String)
    
    /// Transaction errors
    case transactionFailed(reason: String)
    case transactionNotActive
    
    /// General errors
    case notFound(entity: String, id: String)
    case duplicateEntry(entity: String, field: String)
    case invalidOperation(reason: String)
    
    public var description: String {
        switch self {
        case .connectionFailed(let reason):
            return "Database connection failed: \(reason)"
        case .databaseNotOpen:
            return "Database is not open"
        case .databaseLocked:
            return "Database is locked"
        case .sqlExecutionFailed(let query, let reason):
            return "SQL execution failed for query '\(query)': \(reason)"
        case .invalidSQL(let query):
            return "Invalid SQL query: \(query)"
        case .constraintViolation(let constraint):
            return "Constraint violation: \(constraint)"
        case .typeMismatch(let column, let expected, let actual):
            return "Type mismatch for column '\(column)': expected \(expected), got \(actual)"
        case .missingColumn(let name):
            return "Missing column: \(name)"
        case .invalidData(let reason):
            return "Invalid data: \(reason)"
        case .migrationFailed(let version, let reason):
            return "Migration failed at version \(version): \(reason)"
        case .incompatibleSchema(let reason):
            return "Incompatible schema: \(reason)"
        case .transactionFailed(let reason):
            return "Transaction failed: \(reason)"
        case .transactionNotActive:
            return "No active transaction"
        case .notFound(let entity, let id):
            return "\(entity) not found with id: \(id)"
        case .duplicateEntry(let entity, let field):
            return "Duplicate entry for \(entity).\(field)"
        case .invalidOperation(let reason):
            return "Invalid operation: \(reason)"
        }
    }
}

/// Extension to provide convenient error handling methods
public extension Result where Failure == ORMError {
    /// Converts Result to optional value, logging error if present
    func toOptional(logError: Bool = true) -> Success? {
        switch self {
        case .success(let value):
            return value
        case .failure(let error):
            if logError {
                print("[SQLiteORM Error] \(error)")
            }
            return nil
        }
    }
    
    /// Maps the success value using the provided transform
    func flatMap<NewSuccess>(_ transform: (Success) -> ORMResult<NewSuccess>) -> ORMResult<NewSuccess> {
        switch self {
        case .success(let value):
            return transform(value)
        case .failure(let error):
            return .failure(error)
        }
    }
}