import Foundation

/// The core protocol that all ORM models must conform to
/// Provides automatic SQL generation and type-safe database operations
public protocol Model: Codable, Sendable {
    /// The type used for the primary key
    associatedtype IDType: Codable & Sendable & LosslessStringConvertible & Equatable
    
    /// The primary key property
    var id: IDType { get set }
    
    /// The name of the table in the database
    /// Defaults to the pluralized type name
    static var tableName: String { get }
    
    /// Custom column mappings if property names differ from column names
    /// Returns nil by default, meaning property names match column names
    static var columnMappings: [String: String]? { get }
    
    /// Indexes to be created for this table
    static var indexes: [Index] { get }
    
    /// Unique constraints for the table
    static var uniqueConstraints: [UniqueConstraint] { get }
}

/// Default implementations for Model protocol
public extension Model {
    static var tableName: String {
        String(describing: Self.self).pluralized()
    }
    
    static var columnMappings: [String: String]? { nil }
    
    static var indexes: [Index] { [] }
    
    static var uniqueConstraints: [UniqueConstraint] { [] }
}

/// Represents a database index
public struct Index: Sendable {
    public let name: String
    public let columns: [String]
    public let unique: Bool
    
    public init(name: String, columns: [String], unique: Bool = false) {
        self.name = name
        self.columns = columns
        self.unique = unique
    }
}

/// Represents a unique constraint
public struct UniqueConstraint: Sendable {
    public let name: String
    public let columns: [String]
    
    public init(name: String, columns: [String]) {
        self.name = name
        self.columns = columns
    }
}

/// Protocol for models that track creation and update timestamps
public protocol Timestamped {
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
}

/// Protocol for soft-deletable models
public protocol SoftDeletable {
    var deletedAt: Date? { get set }
}

/// String extension for basic pluralization
private extension String {
    func pluralized() -> String {
        if self.hasSuffix("y") {
            return String(self.dropLast()) + "ies"
        } else if self.hasSuffix("s") || self.hasSuffix("x") || self.hasSuffix("z") ||
                  self.hasSuffix("ch") || self.hasSuffix("sh") {
            return self + "es"
        } else {
            return self + "s"
        }
    }
}