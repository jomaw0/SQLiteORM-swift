import Foundation

/// Status of synchronization for a model
public enum SyncStatus: String, Codable, CaseIterable, Sendable {
    case synced = "synced"
    case pending = "pending"
    case syncing = "syncing"
    case failed = "failed"
    case conflict = "conflict"
}

/// The core protocol that all ORM tables must conform to
/// Provides automatic SQL generation and type-safe database operations
/// All ORMTable types are automatically syncable
public protocol ORMTable: Codable, Sendable, Identifiable, Hashable {
    /// The type used for the primary key
    associatedtype IDType: Codable & Sendable & LosslessStringConvertible & Equatable & Hashable
    
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
    
    // MARK: - Sync Properties (automatically included in all models)
    // Note: These are optional protocol requirements with default implementations
    
    /// Timestamp of last successful sync
    var lastSyncTimestamp: Date? { get set }
    
    /// Whether this model has local changes that need to be synchronized
    var isDirty: Bool { get set }
    
    /// Current synchronization status
    var syncStatus: SyncStatus { get set }
    
    /// Server-side identifier (may differ from local ID)
    var serverID: String? { get set }
    
    /// Unique identifier for conflict resolution (defaults to encoded JSON hash)
    var conflictFingerprint: String { get }
}

/// Default implementations for ORMTable protocol
public extension ORMTable {
    static var tableName: String {
        String(describing: Self.self).pluralized()
    }
    
    static var columnMappings: [String: String]? { nil }
    
    static var indexes: [ORMIndex] { [] }
    
    static var uniqueConstraints: [ORMUniqueConstraint] { [] }
    
    // MARK: - Hashable Implementation
    
    /// Default hash implementation based on all Codable properties
    /// Uses the encoded representation to ensure all properties are included
    func hash(into hasher: inout Hasher) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            encoder.dateEncodingStrategy = .secondsSince1970
            let data = try encoder.encode(self)
            hasher.combine(data)
        } catch {
            // Fallback to ID-based hashing if encoding fails
            hasher.combine(self.id)
        }
    }
    
    // MARK: - Equatable Implementation
    
    /// Default equality implementation based on all Codable properties
    /// Two models are considered equal if all their encoded properties are equal
    static func == (lhs: Self, rhs: Self) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            encoder.dateEncodingStrategy = .secondsSince1970
            
            let lhsData = try encoder.encode(lhs)
            let rhsData = try encoder.encode(rhs)
            
            return lhsData == rhsData
        } catch {
            // Fallback to ID-based comparison if encoding fails
            return lhs.id == rhs.id
        }
    }
    
    // MARK: - Default Sync Implementations
    
    /// Default sync property implementations for models that don't explicitly implement them
    /// These can be overridden by models that explicitly declare these properties
    var lastSyncTimestamp: Date? {
        get { nil }
        set { /* Default implementation does nothing */ }
    }
    
    var isDirty: Bool {
        get { false }
        set { /* Default implementation does nothing */ }
    }
    
    var syncStatus: SyncStatus {
        get { .synced }
        set { /* Default implementation does nothing */ }
    }
    
    var serverID: String? {
        get { nil }
        set { /* Default implementation does nothing */ }
    }
    
    /// Default conflict fingerprint based on encoded model data
    /// Uses the Codable protocol to generate a fingerprint from all model properties
    var conflictFingerprint: String {
        // Use Codable to capture all properties of the model
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys // Ensure consistent ordering
            encoder.dateEncodingStrategy = .secondsSince1970
            let data = try encoder.encode(self)
            
            // Create a hash of the encoded data
            return data.base64EncodedString().hashValue.description
        } catch {
            // Fallback to simple fingerprint if encoding fails
            let idString = String(describing: self.id)
            let statusString = self.syncStatus.rawValue
            let timestamp = self.lastSyncTimestamp?.timeIntervalSince1970.description ?? "nil"
            let combined = "\(idString)_\(statusString)_\(timestamp)"
            return String(combined.hashValue)
        }
    }
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