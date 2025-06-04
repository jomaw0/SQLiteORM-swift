import Foundation

/// Type-safe SQL query builder
/// Provides a fluent interface for constructing SQL queries
public struct QueryBuilder<T: Model> {
    private var selectColumns: [String] = ["*"]
    private var whereConditions: [WhereCondition] = []
    private var orderByColumns: [(column: String, ascending: Bool)] = []
    private var limitValue: Int?
    private var offsetValue: Int?
    private var joins: [JoinClause] = []
    private var groupByColumns: [String] = []
    private var havingConditions: [WhereCondition] = []
    
    /// Initialize a new query builder
    public init() {}
    
    /// Select specific columns
    /// - Parameter columns: Column names to select
    /// - Returns: Updated query builder
    public func select(_ columns: String...) -> QueryBuilder {
        var builder = self
        builder.selectColumns = columns
        return builder
    }
    
    /// Add a WHERE condition
    /// - Parameters:
    ///   - column: The column name
    ///   - op: The comparison operator
    ///   - value: The value to compare against
    /// - Returns: Updated query builder
    public func `where`(_ column: String, _ op: ComparisonOperator, _ value: SQLiteConvertible?) -> QueryBuilder {
        var builder = self
        builder.whereConditions.append(WhereCondition(column: column, operator: op, value: value?.sqliteValue ?? .null))
        return builder
    }
    
    /// Add a WHERE IN condition
    /// - Parameters:
    ///   - column: The column name
    ///   - values: The values to check against
    /// - Returns: Updated query builder
    public func whereIn(_ column: String, _ values: [SQLiteConvertible]) -> QueryBuilder {
        var builder = self
        builder.whereConditions.append(WhereCondition(column: column, operator: .in, value: .null, values: values.map { $0.sqliteValue }))
        return builder
    }
    
    /// Add a WHERE NOT IN condition
    /// - Parameters:
    ///   - column: The column name
    ///   - values: The values to check against
    /// - Returns: Updated query builder
    public func whereNotIn(_ column: String, _ values: [SQLiteConvertible]) -> QueryBuilder {
        var builder = self
        builder.whereConditions.append(WhereCondition(column: column, operator: .notIn, value: .null, values: values.map { $0.sqliteValue }))
        return builder
    }
    
    /// Add a WHERE BETWEEN condition
    /// - Parameters:
    ///   - column: The column name
    ///   - min: The minimum value
    ///   - max: The maximum value
    /// - Returns: Updated query builder
    public func whereBetween(_ column: String, _ min: SQLiteConvertible, _ max: SQLiteConvertible) -> QueryBuilder {
        var builder = self
        builder.whereConditions.append(WhereCondition(column: column, operator: .between, value: min.sqliteValue, secondValue: max.sqliteValue))
        return builder
    }
    
    /// Add a WHERE LIKE condition
    /// - Parameters:
    ///   - column: The column name
    ///   - pattern: The LIKE pattern
    /// - Returns: Updated query builder
    public func whereLike(_ column: String, _ pattern: String) -> QueryBuilder {
        var builder = self
        builder.whereConditions.append(WhereCondition(column: column, operator: .like, value: .text(pattern)))
        return builder
    }
    
    /// Add an ORDER BY clause
    /// - Parameters:
    ///   - column: The column to order by
    ///   - ascending: Whether to sort in ascending order (default: true)
    /// - Returns: Updated query builder
    public func orderBy(_ column: String, ascending: Bool = true) -> QueryBuilder {
        var builder = self
        builder.orderByColumns.append((column: column, ascending: ascending))
        return builder
    }
    
    /// Add a LIMIT clause
    /// - Parameter limit: The maximum number of rows to return
    /// - Returns: Updated query builder
    public func limit(_ limit: Int) -> QueryBuilder {
        var builder = self
        builder.limitValue = limit
        return builder
    }
    
    /// Add an OFFSET clause
    /// - Parameter offset: The number of rows to skip
    /// - Returns: Updated query builder
    public func offset(_ offset: Int) -> QueryBuilder {
        var builder = self
        builder.offsetValue = offset
        return builder
    }
    
    /// Add an INNER JOIN clause
    /// - Parameters:
    ///   - table: The table to join
    ///   - on: The join condition
    /// - Returns: Updated query builder
    public func join(_ table: String, on condition: String) -> QueryBuilder {
        var builder = self
        builder.joins.append(JoinClause(type: .inner, table: table, condition: condition))
        return builder
    }
    
    /// Add a LEFT JOIN clause
    /// - Parameters:
    ///   - table: The table to join
    ///   - on: The join condition
    /// - Returns: Updated query builder
    public func leftJoin(_ table: String, on condition: String) -> QueryBuilder {
        var builder = self
        builder.joins.append(JoinClause(type: .left, table: table, condition: condition))
        return builder
    }
    
    /// Add a GROUP BY clause
    /// - Parameter columns: Columns to group by
    /// - Returns: Updated query builder
    public func groupBy(_ columns: String...) -> QueryBuilder {
        var builder = self
        builder.groupByColumns = columns
        return builder
    }
    
    /// Add a HAVING condition
    /// - Parameters:
    ///   - column: The column name
    ///   - op: The comparison operator
    ///   - value: The value to compare against
    /// - Returns: Updated query builder
    public func having(_ column: String, _ op: ComparisonOperator, _ value: SQLiteConvertible) -> QueryBuilder {
        var builder = self
        builder.havingConditions.append(WhereCondition(column: column, operator: op, value: value.sqliteValue))
        return builder
    }
    
    /// Build the SELECT query
    /// - Returns: The SQL query string and parameter bindings
    public func buildSelect() -> (sql: String, bindings: [SQLiteValue]) {
        var sql = "SELECT \(selectColumns.joined(separator: ", ")) FROM \(T.tableName)"
        var bindings: [SQLiteValue] = []
        
        // Add joins
        for join in joins {
            sql += " \(join.type.rawValue) JOIN \(join.table) ON \(join.condition)"
        }
        
        // Add WHERE conditions
        if !whereConditions.isEmpty {
            let (whereClause, whereBindings) = buildWhereClause(whereConditions)
            sql += " WHERE \(whereClause)"
            bindings.append(contentsOf: whereBindings)
        }
        
        // Add GROUP BY
        if !groupByColumns.isEmpty {
            sql += " GROUP BY \(groupByColumns.joined(separator: ", "))"
        }
        
        // Add HAVING conditions
        if !havingConditions.isEmpty {
            let (havingClause, havingBindings) = buildWhereClause(havingConditions)
            sql += " HAVING \(havingClause)"
            bindings.append(contentsOf: havingBindings)
        }
        
        // Add ORDER BY
        if !orderByColumns.isEmpty {
            let orderClauses = orderByColumns.map { "\($0.column) \($0.ascending ? "ASC" : "DESC")" }
            sql += " ORDER BY \(orderClauses.joined(separator: ", "))"
        }
        
        // Add LIMIT
        if let limit = limitValue {
            sql += " LIMIT \(limit)"
        }
        
        // Add OFFSET
        if let offset = offsetValue {
            sql += " OFFSET \(offset)"
        }
        
        return (sql, bindings)
    }
    
    /// Build a DELETE query
    /// - Returns: The SQL query string and parameter bindings
    public func buildDelete() -> (sql: String, bindings: [SQLiteValue]) {
        var sql = "DELETE FROM \(T.tableName)"
        var bindings: [SQLiteValue] = []
        
        if !whereConditions.isEmpty {
            let (whereClause, whereBindings) = buildWhereClause(whereConditions)
            sql += " WHERE \(whereClause)"
            bindings.append(contentsOf: whereBindings)
        }
        
        return (sql, bindings)
    }
    
    /// Build an UPDATE query
    /// - Parameter updates: Dictionary of column names to new values
    /// - Returns: The SQL query string and parameter bindings
    public func buildUpdate(_ updates: [String: SQLiteConvertible]) -> (sql: String, bindings: [SQLiteValue]) {
        var sql = "UPDATE \(T.tableName) SET "
        var bindings: [SQLiteValue] = []
        
        let setClauses = updates.map { key, _ in "\(key) = ?" }
        sql += setClauses.joined(separator: ", ")
        
        bindings.append(contentsOf: updates.values.map { $0.sqliteValue })
        
        if !whereConditions.isEmpty {
            let (whereClause, whereBindings) = buildWhereClause(whereConditions)
            sql += " WHERE \(whereClause)"
            bindings.append(contentsOf: whereBindings)
        }
        
        return (sql, bindings)
    }
    
    /// Build the WHERE clause from conditions
    private func buildWhereClause(_ conditions: [WhereCondition]) -> (clause: String, bindings: [SQLiteValue]) {
        var clauses: [String] = []
        var bindings: [SQLiteValue] = []
        
        for condition in conditions {
            switch condition.operator {
            case .in, .notIn:
                let placeholders = Array(repeating: "?", count: condition.values?.count ?? 0).joined(separator: ", ")
                clauses.append("\(condition.column) \(condition.operator.rawValue) (\(placeholders))")
                bindings.append(contentsOf: condition.values ?? [])
            case .between:
                clauses.append("\(condition.column) BETWEEN ? AND ?")
                bindings.append(condition.value)
                if let secondValue = condition.secondValue {
                    bindings.append(secondValue)
                }
            case .isNull, .isNotNull:
                clauses.append("\(condition.column) \(condition.operator.rawValue)")
            default:
                clauses.append("\(condition.column) \(condition.operator.rawValue) ?")
                bindings.append(condition.value)
            }
        }
        
        return (clauses.joined(separator: " AND "), bindings)
    }
}

/// Comparison operators for WHERE conditions
public enum ComparisonOperator: String, Sendable {
    case equal = "="
    case notEqual = "!="
    case lessThan = "<"
    case lessThanOrEqual = "<="
    case greaterThan = ">"
    case greaterThanOrEqual = ">="
    case like = "LIKE"
    case notLike = "NOT LIKE"
    case `in` = "IN"
    case notIn = "NOT IN"
    case between = "BETWEEN"
    case isNull = "IS NULL"
    case isNotNull = "IS NOT NULL"
}

/// Represents a WHERE condition
private struct WhereCondition {
    let column: String
    let `operator`: ComparisonOperator
    let value: SQLiteValue
    let secondValue: SQLiteValue?
    let values: [SQLiteValue]?
    
    init(column: String, operator: ComparisonOperator, value: SQLiteValue, secondValue: SQLiteValue? = nil, values: [SQLiteValue]? = nil) {
        self.column = column
        self.operator = `operator`
        self.value = value
        self.secondValue = secondValue
        self.values = values
    }
}

/// Types of SQL joins
public enum JoinType: String, Sendable {
    case inner = "INNER"
    case left = "LEFT"
    case right = "RIGHT"
    case outer = "OUTER"
}

/// Represents a JOIN clause
public struct JoinClause: Sendable {
    let type: JoinType
    let table: String
    let condition: String
}