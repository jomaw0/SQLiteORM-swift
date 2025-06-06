import Foundation
import Testing
@testable import SwiftSync

@Suite("Protocol Conformance Tests")
struct ProtocolConformanceTests {
    
    // MARK: - Test Models
    
    @ORMTable
    struct TestUser: ORMTable {
        typealias IDType = Int
        
        var id: Int = 0
        var username: String = ""
        var email: String = ""
        var isActive: Bool = true
        var score: Double = 0.0
        var metadata: Data? = nil
        var createdAt: Date = Date()
        
        // Sync properties (automatically included)
        var lastSyncTimestamp: Date? = nil
        var isDirty: Bool = false
        var syncStatus: SyncStatus = .synced
        var serverID: String? = nil
        
        init(id: Int = 0, username: String = "", email: String = "", isActive: Bool = true, score: Double = 0.0, metadata: Data? = nil, createdAt: Date = Date()) {
            self.id = id
            self.username = username
            self.email = email
            self.isActive = isActive
            self.score = score
            self.metadata = metadata
            self.createdAt = createdAt
        }
    }
    
    @ORMTable
    struct TestProduct: ORMTable {
        typealias IDType = String
        
        var id: String = ""
        var name: String = ""
        var price: Double = 0.0
        var inStock: Bool = true
        
        // Sync properties
        var lastSyncTimestamp: Date? = nil
        var isDirty: Bool = false
        var syncStatus: SyncStatus = .synced
        var serverID: String? = nil
        
        init(id: String = "", name: String = "", price: Double = 0.0, inStock: Bool = true) {
            self.id = id
            self.name = name
            self.price = price
            self.inStock = inStock
        }
    }
    
    // MARK: - Identifiable Tests
    
    @Test("ORMTable conforms to Identifiable")
    func testIdentifiableConformance() async {
        let user = TestUser(id: 42, username: "john")
        
        // Test that id property works as Identifiable
        #expect(user.id == 42)
        
        // Test that it can be used in contexts requiring Identifiable
        func requiresIdentifiable<T: Identifiable>(_ item: T) -> T.ID {
            return item.id
        }
        
        let extractedId = requiresIdentifiable(user)
        #expect(extractedId == 42)
    }
    
    // MARK: - Hashable Tests
    
    @Test("Hashable implementation based on all properties")
    func testHashableAllProperties() async {
        let fixedDate = Date(timeIntervalSince1970: 1234567890)
        
        let user1 = TestUser(id: 1, username: "john", email: "john@example.com", isActive: true, score: 85.5, createdAt: fixedDate)
        let user2 = TestUser(id: 1, username: "john", email: "john@example.com", isActive: true, score: 85.5, createdAt: fixedDate)
        let user3 = TestUser(id: 1, username: "johnny", email: "john@example.com", isActive: true, score: 85.5, createdAt: fixedDate) // Different username
        
        // Same properties should have same hash
        #expect(user1.hashValue == user2.hashValue, "Users with identical properties should have same hash")
        
        // Different properties should have different hash
        #expect(user1.hashValue != user3.hashValue, "Users with different properties should have different hash")
    }
    
    @Test("Hashable with different property types")
    func testHashableDifferentTypes() async {
        let fixedDate = Date(timeIntervalSince1970: 1234567890)
        let testData = "test".data(using: .utf8)
        
        let user1 = TestUser(id: 1, username: "john", email: "john@example.com", isActive: true, score: 42.0, metadata: testData, createdAt: fixedDate)
        let user2 = TestUser(id: 1, username: "john", email: "john@example.com", isActive: true, score: 42.0, metadata: testData, createdAt: fixedDate)
        let user3 = TestUser(id: 1, username: "john", email: "john@example.com", isActive: false, score: 42.0, metadata: testData, createdAt: fixedDate) // Different boolean
        
        #expect(user1.hashValue == user2.hashValue, "Users with identical complex properties should have same hash")
        #expect(user1.hashValue != user3.hashValue, "Users with different boolean should have different hash")
    }
    
    @Test("Hashable with String ID type")
    func testHashableStringID() async {
        let product1 = TestProduct(id: "PROD123", name: "Widget", price: 19.99, inStock: true)
        let product2 = TestProduct(id: "PROD123", name: "Widget", price: 19.99, inStock: true)
        let product3 = TestProduct(id: "PROD123", name: "Widget", price: 29.99, inStock: true) // Different price
        
        #expect(product1.hashValue == product2.hashValue, "Products with identical properties should have same hash")
        #expect(product1.hashValue != product3.hashValue, "Products with different price should have different hash")
    }
    
    @Test("Hashable works in Set")
    func testHashableInSet() async {
        let fixedDate = Date(timeIntervalSince1970: 1234567890)
        
        let user1 = TestUser(id: 1, username: "john", email: "john@example.com", createdAt: fixedDate)
        let user2 = TestUser(id: 1, username: "john", email: "john@example.com", createdAt: fixedDate) // Identical
        let user3 = TestUser(id: 1, username: "johnny", email: "john@example.com", createdAt: fixedDate) // Different username
        let user4 = TestUser(id: 2, username: "john", email: "john@example.com", createdAt: fixedDate) // Different ID
        
        let userSet: Set<TestUser> = [user1, user2, user3, user4]
        
        // user1 and user2 are identical, so Set should contain 3 unique users
        #expect(userSet.count == 3, "Set should contain 3 unique users (user1 and user2 are identical)")
        
        // Verify contains works correctly
        #expect(userSet.contains(user1), "Set should contain user1")
        #expect(userSet.contains(user2), "Set should contain user2 (identical to user1)")
        #expect(userSet.contains(user3), "Set should contain user3")
        #expect(userSet.contains(user4), "Set should contain user4")
    }
    
    @Test("Hashable works as Dictionary keys")
    func testHashableAsDictionaryKeys() async {
        let fixedDate = Date(timeIntervalSince1970: 1234567890)
        
        let user1 = TestUser(id: 1, username: "john", email: "john@example.com", createdAt: fixedDate)
        let user2 = TestUser(id: 1, username: "john", email: "john@example.com", createdAt: fixedDate) // Identical
        let user3 = TestUser(id: 1, username: "johnny", email: "john@example.com", createdAt: fixedDate) // Different username
        
        var userDict: [TestUser: String] = [:]
        
        userDict[user1] = "first"
        userDict[user2] = "second" // Should overwrite because user1 == user2
        userDict[user3] = "third"
        
        #expect(userDict.count == 2, "Dictionary should have 2 entries (user1 and user2 are the same key)")
        #expect(userDict[user1] == "second", "Value should be overwritten to 'second'")
        #expect(userDict[user2] == "second", "user2 should access the same value as user1")
        #expect(userDict[user3] == "third", "user3 should have its own entry")
    }
    
    // MARK: - Equatable Tests
    
    @Test("Equatable implementation based on all properties")
    func testEquatableAllProperties() async {
        let fixedDate = Date(timeIntervalSince1970: 1234567890)
        
        let user1 = TestUser(id: 1, username: "john", email: "john@example.com", isActive: true, score: 85.5, createdAt: fixedDate)
        let user2 = TestUser(id: 1, username: "john", email: "john@example.com", isActive: true, score: 85.5, createdAt: fixedDate)
        let user3 = TestUser(id: 1, username: "johnny", email: "john@example.com", isActive: true, score: 85.5, createdAt: fixedDate) // Different username
        let user4 = TestUser(id: 2, username: "john", email: "john@example.com", isActive: true, score: 85.5, createdAt: fixedDate) // Different ID
        
        // Same properties should be equal
        #expect(user1 == user2, "Users with identical properties should be equal")
        
        // Different properties should not be equal
        #expect(user1 != user3, "Users with different username should not be equal")
        #expect(user1 != user4, "Users with different ID should not be equal")
    }
    
    @Test("Equatable with complex property types")
    func testEquatableComplexTypes() async {
        let fixedDate = Date(timeIntervalSince1970: 1234567890)
        let testData = "test".data(using: .utf8)
        
        let user1 = TestUser(id: 1, username: "john", email: "john@example.com", isActive: true, score: 42.0, metadata: testData, createdAt: fixedDate)
        let user2 = TestUser(id: 1, username: "john", email: "john@example.com", isActive: true, score: 42.0, metadata: testData, createdAt: fixedDate)
        let user3 = TestUser(id: 1, username: "john", email: "john@example.com", isActive: true, score: 42.0, metadata: nil, createdAt: fixedDate) // Different metadata
        let user4 = TestUser(id: 1, username: "john", email: "john@example.com", isActive: true, score: 42.0, metadata: testData, createdAt: Date()) // Different date
        
        #expect(user1 == user2, "Users with identical complex properties should be equal")
        #expect(user1 != user3, "Users with different metadata should not be equal")
        #expect(user1 != user4, "Users with different dates should not be equal")
    }
    
    @Test("Equatable reflexivity")
    func testEquatableReflexivity() async {
        let fixedDate = Date(timeIntervalSince1970: 1234567890)
        let user = TestUser(id: 1, username: "john", email: "john@example.com", createdAt: fixedDate)
        
        #expect(user == user, "User should be equal to itself (reflexivity)")
    }
    
    @Test("Equatable symmetry")
    func testEquatableSymmetry() async {
        let fixedDate = Date(timeIntervalSince1970: 1234567890)
        let user1 = TestUser(id: 1, username: "john", email: "john@example.com", createdAt: fixedDate)
        let user2 = TestUser(id: 1, username: "john", email: "john@example.com", createdAt: fixedDate)
        
        #expect(user1 == user2, "user1 should equal user2")
        #expect(user2 == user1, "user2 should equal user1 (symmetry)")
    }
    
    @Test("Equatable transitivity")
    func testEquatableTransitivity() async {
        let fixedDate = Date(timeIntervalSince1970: 1234567890)
        let user1 = TestUser(id: 1, username: "john", email: "john@example.com", createdAt: fixedDate)
        let user2 = TestUser(id: 1, username: "john", email: "john@example.com", createdAt: fixedDate)
        let user3 = TestUser(id: 1, username: "john", email: "john@example.com", createdAt: fixedDate)
        
        #expect(user1 == user2, "user1 should equal user2")
        #expect(user2 == user3, "user2 should equal user3")
        #expect(user1 == user3, "user1 should equal user3 (transitivity)")
    }
    
    // MARK: - Codable Tests
    
    @Test("Codable encoding and decoding preserves equality")
    func testCodablePreservesEquality() async throws {
        let originalUser = TestUser(id: 1, username: "john", email: "john@example.com", isActive: true, score: 85.5)
        
        // Encode
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(originalUser)
        
        // Decode
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decodedUser = try decoder.decode(TestUser.self, from: data)
        
        // Should be equal
        #expect(originalUser == decodedUser, "Original and decoded user should be equal")
        #expect(originalUser.hashValue == decodedUser.hashValue, "Original and decoded user should have same hash")
    }
    
    // MARK: - Edge Cases
    
    @Test("Hashable and Equatable with default values")
    func testWithDefaultValues() async {
        let fixedDate = Date(timeIntervalSince1970: 1234567890)
        let user1 = TestUser(createdAt: fixedDate) // All default values except fixed date
        let user2 = TestUser(createdAt: fixedDate) // All default values except fixed date
        
        #expect(user1 == user2, "Users with default values should be equal")
        #expect(user1.hashValue == user2.hashValue, "Users with default values should have same hash")
    }
    
    @Test("Hashable and Equatable with optional properties")
    func testWithOptionalProperties() async {
        let fixedDate = Date(timeIntervalSince1970: 1234567890)
        let user1 = TestUser(id: 1, username: "john", metadata: nil, createdAt: fixedDate)
        let user2 = TestUser(id: 1, username: "john", metadata: nil, createdAt: fixedDate)
        let user3 = TestUser(id: 1, username: "john", metadata: "test".data(using: .utf8), createdAt: fixedDate)
        
        #expect(user1 == user2, "Users with same nil metadata should be equal")
        #expect(user1 != user3, "Users with different metadata (nil vs data) should not be equal")
        #expect(user1.hashValue == user2.hashValue, "Users with same nil metadata should have same hash")
        #expect(user1.hashValue != user3.hashValue, "Users with different metadata should have different hash")
    }
    
    @Test("Hash consistency across multiple calls")
    func testHashConsistency() async {
        let fixedDate = Date(timeIntervalSince1970: 1234567890)
        let user = TestUser(id: 1, username: "john", email: "john@example.com", createdAt: fixedDate)
        
        let hash1 = user.hashValue
        let hash2 = user.hashValue
        let hash3 = user.hashValue
        
        #expect(hash1 == hash2, "Hash should be consistent across calls")
        #expect(hash2 == hash3, "Hash should be consistent across calls")
        #expect(hash1 == hash3, "Hash should be consistent across calls")
    }
    
    @Test("Fallback behavior when encoding fails")
    func testFallbackBehavior() async {
        // This is hard to test directly since our models should always encode successfully
        // But we can verify that the implementation doesn't crash with complex data
        
        let fixedDate = Date(timeIntervalSince1970: 1234567890)
        let complexData = Data(repeating: 0xFF, count: 10000) // Large data
        let user1 = TestUser(id: 1, username: "john", metadata: complexData, createdAt: fixedDate)
        let user2 = TestUser(id: 1, username: "john", metadata: complexData, createdAt: fixedDate)
        
        // Should still work correctly
        #expect(user1 == user2, "Users with complex data should still be comparable")
        #expect(user1.hashValue == user2.hashValue, "Users with complex data should have consistent hash")
    }
} 