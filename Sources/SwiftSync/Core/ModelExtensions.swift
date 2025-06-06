import Foundation

/// Extensions to ORMTable protocol for query building
public extension ORMTable {
    /// Create a query for this model type
    /// - Parameter orm: The ORM instance to use for execution
    /// - Returns: A new Query instance
    static func query(using orm: ORM) async -> Query<Self> {
        let repository = await orm.repository(for: Self.self)
        return Query(modelType: Self.self, repository: repository)
    }
    
    /// Find a model by ID
    /// - Parameters:
    ///   - id: The ID to search for
    ///   - orm: The ORM instance to use
    /// - Returns: Result containing the model or nil
    static func find(_ id: IDType, using orm: ORM) async -> ORMResult<Self?> {
        let repository = await orm.repository(for: Self.self)
        return await repository.find(id: id)
    }
    
    /// Find all models
    /// - Parameter orm: The ORM instance to use
    /// - Returns: Result containing array of models
    static func all(using orm: ORM) async -> ORMResult<[Self]> {
        let repository = await orm.repository(for: Self.self)
        return await repository.findAll()
    }
    
    /// Count all models
    /// - Parameter orm: The ORM instance to use
    /// - Returns: Result containing the count
    static func count(using orm: ORM) async -> ORMResult<Int> {
        let repository = await orm.repository(for: Self.self)
        return await repository.count()
    }
    
    /// Create a new query with a WHERE predicate
    /// - Parameters:
    ///   - predicate: The WHERE predicate
    ///   - orm: The ORM instance to use
    /// - Returns: A new Query instance
    static func `where`(_ predicate: Predicate, using orm: ORM) async -> Query<Self> {
        await query(using: orm).where(predicate)
    }
    
    /// Delete all models matching a predicate
    /// - Parameters:
    ///   - predicate: The WHERE predicate
    ///   - orm: The ORM instance to use
    /// - Returns: Result with number of deleted rows
    static func deleteWhere(_ predicate: Predicate, using orm: ORM) async -> ORMResult<Int> {
        await query(using: orm).where(predicate).delete()
    }
}

/// Instance methods for models
public extension ORMTable {
    /// Save this model (insert or update)
    /// - Parameter orm: The ORM instance to use
    /// - Returns: Result containing the saved model
    mutating func save(using orm: ORM) async -> ORMResult<Self> {
        let repository = await orm.repository(for: Self.self)
        return await repository.save(&self)
    }
    
    /// Delete this model
    /// - Parameter orm: The ORM instance to use
    /// - Returns: Result with number of deleted rows
    func delete(using orm: ORM) async -> ORMResult<Int> {
        let repository = await orm.repository(for: Self.self)
        return await repository.delete(id: self.id)
    }
    
    /// Reload this model from the database
    /// - Parameter orm: The ORM instance to use
    /// - Returns: Result containing the reloaded model
    func reload(using orm: ORM) async -> ORMResult<Self?> {
        let repository = await orm.repository(for: Self.self)
        return await repository.find(id: self.id)
    }
}