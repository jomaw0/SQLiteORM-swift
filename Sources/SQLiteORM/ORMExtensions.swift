import Foundation

/// Extensions to ORM for enhanced query support
public extension ORM {
    /// Create a query for a model type
    /// - Parameter type: The model type to query
    /// - Returns: A new Query instance
    func query<T: Model>(_ type: T.Type) async -> Query<T> {
        let repository = self.repository(for: type)
        return Query(modelType: type, repository: repository)
    }
    
    /// Execute a query directly
    /// - Parameter query: The query to execute
    /// - Returns: Result containing array of models
    func execute<T: Model>(_ query: Query<T>) async -> ORMResult<[T]> {
        await query.fetch()
    }
    
    /// Execute a query and get the first result
    /// - Parameter query: The query to execute
    /// - Returns: Result containing the first model or nil
    func executeFirst<T: Model>(_ query: Query<T>) async -> ORMResult<T?> {
        await query.fetchFirst()
    }
    
    /// Execute a count query
    /// - Parameter query: The query to execute
    /// - Returns: Result containing the count
    func executeCount<T: Model>(_ query: Query<T>) async -> ORMResult<Int> {
        await query.count()
    }
}