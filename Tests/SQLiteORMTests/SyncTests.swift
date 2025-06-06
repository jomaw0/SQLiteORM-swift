import Foundation
import Testing
@testable import SQLiteORM

/// Comprehensive tests for sync functionality as demonstrated in README.md
@Suite("Sync Functionality Tests")
struct SyncTests {
    
    // MARK: - Test Models
    
    @ORMTable
    struct TestUser: ORMTable {
        typealias IDType = Int
        var id: Int = 0
        var username: String = ""
        var email: String = ""
        var createdAt: Date = Date()
        var isActive: Bool = true
        
        // Sync properties (automatically included in ORMTable)
        var lastSyncTimestamp: Date? = nil
        var isDirty: Bool = false
        var syncStatus: SyncStatus = .synced
        var serverID: String? = nil
        
        init() {}
        
        init(id: Int = 0, username: String, email: String, isActive: Bool = true) {
            self.id = id
            self.username = username
            self.email = email
            self.isActive = isActive
            self.createdAt = Date()
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
        
        init(id: Int = 0, name: String, price: Double, category: String = "") {
            self.id = id
            self.name = name
            self.price = price
            self.category = category
        }
    }
    
    @ORMTable
    struct TestOrder: ORMTable {
        typealias IDType = Int
        var id: Int = 0
        var customerId: Int = 0
        var total: Double = 0.0
        var orderDate: Date = Date()
        
        // Sync properties
        var lastSyncTimestamp: Date? = nil
        var isDirty: Bool = false
        var syncStatus: SyncStatus = .synced
        var serverID: String? = nil
        
        init() {}
        
        init(id: Int = 0, customerId: Int, total: Double) {
            self.id = id
            self.customerId = customerId
            self.total = total
            self.orderDate = Date()
        }
    }
    
    @ORMTable
    struct TestArticle: ORMTable {
        typealias IDType = Int
        var id: Int = 0
        var title: String = ""
        var content: String = ""
        var publishDate: Date = Date()
        
        // Sync properties
        var lastSyncTimestamp: Date? = nil
        var isDirty: Bool = false
        var syncStatus: SyncStatus = .synced
        var serverID: String? = nil
        
        init() {}
        
        init(id: Int = 0, title: String, content: String) {
            self.id = id
            self.title = title
            self.content = content
            self.publishDate = Date()
        }
    }
    
    // MARK: - Helper Methods
    
    private func setupDatabase() async -> ORM {
        let orm = createInMemoryORM()
        
        let openResult = await orm.open()
        if case .failure(let error) = openResult {
            Issue.record("Open failed: \(error)")
        }
        
        let createResult = await orm.createTables(TestUser.self, TestProduct.self, TestOrder.self, TestArticle.self)
        if case .failure(let error) = createResult {
            Issue.record("Create tables failed: \(error)")
        }
        
        return orm
    }
    
    // MARK: - Simple Sync Tests (README Example 1)
    
    @Test("Simple sync with server wins default")
    func testSimpleSyncServerWins() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        // Server data from README example
        let serverUsers = [
            TestUser(id: 1, username: "john", email: "john@example.com"),
            TestUser(id: 2, username: "jane", email: "jane@example.com")
        ]
        
        // SIMPLEST SYNC - server wins by default
        let result = await TestUser.sync(with: serverUsers, orm: orm)
        
        switch result {
        case .success(let changes):
            #expect(changes.totalChanges == 2)
            #expect(changes.inserted.count == 2)
            #expect(changes.updated.count == 0)
            #expect(changes.conflicts == 0)
            
            // Verify users were inserted
            let repo = await orm.repository(for: TestUser.self)
            let allUsers = await repo.findAll()
            switch allUsers {
            case .success(let users):
                #expect(users.count == 2)
            case .failure(let error):
                Issue.record("Find all users failed: \(error)")
            }
            
        case .failure(let error):
            Issue.record("Sync failed: \(error)")
        }
    }
    
    // MARK: - Automatic Sync Properties Tests (README Example 2)
    
    @Test("Verify automatic sync properties are included")
    func testAutomaticSyncProperties() async throws {
        let user = TestUser(username: "test", email: "test@example.com")
        
        // Verify sync properties exist and have default values
        #expect(user.lastSyncTimestamp == nil)
        #expect(user.isDirty == false)
        #expect(user.syncStatus == .synced)
        #expect(user.serverID == nil)
        
        // Verify conflictFingerprint is generated
        #expect(!user.conflictFingerprint.isEmpty)
    }
    
    // MARK: - Conflict Resolution Tests (README Example 3)
    
    @Test("Server wins conflict resolution")
    func testServerWinsConflictResolution() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: TestUser.self)
        
        // Insert local user first
        var localUser = TestUser(id: 1, username: "john_local", email: "john_local@example.com")
        localUser.isDirty = true
        _ = await repo.insert(&localUser)
        
        // Server user with same ID but different data
        let serverUsers = [
            TestUser(id: 1, username: "john_server", email: "john_server@example.com")
        ]
        
        // Server wins (default)
        let result = await TestUser.sync(with: serverUsers, orm: orm)
        
        switch result {
        case .success(let changes):
            #expect(changes.conflicts == 1)
            #expect(changes.updated.count == 1)
            
            // Verify server data won
            let updatedUser = changes.updated.first
            #expect(updatedUser?.username == "john_server")
            #expect(updatedUser?.email == "john_server@example.com")
            
        case .failure(let error):
            Issue.record("Sync failed: \(error)")
        }
    }
    
    @Test("Local wins conflict resolution")
    func testLocalWinsConflictResolution() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: TestUser.self)
        
        // Insert local user first
        var localUser = TestUser(id: 1, username: "john_local", email: "john_local@example.com")
        localUser.isDirty = true
        _ = await repo.insert(&localUser)
        
        // Server user with same ID but different data
        let serverUsers = [
            TestUser(id: 1, username: "john_server", email: "john_server@example.com")
        ]
        
        // Local wins
        let result = await TestUser.sync(with: serverUsers, orm: orm, conflictResolution: .localWins)
        
        switch result {
        case .success(let changes):
            // With local wins, there should be no updates when local is dirty
            #expect(changes.conflicts == 0)
            #expect(changes.updated.count == 0)
            
            // Verify local data is preserved
            let userResult = await repo.find(id: 1)
            if case .success(let user) = userResult, let user = user {
                #expect(user.username == "john_local")
                #expect(user.email == "john_local@example.com")
            }
            
        case .failure(let error):
            Issue.record("Sync failed: \(error)")
        }
    }
    
    @Test("Newest wins conflict resolution")
    func testNewestWinsConflictResolution() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: TestUser.self)
        
        // Insert local user with older timestamp
        var localUser = TestUser(id: 1, username: "john_local", email: "john_local@example.com")
        localUser.isDirty = true
        localUser.lastSyncTimestamp = Date().addingTimeInterval(-3600) // 1 hour ago
        _ = await repo.insert(&localUser)
        
        // Server user with newer timestamp
        var serverUser = TestUser(id: 1, username: "john_server", email: "john_server@example.com")
        serverUser.lastSyncTimestamp = Date() // Now
        
        // Newest wins
        let result = await TestUser.sync(with: [serverUser], orm: orm, conflictResolution: .newestWins)
        
        switch result {
        case .success(let changes):
            #expect(changes.conflicts == 1)
            #expect(changes.updated.count == 1)
            
            // Verify server data won (newer)
            let updatedUser = changes.updated.first
            #expect(updatedUser?.username == "john_server")
            
        case .failure(let error):
            Issue.record("Sync failed: \(error)")
        }
    }
    
    @Test("Custom conflict resolution")
    func testCustomConflictResolution() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: TestUser.self)
        
        // Insert local user
        var localUser = TestUser(id: 1, username: "john_local", email: "john@company.com")
        localUser.isDirty = true
        _ = await repo.insert(&localUser)
        
        // Server user
        let serverUsers = [
            TestUser(id: 1, username: "john_server", email: "john@external.com")
        ]
        
        // Custom resolution logic from README
        let result = await TestUser.sync(
            with: serverUsers,
            orm: orm,
            conflictResolution: .custom { local, server in
                // Keep company emails, use server for others
                guard let localUser = local as? TestUser,
                      let serverUser = server as? TestUser else {
                    return server
                }
                
                return localUser.email.contains("@company.com") ? localUser : serverUser
            }
        )
        
        switch result {
        case .success(let changes):
            #expect(changes.conflicts == 1)
            #expect(changes.updated.count == 1)
            
            // Verify local user won (company email)
            let updatedUser = changes.updated.first
            #expect(updatedUser?.email == "john@company.com")
            
        case .failure(let error):
            Issue.record("Sync failed: \(error)")
        }
    }
    
    // MARK: - Change Tracking Tests (README Example 4)
    
    @Test("Change tracking callback")
    func testChangeTrackingCallback() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let serverProducts = [
            TestProduct(id: 1, name: "iPhone", price: 999.0, category: "Electronics"),
            TestProduct(id: 2, name: "MacBook", price: 1999.0, category: "Computers")
        ]
        
        var callbackChanges: SyncChanges<TestProduct>?
        
        let result = await TestProduct.sync(
            with: serverProducts,
            orm: orm,
            changeCallback: { changes in
                callbackChanges = changes
            }
        )
        
        switch result {
        case .success(let changes):
            #expect(changes.inserted.count == 2)
            
            // Verify callback was called with same changes
            #expect(callbackChanges != nil)
            #expect(callbackChanges?.inserted.count == 2)
            #expect(callbackChanges?.totalChanges == 2)
            
            // Verify product details from callback
            let firstProduct = callbackChanges?.inserted.first
            #expect(firstProduct?.name == "iPhone")
            #expect(firstProduct?.price == 999.0)
            
        case .failure(let error):
            Issue.record("Sync failed: \(error)")
        }
    }
    
    // MARK: - Two-Way Sync Pattern Tests (README Example 5)
    
    @Test("Two-way sync pattern - download phase")
    func testTwoWaySyncDownloadPhase() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        // === DOWNLOAD PHASE ===
        
        // 1. Mock server data
        let serverOrders = [
            TestOrder(id: 1, customerId: 1, total: 99.99),
            TestOrder(id: 2, customerId: 2, total: 149.99)
        ]
        
        var downloadChanges: SyncChanges<TestOrder>?
        
        // 2. Sync with local - server wins for existing orders
        let downloadResult = await TestOrder.sync(
            with: serverOrders,
            orm: orm,
            conflictResolution: .serverWins,
            changeCallback: { changes in
                downloadChanges = changes
            }
        )
        
        switch downloadResult {
        case .success(let changes):
            #expect(changes.inserted.count == 2)
            #expect(downloadChanges?.totalChanges == 2)
            
        case .failure(let error):
            Issue.record("Download sync failed: \(error)")
        }
    }
    
    @Test("Two-way sync pattern - upload phase")
    func testTwoWaySyncUploadPhase() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: TestOrder.self)
        
        // Create local dirty orders
        var order1 = TestOrder(id: 1, customerId: 1, total: 99.99)
        order1.isDirty = true
        _ = await repo.insert(&order1)
        
        var order2 = TestOrder(id: 2, customerId: 2, total: 149.99)
        order2.isDirty = true
        _ = await repo.insert(&order2)
        
        // === UPLOAD PHASE ===
        
        // 3. Get local changes that need uploading
        let localChangesResult = await TestOrder.getLocalChanges(orm: orm)
        
        switch localChangesResult {
        case .success(let localChanges):
            #expect(localChanges.count == 2)
            #expect(localChanges.allSatisfy { $0.isDirty })
            
            // 4. Mock upload to server (add server IDs)
            let uploadedOrders = localChanges.map { order in
                var updated = order
                updated.serverID = "server_order_\(order.id)"
                return updated
            }
            
            // 5. Mark as synced
            let markSyncedResult = await TestOrder.markAsSynced(uploadedOrders, orm: orm)
            if case .failure(let error) = markSyncedResult {
                Issue.record("Mark synced failed: \(error)")
            }
            
            // Verify orders are no longer dirty
            let finalLocalChanges = await TestOrder.getLocalChanges(orm: orm)
            switch finalLocalChanges {
            case .success(let changes):
                #expect(changes.isEmpty)
            case .failure(let error):
                Issue.record("Failed to get final local changes: \(error)")
            }
            
        case .failure(let error):
            Issue.record("Failed to get local changes: \(error)")
        }
    }
    
    // MARK: - Real-World Use Cases Tests (README Example 6)
    
    @Test("E-commerce app sync scenario")
    func testEcommerceSyncScenario() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        // Products: server is authoritative
        let serverProducts = [
            TestProduct(id: 1, name: "iPhone", price: 999.0, category: "Electronics"),
            TestProduct(id: 2, name: "MacBook", price: 1999.0, category: "Computers")
        ]
        
        let productResult = await TestProduct.sync(with: serverProducts, orm: orm) // Server wins by default
        switch productResult {
        case .success(let changes):
            #expect(changes.inserted.count == 2)
        case .failure(let error):
            Issue.record("Product sync failed: \(error)")
        }
        
        // Users: bidirectional with newest wins
        let serverUsers = [
            TestUser(id: 1, username: "john", email: "john@example.com"),
            TestUser(id: 2, username: "jane", email: "jane@example.com")
        ]
        
        let userResult = await TestUser.sync(with: serverUsers, orm: orm, conflictResolution: .newestWins)
        switch userResult {
        case .success(let changes):
            #expect(changes.inserted.count == 2)
        case .failure(let error):
            Issue.record("User sync failed: \(error)")
        }
        
        // Orders: upload local changes
        let repo = await orm.repository(for: TestOrder.self)
        var localOrder = TestOrder(id: 1, customerId: 1, total: 99.99)
        localOrder.isDirty = true
        _ = await repo.insert(&localOrder)
        
        let localOrders = await TestOrder.getLocalChanges(orm: orm)
        if case .success(let orders) = localOrders, !orders.isEmpty {
            // Mock upload
            let uploaded = orders.map { order in
                var updated = order
                updated.serverID = "server_\(order.id)"
                return updated
            }
            let markResult = await TestOrder.markAsSynced(uploaded, orm: orm)
            if case .failure(let error) = markResult {
                Issue.record("Mark synced failed: \(error)")
            }
        }
    }
    
    @Test("Content management app sync scenario")
    func testContentManagementSyncScenario() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        // Articles from CMS - server always wins
        let articles = [
            TestArticle(id: 1, title: "Article 1", content: "Content 1"),
            TestArticle(id: 2, title: "Article 2", content: "Content 2")
        ]
        
        let articleResult = await TestArticle.sync(with: articles, orm: orm) // Default: server wins
        
        switch articleResult {
        case .success(let changes):
            #expect(changes.inserted.count == 2)
            #expect(changes.totalChanges == 2)
            
        case .failure(let error):
            Issue.record("Article sync failed: \(error)")
        }
    }
    
    @Test("File-based sync scenario")
    func testFileBasedSyncScenario() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        // Mock JSON data (simulating loaded from file)
        let users = [
            TestUser(id: 1, username: "john", email: "john@example.com"),
            TestUser(id: 2, username: "jane", email: "jane@example.com"),
            TestUser(id: 3, username: "bob", email: "bob@example.com")
        ]
        
        // Sync file data with database
        let result = await TestUser.sync(with: users, orm: orm)
        
        switch result {
        case .success(let changes):
            #expect(changes.totalChanges == 3)
            #expect(changes.inserted.count == 3)
            
            // Verify all users were synced
            let repo = await orm.repository(for: TestUser.self)
            let allUsers = await repo.findAll()
            switch allUsers {
            case .success(let users):
                #expect(users.count == 3)
            case .failure(let error):
                Issue.record("Find all users failed: \(error)")
            }
            
        case .failure(let error):
            Issue.record("File sync failed: \(error)")
        }
    }
    
    // MARK: - Edge Cases and Error Handling
    
    @Test("Sync with empty server data")
    func testSyncWithEmptyServerData() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        // Insert some local data first
        let repo = await orm.repository(for: TestUser.self)
        var user = TestUser(username: "local", email: "local@example.com")
        _ = await repo.insert(&user)
        
        // Sync with empty server data
        let result = await TestUser.sync(with: [], orm: orm)
        
        switch result {
        case .success(let changes):
            #expect(changes.inserted.count == 0)
            #expect(changes.updated.count == 0)
            #expect(changes.totalChanges == 0)
            
            // Local data should still exist
            let allUsers = await repo.findAll()
            switch allUsers {
            case .success(let users):
                #expect(users.count == 1)
            case .failure(let error):
                Issue.record("Find all users failed: \(error)")
            }
            
        case .failure(let error):
            Issue.record("Empty sync failed: \(error)")
        }
    }
    
    @Test("Sync with duplicate server data")
    func testSyncWithDuplicateServerData() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        // Server data with duplicates
        let serverUsers = [
            TestUser(id: 1, username: "john", email: "john@example.com"),
            TestUser(id: 1, username: "john_duplicate", email: "john_dup@example.com"), // Same ID
            TestUser(id: 2, username: "jane", email: "jane@example.com")
        ]
        
        let result = await TestUser.sync(with: serverUsers, orm: orm)
        
        switch result {
        case .success(let changes):
            // Should handle duplicates gracefully
            #expect(changes.totalChanges >= 2)
            
            // Verify final state
            let repo = await orm.repository(for: TestUser.self)
            let allUsers = await repo.findAll()
            switch allUsers {
            case .success(let users):
                #expect(users.count == 2) // Only unique IDs
            case .failure(let error):
                Issue.record("Find all users failed: \(error)")
            }
            
        case .failure(let error):
            Issue.record("Duplicate sync failed: \(error)")
        }
    }
    
    @Test("Sync status management")
    func testSyncStatusManagement() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let serverUsers = [
            TestUser(id: 1, username: "john", email: "john@example.com")
        ]
        
        let result = await TestUser.sync(with: serverUsers, orm: orm)
        
        switch result {
        case .success(let changes):
            // Verify sync properties are properly set
            let syncedUser = changes.inserted.first
            #expect(syncedUser?.isDirty == false)
            #expect(syncedUser?.syncStatus == .synced)
            #expect(syncedUser?.lastSyncTimestamp != nil)
            
        case .failure(let error):
            Issue.record("Sync status test failed: \(error)")
        }
    }
    
    @Test("Get local changes functionality")
    func testGetLocalChanges() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: TestUser.self)
        
        // Insert clean user
        var cleanUser = TestUser(username: "clean", email: "clean@example.com")
        cleanUser.isDirty = false
        _ = await repo.insert(&cleanUser)
        
        // Insert dirty user
        var dirtyUser = TestUser(username: "dirty", email: "dirty@example.com")
        dirtyUser.isDirty = true
        _ = await repo.insert(&dirtyUser)
        
        // Get local changes
        let localChanges = await TestUser.getLocalChanges(orm: orm)
        
        switch localChanges {
        case .success(let changes):
            #expect(changes.count == 1)
            #expect(changes.first?.username == "dirty")
            #expect(changes.first?.isDirty == true)
            
        case .failure(let error):
            Issue.record("Get local changes failed: \(error)")
        }
    }
    
    @Test("Mark as synced functionality")
    func testMarkAsSynced() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: TestUser.self)
        
        // Insert dirty users
        var user1 = TestUser(username: "user1", email: "user1@example.com")
        user1.isDirty = true
        user1.syncStatus = .pending
        _ = await repo.insert(&user1)
        
        var user2 = TestUser(username: "user2", email: "user2@example.com")
        user2.isDirty = true
        user2.syncStatus = .pending
        _ = await repo.insert(&user2)
        
        // Mark as synced
        let result = await TestUser.markAsSynced([user1, user2], orm: orm)
        switch result {
        case .success():
            break // Success
        case .failure(let error):
            Issue.record("Mark synced failed: \(error)")
        }
        
        // Verify no more local changes
        let localChanges = await TestUser.getLocalChanges(orm: orm)
        switch localChanges {
        case .success(let changes):
            #expect(changes.isEmpty)
        case .failure(let error):
            Issue.record("Get local changes failed: \(error)")
        }
        
        // Verify users are marked as synced
        let allUsers = await repo.findAll()
        if case .success(let users) = allUsers {
            for user in users {
                #expect(user.isDirty == false)
                #expect(user.syncStatus == .synced)
                #expect(user.lastSyncTimestamp != nil)
            }
        }
    }
    
    // MARK: - Performance Tests
    
    @Test("Large dataset sync performance")
    func testLargeDatasetSync() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        // Create large dataset (1000 users)
        let largeServerData = (1...1000).map { i in
            TestUser(id: i, username: "user\(i)", email: "user\(i)@example.com")
        }
        
        let startTime = Date()
        let result = await TestUser.sync(with: largeServerData, orm: orm)
        let duration = Date().timeIntervalSince(startTime)
        
        switch result {
        case .success(let changes):
            #expect(changes.inserted.count == 1000)
            #expect(duration < 10.0) // Should complete within 10 seconds
            
            // Verify all data was synced
            let repo = await orm.repository(for: TestUser.self)
            let allUsers = await repo.findAll()
            switch allUsers {
            case .success(let users):
                #expect(users.count == 1000)
            case .failure(let error):
                Issue.record("Find all users failed: \(error)")
            }
            
        case .failure(let error):
            Issue.record("Large dataset sync failed: \(error)")
        }
    }
}