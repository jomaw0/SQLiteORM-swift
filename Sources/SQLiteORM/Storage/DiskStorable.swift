import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Protocol for properties that can be stored on disk instead of in the database
public protocol DiskStorable {
    /// Convert to data for disk storage
    func diskData() throws -> Data
    
    /// Create from disk data
    static func fromDiskData(_ data: Data) throws -> Self
    
    /// Minimum size threshold for disk storage (bytes)
    static var diskStorageThreshold: Int { get }
}

/// Default implementations
public extension DiskStorable {
    static var diskStorageThreshold: Int { 1024 } // 1KB default
}

/// Data conformance to DiskStorable
extension Data: DiskStorable {
    public func diskData() throws -> Data {
        return self
    }
    
    public static func fromDiskData(_ data: Data) throws -> Data {
        return data
    }
    
    public static var diskStorageThreshold: Int { 1024 }
}

#if canImport(UIKit)
/// UIImage conformance to DiskStorable
extension UIImage: DiskStorable {
    public func diskData() throws -> Data {
        guard let data = self.jpegData(compressionQuality: 0.8) else {
            throw DiskStorageError.imageConversionFailed
        }
        return data
    }
    
    public static func fromDiskData(_ data: Data) throws -> Self {
        guard let image = Self(data: data) else {
            throw DiskStorageError.imageConversionFailed
        }
        return image
    }
    
    public static var diskStorageThreshold: Int { 512 } // 512 bytes for images
}
#endif

/// Property wrapper for automatic disk storage
@propertyWrapper
public struct DiskStored<T: DiskStorable & Codable> {
    private var _value: T?
    private var _reference: DiskStorageReference?
    
    public var wrappedValue: T? {
        get {
            if let value = _value {
                return value
            }
            
            // For now, just return nil if not loaded
            // Lazy loading will be handled by the Repository
            return nil
        }
        set {
            _value = newValue
            // Disk storage will be handled by the Repository during save operations
        }
    }
    
    /// The disk storage reference (for database storage)
    public var diskReference: DiskStorageReference? {
        get { _reference }
        set { _reference = newValue }
    }
    
    public init() {
        self._value = nil
        self._reference = nil
    }
}

/// Protocol for models that support disk storage
public protocol DiskStorageCapable: Model {
    /// The disk storage manager for this model
    static var diskStorageManager: DiskStorageManager? { get set }
    
    /// Properties that should be considered for disk storage
    var diskStorableProperties: [String: Any] { get }
    
    /// Update disk references after database operations
    mutating func updateDiskReferences(_ references: [String: DiskStorageReference?])
}

/// Default implementation
public extension DiskStorageCapable {
    static var diskStorageManager: DiskStorageManager? {
        get { nil }
        set { }
    }
    
    var diskStorableProperties: [String: Any] { [:] }
    
    mutating func updateDiskReferences(_ references: [String: DiskStorageReference?]) {
        // Default implementation does nothing
        // Override in concrete types to update @DiskStored properties
    }
}