import Foundation

/// Type-safe predicate for building complex WHERE clauses
public indirect enum Predicate: Sendable {
    /// Single column comparison
    case column(String, ComparisonOperator, SQLiteValue)
    
    /// Check if column is NULL
    case isNull(String)
    
    /// Check if column is NOT NULL
    case isNotNull(String)
    
    /// Column IN values
    case `in`(String, [SQLiteValue])
    
    /// Column NOT IN values
    case notIn(String, [SQLiteValue])
    
    /// Column BETWEEN values
    case between(String, SQLiteValue, SQLiteValue)
    
    /// AND combination of predicates
    case and([Predicate])
    
    /// OR combination of predicates
    case or([Predicate])
    
    /// NOT predicate
    case not(Predicate)
    
    /// Raw SQL predicate (use with caution)
    case raw(String, [SQLiteValue])
}

/// Value type for predicates
public enum PredicateValue: Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
    case bool(Bool)
    case date(Date)
    
    /// Convert to SQLiteValue
    var sqliteValue: SQLiteValue {
        switch self {
        case .null:
            return .null
        case .integer(let value):
            return .integer(value)
        case .real(let value):
            return .real(value)
        case .text(let value):
            return .text(value)
        case .blob(let value):
            return .blob(value)
        case .bool(let value):
            return .integer(value ? 1 : 0)
        case .date(let value):
            return .real(value.timeIntervalSince1970)
        }
    }
}

/// Extension to make creating predicates easier
public extension Predicate {
    /// Create a column comparison predicate
    static func column(_ name: String, _ op: ComparisonOperator, _ value: PredicateValue) -> Predicate {
        .column(name, op, value.sqliteValue)
    }
    
    /// Create an equality predicate
    static func equal(_ column: String, _ value: PredicateValue) -> Predicate {
        .column(column, .equal, value.sqliteValue)
    }
    
    /// Create a not equal predicate
    static func notEqual(_ column: String, _ value: PredicateValue) -> Predicate {
        .column(column, .notEqual, value.sqliteValue)
    }
    
    /// Create a greater than predicate
    static func greaterThan(_ column: String, _ value: PredicateValue) -> Predicate {
        .column(column, .greaterThan, value.sqliteValue)
    }
    
    /// Create a less than predicate
    static func lessThan(_ column: String, _ value: PredicateValue) -> Predicate {
        .column(column, .lessThan, value.sqliteValue)
    }
    
    /// Create a LIKE predicate
    static func like(_ column: String, _ pattern: String) -> Predicate {
        .column(column, .like, PredicateValue.text(pattern).sqliteValue)
    }
}

/// Internal extension for building SQL from predicates
extension Predicate {
    /// Build SQL WHERE clause from predicate
    /// - Returns: Tuple of SQL string and bindings
    func buildSQL() -> (sql: String, bindings: [SQLiteValue]) {
        switch self {
        case .column(let name, let op, let value):
            switch op {
            case .isNull:
                return ("\(name) IS NULL", [])
            case .isNotNull:
                return ("\(name) IS NOT NULL", [])
            default:
                return ("\(name) \(op.rawValue) ?", [value])
            }
            
        case .isNull(let name):
            return ("\(name) IS NULL", [])
            
        case .isNotNull(let name):
            return ("\(name) IS NOT NULL", [])
            
        case .in(let name, let values):
            let placeholders = Array(repeating: "?", count: values.count).joined(separator: ", ")
            return ("\(name) IN (\(placeholders))", values)
            
        case .notIn(let name, let values):
            let placeholders = Array(repeating: "?", count: values.count).joined(separator: ", ")
            return ("\(name) NOT IN (\(placeholders))", values)
            
        case .between(let name, let min, let max):
            return ("\(name) BETWEEN ? AND ?", [min, max])
            
        case .and(let predicates):
            let parts = predicates.map { $0.buildSQL() }
            let sql = parts.map { "(\($0.sql))" }.joined(separator: " AND ")
            let bindings = parts.flatMap { $0.bindings }
            return (sql, bindings)
            
        case .or(let predicates):
            let parts = predicates.map { $0.buildSQL() }
            let sql = parts.map { "(\($0.sql))" }.joined(separator: " OR ")
            let bindings = parts.flatMap { $0.bindings }
            return (sql, bindings)
            
        case .not(let predicate):
            let (sql, bindings) = predicate.buildSQL()
            return ("NOT (\(sql))", bindings)
            
        case .raw(let sql, let bindings):
            return (sql, bindings)
        }
    }
}