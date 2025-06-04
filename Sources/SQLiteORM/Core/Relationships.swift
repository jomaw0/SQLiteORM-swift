import Foundation

// MARK: - Relationship Types

/// Protocol for models that support lazy loading of relationships
public protocol RelationshipCapable: Model {
    /// Load all relationships for this model instance
    mutating func loadRelationships() async throws
}

/// Default implementation for RelationshipCapable
public extension RelationshipCapable {
    mutating func loadRelationships() async throws {
        // Default implementation does nothing
        // Specific models can override this to load their relationships
    }
}

// MARK: - Lazy Loading Property Wrapper

/// Property wrapper for lazy-loaded relationships
@propertyWrapper
public struct LazyRelationship<T: Model> {
    private var _value: T?
    private let loadFunction: () async throws -> T?
    
    public var wrappedValue: T? {
        get {
            return _value
        }
        set {
            _value = newValue
        }
    }
    
    /// Load the relationship asynchronously
    public mutating func load() async throws -> T? {
        if let value = _value {
            return value
        }
        
        let loaded = try await loadFunction()
        _value = loaded
        return loaded
    }
    
    /// Direct access to the cached value without loading
    public var cachedValue: T? {
        return _value
    }
    
    /// Check if the relationship has been loaded
    public var isLoaded: Bool {
        return _value != nil
    }
    
    /// Initialize with a loading function
    public init(loader: @escaping () async throws -> T?) {
        self.loadFunction = loader
        self._value = nil
    }
    
    /// Initialize with a pre-loaded value
    public init(value: T?) {
        self._value = value
        self.loadFunction = { return value }
    }
}

/// Property wrapper for lazy-loaded array relationships
@propertyWrapper
public struct LazyRelationshipArray<T: Model> {
    private var _value: [T]?
    private let loadFunction: () async throws -> [T]
    
    public var wrappedValue: [T] {
        get {
            return _value ?? []
        }
        set {
            _value = newValue
        }
    }
    
    /// Load the relationship asynchronously
    public mutating func load() async throws -> [T] {
        if let value = _value {
            return value
        }
        
        let loaded = try await loadFunction()
        _value = loaded
        return loaded
    }
    
    /// Direct access to the cached value without loading
    public var cachedValue: [T]? {
        return _value
    }
    
    /// Check if the relationship has been loaded
    public var isLoaded: Bool {
        return _value != nil
    }
    
    /// Initialize with a loading function
    public init(loader: @escaping () async throws -> [T]) {
        self.loadFunction = loader
        self._value = nil
    }
    
    /// Initialize with pre-loaded values
    public init(value: [T]) {
        self._value = value
        self.loadFunction = { return value }
    }
}

// MARK: - Relationship Configuration

/// Configuration for a belongs-to relationship
public struct BelongsToConfig<T: Model>: Sendable {
    public let relatedType: T.Type
    public let foreignKey: String
    
    public init(relatedType: T.Type, foreignKey: String) {
        self.relatedType = relatedType
        self.foreignKey = foreignKey
    }
}

/// Configuration for a has-many relationship
public struct HasManyConfig<T: Model>: Sendable {
    public let relatedType: T.Type
    public let foreignKey: String
    
    public init(relatedType: T.Type, foreignKey: String) {
        self.relatedType = relatedType
        self.foreignKey = foreignKey
    }
}

/// Configuration for a has-one relationship
public struct HasOneConfig<T: Model>: Sendable {
    public let relatedType: T.Type
    public let foreignKey: String
    
    public init(relatedType: T.Type, foreignKey: String) {
        self.relatedType = relatedType
        self.foreignKey = foreignKey
    }
}

/// Configuration for a many-to-many relationship
public struct ManyToManyConfig<T: Model>: Sendable {
    public let relatedType: T.Type
    public let junctionTable: String
    public let localKey: String
    public let foreignKey: String
    
    public init(relatedType: T.Type, junctionTable: String, localKey: String, foreignKey: String) {
        self.relatedType = relatedType
        self.junctionTable = junctionTable
        self.localKey = localKey
        self.foreignKey = foreignKey
    }
}

// MARK: - Relationship Manager

/// Manages relationship loading for models
public actor RelationshipManager {
    private let orm: ORM
    
    public init(orm: ORM) {
        self.orm = orm
    }
    
    /// Load a belongs-to relationship
    public func loadBelongsTo<Owner: Model, Related: Model>(
        for owner: Owner,
        config: BelongsToConfig<Related>
    ) async -> ORMResult<Related?> {
        let repository = await orm.repository(for: config.relatedType)
        
        // Get the foreign key value from the owner
        let mirror = Mirror(reflecting: owner)
        guard let foreignKeyProperty = mirror.children.first(where: { $0.label == config.foreignKey }) else {
            return .failure(.notFound(entity: "Property", id: config.foreignKey))
        }
        
        guard let foreignKeyValue = foreignKeyProperty.value as? Int, foreignKeyValue > 0 else {
            return .success(nil)
        }
        
        return await repository.find(id: foreignKeyValue as! Related.IDType)
    }
    
    /// Load a has-many relationship
    public func loadHasMany<Owner: Model, Related: Model>(
        for owner: Owner,
        config: HasManyConfig<Related>
    ) async -> ORMResult<[Related]> {
        let repository = await orm.repository(for: config.relatedType)
        let ownerIdValue = owner.id
        
        let query = QueryBuilder<Related>()
            .where(config.foreignKey, .equal, ownerIdValue as? SQLiteConvertible)
        
        return await repository.findAll(query: query)
    }
    
    /// Load a has-one relationship
    public func loadHasOne<Owner: Model, Related: Model>(
        for owner: Owner,
        config: HasOneConfig<Related>
    ) async -> ORMResult<Related?> {
        let repository = await orm.repository(for: config.relatedType)
        let ownerIdValue = owner.id
        
        let query = QueryBuilder<Related>()
            .where(config.foreignKey, .equal, ownerIdValue as? SQLiteConvertible)
            .limit(1)
        
        let result = await repository.findAll(query: query)
        return result.map { $0.first }
    }
    
    /// Load a many-to-many relationship
    public func loadManyToMany<Owner: Model, Related: Model>(
        for owner: Owner,
        config: ManyToManyConfig<Related>
    ) async -> ORMResult<[Related]> {
        // This would require raw SQL execution for JOIN queries
        // For now, return empty array as placeholder
        return .success([])
    }
}