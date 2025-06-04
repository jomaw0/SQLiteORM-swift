import Foundation

/// Sorting order for queries
public enum SortOrder: String, Sendable {
    case ascending = "ASC"
    case descending = "DESC"
}

/// Type-safe query builder with predicate support
public struct Query<T: Model>: Sendable {
    /// The model type this query operates on
    public let modelType: T.Type
    
    /// The database to execute against
    private let database: SQLiteDatabase?
    
    /// The repository to use for fetching
    private let repository: Repository<T>?
    
    /// Selected columns
    private var selectColumns: [String] = ["*"]
    
    /// WHERE predicate
    private var predicate: Predicate?
    
    /// ORDER BY clauses
    private var orderByClauses: [(column: String, order: SortOrder)] = []
    
    /// LIMIT value
    private var limitValue: Int?
    
    /// OFFSET value
    private var offsetValue: Int?
    
    /// GROUP BY columns
    private var groupByColumns: [String] = []
    
    /// HAVING predicate
    private var havingPredicate: Predicate?
    
    /// JOIN clauses
    private var joins: [JoinClause] = []
    
    /// Initialize a query
    init(modelType: T.Type, database: SQLiteDatabase? = nil, repository: Repository<T>? = nil) {
        self.modelType = modelType
        self.database = database
        self.repository = repository
    }
    
    /// Maps property name to actual column name using columnMappings
    private func mapColumnName(_ propertyName: String) -> String {
        return T.columnMappings?[propertyName] ?? propertyName
    }
    
    /// Internal init for repository-based queries
    internal init(modelType: T.Type, repository: Repository<T>) {
        self.modelType = modelType
        self.database = nil
        self.repository = repository
    }
    
    /// Select specific columns
    public func select(_ columns: String...) -> Query {
        var query = self
        query.selectColumns = columns
        return query
    }
    
    /// Add a WHERE predicate
    public func `where`(_ predicate: Predicate) -> Query {
        var query = self
        query.predicate = predicate
        return query
    }
    
    /// Add an ORDER BY clause
    public func orderBy(_ column: String, _ order: SortOrder = .ascending) -> Query {
        var query = self
        let mappedColumn = mapColumnName(column)
        query.orderByClauses.append((column: mappedColumn, order: order))
        return query
    }
    
    /// Set the LIMIT
    public func limit(_ limit: Int) -> Query {
        var query = self
        query.limitValue = limit
        return query
    }
    
    /// Set the OFFSET
    public func offset(_ offset: Int) -> Query {
        var query = self
        query.offsetValue = offset
        return query
    }
    
    /// Add GROUP BY columns
    public func groupBy(_ columns: String...) -> Query {
        var query = self
        query.groupByColumns = columns.map { mapColumnName($0) }
        return query
    }
    
    /// Add a HAVING predicate
    public func having(_ predicate: Predicate) -> Query {
        var query = self
        query.havingPredicate = predicate
        return query
    }
    
    /// Add an INNER JOIN
    public func join(_ table: String, on condition: String) -> Query {
        var query = self
        query.joins.append(JoinClause(type: .inner, table: table, condition: condition))
        return query
    }
    
    /// Add a LEFT JOIN
    public func leftJoin(_ table: String, on condition: String) -> Query {
        var query = self
        query.joins.append(JoinClause(type: .left, table: table, condition: condition))
        return query
    }
    
    /// Execute the query and fetch results
    public func fetch() async -> ORMResult<[T]> {
        guard let repository = repository else {
            return .failure(.invalidOperation(reason: "No repository available for fetch"))
        }
        
        // Convert to QueryBuilder for execution
        let queryBuilder = toQueryBuilder()
        return await repository.findAll(query: queryBuilder)
    }
    
    /// Execute the query and fetch the first result
    public func fetchFirst() async -> ORMResult<T?> {
        guard let repository = repository else {
            return .failure(.invalidOperation(reason: "No repository available for fetch"))
        }
        
        // Convert to QueryBuilder for execution
        let queryBuilder = toQueryBuilder().limit(1)
        return await repository.findFirst(query: queryBuilder)
    }
    
    /// Execute the query and count results
    public func count() async -> ORMResult<Int> {
        guard let repository = repository else {
            return .failure(.invalidOperation(reason: "No repository available for count"))
        }
        
        // Convert to QueryBuilder for execution
        let queryBuilder = toQueryBuilder()
        return await repository.count(query: queryBuilder)
    }
    
    /// Delete all matching records
    public func delete() async -> ORMResult<Int> {
        guard let repository = repository else {
            return .failure(.invalidOperation(reason: "No repository available for delete"))
        }
        
        // Convert to QueryBuilder for execution
        let queryBuilder = toQueryBuilder()
        return await repository.deleteWhere(query: queryBuilder)
    }
    
    /// Build the SQL query
    public func buildSQL() -> (sql: String, bindings: [SQLiteValue]) {
        var sql = "SELECT \(selectColumns.joined(separator: ", ")) FROM \(T.tableName)"
        var bindings: [SQLiteValue] = []
        
        // Add JOINs
        for join in joins {
            sql += " \(join.type.rawValue) JOIN \(join.table) ON \(join.condition)"
        }
        
        // Add WHERE clause
        if let predicate = predicate {
            let (whereSQL, whereBindings) = predicate.buildSQL(columnMapper: mapColumnName)
            sql += " WHERE \(whereSQL)"
            bindings.append(contentsOf: whereBindings)
        }
        
        // Add GROUP BY
        if !groupByColumns.isEmpty {
            sql += " GROUP BY \(groupByColumns.joined(separator: ", "))"
        }
        
        // Add HAVING clause
        if let havingPredicate = havingPredicate {
            let (havingSQL, havingBindings) = havingPredicate.buildSQL(columnMapper: mapColumnName)
            sql += " HAVING \(havingSQL)"
            bindings.append(contentsOf: havingBindings)
        }
        
        // Add ORDER BY
        if !orderByClauses.isEmpty {
            let orderClauses = orderByClauses.map { "\($0.column) \($0.order.rawValue)" }
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
    
    /// Convert to legacy QueryBuilder for compatibility
    private func toQueryBuilder() -> QueryBuilder<T> {
        var builder = QueryBuilder<T>()
        
        // Apply select
        if selectColumns != ["*"] {
            builder = builder.select(selectColumns.joined(separator: ", "))
        }
        
        // Apply WHERE predicate
        if let predicate = predicate {
            builder = applyPredicateToBuilder(builder, predicate: predicate)
        }
        
        // Apply ORDER BY
        for orderBy in orderByClauses {
            builder = builder.orderBy(orderBy.column, ascending: orderBy.order == .ascending)
        }
        
        // Apply LIMIT
        if let limit = limitValue {
            builder = builder.limit(limit)
        }
        
        // Apply OFFSET
        if let offset = offsetValue {
            builder = builder.offset(offset)
        }
        
        // Apply GROUP BY
        if !groupByColumns.isEmpty {
            builder = builder.groupBy(groupByColumns.joined(separator: ", "))
        }
        
        // Apply JOINs
        for join in joins {
            switch join.type {
            case .inner:
                builder = builder.join(join.table, on: join.condition)
            case .left:
                builder = builder.leftJoin(join.table, on: join.condition)
            default:
                break
            }
        }
        
        return builder
    }
    
    /// Apply a predicate to a QueryBuilder
    private func applyPredicateToBuilder(_ builder: QueryBuilder<T>, predicate: Predicate) -> QueryBuilder<T> {
        switch predicate {
        case .column(let name, let op, let value):
            if let convertible = SQLiteValueConvertible(value: value) {
                return builder.where(name, op, convertible)
            }
            return builder
            
        case .isNull(let name):
            return builder.where(name, .isNull, nil)
            
        case .isNotNull(let name):
            return builder.where(name, .isNotNull, nil)
            
        case .in(let name, let values):
            let convertibles = values.compactMap { SQLiteValueConvertible(value: $0) }
            return builder.whereIn(name, convertibles)
            
        case .notIn(let name, let values):
            let convertibles = values.compactMap { SQLiteValueConvertible(value: $0) }
            return builder.whereNotIn(name, convertibles)
            
        case .between(let name, let min, let max):
            if let minConv = SQLiteValueConvertible(value: min),
               let maxConv = SQLiteValueConvertible(value: max) {
                return builder.whereBetween(name, minConv, maxConv)
            }
            return builder
            
        default:
            // For complex predicates, we'd need to enhance QueryBuilder
            // For now, return the builder as-is
            return builder
        }
    }
}

/// Helper to make SQLiteValue conform to SQLiteConvertible
private struct SQLiteValueConvertible: SQLiteConvertible {
    let value: SQLiteValue
    
    init?(value: SQLiteValue) {
        self.value = value
    }
    
    init?(sqliteValue: SQLiteValue) {
        self.value = sqliteValue
    }
    
    var sqliteValue: SQLiteValue {
        value
    }
}