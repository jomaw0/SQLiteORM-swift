import Foundation
@preconcurrency import Combine

/// Type-safe SQL query builder
/// Provides a fluent interface for constructing SQL queries
public struct ORMQueryBuilder<T: ORMTable>: Sendable {
    private var selectColumns: [String] = ["*"]
    private var whereConditions: [WhereCondition] = []
    private var orderByColumns: [(column: String, ascending: Bool)] = []
    private var limitValue: Int?
    private var offsetValue: Int?
    private var joins: [ORMJoinClause] = []
    private var groupByColumns: [String] = []
    private var havingConditions: [WhereCondition] = []
    
    /// Initialize a new query builder
    public init() {}
    
    /// Maps property name to actual column name using columnMappings
    private func mapColumnName(_ propertyName: String) -> String {
        return T.columnMappings?[propertyName] ?? propertyName
    }
    
    /// The repository associated with this query builder (for subscriptions)
    private var repository: Repository<T>?
    
    /// Initialize with a repository for subscription support
    /// - Parameter repository: The repository to use for subscriptions
    public init(repository: Repository<T>) {
        self.repository = repository
    }
    
    /// Internal method to create a new builder with the same repository
    private func withRepository() -> Self {
        var builder = self
        builder.repository = self.repository
        return builder
    }
    
    /// Select specific columns
    /// - Parameter columns: Column names to select
    /// - Returns: Updated query builder
    public func select(_ columns: String...) -> Self {
        var builder = self
        builder.selectColumns = columns
        return builder
    }
    
    /// Select specific columns from array
    /// - Parameter columns: Array of column names to select
    /// - Returns: Updated query builder
    public func select(_ columns: [String]) -> Self {
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
    public func `where`(_ column: String, _ op: ComparisonOperator, _ value: SQLiteConvertible?) -> Self {
        var builder = self
        let mappedColumn = mapColumnName(column)
        builder.whereConditions.append(WhereCondition(column: mappedColumn, operator: op, value: value?.sqliteValue ?? .null))
        return builder
    }
    
    /// Add a WHERE IN condition
    /// - Parameters:
    ///   - column: The column name
    ///   - values: The values to check against
    /// - Returns: Updated query builder
    public func whereIn(_ column: String, _ values: [SQLiteConvertible]) -> Self {
        var builder = self
        let mappedColumn = mapColumnName(column)
        builder.whereConditions.append(WhereCondition(column: mappedColumn, operator: .in, value: .null, values: values.map { $0.sqliteValue }))
        return builder
    }
    
    /// Add a WHERE NOT IN condition
    /// - Parameters:
    ///   - column: The column name
    ///   - values: The values to check against
    /// - Returns: Updated query builder
    public func whereNotIn(_ column: String, _ values: [SQLiteConvertible]) -> Self {
        var builder = self
        let mappedColumn = mapColumnName(column)
        builder.whereConditions.append(WhereCondition(column: mappedColumn, operator: .notIn, value: .null, values: values.map { $0.sqliteValue }))
        return builder
    }
    
    /// Add a WHERE BETWEEN condition
    /// - Parameters:
    ///   - column: The column name
    ///   - min: The minimum value
    ///   - max: The maximum value
    /// - Returns: Updated query builder
    public func whereBetween(_ column: String, _ min: SQLiteConvertible, _ max: SQLiteConvertible) -> Self {
        var builder = self
        let mappedColumn = mapColumnName(column)
        builder.whereConditions.append(WhereCondition(column: mappedColumn, operator: .between, value: min.sqliteValue, secondValue: max.sqliteValue))
        return builder
    }
    
    /// Add a WHERE LIKE condition
    /// - Parameters:
    ///   - column: The column name
    ///   - pattern: The LIKE pattern
    /// - Returns: Updated query builder
    public func whereLike(_ column: String, _ pattern: String) -> Self {
        var builder = self
        let mappedColumn = mapColumnName(column)
        builder.whereConditions.append(WhereCondition(column: mappedColumn, operator: .like, value: .text(pattern)))
        return builder
    }
    
    // MARK: - Convenience WHERE Methods
    
    /// Add a WHERE column = value condition
    /// - Parameters:
    ///   - column: The column name
    ///   - value: The value to compare against
    /// - Returns: Updated query builder
    public func whereEqual(_ column: String, _ value: SQLiteConvertible?) -> Self {
        return `where`(column, .equal, value)
    }
    
    /// Add a WHERE column != value condition
    /// - Parameters:
    ///   - column: The column name
    ///   - value: The value to compare against
    /// - Returns: Updated query builder
    public func whereNotEqual(_ column: String, _ value: SQLiteConvertible?) -> Self {
        return `where`(column, .notEqual, value)
    }
    
    /// Add a WHERE column > value condition
    /// - Parameters:
    ///   - column: The column name
    ///   - value: The value to compare against
    /// - Returns: Updated query builder
    public func whereGreaterThan(_ column: String, _ value: SQLiteConvertible?) -> Self {
        return `where`(column, .greaterThan, value)
    }
    
    /// Add a WHERE column >= value condition
    /// - Parameters:
    ///   - column: The column name
    ///   - value: The value to compare against
    /// - Returns: Updated query builder
    public func whereGreaterThanOrEqual(_ column: String, _ value: SQLiteConvertible?) -> Self {
        return `where`(column, .greaterThanOrEqual, value)
    }
    
    /// Add a WHERE column < value condition
    /// - Parameters:
    ///   - column: The column name
    ///   - value: The value to compare against
    /// - Returns: Updated query builder
    public func whereLessThan(_ column: String, _ value: SQLiteConvertible?) -> Self {
        return `where`(column, .lessThan, value)
    }
    
    /// Add a WHERE column <= value condition
    /// - Parameters:
    ///   - column: The column name
    ///   - value: The value to compare against
    /// - Returns: Updated query builder
    public func whereLessThanOrEqual(_ column: String, _ value: SQLiteConvertible?) -> Self {
        return `where`(column, .lessThanOrEqual, value)
    }
    
    /// Add a WHERE column NOT LIKE pattern condition
    /// - Parameters:
    ///   - column: The column name
    ///   - pattern: The NOT LIKE pattern
    /// - Returns: Updated query builder
    public func whereNotLike(_ column: String, _ pattern: String) -> Self {
        var builder = self
        let mappedColumn = mapColumnName(column)
        builder.whereConditions.append(WhereCondition(column: mappedColumn, operator: .notLike, value: .text(pattern)))
        return builder
    }
    
    /// Add a WHERE column IS NULL condition
    /// - Parameter column: The column name
    /// - Returns: Updated query builder
    public func whereNull(_ column: String) -> Self {
        var builder = self
        let mappedColumn = mapColumnName(column)
        builder.whereConditions.append(WhereCondition(column: mappedColumn, operator: .isNull, value: .null))
        return builder
    }
    
    /// Add a WHERE column IS NOT NULL condition
    /// - Parameter column: The column name
    /// - Returns: Updated query builder
    public func whereNotNull(_ column: String) -> Self {
        var builder = self
        let mappedColumn = mapColumnName(column)
        builder.whereConditions.append(WhereCondition(column: mappedColumn, operator: .isNotNull, value: .null))
        return builder
    }
    
    /// Add an ORDER BY clause
    /// - Parameters:
    ///   - column: The column to order by
    ///   - ascending: Whether to sort in ascending order (default: true)
    /// - Returns: Updated query builder
    public func orderBy(_ column: String, ascending: Bool = true) -> Self {
        var builder = self
        let mappedColumn = mapColumnName(column)
        builder.orderByColumns.append((column: mappedColumn, ascending: ascending))
        return builder
    }
    
    /// Add a LIMIT clause
    /// - Parameter limit: The maximum number of rows to return
    /// - Returns: Updated query builder
    public func limit(_ limit: Int) -> Self {
        var builder = self
        builder.limitValue = limit
        return builder
    }
    
    /// Add an OFFSET clause
    /// - Parameter offset: The number of rows to skip
    /// - Returns: Updated query builder
    public func offset(_ offset: Int) -> Self {
        var builder = self
        builder.offsetValue = offset
        return builder
    }
    
    /// Add an INNER JOIN clause
    /// - Parameters:
    ///   - table: The table to join
    ///   - on: The join condition
    /// - Returns: Updated query builder
    public func join(_ table: String, on condition: String) -> Self {
        var builder = self
        builder.joins.append(ORMJoinClause(type: .inner, table: table, condition: condition))
        return builder
    }
    
    /// Add a LEFT JOIN clause
    /// - Parameters:
    ///   - table: The table to join
    ///   - on: The join condition
    /// - Returns: Updated query builder
    public func leftJoin(_ table: String, on condition: String) -> Self {
        var builder = self
        builder.joins.append(ORMJoinClause(type: .left, table: table, condition: condition))
        return builder
    }
    
    /// Add a GROUP BY clause
    /// - Parameter columns: Columns to group by
    /// - Returns: Updated query builder
    public func groupBy(_ columns: String...) -> Self {
        var builder = self
        builder.groupByColumns = columns.map { mapColumnName($0) }
        return builder
    }
    
    /// Add a GROUP BY clause from array
    /// - Parameter columns: Array of columns to group by
    /// - Returns: Updated query builder
    public func groupBy(_ columns: [String]) -> Self {
        var builder = self
        builder.groupByColumns = columns.map { mapColumnName($0) }
        return builder
    }
    
    /// Add a HAVING condition
    /// - Parameters:
    ///   - column: The column name
    ///   - op: The comparison operator
    ///   - value: The value to compare against
    /// - Returns: Updated query builder
    public func having(_ column: String, _ op: ComparisonOperator, _ value: SQLiteConvertible) -> Self {
        var builder = self
        let mappedColumn = mapColumnName(column)
        builder.havingConditions.append(WhereCondition(column: mappedColumn, operator: op, value: value.sqliteValue))
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
        
        let sortedKeys = updates.keys.sorted()
        let setClauses = sortedKeys.map { key in "\(mapColumnName(key)) = ?" }
        sql += setClauses.joined(separator: ", ")
        
        bindings.append(contentsOf: sortedKeys.map { updates[$0]!.sqliteValue })
        
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

// MARK: - Combine Subscription Extensions
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension ORMQueryBuilder {
    
    /// Subscribe to this query's results using the provided repository
    /// - Parameter repository: The repository to use for the subscription
    /// - Returns: A subscription that emits updated query results when data changes
    public func subscribe(using repository: Repository<T>) -> SimpleQuerySubscription<T> {
        return repository.subscribe(query: self)
    }
    
    /// Subscribe to the first result of this query using the provided repository
    /// - Parameter repository: The repository to use for the subscription
    /// - Returns: A subscription that emits the first updated query result when data changes
    public func subscribeFirst(using repository: Repository<T>) -> SimpleSingleQuerySubscription<T> {
        return repository.subscribeFirst(query: self)
    }
    
    /// Subscribe to the count of results for this query using the provided repository
    /// - Parameter repository: The repository to use for the subscription
    /// - Returns: A subscription that emits updated count when data changes
    public func subscribeCount(using repository: Repository<T>) -> SimpleCountSubscription<T> {
        return repository.subscribeCount(query: self)
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
public struct ORMJoinClause: Sendable {
    let type: JoinType
    let table: String
    let condition: String
}

// MARK: - Backward Compatibility

/// Backward compatibility alias
@available(*, deprecated, renamed: "ORMQueryBuilder")
public typealias QueryBuilder<T: ORMTable> = ORMQueryBuilder<T>

/// Backward compatibility alias
@available(*, deprecated, renamed: "ORMJoinClause")
public typealias JoinClause = ORMJoinClause