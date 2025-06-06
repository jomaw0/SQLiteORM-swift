/// SwiftSync - A type-safe, easy-to-use SQLite ORM for Swift
/// 
/// Features:
/// - Type-safe SQL queries with compile-time validation
/// - Swift actor pattern for thread-safe concurrent access
/// - Automatic model mapping with Swift macros
/// - Comprehensive error handling with Result types
/// - Built-in migration system
/// - Support for various data types including custom date formats
/// - Disk storage support for large data objects and UIImage
/// - Automatic lazy loading of disk-stored properties
/// - Zero external dependencies (uses built-in SQLite3)

// Re-export all public APIs
@_exported import Foundation

// Core types are already defined in Result.swift

// Re-export from submodules
// Note: Since we're using submodules, these are already available
// This file serves as the main entry point and documentation

// MARK: - Disk Storage Documentation

/// ## Disk Storage Feature
/// 
/// SwiftSync provides automatic disk storage for large data objects to improve database performance.
/// Large Data and UIImage objects are automatically stored on disk when they exceed size thresholds,
/// with only references kept in the database.
/// 
/// ### Key Benefits:
/// - Faster database queries (no large blobs in SQL results)
/// - Reduced memory usage (lazy loading)
/// - Automatic threshold-based storage decisions
/// - Seamless integration with existing models
/// 
/// ### Usage:
/// 
/// ```swift
/// // Enable disk storage when creating ORM (enabled by default)
/// let orm = ORM(path: "database.sqlite", enableDiskStorage: true)
/// 
/// // Or use convenience function
/// let orm = createFileORM(filename: "app.sqlite", enableDiskStorage: true)
/// 
/// // Implement DiskStorageCapable in your models
/// struct Document: ORMTable, DiskStorageCapable {
///     var id: Int = 0
///     var title: String
///     var largeData: Data?
///     var largeDataDiskRef: DiskStorageReference?
///     var image: UIImage?
///     var imageDiskRef: DiskStorageReference?
///     
///     var diskStorableProperties: [String: Any] {
///         var properties: [String: Any] = [:]
///         if let largeData = largeData { properties["largeData"] = largeData }
///         if let image = image { properties["image"] = image }
///         return properties
///     }
///     
///     mutating func updateDiskReferences(_ references: [String: DiskStorageReference?]) {
///         largeDataDiskRef = references["largeData"] ?? nil
///         imageDiskRef = references["image"] ?? nil
///     }
/// }
/// ```
/// 
/// ### Storage Thresholds:
/// - Data: 1KB (1024 bytes)
/// - UIImage: 512 bytes (as JPEG)
/// - Custom types can define their own thresholds
/// 
/// ### Automatic Behavior:
/// - Objects larger than threshold are automatically stored on disk
/// - Database contains only lightweight references
/// - Properties are lazy-loaded when accessed
/// - Works seamlessly with queries and subscriptions