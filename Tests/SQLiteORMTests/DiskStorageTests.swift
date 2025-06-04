import Testing
@testable import SQLiteORM
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// Helper function to setup test environment
func setupDiskStorageTestEnvironment() async throws -> (URL, ORM) {
    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SQLiteORM_DiskStorage_Tests_\(UUID().uuidString)")
    
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    
    let dbPath = tempDirectory.appendingPathComponent("test.sqlite").path
    let orm = ORM(path: dbPath, enableDiskStorage: true)
    
    let openResult = await orm.open()
    switch openResult {
    case .success:
        break
    case .failure(let error):
        throw error
    }
    
    return (tempDirectory, orm)
}

// Helper function to cleanup test environment
func cleanupDiskStorageTestEnvironment(tempDirectory: URL, orm: ORM) async {
    let _ = await orm.close()
    try? FileManager.default.removeItem(at: tempDirectory)
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@Test("Disk storage manager initialization")
func diskStorageManagerInitialization() async throws {
    let (tempDirectory, orm) = try await setupDiskStorageTestEnvironment()
    defer { Task { await cleanupDiskStorageTestEnvironment(tempDirectory: tempDirectory, orm: orm) } }
    
    #expect(orm.diskStorageManager != nil)
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@Test("Data storage and retrieval")
func dataStorageAndRetrieval() async throws {
    let (tempDirectory, orm) = try await setupDiskStorageTestEnvironment()
    defer { Task { await cleanupDiskStorageTestEnvironment(tempDirectory: tempDirectory, orm: orm) } }
    
    let storageManager = try #require(orm.diskStorageManager)
    
    // Create test data
    let testData = Data(repeating: 0xFF, count: 2048) // 2KB
    let key = "test_data_\(UUID().uuidString)"
    
    // Store data
    let reference = try await storageManager.store(data: testData, for: key)
    
    #expect(reference.key == key)
    #expect(reference.size == testData.count)
    #expect(await storageManager.exists(reference: reference))
    
    // Retrieve data
    let retrievedData = try await storageManager.retrieve(reference: reference)
    #expect(retrievedData == testData)
    
    // Clean up
    try await storageManager.delete(reference: reference)
    #expect(await storageManager.exists(reference: reference) == false)
}

#if canImport(UIKit)
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@Test("UIImage storage and retrieval")
func uiImageStorageAndRetrieval() async throws {
    let (tempDirectory, orm) = try await setupDiskStorageTestEnvironment()
    defer { Task { await cleanupDiskStorageTestEnvironment(tempDirectory: tempDirectory, orm: orm) } }
    
    let storageManager = try #require(orm.diskStorageManager)
    
    // Create test image
    let size = CGSize(width: 100, height: 100)
    UIGraphicsBeginImageContext(size)
    UIColor.red.setFill()
    UIRectFill(CGRect(origin: .zero, size: size))
    let testImage = UIGraphicsGetImageFromCurrentImageContext()!
    UIGraphicsEndImageContext()
    
    let key = "test_image_\(UUID().uuidString)"
    
    // Store image
    let reference = try await storageManager.store(image: testImage, for: key)
    
    #expect(reference.key == key)
    #expect(await storageManager.exists(reference: reference))
    
    // Retrieve image
    let retrievedImage = try await storageManager.retrieveImage(reference: reference)
    #expect(retrievedImage != nil)
    
    // Clean up
    try await storageManager.delete(reference: reference)
    #expect(await storageManager.exists(reference: reference) == false)
}
#endif

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@Test("Storage works with small data")
func storageWithSmallData() async throws {
    let (tempDirectory, orm) = try await setupDiskStorageTestEnvironment()
    defer { Task { await cleanupDiskStorageTestEnvironment(tempDirectory: tempDirectory, orm: orm) } }
    
    let storageManager = try #require(orm.diskStorageManager)
    
    // Small data should still be stored (no minimum size restriction)
    let smallData = Data(repeating: 0xAA, count: 512) // 512 bytes
    let key = "small_data_\(UUID().uuidString)"
    
    let reference = try await storageManager.store(data: smallData, for: key)
    #expect(reference.key == key)
    #expect(reference.size == smallData.count)
    
    // Clean up
    try await storageManager.delete(reference: reference)
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@Test("Storage info tracking")
func storageInfoTracking() async throws {
    let (tempDirectory, orm) = try await setupDiskStorageTestEnvironment()
    defer { Task { await cleanupDiskStorageTestEnvironment(tempDirectory: tempDirectory, orm: orm) } }
    
    let storageManager = try #require(orm.diskStorageManager)
    
    // Initially should be empty
    let initialInfo = try await storageManager.getStorageInfo()
    #expect(initialInfo.fileCount == 0)
    #expect(initialInfo.totalSize == 0)
    
    // Store some data
    let testData1 = Data(repeating: 0xFF, count: 2048)
    let testData2 = Data(repeating: 0xAA, count: 4096)
    
    let ref1 = try await storageManager.store(data: testData1, for: "test1")
    let ref2 = try await storageManager.store(data: testData2, for: "test2")
    
    let finalInfo = try await storageManager.getStorageInfo()
    #expect(finalInfo.fileCount == 2)
    #expect(finalInfo.totalSize == 2048 + 4096)
    
    // Clean up
    try await storageManager.delete(reference: ref1)
    try await storageManager.delete(reference: ref2)
}

@Test("DiskStorageReference SQLite conversion")
func diskStorageReferenceSQLiteConversion() {
    let reference = DiskStorageReference(
        key: "test_key",
        filename: "test_file.blob",
        size: 1024,
        createdAt: Date()
    )
    
    // Test SQLiteConvertible conformance
    let sqliteValue = reference.sqliteValue
    let decodedReference = DiskStorageReference(sqliteValue: sqliteValue)
    
    #expect(decodedReference != nil)
    #expect(decodedReference?.key == reference.key)
    #expect(decodedReference?.filename == reference.filename)
    #expect(decodedReference?.size == reference.size)
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@Test("Storage cleanup functionality")
func storageCleanupFunctionality() async throws {
    let (tempDirectory, orm) = try await setupDiskStorageTestEnvironment()
    defer { Task { await cleanupDiskStorageTestEnvironment(tempDirectory: tempDirectory, orm: orm) } }
    
    let storageManager = try #require(orm.diskStorageManager)
    
    // Store some data
    let testData1 = Data(repeating: 0xFF, count: 2048)
    let testData2 = Data(repeating: 0xAA, count: 4096)
    let testData3 = Data(repeating: 0x55, count: 1024)
    
    let ref1 = try await storageManager.store(data: testData1, for: "test1")
    let ref2 = try await storageManager.store(data: testData2, for: "test2")
    let ref3 = try await storageManager.store(data: testData3, for: "test3")
    
    // Keep only ref1 and ref2 as valid
    let validReferences = Set([ref1.filename, ref2.filename])
    
    try await storageManager.cleanup(validReferences: validReferences)
    
    // ref1 and ref2 should still exist
    #expect(await storageManager.exists(reference: ref1))
    #expect(await storageManager.exists(reference: ref2))
    
    // ref3 should be cleaned up
    #expect(await storageManager.exists(reference: ref3) == false)
    
    // Clean up remaining
    try await storageManager.delete(reference: ref1)
    try await storageManager.delete(reference: ref2)
}

// Test model with disk storage support
struct TestDocumentWithDiskStorage: Model, DiskStorageCapable {
    typealias IDType = Int
    var id: Int = 0
    var title: String
    var content: String
    var largeData: Data?
    var largeDataDiskRef: DiskStorageReference?
    
    #if canImport(UIKit)
    var image: UIImage?
    var imageDiskRef: DiskStorageReference?
    #endif
    
    nonisolated(unsafe) static var diskStorageManager: DiskStorageManager?
    
    var diskStorableProperties: [String: Any] {
        var properties: [String: Any] = [:]
        if let largeData = largeData {
            properties["largeData"] = largeData
        }
        #if canImport(UIKit)
        if let image = image {
            properties["image"] = image
        }
        #endif
        return properties
    }
    
    mutating func updateDiskReferences(_ references: [String: DiskStorageReference?]) {
        if let ref = references["largeData"] {
            largeDataDiskRef = ref
        }
        #if canImport(UIKit)
        if let ref = references["image"] {
            imageDiskRef = ref
        }
        #endif
    }
}

// Helper function for integration tests
func setupDiskStorageIntegrationTestEnvironment() async throws -> (URL, ORM) {
    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SQLiteORM_ModelDiskStorage_Tests_\(UUID().uuidString)")
    
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    
    let dbPath = tempDirectory.appendingPathComponent("test.sqlite").path
    let orm = ORM(path: dbPath, enableDiskStorage: true)
    
    let openResult = await orm.open()
    switch openResult {
    case .success:
        break
    case .failure(let error):
        throw error
    }
    
    // Create table
    let repo = await orm.repository(for: TestDocumentWithDiskStorage.self)
    let createResult = await repo.createTable()
    switch createResult {
    case .success:
        break
    case .failure(let error):
        throw error
    }
    
    return (tempDirectory, orm)
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@Test("Model with disk storage insertion")
func modelWithDiskStorageInsertion() async throws {
    let (tempDirectory, orm) = try await setupDiskStorageIntegrationTestEnvironment()
    defer { Task { await cleanupDiskStorageTestEnvironment(tempDirectory: tempDirectory, orm: orm) } }
    
    let repo = await orm.repository(for: TestDocumentWithDiskStorage.self)
    
    // Create test document with large data
    var document = TestDocumentWithDiskStorage(
        title: "Test Document",
        content: "This is a test document",
        largeData: Data(repeating: 0xFF, count: 5120) // 5KB
    )
    
    // Insert document
    let insertResult = await repo.insert(&document)
    switch insertResult {
    case .success:
        break
    case .failure(let error):
        throw error
    }
    
    // Verify the document was inserted with ID
    #expect(document.id > 0)
    
    // Find the document
    let findResult = await repo.find(id: document.id)
    switch findResult {
    case .success(let foundDocument):
        guard let found = foundDocument else {
            Issue.record("Document not found")
            return
        }
        
        #expect(found.title == document.title)
        #expect(found.content == document.content)
    case .failure(let error):
        throw error
    }
}