import Foundation
import Testing
@testable import SQLiteORM

@Suite("Soft Sync Tests")
struct SoftSyncTests {
    
    // MARK: - Test Models
    
    @ORMTable
    struct TestUser: ORMTable {
        typealias IDType = Int
        
        var id: Int = 0
        var username: String = ""
        var email: String = ""
        var isActive: Bool = true
        
        // Sync properties
        var lastSyncTimestamp: Date? = nil
        var isDirty: Bool = false
        var syncStatus: SyncStatus = .synced
        var serverID: String? = nil
        
        init() {}
        
        init(id: Int = 0, username: String = "", email: String = "", isActive: Bool = true) {
            self.id = id
            self.username = username
            self.email = email
            self.isActive = isActive
        }
    }
    
    @ORMTable
    struct TestProduct: ORMTable {
        typealias IDType = Int
        
        var id: Int = 0
        var name: String = ""
        var price: Double = 0.0
        var category: String = ""
        
        // Sync properties
        var lastSyncTimestamp: Date? = nil
        var isDirty: Bool = false
        var syncStatus: SyncStatus = .synced
        var serverID: String? = nil
        
        init() {}
        
        init(id: Int = 0, name: String = "", price: Double = 0.0, category: String = "") {
            self.id = id
            self.name = name
            self.price = price
            self.category = category
        }
    }
    
    // MARK: - Container Models for Testing Nested Sync
    
    struct APIResponse: Codable {
        let users: [TestUser]
        let products: [TestProduct]
        let metadata: String
        
        init(users: [TestUser] = [], products: [TestProduct] = [], metadata: String = "test") {
            self.users = users
            self.products = products
            self.metadata = metadata
        }
    }
    
    struct UserContainer: Codable {
        let user: TestUser?
        let success: Bool
        
        init(user: TestUser? = nil, success: Bool = true) {
            self.user = user
            self.success = success
        }
    }
    
    // MARK: - Setup Helper
    
    private func setupDatabase() async -> ORM {
        let orm = createInMemoryORM()
        
        let openResult = await orm.open()
        if case .failure(let error) = openResult {
            Issue.record("Open failed: \(error)")
        }
        
        let createResult = await orm.createTables(TestUser.self, TestProduct.self)
        if case .failure(let error) = createResult {
            Issue.record("Create tables failed: \(error)")
        }
        
        return orm
    }
    
    // MARK: - Basic Soft Sync Tests
    
    @Test("Soft sync with single item - insert new")
    func testSoftSyncSingleItemInsert() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        // Server has a new user
        let serverUser = TestUser(id: 1, username: "john", email: "john@example.com")
        
        let result = await TestUser.softSync(with: serverUser, orm: orm)
        
        switch result {
        case .success(let changes):
            #expect(changes.inserted.count == 1, "Should insert 1 new user")
            #expect(changes.updated.count == 0, "Should not update any users")
            #expect(changes.removed.count == 0, "Soft sync should never remove users")
            #expect(changes.totalChanges == 1, "Should have 1 total change")
            
            let insertedUser = changes.inserted.first
            #expect(insertedUser?.username == "john", "Inserted user should have correct username")
            
        case .failure(let error):
            Issue.record("Soft sync failed: \(error)")
        }
    }
    
    @Test("Soft sync with array - insert and update")
    func testSoftSyncArrayInsertAndUpdate() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: TestUser.self)
        
        // Pre-insert a local user
        var localUser = TestUser(id: 1, username: "john_old", email: "john_old@example.com")
        _ = await repo.insert(&localUser)
        
        // Server data: update existing user + add new user
        let serverUsers = [
            TestUser(id: 1, username: "john_new", email: "john_new@example.com"), // Update
            TestUser(id: 2, username: "jane", email: "jane@example.com") // Insert
        ]
        
        let result = await TestUser.softSync(with: serverUsers, orm: orm)
        
        switch result {
        case .success(let changes):
            #expect(changes.inserted.count == 1, "Should insert 1 new user")
            #expect(changes.updated.count == 1, "Should update 1 existing user")
            #expect(changes.removed.count == 0, "Soft sync should never remove users")
            #expect(changes.totalChanges == 2, "Should have 2 total changes")
            
            let updatedUser = changes.updated.first
            #expect(updatedUser?.username == "john_new", "Updated user should have new username")
            
            let insertedUser = changes.inserted.first
            #expect(insertedUser?.username == "jane", "Inserted user should be jane")
            
        case .failure(let error):
            Issue.record("Soft sync failed: \(error)")
        }
    }
    
    @Test("Soft sync preserves local-only items")
    func testSoftSyncPreservesLocalOnlyItems() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: TestUser.self)
        
        // Pre-insert local users
        var localUser1 = TestUser(id: 1, username: "local_user1", email: "local1@example.com")
        var localUser2 = TestUser(id: 2, username: "local_user2", email: "local2@example.com")
        var localUser3 = TestUser(id: 3, username: "local_user3", email: "local3@example.com")
        
        _ = await repo.insert(&localUser1)
        _ = await repo.insert(&localUser2)
        _ = await repo.insert(&localUser3)
        
        // Server only has user 1 (updated) and a new user 4
        let serverUsers = [
            TestUser(id: 1, username: "server_user1", email: "server1@example.com"), // Update
            TestUser(id: 4, username: "server_user4", email: "server4@example.com")  // Insert
        ]
        
        let result = await TestUser.softSync(with: serverUsers, orm: orm)
        
        switch result {
        case .success(let changes):
            #expect(changes.inserted.count == 1, "Should insert 1 new user")
            #expect(changes.updated.count == 1, "Should update 1 existing user")
            #expect(changes.removed.count == 0, "Soft sync should never remove users")
            
            // Verify all local users still exist
            let allUsersResult = await repo.findAll()
            if case .success(let allUsers) = allUsersResult {
                #expect(allUsers.count == 4, "Should have 4 users total (3 local + 1 new from server)")
                
                // Check that local-only users are preserved
                let user2 = allUsers.first { $0.id == 2 }
                let user3 = allUsers.first { $0.id == 3 }
                
                #expect(user2?.username == "local_user2", "Local-only user 2 should be preserved")
                #expect(user3?.username == "local_user3", "Local-only user 3 should be preserved")
            }
            
        case .failure(let error):
            Issue.record("Soft sync failed: \(error)")
        }
    }
    
    // MARK: - Conflict Resolution Tests
    
    @Test("Soft sync with server wins conflict resolution")
    func testSoftSyncServerWinsConflict() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: TestUser.self)
        
        // Insert local user with changes (dirty)
        var localUser = TestUser(id: 1, username: "local_version", email: "local@example.com")
        localUser.isDirty = true
        _ = await repo.insert(&localUser)
        
        // Server user with same ID but different data
        let serverUsers = [
            TestUser(id: 1, username: "server_version", email: "server@example.com")
        ]
        
        let result = await TestUser.softSync(with: serverUsers, orm: orm, conflictResolution: .serverWins)
        
        switch result {
        case .success(let changes):
            #expect(changes.conflicts == 1, "Should resolve 1 conflict")
            #expect(changes.updated.count == 1, "Should update 1 user")
            
            let updatedUser = changes.updated.first
            #expect(updatedUser?.username == "server_version", "Server version should win")
            
        case .failure(let error):
            Issue.record("Soft sync failed: \(error)")
        }
    }
    
    @Test("Soft sync with local wins conflict resolution")
    func testSoftSyncLocalWinsConflict() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: TestUser.self)
        
        // Insert local user with changes (dirty)
        var localUser = TestUser(id: 1, username: "local_version", email: "local@example.com")
        localUser.isDirty = true
        _ = await repo.insert(&localUser)
        
        // Server user with same ID but different data
        let serverUsers = [
            TestUser(id: 1, username: "server_version", email: "server@example.com")
        ]
        
        let result = await TestUser.softSync(with: serverUsers, orm: orm, conflictResolution: .localWins)
        
        switch result {
        case .success(let changes):
            #expect(changes.conflicts == 0, "Local wins should not create conflicts")
            #expect(changes.updated.count == 0, "Should not update when local wins")
            
            // Verify local version is preserved
            let userResult = await repo.find(id: 1)
            if case .success(let user) = userResult, let user = user {
                #expect(user.username == "local_version", "Local version should be preserved")
            }
            
        case .failure(let error):
            Issue.record("Soft sync failed: \(error)")
        }
    }
    
    // MARK: - Nested Container Tests
    
    @Test("Soft sync from codable container with array")
    func testSoftSyncFromContainer() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        // Create API response with nested users
        let apiResponse = APIResponse(
            users: [
                TestUser(id: 1, username: "john", email: "john@example.com"),
                TestUser(id: 2, username: "jane", email: "jane@example.com")
            ]
        )
        
        let result = await TestUser.softSync(from: apiResponse, keyPath: \.users, orm: orm)
        
        switch result {
        case .success(let changes):
            #expect(changes.inserted.count == 2, "Should insert 2 users from container")
            #expect(changes.updated.count == 0, "Should not update any users")
            #expect(changes.removed.count == 0, "Soft sync should never remove users")
            
        case .failure(let error):
            Issue.record("Soft sync from container failed: \(error)")
        }
    }
    
    @Test("Soft sync from codable container with optional item")
    func testSoftSyncFromOptionalContainer() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        // Container with a single user
        let userContainer = UserContainer(
            user: TestUser(id: 1, username: "john", email: "john@example.com")
        )
        
        let result = await TestUser.softSync(from: userContainer, keyPath: \.user, orm: orm)
        
        switch result {
        case .success(let changes):
            #expect(changes.inserted.count == 1, "Should insert 1 user from optional container")
            #expect(changes.updated.count == 0, "Should not update any users")
            
        case .failure(let error):
            Issue.record("Soft sync from optional container failed: \(error)")
        }
    }
    
    @Test("Soft sync from empty optional container")
    func testSoftSyncFromEmptyOptionalContainer() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        // Container with no user
        let userContainer = UserContainer(user: nil)
        
        let result = await TestUser.softSync(from: userContainer, keyPath: \.user, orm: orm)
        
        switch result {
        case .success(let changes):
            #expect(changes.inserted.count == 0, "Should insert 0 users from empty container")
            #expect(changes.updated.count == 0, "Should not update any users")
            #expect(changes.totalChanges == 0, "Should have no changes")
            
        case .failure(let error):
            Issue.record("Soft sync from empty container failed: \(error)")
        }
    }
    
    // MARK: - Mixed Type Container Tests
    
    @Test("Soft sync different types from same container")
    func testSoftSyncMixedTypesFromContainer() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        // Create API response with both users and products
        let apiResponse = APIResponse(
            users: [
                TestUser(id: 1, username: "john", email: "john@example.com")
            ],
            products: [
                TestProduct(id: 1, name: "iPhone", price: 999.0, category: "Electronics"),
                TestProduct(id: 2, name: "MacBook", price: 1999.0, category: "Computers")
            ]
        )
        
        // Sync users first
        let userResult = await TestUser.softSync(from: apiResponse, keyPath: \.users, orm: orm)
        switch userResult {
        case .success(let changes):
            #expect(changes.inserted.count == 1, "Should insert 1 user")
        case .failure(let error):
            Issue.record("User soft sync failed: \(error)")
        }
        
        // Sync products second
        let productResult = await TestProduct.softSync(from: apiResponse, keyPath: \.products, orm: orm)
        switch productResult {
        case .success(let changes):
            #expect(changes.inserted.count == 2, "Should insert 2 products")
        case .failure(let error):
            Issue.record("Product soft sync failed: \(error)")
        }
    }
    
    // MARK: - Change Callback Tests
    
    @Test("Soft sync with change callback")
    func testSoftSyncWithChangeCallback() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        var callbackChanges: SyncChanges<TestUser>?
        
        let serverUsers = [
            TestUser(id: 1, username: "john", email: "john@example.com"),
            TestUser(id: 2, username: "jane", email: "jane@example.com")
        ]
        
        let result = await TestUser.softSync(
            with: serverUsers,
            orm: orm,
            changeCallback: { changes in
                callbackChanges = changes
            }
        )
        
        switch result {
        case .success(let changes):
            #expect(changes.inserted.count == 2, "Should insert 2 users")
            
            // Verify callback was called
            #expect(callbackChanges != nil, "Callback should be called")
            #expect(callbackChanges?.totalChanges == 2, "Callback should receive correct changes")
            
        case .failure(let error):
            Issue.record("Soft sync with callback failed: \(error)")
        }
    }
    
    // MARK: - Edge Cases
    
    @Test("Soft sync with empty server data")
    func testSoftSyncWithEmptyServerData() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: TestUser.self)
        
        // Pre-insert some local users
        var localUser1 = TestUser(id: 1, username: "local1", email: "local1@example.com")
        var localUser2 = TestUser(id: 2, username: "local2", email: "local2@example.com")
        _ = await repo.insert(&localUser1)
        _ = await repo.insert(&localUser2)
        
        // Soft sync with empty server data
        let result = await TestUser.softSync(with: [], orm: orm)
        
        switch result {
        case .success(let changes):
            #expect(changes.inserted.count == 0, "Should insert 0 users")
            #expect(changes.updated.count == 0, "Should update 0 users")
            #expect(changes.removed.count == 0, "Should remove 0 users")
            #expect(changes.totalChanges == 0, "Should have 0 total changes")
            
            // Verify local users are still there
            let allUsersResult = await repo.findAll()
            if case .success(let allUsers) = allUsersResult {
                #expect(allUsers.count == 2, "Local users should be preserved")
            }
            
        case .failure(let error):
            Issue.record("Soft sync with empty data failed: \(error)")
        }
    }
    
    @Test("Soft sync does not affect clean local items")
    func testSoftSyncDoesNotAffectCleanLocalItems() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: TestUser.self)
        
        // Insert local user that's clean (not dirty)
        var localUser = TestUser(id: 1, username: "local_clean", email: "local@example.com")
        localUser.isDirty = false // Explicitly clean
        _ = await repo.insert(&localUser)
        
        // Server has same user with different data
        let serverUsers = [
            TestUser(id: 1, username: "server_version", email: "server@example.com")
        ]
        
        let result = await TestUser.softSync(with: serverUsers, orm: orm)
        
        switch result {
        case .success(let changes):
            #expect(changes.conflicts == 0, "Should have no conflicts")
            #expect(changes.updated.count == 1, "Should update the clean local user")
            
            let updatedUser = changes.updated.first
            #expect(updatedUser?.username == "server_version", "Clean local user should be updated with server data")
            
        case .failure(let error):
            Issue.record("Soft sync clean local failed: \(error)")
        }
    }
    
    // MARK: - ORM-Level Multi-Model Soft Sync Tests
    
    @Test("ORM soft sync with multiple model types")
    func testORMSoftSyncMultipleModelTypes() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        // Create API response with multiple model types
        let apiResponse = APIResponse(
            users: [
                TestUser(id: 1, username: "john", email: "john@example.com"),
                TestUser(id: 2, username: "jane", email: "jane@example.com")
            ],
            products: [
                TestProduct(id: 1, name: "iPhone", price: 999.0, category: "Electronics"),
                TestProduct(id: 2, name: "MacBook", price: 1999.0, category: "Computers")
            ]
        )
        
        // Soft sync multiple model types from container
        let result = await orm.softSync(
            from: apiResponse,
            modelTypes: [TestUser.self, TestProduct.self]
        )
        
        switch result {
        case .success(let syncResults):
            #expect(syncResults.modelResults.count == 2, "Should have results for 2 model types")
            
            // Check user sync results
            if let userResult = syncResults.modelResults["TestUser"] {
                #expect(userResult.totalChanges == 2, "Should have 2 total changes for users")
            } else {
                Issue.record("User sync results not found")
            }
            
            // Check product sync results  
            if let productResult = syncResults.modelResults["TestProduct"] {
                #expect(productResult.totalChanges == 2, "Should have 2 total changes for products")
            } else {
                Issue.record("Product sync results not found")
            }
            
        case .failure(let error):
            Issue.record("ORM soft sync failed: \(error)")
        }
    }
    
    @Test("ORM soft sync with existing local data")
    func testORMSoftSyncWithExistingLocalData() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        // Pre-insert some local data
        let userRepo = await orm.repository(for: TestUser.self)
        let productRepo = await orm.repository(for: TestProduct.self)
        
        var localUser = TestUser(id: 1, username: "local_john", email: "local_john@example.com")
        var localProduct = TestProduct(id: 1, name: "Local iPhone", price: 899.0, category: "Electronics")
        
        _ = await userRepo.insert(&localUser)
        _ = await productRepo.insert(&localProduct)
        
        // Create API response with updates and new items
        let apiResponse = APIResponse(
            users: [
                TestUser(id: 1, username: "server_john", email: "server_john@example.com"), // Update
                TestUser(id: 3, username: "alice", email: "alice@example.com") // New
            ],
            products: [
                TestProduct(id: 1, name: "Server iPhone", price: 999.0, category: "Electronics"), // Update
                TestProduct(id: 3, name: "iPad", price: 599.0, category: "Tablets") // New
            ]
        )
        
        // Soft sync multiple model types
        let result = await orm.softSync(
            from: apiResponse,
            modelTypes: [TestUser.self, TestProduct.self],
            conflictResolution: .serverWins
        )
        
        switch result {
        case .success(let syncResults):
            #expect(syncResults.modelResults.count == 2, "Should have results for 2 model types")
            
            // Check user sync results
            if let userResult = syncResults.modelResults["TestUser"] {
                #expect(userResult.totalChanges == 2, "Should have 2 total changes for users (1 insert + 1 update)")
            }
            
            // Check product sync results
            if let productResult = syncResults.modelResults["TestProduct"] {
                #expect(productResult.totalChanges == 2, "Should have 2 total changes for products (1 insert + 1 update)")
            }
            
        case .failure(let error):
            Issue.record("ORM soft sync with existing data failed: \(error)")
        }
    }
    
    @Test("ORM soft sync with empty container")
    func testORMSoftSyncWithEmptyContainer() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        // Pre-insert some local data
        let userRepo = await orm.repository(for: TestUser.self)
        var localUser = TestUser(id: 1, username: "local_john", email: "local_john@example.com")
        _ = await userRepo.insert(&localUser)
        
        // Create empty API response
        let apiResponse = APIResponse() // All arrays empty
        
        // Soft sync with empty container
        let result = await orm.softSync(
            from: apiResponse,
            modelTypes: [TestUser.self, TestProduct.self]
        )
        
        switch result {
        case .success(let syncResults):
            #expect(syncResults.modelResults.count == 2, "Should have results for 2 model types")
            
            // Check that no changes occurred when container is empty
            if let userResult = syncResults.modelResults["TestUser"] {
                #expect(userResult.totalChanges == 0, "Should have 0 changes when container is empty")
            }
            
            if let productResult = syncResults.modelResults["TestProduct"] {
                #expect(productResult.totalChanges == 0, "Should have 0 changes when container is empty")
            }
            
            // Verify local data still exists
            let allUsersResult = await userRepo.findAll()
            if case .success(let allUsers) = allUsersResult {
                #expect(allUsers.count == 1, "Local user should still exist")
                #expect(allUsers.first?.username == "local_john", "Local user should be unchanged")
            }
            
        case .failure(let error):
            Issue.record("ORM soft sync with empty container failed: \(error)")
        }
    }
    
    @Test("ORM soft sync with partial model types")
    func testORMSoftSyncWithPartialModelTypes() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        // Create API response with multiple model types
        let apiResponse = APIResponse(
            users: [
                TestUser(id: 1, username: "john", email: "john@example.com")
            ],
            products: [
                TestProduct(id: 1, name: "iPhone", price: 999.0, category: "Electronics")
            ]
        )
        
        // Only sync users, not products
        let result = await orm.softSync(
            from: apiResponse,
            modelTypes: [TestUser.self] // Only sync users
        )
        
        switch result {
        case .success(let syncResults):
            #expect(syncResults.modelResults.count == 1, "Should have results for 1 model type only")
            #expect(syncResults.modelResults["TestUser"] != nil, "Should have user results")
            #expect(syncResults.modelResults["TestProduct"] == nil, "Should not have product results")
            
            // Verify users were synced
            if let userResult = syncResults.modelResults["TestUser"] {
                #expect(userResult.totalChanges == 1, "Should have 1 total change for users")
            }
            
            // Verify products were not synced
            let productRepo = await orm.repository(for: TestProduct.self)
            let allProductsResult = await productRepo.findAll()
            if case .success(let allProducts) = allProductsResult {
                #expect(allProducts.count == 0, "No products should be synced")
            }
            
        case .failure(let error):
            Issue.record("ORM soft sync with partial model types failed: \(error)")
        }
    }
} 