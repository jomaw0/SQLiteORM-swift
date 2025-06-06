import Foundation
@preconcurrency import Combine

/// A QueryBuilder that has a repository context, enabling fluent subscription chaining
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public struct QueryBuilderWithRepository<T: ORMTable>: Sendable {
    private let repository: Repository<T>
    private let queryBuilder: QueryBuilder<T>
    
    /// Initialize with a repository
    /// - Parameter repository: The repository to use for queries and subscriptions
    public init(repository: Repository<T>) {
        self.repository = repository
        self.queryBuilder = QueryBuilder<T>()
    }
    
    /// Internal initializer with existing query builder
    private init(repository: Repository<T>, queryBuilder: QueryBuilder<T>) {
        self.repository = repository
        self.queryBuilder = queryBuilder
    }
    
    /// Create a new instance with updated query builder
    private func with(_ newQueryBuilder: QueryBuilder<T>) -> QueryBuilderWithRepository<T> {
        return QueryBuilderWithRepository(repository: repository, queryBuilder: newQueryBuilder)
    }
    
    // MARK: - Query Building Methods
    
    /// Select specific columns
    /// - Parameter columns: Column names to select
    /// - Returns: Updated query builder
    public func select(_ columns: String...) -> QueryBuilderWithRepository<T> {
        return with(queryBuilder.select(Array(columns)))
    }
    
    /// Add a WHERE condition
    /// - Parameters:
    ///   - column: The column name
    ///   - op: The comparison operator
    ///   - value: The value to compare against
    /// - Returns: Updated query builder
    public func `where`(_ column: String, _ op: ComparisonOperator, _ value: SQLiteConvertible?) -> QueryBuilderWithRepository<T> {
        return with(queryBuilder.where(column, op, value))
    }
    
    /// Add a WHERE IN condition
    /// - Parameters:
    ///   - column: The column name
    ///   - values: The values to check against
    /// - Returns: Updated query builder
    public func whereIn(_ column: String, _ values: [SQLiteConvertible]) -> QueryBuilderWithRepository<T> {
        return with(queryBuilder.whereIn(column, values))
    }
    
    /// Add a WHERE NOT IN condition
    /// - Parameters:
    ///   - column: The column name
    ///   - values: The values to check against
    /// - Returns: Updated query builder
    public func whereNotIn(_ column: String, _ values: [SQLiteConvertible]) -> QueryBuilderWithRepository<T> {
        return with(queryBuilder.whereNotIn(column, values))
    }
    
    /// Add a WHERE BETWEEN condition
    /// - Parameters:
    ///   - column: The column name
    ///   - min: The minimum value
    ///   - max: The maximum value
    /// - Returns: Updated query builder
    public func whereBetween(_ column: String, _ min: SQLiteConvertible, _ max: SQLiteConvertible) -> QueryBuilderWithRepository<T> {
        return with(queryBuilder.whereBetween(column, min, max))
    }
    
    /// Add a WHERE LIKE condition
    /// - Parameters:
    ///   - column: The column name
    ///   - pattern: The LIKE pattern
    /// - Returns: Updated query builder
    public func whereLike(_ column: String, _ pattern: String) -> QueryBuilderWithRepository<T> {
        return with(queryBuilder.whereLike(column, pattern))
    }
    
    /// Add an ORDER BY clause
    /// - Parameters:
    ///   - column: The column to order by
    ///   - ascending: Whether to sort in ascending order (default: true)
    /// - Returns: Updated query builder
    public func orderBy(_ column: String, ascending: Bool = true) -> QueryBuilderWithRepository<T> {
        return with(queryBuilder.orderBy(column, ascending: ascending))
    }
    
    /// Add a LIMIT clause
    /// - Parameter limit: The maximum number of rows to return
    /// - Returns: Updated query builder
    public func limit(_ limit: Int) -> QueryBuilderWithRepository<T> {
        return with(queryBuilder.limit(limit))
    }
    
    /// Add an OFFSET clause
    /// - Parameter offset: The number of rows to skip
    /// - Returns: Updated query builder
    public func offset(_ offset: Int) -> QueryBuilderWithRepository<T> {
        return with(queryBuilder.offset(offset))
    }
    
    /// Add an INNER JOIN clause
    /// - Parameters:
    ///   - table: The table to join
    ///   - on: The join condition
    /// - Returns: Updated query builder
    public func join(_ table: String, on condition: String) -> QueryBuilderWithRepository<T> {
        return with(queryBuilder.join(table, on: condition))
    }
    
    /// Add a LEFT JOIN clause
    /// - Parameters:
    ///   - table: The table to join
    ///   - on: The join condition
    /// - Returns: Updated query builder
    public func leftJoin(_ table: String, on condition: String) -> QueryBuilderWithRepository<T> {
        return with(queryBuilder.leftJoin(table, on: condition))
    }
    
    /// Add a GROUP BY clause
    /// - Parameter columns: Columns to group by
    /// - Returns: Updated query builder
    public func groupBy(_ columns: String...) -> QueryBuilderWithRepository<T> {
        return with(queryBuilder.groupBy(Array(columns)))
    }
    
    /// Add a HAVING condition
    /// - Parameters:
    ///   - column: The column name
    ///   - op: The comparison operator
    ///   - value: The value to compare against
    /// - Returns: Updated query builder
    public func having(_ column: String, _ op: ComparisonOperator, _ value: SQLiteConvertible) -> QueryBuilderWithRepository<T> {
        return with(queryBuilder.having(column, op, value))
    }
    
    // MARK: - Execution Methods
    
    /// Execute the query and return all matching results
    /// - Returns: Result containing array of models or error
    public func findAll() async -> ORMResult<[T]> {
        return await repository.findAll(query: queryBuilder)
    }
    
    /// Execute the query and return the first matching result
    /// - Returns: Result containing the first model or nil
    public func findFirst() async -> ORMResult<T?> {
        return await repository.findFirst(query: queryBuilder)
    }
    
    /// Execute the query and return the count of matching results
    /// - Returns: Result containing the count
    public func count() async -> ORMResult<Int> {
        return await repository.count(query: queryBuilder)
    }
    
    // MARK: - Subscription Methods
    
    /// Subscribe to this query's results
    /// - Returns: A subscription that emits updated query results when data changes
    public func subscribe() async -> SimpleQuerySubscription<T> {
        return await repository.subscribe(query: queryBuilder)
    }
    
    /// Subscribe to the first result of this query
    /// - Returns: A subscription that emits the first updated query result when data changes
    public func subscribeFirst() async -> SimpleSingleQuerySubscription<T> {
        return await repository.subscribeFirst(query: queryBuilder)
    }
    
    /// Subscribe to the count of results for this query
    /// - Returns: A subscription that emits updated count when data changes
    public func subscribeCount() async -> SimpleCountSubscription<T> {
        return await repository.subscribeCount(query: queryBuilder)
    }
    
    /// Get the underlying QueryBuilder for compatibility
    /// - Returns: The underlying QueryBuilder instance
    public func asQueryBuilder() -> QueryBuilder<T> {
        return queryBuilder
    }
}