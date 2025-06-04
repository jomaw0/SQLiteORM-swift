import Foundation

/// The core protocol that all ORM tables must conform to
/// Provides automatic SQL generation and type-safe database operations
public protocol ORMTable: Codable, Sendable {
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
    static var indexes: [ORMIndex] { get }
    
    /// Unique constraints for the table
    static var uniqueConstraints: [ORMUniqueConstraint] { get }
}

/// Default implementations for ORMTable protocol
public extension ORMTable {
    static var tableName: String {
        String(describing: Self.self).pluralized()
    }
    
    static var columnMappings: [String: String]? { nil }
    
    static var indexes: [ORMIndex] { [] }
    
    static var uniqueConstraints: [ORMUniqueConstraint] { [] }
}

/// Represents a database index
public struct ORMIndex: Sendable {
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
public struct ORMUniqueConstraint: Sendable {
    public let name: String
    public let columns: [String]
    
    public init(name: String, columns: [String]) {
        self.name = name
        self.columns = columns
    }
}

/// Protocol for tables that track creation and update timestamps
public protocol ORMTimestamped {
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
}

/// Protocol for soft-deletable tables
public protocol ORMSoftDeletable {
    var deletedAt: Date? { get set }
}

// MARK: - Backward Compatibility

/// Backward compatibility alias
@available(*, deprecated, renamed: "ORMTable")
public typealias Model = ORMTable

/// Backward compatibility alias
@available(*, deprecated, renamed: "ORMIndex")
public typealias Index = ORMIndex

/// Backward compatibility alias
@available(*, deprecated, renamed: "ORMUniqueConstraint")
public typealias UniqueConstraint = ORMUniqueConstraint

/// Backward compatibility alias
@available(*, deprecated, renamed: "ORMTimestamped")
public typealias Timestamped = ORMTimestamped

/// Backward compatibility alias
@available(*, deprecated, renamed: "ORMSoftDeletable")
public typealias SoftDeletable = ORMSoftDeletable

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