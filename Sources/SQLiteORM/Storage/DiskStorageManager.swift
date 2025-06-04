import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Actor that manages disk storage for large data objects
/// Provides automatic storage and retrieval of data and UIImage objects
public actor DiskStorageManager {
    
    /// Storage configuration
    public struct Configuration {
        public let baseDirectory: URL
        public let maxFileSize: Int
        public let compressionQuality: Double
        
        public init(
            baseDirectory: URL,
            maxFileSize: Int = 10 * 1024 * 1024, // 10MB default
            compressionQuality: Double = 0.8
        ) {
            self.baseDirectory = baseDirectory
            self.maxFileSize = maxFileSize
            self.compressionQuality = compressionQuality
        }
    }
    
    private let configuration: Configuration
    private let fileManager = FileManager.default
    
    /// Initialize with configuration
    public init(configuration: Configuration) throws {
        self.configuration = configuration
        try Self.createDirectoryIfNeeded(at: configuration.baseDirectory)
    }
    
    /// Initialize with database path
    public init(databasePath: String) throws {
        let dbURL = URL(fileURLWithPath: databasePath)
        let storageDirectory = dbURL.deletingPathExtension().appendingPathComponent("storage")
        
        self.configuration = Configuration(baseDirectory: storageDirectory)
        try Self.createDirectoryIfNeeded(at: storageDirectory)
    }
    
    private static func createDirectoryIfNeeded(at directory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
    
    private func createDirectoryIfNeeded() throws {
        try fileManager.createDirectory(
            at: configuration.baseDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
    
    /// Store data on disk and return a reference
    public func store(data: Data, for key: String) throws -> DiskStorageReference {        
        guard data.count <= configuration.maxFileSize else {
            throw DiskStorageError.dataTooLarge
        }
        
        let reference = DiskStorageReference(
            key: key,
            filename: generateFilename(for: key),
            size: data.count,
            createdAt: Date()
        )
        
        let fileURL = configuration.baseDirectory.appendingPathComponent(reference.filename)
        try data.write(to: fileURL)
        
        return reference
    }
    
    #if canImport(UIKit)
    /// Store UIImage on disk and return a reference
    public func store(image: UIImage, for key: String) throws -> DiskStorageReference {
        guard let data = image.jpegData(compressionQuality: configuration.compressionQuality) else {
            throw DiskStorageError.imageConversionFailed
        }
        
        return try store(data: data, for: key)
    }
    #endif
    
    /// Retrieve data from disk using reference
    public func retrieve(reference: DiskStorageReference) throws -> Data {
        let fileURL = configuration.baseDirectory.appendingPathComponent(reference.filename)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw DiskStorageError.fileNotFound
        }
        
        return try Data(contentsOf: fileURL)
    }
    
    #if canImport(UIKit)
    /// Retrieve UIImage from disk using reference
    public func retrieveImage(reference: DiskStorageReference) throws -> UIImage {
        let data = try retrieve(reference: reference)
        
        guard let image = UIImage(data: data) else {
            throw DiskStorageError.imageConversionFailed
        }
        
        return image
    }
    #endif
    
    /// Delete stored file
    public func delete(reference: DiskStorageReference) throws {
        let fileURL = configuration.baseDirectory.appendingPathComponent(reference.filename)
        try fileManager.removeItem(at: fileURL)
    }
    
    /// Check if file exists for reference
    public func exists(reference: DiskStorageReference) -> Bool {
        let fileURL = configuration.baseDirectory.appendingPathComponent(reference.filename)
        return fileManager.fileExists(atPath: fileURL.path)
    }
    
    /// Clean up orphaned files
    public func cleanup(validReferences: Set<String>) throws {
        let contents = try fileManager.contentsOfDirectory(
            at: configuration.baseDirectory,
            includingPropertiesForKeys: nil
        )
        
        for fileURL in contents {
            let filename = fileURL.lastPathComponent
            if !validReferences.contains(filename) {
                try fileManager.removeItem(at: fileURL)
            }
        }
    }
    
    /// Get storage statistics
    public func getStorageInfo() throws -> StorageInfo {
        let contents = try fileManager.contentsOfDirectory(
            at: configuration.baseDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        )
        
        var totalSize: Int = 0
        var fileCount = 0
        
        for fileURL in contents {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += fileSize
                fileCount += 1
            }
        }
        
        return StorageInfo(
            fileCount: fileCount,
            totalSize: totalSize,
            baseDirectory: configuration.baseDirectory
        )
    }
    
    private func generateFilename(for key: String) -> String {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let hash = key.djb2hash
        return "\(timestamp)_\(hash).blob"
    }
}

/// Reference to a file stored on disk
public struct DiskStorageReference: Codable, Sendable {
    public let key: String
    public let filename: String
    public let size: Int
    public let createdAt: Date
    
    public init(key: String, filename: String, size: Int, createdAt: Date) {
        self.key = key
        self.filename = filename
        self.size = size
        self.createdAt = createdAt
    }
}

/// Storage information
public struct StorageInfo: Sendable {
    public let fileCount: Int
    public let totalSize: Int
    public let baseDirectory: URL
    
    public var formattedSize: String {
        ByteCountFormatter().string(fromByteCount: Int64(totalSize))
    }
}

/// Disk storage errors
public enum DiskStorageError: Error, LocalizedError {
    case dataTooLarge
    case fileNotFound
    case imageConversionFailed
    case directoryCreationFailed
    
    public var errorDescription: String? {
        switch self {
        case .dataTooLarge:
            return "Data exceeds maximum file size limit"
        case .fileNotFound:
            return "File not found on disk"
        case .imageConversionFailed:
            return "Failed to convert image data"
        case .directoryCreationFailed:
            return "Failed to create storage directory"
        }
    }
}

/// SQLiteConvertible conformance for DiskStorageReference
extension DiskStorageReference: SQLiteConvertible {
    public init?(sqliteValue: SQLiteValue) {
        switch sqliteValue {
        case .text(let jsonString):
            guard let data = jsonString.data(using: .utf8),
                  let reference = try? JSONDecoder().decode(DiskStorageReference.self, from: data) else {
                return nil
            }
            self = reference
        default:
            return nil
        }
    }
    
    public var sqliteValue: SQLiteValue {
        guard let data = try? JSONEncoder().encode(self),
              let jsonString = String(data: data, encoding: .utf8) else {
            return .null
        }
        return .text(jsonString)
    }
}

/// String extension for simple hash function
private extension String {
    var djb2hash: String {
        let utf8 = self.utf8
        var hash: UInt32 = 5381
        
        for byte in utf8 {
            hash = 127 * (hash & 0x00ffffff) + UInt32(byte)
        }
        
        return String(hash, radix: 16)
    }
}