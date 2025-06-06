import Testing
import Foundation
@testable import SwiftSync
@preconcurrency import Combine

/// Comprehensive test suite for SwiftSync Combine subscription functionality
/// 
/// This test suite validates that the reactive subscription system correctly:
/// - Loads initial data (not empty arrays)
/// - Responds to database changes with reactive updates
/// - Handles query filtering properly
/// - Manages memory and threading correctly
/// - Performs well with large datasets
/// - Handles edge cases gracefully
@Suite("Combine Subscription Tests")
struct CombineSubscriptionTests {
    
    // MARK: - Test Models
    
    /// Test user model with various properties for comprehensive testing
    @ORMTable
    struct TestUser: ORMTable {
        typealias IDType = Int
        var id: Int = 0
        var username: String
        var email: String
        var isActive: Bool = true
        var score: Int = 0
        var createdAt: Date = Date()
    }
    
    /// Test post model for relationship and cross-table testing
    @ORMTable
    struct TestPost: ORMTable {
        typealias IDType = Int
        var id: Int = 0
        var userId: Int
        var title: String
        var content: String
        var isPublished: Bool = false
        var createdAt: Date = Date()
    }
    
    // MARK: - Helper Functions
    
    /// Sets up a clean test environment with in-memory database and tables
    /// - Returns: Tuple of (ORM instance, User repository, Post repository)
    private func setupTestEnvironment() async -> (ORM, Repository<TestUser>, Repository<TestPost>) {
        let orm = createInMemoryORM()
        let openResult = await orm.open()
        #expect(openResult.isSuccess, "ORM should open successfully")
        
        let createUsersResult = await orm.repository(for: TestUser.self).createTable()
        #expect(createUsersResult.isSuccess, "User table should be created successfully")
        
        let createPostsResult = await orm.repository(for: TestPost.self).createTable()
        #expect(createPostsResult.isSuccess, "Post table should be created successfully")
        
        let userRepo = await orm.repository(for: TestUser.self)
        let postRepo = await orm.repository(for: TestPost.self)
        
        return (orm, userRepo, postRepo)
    }
    
    /// Inserts a set of test users with varied properties for testing
    /// - Parameter repo: The user repository
    /// - Returns: Array of inserted users with populated IDs
    private func insertTestUsers(_ repo: Repository<TestUser>) async -> [TestUser] {
        var users: [TestUser] = []
        
        let testData = [
            ("alice", "alice@example.com", true, 100),
            ("bob", "bob@example.com", false, 50),
            ("charlie", "charlie@example.com", true, 75)
        ]
        
        for (username, email, isActive, score) in testData {
            var user = TestUser(username: username, email: email, isActive: isActive, score: score)
            let result = await repo.insert(&user)
            #expect(result.isSuccess, "User '\(username)' should be inserted successfully")
            users.append(user)
        }
        
        return users
    }
    
    // MARK: - SimpleQuerySubscription Tests
    
    @Test("SimpleQuerySubscription - Initial Data Load")
    func testSimpleQuerySubscriptionInitialLoad() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, userRepo, _) = await setupTestEnvironment()
        _ = await insertTestUsers(userRepo)
        
        // Create subscription after data exists
        let subscription = userRepo.subscribe()
        
        // Wait for initial load - subscription should load existing data, not start empty
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        await MainActor.run {
            switch subscription.result {
            case .success(let loadedUsers):
                #expect(loadedUsers.count == 3, "Should load all 3 existing users")
                #expect(loadedUsers.map { $0.username }.sorted() == ["alice", "bob", "charlie"], "Should load correct users")
            case .failure(let error):
                Issue.record("Subscription should not fail on initial load: \(error)")
            }
        }
    }
    
    @Test("SimpleQuerySubscription - Query Filtering")
    func testSimpleQuerySubscriptionWithFilter() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, userRepo, _) = await setupTestEnvironment()
        _ = await insertTestUsers(userRepo)
        
        // Create subscription with filter for active users only
        let query = ORMQueryBuilder<TestUser>().where("isActive", .equal, true)
        let subscription = userRepo.subscribe(query: query)
        
        // Wait for initial filtered load
        try await Task.sleep(nanoseconds: 100_000_000)
        
        await MainActor.run {
            switch subscription.result {
            case .success(let activeUsers):
                #expect(activeUsers.count == 2, "Should filter to 2 active users")
                #expect(activeUsers.map { $0.username }.sorted() == ["alice", "charlie"], "Should load only active users")
                #expect(activeUsers.allSatisfy { $0.isActive }, "All returned users should be active")
            case .failure(let error):
                Issue.record("Filtered subscription should not fail: \(error)")
            }
        }
    }
    
    @Test("SimpleQuerySubscription - Reactive Insert Updates")
    func testSimpleQuerySubscriptionReactiveInsert() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, userRepo, _) = await setupTestEnvironment()
        
        // Create subscription on empty database
        let subscription = userRepo.subscribe()
        
        // Wait for initial empty load
        try await Task.sleep(nanoseconds: 100_000_000)
        
        await MainActor.run {
            switch subscription.result {
            case .success(let users):
                #expect(users.isEmpty, "Should start with empty array")
            case .failure(let error):
                Issue.record("Empty database subscription should not fail: \(error)")
            }
        }
        
        // Insert a new user - subscription should reactively update
        var newUser = TestUser(username: "dave", email: "dave@example.com", score: 80)
        let insertResult = await userRepo.insert(&newUser)
        #expect(insertResult.isSuccess, "User insert should succeed")
        
        // Wait for reactive update
        try await Task.sleep(nanoseconds: 200_000_000)
        
        await MainActor.run {
            switch subscription.result {
            case .success(let users):
                #expect(users.count == 1, "Should reactively update to show 1 user")
                #expect(users.first?.username == "dave", "Should show the newly inserted user")
                #expect(users.first?.id == newUser.id, "Should have correct ID")
            case .failure(let error):
                Issue.record("Subscription should reactively update on insert: \(error)")
            }
        }
    }
    
    @Test("SimpleQuerySubscription - Reactive Update Changes")
    func testSimpleQuerySubscriptionReactiveUpdate() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, userRepo, _) = await setupTestEnvironment()
        let users = await insertTestUsers(userRepo)
        
        // Create subscription
        let subscription = userRepo.subscribe()
        
        // Wait for initial load
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Update a user's properties - subscription should reflect changes
        var updatedUser = users[0]
        updatedUser.username = "alice_updated"
        updatedUser.score = 999
        let updateResult = await userRepo.update(updatedUser)
        #expect(updateResult.isSuccess, "User update should succeed")
        
        // Wait for reactive update
        try await Task.sleep(nanoseconds: 200_000_000)
        
        await MainActor.run {
            switch subscription.result {
            case .success(let loadedUsers):
                let alice = loadedUsers.first { $0.id == users[0].id }
                #expect(alice != nil, "Updated user should still exist")
                #expect(alice?.username == "alice_updated", "Username should be updated")
                #expect(alice?.score == 999, "Score should be updated")
            case .failure(let error):
                Issue.record("Subscription should reactively update on user changes: \(error)")
            }
        }
    }
    
    @Test("SimpleQuerySubscription - Reactive Delete Updates")
    func testSimpleQuerySubscriptionReactiveDelete() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, userRepo, _) = await setupTestEnvironment()
        let users = await insertTestUsers(userRepo)
        
        // Create subscription
        let subscription = userRepo.subscribe()
        
        // Wait for initial load
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Delete a user - subscription should remove it from results
        let deleteResult = await userRepo.delete(id: users[1].id)
        #expect(deleteResult.isSuccess, "User delete should succeed")
        
        // Wait for reactive update
        try await Task.sleep(nanoseconds: 200_000_000)
        
        await MainActor.run {
            switch subscription.result {
            case .success(let loadedUsers):
                #expect(loadedUsers.count == 2, "Should have 2 users after delete")
                #expect(!loadedUsers.contains { $0.id == users[1].id }, "Deleted user should not appear")
                #expect(loadedUsers.contains { $0.username == "alice" }, "Other users should remain")
                #expect(loadedUsers.contains { $0.username == "charlie" }, "Other users should remain")
            case .failure(let error):
                Issue.record("Subscription should reactively update on delete: \(error)")
            }
        }
    }
    
    // MARK: - SimpleSingleQuerySubscription Tests
    
    @Test("SimpleSingleQuerySubscription - Subscribe by ID")
    func testSingleQuerySubscriptionById() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, userRepo, _) = await setupTestEnvironment()
        let users = await insertTestUsers(userRepo)
        
        // Subscribe to specific user by ID
        let subscription = userRepo.subscribe(id: users[0].id)
        
        // Wait for initial load
        try await Task.sleep(nanoseconds: 100_000_000)
        
        await MainActor.run {
            switch subscription.result {
            case .success(let user):
                #expect(user != nil, "Should find the user by ID")
                #expect(user?.username == "alice", "Should load correct user")
                #expect(user?.id == users[0].id, "Should have correct ID")
            case .failure(let error):
                Issue.record("Single subscription by ID should not fail: \(error)")
            }
        }
    }
    
    @Test("SimpleSingleQuerySubscription - Reactive Update")
    func testSingleQuerySubscriptionReactiveUpdate() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, userRepo, _) = await setupTestEnvironment()
        let users = await insertTestUsers(userRepo)
        
        // Subscribe to specific user
        let subscription = userRepo.subscribe(id: users[0].id)
        
        // Wait for initial load
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Update the subscribed user
        var updatedUser = users[0]
        updatedUser.email = "alice_new@example.com"
        updatedUser.score = 150
        let updateResult = await userRepo.update(updatedUser)
        #expect(updateResult.isSuccess, "User update should succeed")
        
        // Wait for reactive update
        try await Task.sleep(nanoseconds: 200_000_000)
        
        await MainActor.run {
            switch subscription.result {
            case .success(let user):
                #expect(user != nil, "User should still exist after update")
                #expect(user?.email == "alice_new@example.com", "Email should be updated")
                #expect(user?.score == 150, "Score should be updated")
            case .failure(let error):
                Issue.record("Single subscription should reactively update: \(error)")
            }
        }
    }
    
    @Test("SimpleSingleQuerySubscription - First Match Query")
    func testSingleQuerySubscriptionFirst() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, userRepo, _) = await setupTestEnvironment()
        _ = await insertTestUsers(userRepo)
        
        // Subscribe to first user with score > 60 (should be alice with score 100)
        let query = ORMQueryBuilder<TestUser>()
            .where("score", .greaterThan, 60)
            .orderBy("score", ascending: false)
        let subscription = userRepo.subscribeFirst(query: query)
        
        // Wait for initial load
        try await Task.sleep(nanoseconds: 100_000_000)
        
        await MainActor.run {
            switch subscription.result {
            case .success(let user):
                #expect(user != nil, "Should find a user matching criteria")
                #expect(user?.username == "alice", "Should be highest scoring user above 60")
                #expect(user?.score == 100, "Should have score of 100")
            case .failure(let error):
                Issue.record("First match subscription should not fail: \(error)")
            }
        }
    }
    
    // MARK: - SimpleCountSubscription Tests
    
    @Test("SimpleCountSubscription - Count All Records")
    func testCountSubscriptionAllRecords() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, userRepo, _) = await setupTestEnvironment()
        
        // Create count subscription on empty database
        let subscription = userRepo.subscribeCount()
        
        // Wait for initial count
        try await Task.sleep(nanoseconds: 100_000_000)
        
        await MainActor.run {
            switch subscription.result {
            case .success(let count):
                #expect(count == 0, "Should start with count of 0")
            case .failure(let error):
                Issue.record("Count subscription should not fail on empty DB: \(error)")
            }
        }
        
        // Insert users and verify reactive count updates
        _ = await insertTestUsers(userRepo)
        
        // Wait for reactive count update
        try await Task.sleep(nanoseconds: 200_000_000)
        
        await MainActor.run {
            switch subscription.result {
            case .success(let count):
                #expect(count == 3, "Should reactively update to count of 3")
            case .failure(let error):
                Issue.record("Count subscription should reactively update: \(error)")
            }
        }
    }
    
    @Test("SimpleCountSubscription - Count with Query Filter")
    func testCountSubscriptionWithQuery() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, userRepo, _) = await setupTestEnvironment()
        _ = await insertTestUsers(userRepo)
        
        // Create count subscription for active users only
        let query = ORMQueryBuilder<TestUser>().where("isActive", .equal, true)
        let subscription = userRepo.subscribeCount(query: query)
        
        // Wait for initial filtered count
        try await Task.sleep(nanoseconds: 100_000_000)
        
        await MainActor.run {
            switch subscription.result {
            case .success(let count):
                #expect(count == 2, "Should count 2 active users (alice and charlie)")
            case .failure(let error):
                Issue.record("Filtered count subscription should not fail: \(error)")
            }
        }
        
        // Activate bob and verify count updates
        let findResult = await userRepo.findAll(query: ORMQueryBuilder<TestUser>().where("username", .equal, "bob"))
        guard case .success(let users) = findResult, var bob = users.first else {
            Issue.record("Failed to find bob for activation test")
            return
        }
        
        bob.isActive = true
        let updateResult = await userRepo.update(bob)
        #expect(updateResult.isSuccess, "Bob activation should succeed")
        
        // Wait for reactive count update
        try await Task.sleep(nanoseconds: 200_000_000)
        
        await MainActor.run {
            switch subscription.result {
            case .success(let count):
                #expect(count == 3, "Should now count 3 active users")
            case .failure(let error):
                Issue.record("Count subscription should reactively update after bob activation: \(error)")
            }
        }
    }
    
    // MARK: - Integration and Edge Case Tests
    
    @Test("Multiple Independent Subscriptions")
    func testMultipleSubscriptionsIndependentUpdates() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, userRepo, _) = await setupTestEnvironment()
        
        // Create multiple independent subscriptions
        let allUsersSubscription = userRepo.subscribe()
        let activeUsersSubscription = userRepo.subscribe(
            query: ORMQueryBuilder<TestUser>().where("isActive", .equal, true)
        )
        let countSubscription = userRepo.subscribeCount()
        
        // Wait for initial loads
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Insert test users
        _ = await insertTestUsers(userRepo)
        
        // Wait for all subscriptions to update
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Verify all subscriptions updated independently and correctly
        await MainActor.run {
            // All users subscription
            if case .success(let allUsers) = allUsersSubscription.result {
                #expect(allUsers.count == 3, "All users subscription should show 3 users")
            } else {
                Issue.record("All users subscription failed")
            }
            
            // Active users subscription
            if case .success(let activeUsers) = activeUsersSubscription.result {
                #expect(activeUsers.count == 2, "Active users subscription should show 2 users")
                #expect(activeUsers.allSatisfy { $0.isActive }, "All should be active")
            } else {
                Issue.record("Active users subscription failed")
            }
            
            // Count subscription
            if case .success(let count) = countSubscription.result {
                #expect(count == 3, "Count subscription should show 3")
            } else {
                Issue.record("Count subscription failed")
            }
        }
    }
    
    @Test("Cross-Table Change Isolation")
    func testChangeNotifierCrossTableNotifications() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, userRepo, postRepo) = await setupTestEnvironment()
        
        // Create user subscription
        let userSubscription = userRepo.subscribe()
        
        // Wait for initial load
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Insert posts (different table) - should not affect user subscription
        var post = TestPost(userId: 1, title: "Test Post", content: "Content")
        let postResult = await postRepo.insert(&post)
        #expect(postResult.isSuccess, "Post insert should succeed")
        
        // Wait and verify user subscription unchanged
        try await Task.sleep(nanoseconds: 100_000_000)
        
        await MainActor.run {
            if case .success(let users) = userSubscription.result {
                #expect(users.isEmpty, "User subscription should remain empty after post insert")
            }
        }
        
        // Now insert a user - should update user subscription
        var user = TestUser(username: "test", email: "test@example.com")
        let userResult = await userRepo.insert(&user)
        #expect(userResult.isSuccess, "User insert should succeed")
        
        // Wait for user subscription update
        try await Task.sleep(nanoseconds: 200_000_000)
        
        await MainActor.run {
            if case .success(let users) = userSubscription.result {
                #expect(users.count == 1, "User subscription should update after user insert")
            }
        }
    }
    
    @Test("Subscription Memory Management")
    func testSubscriptionMemoryManagement() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, userRepo, _) = await setupTestEnvironment()
        
        // Create subscription in limited scope
        weak var weakSubscription: SimpleQuerySubscription<TestUser>?
        
        autoreleasepool {
            let subscription = userRepo.subscribe()
            weakSubscription = subscription
            
            // Verify it's alive
            #expect(weakSubscription != nil, "Subscription should be alive in scope")
        }
        
        // Allow time for cleanup
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Should be deallocated when out of scope
        #expect(weakSubscription == nil, "Subscription should be deallocated when out of scope")
    }
    
    @Test("Subscription Performance with Large Dataset")
    func testSubscriptionPerformanceLargeDataset() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, userRepo, _) = await setupTestEnvironment()
        
        // Insert large dataset
        for i in 0..<100 {
            var user = TestUser(
                username: "user\(i)",
                email: "user\(i)@example.com",
                isActive: i % 2 == 0,
                score: i * 10
            )
            _ = await userRepo.insert(&user)
        }
        
        // Create filtered subscription and measure performance
        let startTime = Date()
        let subscription = userRepo.subscribe(
            query: ORMQueryBuilder<TestUser>()
                .where("isActive", .equal, true)
                .where("score", .greaterThan, 500)
        )
        
        // Wait for load
        try await Task.sleep(nanoseconds: 200_000_000)
        
        let loadTime = Date().timeIntervalSince(startTime)
        
        // Should load quickly even with many records
        #expect(loadTime < 1.0, "Large dataset should load within 1 second")
        
        await MainActor.run {
            if case .success(let users) = subscription.result {
                // Should have users with score > 500 and active (even indices)
                #expect(users.count == 24, "Should efficiently filter large dataset")
                #expect(users.allSatisfy { $0.isActive && $0.score > 500 }, "All users should match filter criteria")
            }
        }
    }
    
    // MARK: - Shopping List Demo Scenario Tests
    
    /// Test shopping list model with similar structure to the demo app
    @ORMTable
    struct ShoppingList: ORMTable {
        typealias IDType = Int
        var id: Int = 0
        var name: String
        var createdAt: Date = Date()
        var isActive: Bool = true
    }
    
    /// Test shopping item model with similar structure to the demo app
    @ORMTable
    struct ShoppingItem: ORMTable {
        typealias IDType = Int
        var id: Int = 0
        var listId: Int
        var name: String
        var quantity: Int = 1
        var price: Double = 0.0
        var isChecked: Bool = false
        var category: String = "Other"
        var addedAt: Date = Date()
    }
    
    @Test("Demo App Scenario - Subscription Created Before Initial Data Load")
    func testDemoAppSubscriptionScenario() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let orm = createInMemoryORM()
        let openResult = await orm.open()
        #expect(openResult.isSuccess, "ORM should open successfully")
        
        // Create tables
        let listRepo = await orm.repository(for: ShoppingList.self)
        let itemRepo = await orm.repository(for: ShoppingItem.self)
        
        let createListsResult = await listRepo.createTable()
        #expect(createListsResult.isSuccess, "ShoppingList table should be created")
        
        let createItemsResult = await itemRepo.createTable()
        #expect(createItemsResult.isSuccess, "ShoppingItem table should be created")
        
        // Step 1: Setup subscriptions BEFORE any data exists (mimicking demo app behavior)
        let listSubscription = listRepo.subscribe(
            query: ORMQueryBuilder<ShoppingList>()
                .where("isActive", .equal, true)
                .orderBy("createdAt", ascending: false)
        )
        
        let itemSubscription = itemRepo.subscribe(
            query: ORMQueryBuilder<ShoppingItem>()
                .orderBy("addedAt", ascending: false)
        )
        
        // Wait for initial subscription setup and first trigger (empty database)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Verify first trigger - should show empty results
        await MainActor.run {
            switch listSubscription.result {
            case .success(let lists):
                #expect(lists.isEmpty, "List subscription should start with empty results")
            case .failure(let error):
                Issue.record("List subscription should not fail initially: \(error)")
            }
            
            switch itemSubscription.result {
            case .success(let items):
                #expect(items.isEmpty, "Item subscription should start with empty results")
            case .failure(let error):
                Issue.record("Item subscription should not fail initially: \(error)")
            }
        }
        
        // Step 2: Check if database is empty (mimicking loadInitialData)
        let allListsResult = await listRepo.findAll()
        let hasExistingData = switch allListsResult {
        case .success(let lists): !lists.isEmpty
        case .failure: false
        }
        
        #expect(hasExistingData == false, "Database should be empty initially")
        
        // Step 3: Create sample data (mimicking createSampleData)
        var sampleList = ShoppingList(name: "Grocery Shopping")
        let createListResult = await listRepo.insert(&sampleList)
        #expect(createListResult.isSuccess, "Sample list should be created successfully")
        
        // Add sample items to the list
        let sampleItemsData = [
            ("Apples", 6, 3.99, "Groceries"),
            ("Bread", 1, 2.50, "Groceries"),
            ("Milk", 1, 4.25, "Groceries")
        ]
        
        var insertedItems: [ShoppingItem] = []
        for (name, quantity, price, category) in sampleItemsData {
            var item = ShoppingItem(
                listId: sampleList.id,
                name: name,
                quantity: quantity,
                price: price,
                category: category
            )
            let result = await itemRepo.insert(&item)
            #expect(result.isSuccess, "Sample item '\(name)' should be created successfully")
            insertedItems.append(item)
        }
        
        // Wait for reactive updates after data insertion
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Step 4: Verify second trigger - should show the created data
        await MainActor.run {
            switch listSubscription.result {
            case .success(let lists):
                #expect(lists.count == 1, "List subscription should now contain 1 shopping list")
                #expect(lists.first?.name == "Grocery Shopping", "List should have correct name")
                #expect(lists.first?.isActive == true, "List should be active")
                #expect(lists.first?.id == sampleList.id, "List should have correct ID")
            case .failure(let error):
                Issue.record("List subscription should show created data: \(error)")
            }
            
            switch itemSubscription.result {
            case .success(let items):
                #expect(items.count == 3, "Item subscription should contain 3 shopping items")
                #expect(items.allSatisfy { $0.listId == sampleList.id }, "All items should belong to the created list")
                #expect(Set(items.map { $0.name }) == Set(["Apples", "Bread", "Milk"]), "Should contain all expected items")
            case .failure(let error):
                Issue.record("Item subscription should show created data: \(error)")
            }
        }
        
        // Step 5: Test incremental updates
        var newItem = ShoppingItem(
            listId: sampleList.id,
            name: "Cheese",
            quantity: 1,
            price: 5.99,
            category: "Groceries"
        )
        let newItemResult = await itemRepo.insert(&newItem)
        #expect(newItemResult.isSuccess, "New item should be inserted successfully")
        
        // Wait for reactive update
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Verify additional trigger and updated content
        await MainActor.run {
            switch itemSubscription.result {
            case .success(let items):
                #expect(items.count == 4, "Should now have 4 items including the new one")
                #expect(items.contains { $0.name == "Cheese" }, "Should contain the newly added item")
            case .failure(let error):
                Issue.record("Item subscription should show new item: \(error)")
            }
        }
    }
    
    @Test("Demo App Scenario - Multiple Sequential Data Operations")
    func testDemoAppMultipleDataOperations() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let orm = createInMemoryORM()
        let openResult = await orm.open()
        #expect(openResult.isSuccess, "ORM should open successfully")
        
        let listRepo = await orm.repository(for: ShoppingList.self)
        let itemRepo = await orm.repository(for: ShoppingItem.self)
        
        _ = await listRepo.createTable()
        _ = await itemRepo.createTable()
        
        // Create subscriptions first
        let listSubscription = listRepo.subscribe(
            query: ORMQueryBuilder<ShoppingList>()
                .where("isActive", .equal, true)
                .orderBy("createdAt", ascending: false)
        )
        
        // Wait for initial empty trigger
        try await Task.sleep(nanoseconds: 100_000_000)
        
        await MainActor.run {
            switch listSubscription.result {
            case .success(let lists):
                #expect(lists.isEmpty, "Should start with empty lists")
            case .failure(let error):
                Issue.record("List subscription should not fail initially: \(error)")
            }
        }
        
        // Perform multiple operations in sequence
        var list1 = ShoppingList(name: "List 1")
        _ = await listRepo.insert(&list1)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        await MainActor.run {
            switch listSubscription.result {
            case .success(let lists):
                #expect(lists.count == 1, "Should have 1 list after first insert")
                #expect(lists.first?.name == "List 1", "Should contain first list")
            case .failure(let error):
                Issue.record("List subscription should update after first insert: \(error)")
            }
        }
        
        var list2 = ShoppingList(name: "List 2")
        _ = await listRepo.insert(&list2)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        await MainActor.run {
            switch listSubscription.result {
            case .success(let lists):
                #expect(lists.count == 2, "Should have 2 lists after second insert")
                #expect(Set(lists.map { $0.name }) == Set(["List 1", "List 2"]), "Should contain both lists")
            case .failure(let error):
                Issue.record("List subscription should update after second insert: \(error)")
            }
        }
        
        // Deactivate one list
        list1.isActive = false
        _ = await listRepo.update(list1)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Verify final state
        await MainActor.run {
            if case .success(let lists) = listSubscription.result {
                #expect(lists.count == 1, "Should only show active list")
                #expect(lists.first?.name == "List 2", "Should show the remaining active list")
            }
        }
    }
    
    @Test("Demo App Scenario - Filtered Item Subscription by List")
    func testDemoAppFilteredItemSubscription() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let orm = createInMemoryORM()
        let openResult = await orm.open()
        #expect(openResult.isSuccess, "ORM should open successfully")
        
        let listRepo = await orm.repository(for: ShoppingList.self)
        let itemRepo = await orm.repository(for: ShoppingItem.self)
        
        _ = await listRepo.createTable()
        _ = await itemRepo.createTable()
        
        // Create two lists
        var list1 = ShoppingList(name: "Groceries")
        var list2 = ShoppingList(name: "Electronics")
        _ = await listRepo.insert(&list1)
        _ = await listRepo.insert(&list2)
        
        // Create subscription for items in list1 only
        let list1ItemSubscription = itemRepo.subscribe(
            query: ORMQueryBuilder<ShoppingItem>()
                .where("listId", .equal, list1.id)
                .orderBy("addedAt", ascending: false)
        )
        
        // Wait for initial empty trigger
        try await Task.sleep(nanoseconds: 100_000_000)
        
        await MainActor.run {
            if case .success(let items) = list1ItemSubscription.result {
                #expect(items.isEmpty, "Should start empty for list1 items")
            }
        }
        
        // Add items to list1
        var item1 = ShoppingItem(listId: list1.id, name: "Apples", category: "Groceries")
        var item2 = ShoppingItem(listId: list1.id, name: "Bananas", category: "Groceries")
        _ = await itemRepo.insert(&item1)
        _ = await itemRepo.insert(&item2)
        
        // Add item to list2 (should not appear in list1 subscription)
        var item3 = ShoppingItem(listId: list2.id, name: "Phone", category: "Electronics")
        _ = await itemRepo.insert(&item3)
        
        // Wait for updates
        try await Task.sleep(nanoseconds: 200_000_000)
        
        await MainActor.run {
            if case .success(let items) = list1ItemSubscription.result {
                #expect(items.count == 2, "Should show only items from list1")
                #expect(items.allSatisfy { $0.listId == list1.id }, "All items should belong to list1")
                #expect(Set(items.map { $0.name }) == Set(["Apples", "Bananas"]), "Should contain correct items")
                #expect(!items.contains { $0.name == "Phone" }, "Should not contain items from other lists")
            }
        }
    }
    
    // MARK: - Multiple Insert/Delete Operation Tests
    
    @Test("Multiple Sequential Inserts - Single Subscription")
    func testMultipleSequentialInsertsSingleSubscription() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let orm = createInMemoryORM()
        let openResult = await orm.open()
        #expect(openResult.isSuccess, "ORM should open successfully")
        
        let listRepo = await orm.repository(for: ShoppingList.self)
        _ = await listRepo.createTable()
        
        // Create subscription first
        let listSubscription = listRepo.subscribe(
            query: ORMQueryBuilder<ShoppingList>()
                .where("isActive", .equal, true)
                .orderBy("name", ascending: true)
        )
        
        // Wait for initial empty state
        try await Task.sleep(nanoseconds: 100_000_000)
        
        await MainActor.run {
            switch listSubscription.result {
            case .success(let lists):
                #expect(lists.isEmpty, "Should start with empty lists")
            case .failure(let error):
                Issue.record("Initial subscription should not fail: \(error)")
            }
        }
        
        // Perform multiple sequential inserts
        let listNames = ["Groceries", "Electronics", "Clothing", "Books", "Home Supplies"]
        var insertedLists: [ShoppingList] = []
        
        for (index, name) in listNames.enumerated() {
            var list = ShoppingList(name: name)
            let insertResult = await listRepo.insert(&list)
            #expect(insertResult.isSuccess, "Insert of '\(name)' should succeed")
            insertedLists.append(list)
            
            // Wait for reactive update after each insert
            try await Task.sleep(nanoseconds: 150_000_000)
            
            // Verify subscription reflects the current state
            await MainActor.run {
                switch listSubscription.result {
                case .success(let lists):
                    #expect(lists.count == index + 1, "Should have \(index + 1) lists after insert \(index + 1)")
                    #expect(lists.map { $0.name }.sorted() == listNames.prefix(index + 1).sorted(), "Should contain correct lists up to index \(index)")
                    #expect(lists.allSatisfy { $0.isActive }, "All lists should be active")
                case .failure(let error):
                    Issue.record("Subscription should update after insert \(index + 1): \(error)")
                }
            }
        }
        
        // Verify final state has all lists
        await MainActor.run {
            switch listSubscription.result {
            case .success(let lists):
                #expect(lists.count == listNames.count, "Should have all \(listNames.count) lists")
                #expect(Set(lists.map { $0.name }) == Set(listNames), "Should contain all expected lists")
                #expect(lists.map { $0.name } == listNames.sorted(), "Should be ordered by name")
            case .failure(let error):
                Issue.record("Final state verification failed: \(error)")
            }
        }
    }
    
    @Test("Multiple Sequential Deletes - Single Subscription")
    func testMultipleSequentialDeletesSingleSubscription() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let orm = createInMemoryORM()
        let openResult = await orm.open()
        #expect(openResult.isSuccess, "ORM should open successfully")
        
        let listRepo = await orm.repository(for: ShoppingList.self)
        _ = await listRepo.createTable()
        
        // Insert initial data
        let listNames = ["Groceries", "Electronics", "Clothing", "Books", "Home Supplies"]
        var insertedLists: [ShoppingList] = []
        
        for name in listNames {
            var list = ShoppingList(name: name)
            let insertResult = await listRepo.insert(&list)
            #expect(insertResult.isSuccess, "Initial insert of '\(name)' should succeed")
            insertedLists.append(list)
        }
        
        // Create subscription after data exists
        let listSubscription = listRepo.subscribe(
            query: ORMQueryBuilder<ShoppingList>()
                .where("isActive", .equal, true)
                .orderBy("name", ascending: true)
        )
        
        // Wait for initial load
        try await Task.sleep(nanoseconds: 100_000_000)
        
        await MainActor.run {
            switch listSubscription.result {
            case .success(let lists):
                #expect(lists.count == listNames.count, "Should initially load all lists")
            case .failure(let error):
                Issue.record("Initial load should not fail: \(error)")
            }
        }
        
        // Perform multiple sequential deletes
        for (index, list) in insertedLists.enumerated() {
            let deleteResult = await listRepo.delete(id: list.id)
            #expect(deleteResult.isSuccess, "Delete of '\(list.name)' should succeed")
            
            // Wait for reactive update after each delete
            try await Task.sleep(nanoseconds: 150_000_000)
            
            let remainingCount = listNames.count - (index + 1)
            let remainingNames = Set(insertedLists.dropFirst(index + 1).map { $0.name })
            
            // Verify subscription reflects the current state
            await MainActor.run {
                switch listSubscription.result {
                case .success(let lists):
                    #expect(lists.count == remainingCount, "Should have \(remainingCount) lists after delete \(index + 1)")
                    #expect(Set(lists.map { $0.name }) == remainingNames, "Should contain correct remaining lists")
                    #expect(!lists.contains { $0.id == list.id }, "Deleted list should not appear")
                case .failure(let error):
                    Issue.record("Subscription should update after delete \(index + 1): \(error)")
                }
            }
        }
        
        // Verify final state is empty
        await MainActor.run {
            switch listSubscription.result {
            case .success(let lists):
                #expect(lists.isEmpty, "Should have no lists after all deletes")
            case .failure(let error):
                Issue.record("Final empty state verification failed: \(error)")
            }
        }
    }
    
    @Test("Mixed Insert/Delete Operations - Multiple Subscriptions")
    func testMixedOperationsMultipleSubscriptions() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let orm = createInMemoryORM()
        let openResult = await orm.open()
        #expect(openResult.isSuccess, "ORM should open successfully")
        
        let listRepo = await orm.repository(for: ShoppingList.self)
        let itemRepo = await orm.repository(for: ShoppingItem.self)
        _ = await listRepo.createTable()
        _ = await itemRepo.createTable()
        
        // Create multiple subscriptions with different filters
        let allListsSubscription = listRepo.subscribe()
        let activeListsSubscription = listRepo.subscribe(
            query: ORMQueryBuilder<ShoppingList>().where("isActive", .equal, true)
        )
        let allItemsSubscription = itemRepo.subscribe()
        let countSubscription = listRepo.subscribeCount()
        
        // Wait for initial setup
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Verify all subscriptions start empty
        await MainActor.run {
            if case .success(let lists) = allListsSubscription.result {
                #expect(lists.isEmpty, "All lists subscription should start empty")
            }
            if case .success(let lists) = activeListsSubscription.result {
                #expect(lists.isEmpty, "Active lists subscription should start empty")
            }
            if case .success(let items) = allItemsSubscription.result {
                #expect(items.isEmpty, "All items subscription should start empty")
            }
            if case .success(let count) = countSubscription.result {
                #expect(count == 0, "Count subscription should start at 0")
            }
        }
        
        // Step 1: Insert multiple lists
        var list1 = ShoppingList(name: "Groceries")
        var list2 = ShoppingList(name: "Electronics")
        _ = await listRepo.insert(&list1)
        _ = await listRepo.insert(&list2)
        
        try await Task.sleep(nanoseconds: 150_000_000)
        
        await MainActor.run {
            if case .success(let lists) = allListsSubscription.result {
                #expect(lists.count == 2, "All lists should show 2 lists")
            }
            if case .success(let lists) = activeListsSubscription.result {
                #expect(lists.count == 2, "Active lists should show 2 lists")
            }
            if case .success(let count) = countSubscription.result {
                #expect(count == 2, "Count should be 2")
            }
        }
        
        // Step 2: Insert items for both lists
        var item1 = ShoppingItem(listId: list1.id, name: "Apples", category: "Groceries")
        var item2 = ShoppingItem(listId: list1.id, name: "Bananas", category: "Groceries")
        var item3 = ShoppingItem(listId: list2.id, name: "Phone", category: "Electronics")
        
        _ = await itemRepo.insert(&item1)
        _ = await itemRepo.insert(&item2)
        _ = await itemRepo.insert(&item3)
        
        try await Task.sleep(nanoseconds: 150_000_000)
        
        await MainActor.run {
            if case .success(let items) = allItemsSubscription.result {
                #expect(items.count == 3, "Should have 3 items total")
                #expect(Set(items.map { $0.name }) == Set(["Apples", "Bananas", "Phone"]), "Should contain all items")
            }
        }
        
        // Step 3: Deactivate one list (mixed update operation)
        list1.isActive = false
        _ = await listRepo.update(list1)
        
        try await Task.sleep(nanoseconds: 150_000_000)
        
        await MainActor.run {
            if case .success(let allLists) = allListsSubscription.result {
                #expect(allLists.count == 2, "All lists should still show 2 lists")
            }
            if case .success(let activeLists) = activeListsSubscription.result {
                #expect(activeLists.count == 1, "Active lists should now show 1 list")
                #expect(activeLists.first?.name == "Electronics", "Should only show Electronics list")
            }
            if case .success(let count) = countSubscription.result {
                #expect(count == 2, "Total count should still be 2")
            }
        }
        
        // Step 4: Delete items from deactivated list
        _ = await itemRepo.delete(id: item1.id)
        _ = await itemRepo.delete(id: item2.id)
        
        try await Task.sleep(nanoseconds: 150_000_000)
        
        await MainActor.run {
            if case .success(let items) = allItemsSubscription.result {
                #expect(items.count == 1, "Should have 1 item remaining")
                #expect(items.first?.name == "Phone", "Should only have Phone item")
            }
        }
        
        // Step 5: Delete the remaining list
        _ = await listRepo.delete(id: list2.id)
        
        try await Task.sleep(nanoseconds: 150_000_000)
        
        await MainActor.run {
            if case .success(let allLists) = allListsSubscription.result {
                #expect(allLists.count == 1, "All lists should show 1 list (deactivated)")
            }
            if case .success(let activeLists) = activeListsSubscription.result {
                #expect(activeLists.isEmpty, "Active lists should be empty")
            }
            if case .success(let count) = countSubscription.result {
                #expect(count == 1, "Count should be 1")
            }
        }
        
        // Step 6: Delete the final list
        _ = await listRepo.delete(id: list1.id)
        
        try await Task.sleep(nanoseconds: 150_000_000)
        
        // Verify all subscriptions return to empty state
        await MainActor.run {
            if case .success(let allLists) = allListsSubscription.result {
                #expect(allLists.isEmpty, "All lists should be empty")
            }
            if case .success(let activeLists) = activeListsSubscription.result {
                #expect(activeLists.isEmpty, "Active lists should be empty")
            }
            if case .success(let items) = allItemsSubscription.result {
                #expect(items.count == 1, "Items should still show orphaned phone item")
            }
            if case .success(let count) = countSubscription.result {
                #expect(count == 0, "Count should be 0")
            }
        }
    }
    
    @Test("Rapid Batch Insert/Delete Operations")
    func testRapidBatchOperations() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let orm = createInMemoryORM()
        let openResult = await orm.open()
        #expect(openResult.isSuccess, "ORM should open successfully")
        
        let listRepo = await orm.repository(for: ShoppingList.self)
        _ = await listRepo.createTable()
        
        // Create subscription
        let subscription = listRepo.subscribe(
            query: ORMQueryBuilder<ShoppingList>()
                .where("isActive", .equal, true)
                .orderBy("createdAt", ascending: false)
        )
        
        // Wait for initial state
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Rapid batch insert (10 lists in quick succession)
        var insertedLists: [ShoppingList] = []
        for i in 0..<10 {
            var list = ShoppingList(name: "List \(i)")
            let result = await listRepo.insert(&list)
            #expect(result.isSuccess, "Batch insert \(i) should succeed")
            insertedLists.append(list)
            
            // Very short delay to simulate rapid operations
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }
        
        // Wait for all reactive updates to settle
        try await Task.sleep(nanoseconds: 300_000_000)
        
        await MainActor.run {
            switch subscription.result {
            case .success(let lists):
                #expect(lists.count == 10, "Should have all 10 inserted lists")
                #expect(Set(lists.map { $0.name }) == Set((0..<10).map { "List \($0)" }), "Should contain all expected lists")
            case .failure(let error):
                Issue.record("Batch insert should result in 10 lists: \(error)")
            }
        }
        
        // Rapid batch delete (delete every other list)
        for i in stride(from: 0, to: 10, by: 2) {
            let result = await listRepo.delete(id: insertedLists[i].id)
            #expect(result.isSuccess, "Batch delete \(i) should succeed")
            
            // Very short delay
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        
        // Wait for all deletes to settle
        try await Task.sleep(nanoseconds: 300_000_000)
        
        await MainActor.run {
            switch subscription.result {
            case .success(let lists):
                #expect(lists.count == 5, "Should have 5 remaining lists after batch delete")
                let expectedNames = Set([1, 3, 5, 7, 9].map { "List \($0)" })
                #expect(Set(lists.map { $0.name }) == expectedNames, "Should contain correct remaining lists")
            case .failure(let error):
                Issue.record("Batch delete should result in 5 lists: \(error)")
            }
        }
    }
    
    @Test("Concurrent Insert/Delete with Multiple Table Subscriptions")
    func testConcurrentOperationsMultipleTables() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let orm = createInMemoryORM()
        let openResult = await orm.open()
        #expect(openResult.isSuccess, "ORM should open successfully")
        
        let listRepo = await orm.repository(for: ShoppingList.self)
        let itemRepo = await orm.repository(for: ShoppingItem.self)
        _ = await listRepo.createTable()
        _ = await itemRepo.createTable()
        
        // Create subscriptions for both tables
        let listSubscription = listRepo.subscribe()
        let itemSubscription = itemRepo.subscribe()
        
        // Wait for initial setup
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Concurrent operations on both tables
        var list1 = ShoppingList(name: "List 1")
        var list2 = ShoppingList(name: "List 2")
        
        // Insert lists
        async let insert1 = listRepo.insert(&list1)
        async let insert2 = listRepo.insert(&list2)
        
        let (result1, result2) = await (insert1, insert2)
        #expect(result1.isSuccess && result2.isSuccess, "Concurrent list inserts should succeed")
        
        // Wait for updates
        try await Task.sleep(nanoseconds: 150_000_000)
        
        await MainActor.run {
            if case .success(let lists) = listSubscription.result {
                #expect(lists.count == 2, "Should have 2 lists after concurrent inserts")
            }
        }
        
        // Insert items for different lists sequentially to ensure predictable IDs
        var item1 = ShoppingItem(listId: list1.id, name: "Item 1A")
        var item2 = ShoppingItem(listId: list1.id, name: "Item 1B") 
        var item3 = ShoppingItem(listId: list2.id, name: "Item 2A")
        var item4 = ShoppingItem(listId: list2.id, name: "Item 2B")
        
        let ir1 = await itemRepo.insert(&item1)
        let ir2 = await itemRepo.insert(&item2)
        let ir3 = await itemRepo.insert(&item3) 
        let ir4 = await itemRepo.insert(&item4)
        
        #expect(ir1.isSuccess && ir2.isSuccess && ir3.isSuccess && ir4.isSuccess, "Item inserts should succeed")
        
        // Wait for updates
        try await Task.sleep(nanoseconds: 150_000_000)
        
        await MainActor.run {
            if case .success(let items) = itemSubscription.result {
                #expect(items.count == 4, "Should have 4 items after concurrent inserts")
                #expect(Set(items.map { $0.name }) == Set(["Item 1A", "Item 1B", "Item 2A", "Item 2B"]), "Should contain all items")
            }
        }
        
        // Delete specific items and verify which ones remain
        let deleteResult1 = await itemRepo.delete(id: item1.id)  // Delete "Item 1A"
        let deleteResult3 = await itemRepo.delete(id: item3.id)  // Delete "Item 2A"
        #expect(deleteResult1.isSuccess, "Delete of Item 1A should succeed")
        #expect(deleteResult3.isSuccess, "Delete of Item 2A should succeed")
        
        try await Task.sleep(nanoseconds: 150_000_000)
        
        await MainActor.run {
            if case .success(let items) = itemSubscription.result {
                #expect(items.count == 2, "Should have 2 items after deleting 2 items")
                let itemNames = Set(items.map { $0.name })
                // Should have Item 1B and Item 2B remaining
                #expect(itemNames.contains("Item 1B"), "Should contain Item 1B")
                #expect(itemNames.contains("Item 2B"), "Should contain Item 2B")
                #expect(!itemNames.contains("Item 1A"), "Should not contain deleted Item 1A")
                #expect(!itemNames.contains("Item 2A"), "Should not contain deleted Item 2A")
            }
        }
        
        // Now delete list2
        _ = await listRepo.delete(id: list2.id)
        
        // Wait for final updates
        try await Task.sleep(nanoseconds: 200_000_000)
        
        await MainActor.run {
            if case .success(let lists) = listSubscription.result {
                #expect(lists.count == 1, "Should have 1 list remaining")
                let remainingListName = lists.first?.name
                #expect(remainingListName == "List 1" || remainingListName == "List 2", "Should be one of the created lists")
            }
            if case .success(let items) = itemSubscription.result {
                // After deleting one list, should have items from remaining list plus potentially orphaned items
                #expect(items.count >= 1, "Should have at least 1 item remaining")
                let itemNames = Set(items.map { $0.name })
                // Should contain items that weren't deleted
                let hasValidItems = itemNames.contains("Item 1B") || itemNames.contains("Item 2B")
                #expect(hasValidItems, "Should contain at least one of the remaining items")
            }
        }
    }
    
    // MARK: - Advanced Edge Cases
    
    @Test("Empty Database Initial Subscription")
    func testSubscriptionEmptyDatabaseInitially() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, userRepo, _) = await setupTestEnvironment()
        
        // Create subscription on truly empty database
        let subscription = userRepo.subscribe()
        
        // Wait for initial load
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Should start with empty array, not nil or error
        await MainActor.run {
            switch subscription.result {
            case .success(let users):
                #expect(users.isEmpty, "Should start with empty array")
                #expect(users.count == 0, "Count should be exactly 0")
            case .failure(let error):
                Issue.record("Empty database should not cause error: \(error)")
            }
        }
        
        // Add first user and verify transition from empty to populated
        var user = TestUser(username: "first", email: "first@example.com")
        let insertResult = await userRepo.insert(&user)
        #expect(insertResult.isSuccess, "First user insert should succeed")
        
        // Wait for reactive update
        try await Task.sleep(nanoseconds: 200_000_000)
        
        await MainActor.run {
            switch subscription.result {
            case .success(let users):
                #expect(users.count == 1, "Should transition to 1 user")
                #expect(users.first?.username == "first", "Should contain the first user")
            case .failure(let error):
                Issue.record("Should successfully transition from empty to populated: \(error)")
            }
        }
    }
    
    @Test("Non-existent ID Subscription")
    func testSingleSubscriptionNonExistentId() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, userRepo, _) = await setupTestEnvironment()
        _ = await insertTestUsers(userRepo)
        
        // Subscribe to non-existent ID
        let subscription = userRepo.subscribe(id: 999)
        
        // Wait for initial load
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Should return nil for user, not error
        await MainActor.run {
            switch subscription.result {
            case .success(let user):
                #expect(user == nil, "Non-existent ID should return nil")
            case .failure(let error):
                Issue.record("Non-existent ID should not cause error: \(error)")
            }
        }
    }
    
    @Test("Rapid Sequential Updates Handling")
    func testSubscriptionRapidSequentialUpdates() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return // Skip test on older platforms
        }
        
        let (_, userRepo, _) = await setupTestEnvironment()
        var user = TestUser(username: "rapid", email: "rapid@example.com", score: 0)
        let insertResult = await userRepo.insert(&user)
        #expect(insertResult.isSuccess, "Initial user insert should succeed")
        
        // Create subscription
        let subscription = userRepo.subscribe()
        
        // Wait for initial load
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Perform rapid updates to test subscription stability
        for i in 1...5 {
            user.score = i * 100
            let updateResult = await userRepo.update(user)
            #expect(updateResult.isSuccess, "Rapid update \(i) should succeed")
            
            // Small delay between updates
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        
        // Wait for all updates to propagate
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Should reflect the final state correctly
        await MainActor.run {
            switch subscription.result {
            case .success(let users):
                #expect(users.count == 1, "Should maintain single user through rapid updates")
                #expect(users.first?.score == 500, "Should reflect final score after rapid updates")
            case .failure(let error):
                Issue.record("Rapid updates should not break subscription: \(error)")
            }
        }
    }
}

// MARK: - Test Utilities

/// Extension providing utility methods for test assertions
private extension ORMResult {
    /// Returns true if the result represents a successful operation
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}