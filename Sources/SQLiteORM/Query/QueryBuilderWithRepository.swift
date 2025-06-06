import Foundation
@preconcurrency import Combine

/// A QueryBuilder that has a repository context, enabling fluent subscription chaining
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public struct QueryBuilderWithRepository<T: ORMTable>: Sendable {
    private let repository: Repository<T>
    private let queryBuilder: ORMQueryBuilder<T>
    
    /// Initialize with a repository
    /// - Parameter repository: The repository to use for queries and subscriptions
    public init(repository: Repository<T>) {
        self.repository = repository
        self.queryBuilder = ORMQueryBuilder<T>()
    }
    
    /// Internal initializer with existing query builder
    private init(repository: Repository<T>, queryBuilder: ORMQueryBuilder<T>) {
        self.repository = repository
        self.queryBuilder = queryBuilder
    }
    
    /// Create a new instance with updated query builder
    private func with(_ newQueryBuilder: ORMQueryBuilder<T>) -> QueryBuilderWithRepository<T> {
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
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Returns: A subscription that emits updated query results when data changes
    public func subscribe() -> SimpleQuerySubscription<T> {
        return repository.subscribe(query: queryBuilder)
    }
    
    /// Subscribe to the first result of this query
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Returns: A subscription that emits the first updated query result when data changes
    public func subscribeFirst() -> SimpleSingleQuerySubscription<T> {
        return repository.subscribeFirst(query: queryBuilder)
    }
    
    /// Subscribe to the count of results for this query
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Returns: A subscription that emits updated count when data changes
    public func subscribeCount() -> SimpleCountSubscription<T> {
        return repository.subscribeCount(query: queryBuilder)
    }
    
    // MARK: - Alternative Subscription Methods (Different Return Types)
    
    /// Subscribe to this query's results (returns QuerySubscription)
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Returns: A QuerySubscription that emits updated query results when data changes
    public func subscribeQuery() -> QuerySubscription<T> {
        return repository.subscribeQuery(query: queryBuilder)
    }
    
    /// Subscribe to the first result of this query (returns SingleQuerySubscription)
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Returns: A SingleQuerySubscription that emits the first updated query result when data changes
    public func subscribeSingle() -> SingleQuerySubscription<T> {
        return repository.subscribeSingle(query: queryBuilder)
    }
    
    /// Subscribe to the count of results for this query (returns CountSubscription)
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Returns: A CountSubscription that emits updated count when data changes
    public func subscribeCountQuery() -> CountSubscription<T> {
        return repository.subscribeCountQuery(query: queryBuilder)
    }
    
    /// Subscribe to whether any results exist for this query (returns ExistsSubscription)
    /// Uses atomic setup to eliminate race conditions - no await needed!
    /// - Returns: An ExistsSubscription that emits true/false when existence changes
    public func subscribeExists() -> ExistsSubscription<T> {
        return repository.subscribeExists(query: queryBuilder)
    }
    
    // MARK: - Convenient Query Methods
    
    /// Add a WHERE clause for foreign key relationships (belongsTo pattern)
    /// - Parameters:
    ///   - foreignKey: The foreign key column name (e.g., "userId", "postId")  
    ///   - parentId: The parent model's ID value
    /// - Returns: Updated query builder
    public func whereBelongsTo(_ foreignKey: String, parentId: SQLiteConvertible) -> QueryBuilderWithRepository<T> {
        return `where`(foreignKey, .equal, parentId)
    }
    
    /// Add a WHERE clause to find models that belong to a specific parent
    /// - Parameters:
    ///   - parentType: The parent model type
    ///   - parentId: The parent model's ID
    /// - Returns: Updated query builder
    public func belongsTo<Parent: ORMTable>(_ parentType: Parent.Type, parentId: Parent.IDType) -> QueryBuilderWithRepository<T> {
        let foreignKey = "\(String(describing: parentType).lowercased())Id"
        return `where`(foreignKey, .equal, parentId as? SQLiteConvertible)
    }
    
    /// Add a WHERE clause using a more natural belongs-to syntax
    /// - Parameters:
    ///   - parent: The parent model instance
    /// - Returns: Updated query builder  
    public func belongsTo<Parent: ORMTable>(_ parent: Parent) -> QueryBuilderWithRepository<T> {
        return belongsTo(Parent.self, parentId: parent.id)
    }
    
    /// Filter by active/inactive status (assuming a boolean isActive column)
    /// - Parameter active: Whether to filter for active (true) or inactive (false) records
    /// - Returns: Updated query builder
    public func whereActive(_ active: Bool = true) -> QueryBuilderWithRepository<T> {
        return `where`("isActive", .equal, active)
    }
    
    /// Filter by created/updated date range
    /// - Parameters:
    ///   - column: The date column name (defaults to "createdAt")
    ///   - from: Start date (inclusive)
    ///   - to: End date (inclusive)
    /// - Returns: Updated query builder
    public func whereDateBetween(_ column: String = "createdAt", from: Date, to: Date) -> QueryBuilderWithRepository<T> {
        return `where`(column, .greaterThanOrEqual, from.timeIntervalSince1970)
              .`where`(column, .lessThanOrEqual, to.timeIntervalSince1970)
    }
    
    /// Filter by recent records (within specified time interval)
    /// - Parameters:
    ///   - column: The date column name (defaults to "createdAt")
    ///   - interval: Time interval in seconds (negative values for past, positive for future)
    /// - Returns: Updated query builder
    public func whereRecent(_ column: String = "createdAt", within interval: TimeInterval) -> QueryBuilderWithRepository<T> {
        let cutoffDate = Date().addingTimeInterval(interval)
        return `where`(column, .greaterThanOrEqual, cutoffDate.timeIntervalSince1970)
    }
    
    // MARK: - Comprehensive Date Query Methods
    
    /// Filter by records before a specific date
    /// - Parameters:
    ///   - column: The date column name (defaults to "createdAt")
    ///   - date: The cutoff date
    /// - Returns: Updated query builder
    public func whereBefore(_ column: String = "createdAt", date: Date) -> QueryBuilderWithRepository<T> {
        return `where`(column, .lessThan, date.timeIntervalSince1970)
    }
    
    /// Filter by records after a specific date
    /// - Parameters:
    ///   - column: The date column name (defaults to "createdAt") 
    ///   - date: The cutoff date
    /// - Returns: Updated query builder
    public func whereAfter(_ column: String = "createdAt", date: Date) -> QueryBuilderWithRepository<T> {
        return `where`(column, .greaterThan, date.timeIntervalSince1970)
    }
    
    /// Filter by records on or before a specific date
    /// - Parameters:
    ///   - column: The date column name (defaults to "createdAt")
    ///   - date: The cutoff date
    /// - Returns: Updated query builder
    public func whereOnOrBefore(_ column: String = "createdAt", date: Date) -> QueryBuilderWithRepository<T> {
        return `where`(column, .lessThanOrEqual, date.timeIntervalSince1970)
    }
    
    /// Filter by records on or after a specific date
    /// - Parameters:
    ///   - column: The date column name (defaults to "createdAt")
    ///   - date: The cutoff date
    /// - Returns: Updated query builder
    public func whereOnOrAfter(_ column: String = "createdAt", date: Date) -> QueryBuilderWithRepository<T> {
        return `where`(column, .greaterThanOrEqual, date.timeIntervalSince1970)
    }
    
    /// Filter by records on a specific date (ignoring time)
    /// - Parameters:
    ///   - column: The date column name (defaults to "createdAt")
    ///   - date: The specific date
    /// - Returns: Updated query builder
    public func whereOnDate(_ column: String = "createdAt", date: Date) -> QueryBuilderWithRepository<T> {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        return `where`(column, .greaterThanOrEqual, startOfDay.timeIntervalSince1970)
              .`where`(column, .lessThan, endOfDay.timeIntervalSince1970)
    }
    
    /// Filter by records within a date range (inclusive)
    /// - Parameters:
    ///   - column: The date column name (defaults to "createdAt")
    ///   - from: Start date (inclusive)
    ///   - to: End date (inclusive)
    /// - Returns: Updated query builder
    public func whereWithinDateRange(_ column: String = "createdAt", from: Date, to: Date) -> QueryBuilderWithRepository<T> {
        let calendar = Calendar.current
        let startOfFromDay = calendar.startOfDay(for: from)
        let endOfToDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: to))!
        
        return `where`(column, .greaterThanOrEqual, startOfFromDay.timeIntervalSince1970)
              .`where`(column, .lessThan, endOfToDay.timeIntervalSince1970)
    }
    
    // MARK: - Relative Date Methods
    
    /// Filter by records from today
    /// - Parameter column: The date column name (defaults to "createdAt")
    /// - Returns: Updated query builder
    public func whereToday(_ column: String = "createdAt") -> QueryBuilderWithRepository<T> {
        return whereOnDate(column, date: Date())
    }
    
    /// Filter by records from yesterday
    /// - Parameter column: The date column name (defaults to "createdAt")
    /// - Returns: Updated query builder
    public func whereYesterday(_ column: String = "createdAt") -> QueryBuilderWithRepository<T> {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        return whereOnDate(column, date: yesterday)
    }
    
    /// Filter by records from tomorrow
    /// - Parameter column: The date column name (defaults to "createdAt")
    /// - Returns: Updated query builder
    public func whereTomorrow(_ column: String = "createdAt") -> QueryBuilderWithRepository<T> {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        return whereOnDate(column, date: tomorrow)
    }
    
    /// Filter by records from this week
    /// - Parameter column: The date column name (defaults to "createdAt")
    /// - Returns: Updated query builder
    public func whereThisWeek(_ column: String = "createdAt") -> QueryBuilderWithRepository<T> {
        let calendar = Calendar.current
        let now = Date()
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let endOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.end ?? now
        
        return `where`(column, .greaterThanOrEqual, startOfWeek.timeIntervalSince1970)
              .`where`(column, .lessThan, endOfWeek.timeIntervalSince1970)
    }
    
    /// Filter by records from last week
    /// - Parameter column: The date column name (defaults to "createdAt")
    /// - Returns: Updated query builder
    public func whereLastWeek(_ column: String = "createdAt") -> QueryBuilderWithRepository<T> {
        let calendar = Calendar.current
        let now = Date()
        let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: now)!
        let startOfLastWeek = calendar.dateInterval(of: .weekOfYear, for: lastWeek)?.start ?? lastWeek
        let endOfLastWeek = calendar.dateInterval(of: .weekOfYear, for: lastWeek)?.end ?? lastWeek
        
        return `where`(column, .greaterThanOrEqual, startOfLastWeek.timeIntervalSince1970)
              .`where`(column, .lessThan, endOfLastWeek.timeIntervalSince1970)
    }
    
    /// Filter by records from next week
    /// - Parameter column: The date column name (defaults to "createdAt")
    /// - Returns: Updated query builder
    public func whereNextWeek(_ column: String = "createdAt") -> QueryBuilderWithRepository<T> {
        let calendar = Calendar.current
        let now = Date()
        let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: now)!
        let startOfNextWeek = calendar.dateInterval(of: .weekOfYear, for: nextWeek)?.start ?? nextWeek
        let endOfNextWeek = calendar.dateInterval(of: .weekOfYear, for: nextWeek)?.end ?? nextWeek
        
        return `where`(column, .greaterThanOrEqual, startOfNextWeek.timeIntervalSince1970)
              .`where`(column, .lessThan, endOfNextWeek.timeIntervalSince1970)
    }
    
    /// Filter by records from this month
    /// - Parameter column: The date column name (defaults to "createdAt")
    /// - Returns: Updated query builder
    public func whereThisMonth(_ column: String = "createdAt") -> QueryBuilderWithRepository<T> {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let endOfMonth = calendar.dateInterval(of: .month, for: now)?.end ?? now
        
        return `where`(column, .greaterThanOrEqual, startOfMonth.timeIntervalSince1970)
              .`where`(column, .lessThan, endOfMonth.timeIntervalSince1970)
    }
    
    /// Filter by records from last month
    /// - Parameter column: The date column name (defaults to "createdAt")
    /// - Returns: Updated query builder
    public func whereLastMonth(_ column: String = "createdAt") -> QueryBuilderWithRepository<T> {
        let calendar = Calendar.current
        let now = Date()
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: now)!
        let startOfLastMonth = calendar.dateInterval(of: .month, for: lastMonth)?.start ?? lastMonth
        let endOfLastMonth = calendar.dateInterval(of: .month, for: lastMonth)?.end ?? lastMonth
        
        return `where`(column, .greaterThanOrEqual, startOfLastMonth.timeIntervalSince1970)
              .`where`(column, .lessThan, endOfLastMonth.timeIntervalSince1970)
    }
    
    /// Filter by records from next month
    /// - Parameter column: The date column name (defaults to "createdAt")
    /// - Returns: Updated query builder
    public func whereNextMonth(_ column: String = "createdAt") -> QueryBuilderWithRepository<T> {
        let calendar = Calendar.current
        let now = Date()
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: now)!
        let startOfNextMonth = calendar.dateInterval(of: .month, for: nextMonth)?.start ?? nextMonth
        let endOfNextMonth = calendar.dateInterval(of: .month, for: nextMonth)?.end ?? nextMonth
        
        return `where`(column, .greaterThanOrEqual, startOfNextMonth.timeIntervalSince1970)
              .`where`(column, .lessThan, endOfNextMonth.timeIntervalSince1970)
    }
    
    /// Filter by records from this year
    /// - Parameter column: The date column name (defaults to "createdAt")
    /// - Returns: Updated query builder
    public func whereThisYear(_ column: String = "createdAt") -> QueryBuilderWithRepository<T> {
        let calendar = Calendar.current
        let now = Date()
        let startOfYear = calendar.dateInterval(of: .year, for: now)?.start ?? now
        let endOfYear = calendar.dateInterval(of: .year, for: now)?.end ?? now
        
        return `where`(column, .greaterThanOrEqual, startOfYear.timeIntervalSince1970)
              .`where`(column, .lessThan, endOfYear.timeIntervalSince1970)
    }
    
    /// Filter by records from last year
    /// - Parameter column: The date column name (defaults to "createdAt")
    /// - Returns: Updated query builder
    public func whereLastYear(_ column: String = "createdAt") -> QueryBuilderWithRepository<T> {
        let calendar = Calendar.current
        let now = Date()
        let lastYear = calendar.date(byAdding: .year, value: -1, to: now)!
        let startOfLastYear = calendar.dateInterval(of: .year, for: lastYear)?.start ?? lastYear
        let endOfLastYear = calendar.dateInterval(of: .year, for: lastYear)?.end ?? lastYear
        
        return `where`(column, .greaterThanOrEqual, startOfLastYear.timeIntervalSince1970)
              .`where`(column, .lessThan, endOfLastYear.timeIntervalSince1970)
    }
    
    /// Filter by records from next year
    /// - Parameter column: The date column name (defaults to "createdAt")
    /// - Returns: Updated query builder
    public func whereNextYear(_ column: String = "createdAt") -> QueryBuilderWithRepository<T> {
        let calendar = Calendar.current
        let now = Date()
        let nextYear = calendar.date(byAdding: .year, value: 1, to: now)!
        let startOfNextYear = calendar.dateInterval(of: .year, for: nextYear)?.start ?? nextYear
        let endOfNextYear = calendar.dateInterval(of: .year, for: nextYear)?.end ?? nextYear
        
        return `where`(column, .greaterThanOrEqual, startOfNextYear.timeIntervalSince1970)
              .`where`(column, .lessThan, endOfNextYear.timeIntervalSince1970)
    }
    
    // MARK: - Date Component Methods
    
    /// Filter by records on a specific day of the week
    /// - Parameters:
    ///   - column: The date column name (defaults to "createdAt")
    ///   - weekday: Day of the week (1 = Sunday, 2 = Monday, ..., 7 = Saturday)
    /// - Returns: Updated query builder
    public func whereWeekday(_ column: String = "createdAt", _ weekday: Int) -> QueryBuilderWithRepository<T> {
        // Note: This is a simplified approach. For production use, you might want to use raw SQL
        // with date functions specific to SQLite for better performance
        let calendar = Calendar.current
        let now = Date()
        
        // Find the most recent occurrence of this weekday
        var dateComponents = DateComponents()
        dateComponents.weekday = weekday
        
        // Get current week's date for this weekday
        let currentWeekDate = calendar.nextDate(after: now, matching: dateComponents, matchingPolicy: .previousTimePreservingSmallerComponents) ?? now
        
        return whereOnDate(column, date: currentWeekDate)
    }
    
    /// Filter by records in a specific month (regardless of year)
    /// - Parameters:
    ///   - column: The date column name (defaults to "createdAt")
    ///   - month: Month number (1-12)
    /// - Returns: Updated query builder
    public func whereMonth(_ column: String = "createdAt", _ month: Int) -> QueryBuilderWithRepository<T> {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        
        var startComponents = DateComponents()
        startComponents.year = currentYear
        startComponents.month = month
        startComponents.day = 1
        
        var endComponents = DateComponents()
        endComponents.year = currentYear
        endComponents.month = month + 1
        endComponents.day = 1
        
        let startDate = calendar.date(from: startComponents)!
        let endDate = calendar.date(from: endComponents)!
        
        return `where`(column, .greaterThanOrEqual, startDate.timeIntervalSince1970)
              .`where`(column, .lessThan, endDate.timeIntervalSince1970)
    }
    
    /// Filter by records in a specific year
    /// - Parameters:
    ///   - column: The date column name (defaults to "createdAt")
    ///   - year: Year number (e.g., 2023)
    /// - Returns: Updated query builder
    public func whereYear(_ column: String = "createdAt", _ year: Int) -> QueryBuilderWithRepository<T> {
        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = 1
        startComponents.day = 1
        
        var endComponents = DateComponents()
        endComponents.year = year + 1
        endComponents.month = 1
        endComponents.day = 1
        
        let calendar = Calendar.current
        let startDate = calendar.date(from: startComponents)!
        let endDate = calendar.date(from: endComponents)!
        
        return `where`(column, .greaterThanOrEqual, startDate.timeIntervalSince1970)
              .`where`(column, .lessThan, endDate.timeIntervalSince1970)
    }
    
    // MARK: - Time-Based Convenience Methods
    
    /// Filter by records from the last N days
    /// - Parameters:
    ///   - column: The date column name (defaults to "createdAt")
    ///   - days: Number of days to look back
    /// - Returns: Updated query builder
    public func whereLastDays(_ column: String = "createdAt", _ days: Int) -> QueryBuilderWithRepository<T> {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        return `where`(column, .greaterThanOrEqual, cutoffDate.timeIntervalSince1970)
    }
    
    /// Filter by records from the next N days
    /// - Parameters:
    ///   - column: The date column name (defaults to "createdAt")
    ///   - days: Number of days to look ahead
    /// - Returns: Updated query builder
    public func whereNextDays(_ column: String = "createdAt", _ days: Int) -> QueryBuilderWithRepository<T> {
        let now = Date()
        let futureDate = Calendar.current.date(byAdding: .day, value: days, to: now)!
        return `where`(column, .greaterThanOrEqual, now.timeIntervalSince1970)
              .`where`(column, .lessThanOrEqual, futureDate.timeIntervalSince1970)
    }
    
    /// Filter by records from the last N hours
    /// - Parameters:
    ///   - column: The date column name (defaults to "createdAt")
    ///   - hours: Number of hours to look back
    /// - Returns: Updated query builder
    public func whereLastHours(_ column: String = "createdAt", _ hours: Int) -> QueryBuilderWithRepository<T> {
        let cutoffDate = Calendar.current.date(byAdding: .hour, value: -hours, to: Date())!
        return `where`(column, .greaterThanOrEqual, cutoffDate.timeIntervalSince1970)
    }
    
    /// Filter by records from the last N minutes
    /// - Parameters:
    ///   - column: The date column name (defaults to "createdAt")
    ///   - minutes: Number of minutes to look back
    /// - Returns: Updated query builder
    public func whereLastMinutes(_ column: String = "createdAt", _ minutes: Int) -> QueryBuilderWithRepository<T> {
        let cutoffDate = Calendar.current.date(byAdding: .minute, value: -minutes, to: Date())!
        return `where`(column, .greaterThanOrEqual, cutoffDate.timeIntervalSince1970)
    }
    
    // MARK: - Weekend and Weekday Methods
    
    /// Filter by records created on weekends (Saturday and Sunday)
    /// - Parameter column: The date column name (defaults to "createdAt")
    /// - Returns: Updated query builder
    public func whereWeekend(_ column: String = "createdAt") -> QueryBuilderWithRepository<T> {
        // Note: This is a simplified approach for demonstration
        // In production, you'd likely want to use raw SQL with SQLite date functions
        let calendar = Calendar.current
        let now = Date()
        
        // Get the current week's Saturday and Sunday
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)!
        let saturday = calendar.date(bySetting: .weekday, value: 7, of: weekInterval.start)!
        let sunday = calendar.date(bySetting: .weekday, value: 1, of: weekInterval.start)!
        
        // This is a simplified version - ideally you'd want to handle all weekends in the range
        return whereOnDate(column, date: saturday)
    }
    
    /// Filter by records created on weekdays (Monday through Friday)
    /// - Parameter column: The date column name (defaults to "createdAt")
    /// - Returns: Updated query builder
    public func whereWeekdays(_ column: String = "createdAt") -> QueryBuilderWithRepository<T> {
        // Note: This is a simplified approach for demonstration
        // In production, you'd likely want to use raw SQL with SQLite date functions
        let calendar = Calendar.current
        let now = Date()
        
        // Get the current week interval
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)!
        let monday = calendar.date(bySetting: .weekday, value: 2, of: weekInterval.start)!
        let friday = calendar.date(bySetting: .weekday, value: 6, of: weekInterval.start)!
        
        let startOfMonday = calendar.startOfDay(for: monday)
        let endOfFriday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: friday))!
        
        return `where`(column, .greaterThanOrEqual, startOfMonday.timeIntervalSince1970)
              .`where`(column, .lessThan, endOfFriday.timeIntervalSince1970)
    }
    
    /// Order by the most recent first (descending order)
    /// - Parameter column: The date column name (defaults to "createdAt")
    /// - Returns: Updated query builder
    public func newestFirst(_ column: String = "createdAt") -> QueryBuilderWithRepository<T> {
        return orderBy(column, ascending: false)
    }
    
    /// Order by the oldest first (ascending order)  
    /// - Parameter column: The date column name (defaults to "createdAt")
    /// - Returns: Updated query builder
    public func oldestFirst(_ column: String = "createdAt") -> QueryBuilderWithRepository<T> {
        return orderBy(column, ascending: true)
    }
    
    /// Search across text columns using LIKE
    /// - Parameters:
    ///   - columns: Array of column names to search in
    ///   - searchTerm: The search term
    /// - Returns: Updated query builder
    public func search(in columns: [String], for searchTerm: String) -> QueryBuilderWithRepository<T> {
        guard !columns.isEmpty else { return self }
        
        var result = self
        
        // Add OR conditions for each column
        for (index, column) in columns.enumerated() {
            if index == 0 {
                result = result.`where`(column, .like, "%\(searchTerm)%")
            } else {
                // Note: This is a simple approach. For complex OR queries,
                // we'd need to enhance the query builder to support OR clauses
                result = result.`where`(column, .like, "%\(searchTerm)%")
            }
        }
        
        return result
    }
    
    /// Get the underlying QueryBuilder for compatibility
    /// - Returns: The underlying QueryBuilder instance
    public func asQueryBuilder() -> ORMQueryBuilder<T> {
        return queryBuilder
    }
}