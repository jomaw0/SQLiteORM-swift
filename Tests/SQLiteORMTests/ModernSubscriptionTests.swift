import Foundation
import Testing
@testable import SQLiteORM

@Suite("Modern Subscription API Tests")
struct ModernSubscriptionTests {
    
    private func setupDatabase() async -> ORM {
        let orm = createInMemoryORM()
        
        let openResult = await orm.open()
        #expect(openResult.toOptional() != nil, "Database should open successfully")
        
        let createResult = await orm.createTables(for: [User.self])
        #expect(createResult.toOptional() != nil, "Tables should be created successfully")
        
        return orm
    }
    
    @Test("New QuerySubscription works correctly")
    func testQuerySubscription() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: User.self)
        
        // Test new subscription method
        let subscription = repo.subscribeQuery()
        
        // Verify it's the new type
        #expect(type(of: subscription) == QuerySubscription<User>.self, "Should return QuerySubscription type")
        
        // Insert test data
        var user = User(
            username: "moderntest",
            email: "modern@example.com",
            firstName: "Modern",
            lastName: "Test",
            createdAt: Date()
        )
        
        let insertResult = await repo.insert(&user)
        #expect(insertResult.toOptional() != nil, "Insert should succeed")
        
        // Give subscription time to update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Verify subscription received the data
        await MainActor.run {
            switch subscription.result {
            case .success(let users):
                #expect(users.count >= 1, "Subscription should receive inserted user")
                #expect(users.contains { $0.username == "moderntest" }, "Should contain the inserted user")
            case .failure(let error):
                Issue.record("Subscription failed: \(error)")
            }
            
            // Test convenience properties
            #expect(subscription.hasItems, "Should have items")
            #expect(subscription.items.count >= 1, "Items should be accessible")
            #expect(subscription.error == nil, "Should have no error")
        }
    }
    
    @Test("New SingleQuerySubscription works correctly")
    func testSingleQuerySubscription() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: User.self)
        
        // Insert test data first
        var user = User(
            username: "singletest",
            email: "single@example.com",
            firstName: "Single",
            lastName: "Test",
            createdAt: Date()
        )
        
        let insertResult = await repo.insert(&user)
        #expect(insertResult.toOptional() != nil, "Insert should succeed")
        
        // Test new subscription method by ID
        let subscription = repo.subscribeSingle(id: user.id)
        
        // Verify it's the new type
        #expect(type(of: subscription) == SingleQuerySubscription<User>.self, "Should return SingleQuerySubscription type")
        
        // Give subscription time to load data
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Verify subscription received the data
        await MainActor.run {
            switch subscription.result {
            case .success(let foundUser):
                #expect(foundUser != nil, "Should find the user")
                #expect(foundUser?.username == "singletest", "Should find correct user")
            case .failure(let error):
                Issue.record("Single subscription failed: \(error)")
            }
            
            // Test convenience properties
            #expect(subscription.hasModel, "Should have model")
            #expect(subscription.model?.username == "singletest", "Model should be accessible")
            #expect(subscription.error == nil, "Should have no error")
        }
    }
    
    @Test("New CountSubscription works correctly")
    func testCountSubscription() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: User.self)
        
        // Test new subscription method
        let subscription = repo.subscribeCountQuery()
        
        // Verify it's the new type
        #expect(type(of: subscription) == CountSubscription<User>.self, "Should return CountSubscription type")
        
        // Initial count should be 0
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        await MainActor.run {
            switch subscription.result {
            case .success(let count):
                #expect(count == 0, "Initial count should be 0")
            case .failure(let error):
                Issue.record("Count subscription failed: \(error)")
            }
        }
        
        // Insert test data
        var user1 = User(
            username: "counttest1",
            email: "count1@example.com",
            firstName: "Count",
            lastName: "Test1",
            createdAt: Date()
        )
        
        var user2 = User(
            username: "counttest2",
            email: "count2@example.com",
            firstName: "Count",
            lastName: "Test2",
            createdAt: Date()
        )
        
        _ = await repo.insert(&user1)
        _ = await repo.insert(&user2)
        
        // Give subscription time to update
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // Verify count updated
        await MainActor.run {
            switch subscription.result {
            case .success(let count):
                #expect(count == 2, "Count should be 2 after inserts")
            case .failure(let error):
                Issue.record("Count subscription update failed: \(error)")
            }
            
            // Test convenience properties
            #expect(subscription.hasItems, "Should have items")
            #expect(subscription.count == 2, "Count should be accessible")
            #expect(subscription.error == nil, "Should have no error")
        }
    }
    
    @Test("Backward compatibility with deprecated methods")
    func testBackwardCompatibility() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: User.self)
        
        // Test that old methods still work (with deprecation warnings)
        let oldSubscription = repo.subscribe()
        let oldSingleSubscription = repo.subscribe(id: 1)
        let oldCountSubscription = repo.subscribeCount()
        
        // Verify the types are still the old ones
        #expect(type(of: oldSubscription) == SimpleQuerySubscription<User>.self, "Should return SimpleQuerySubscription")
        #expect(type(of: oldSingleSubscription) == SimpleSingleQuerySubscription<User>.self, "Should return SimpleSingleQuerySubscription")
        #expect(type(of: oldCountSubscription) == SimpleCountSubscription<User>.self, "Should return SimpleCountSubscription")
        
        // Test that they still function correctly
        var user = User(
            username: "backwardtest",
            email: "backward@example.com",
            firstName: "Backward",
            lastName: "Test",
            createdAt: Date()
        )
        
        _ = await repo.insert(&user)
        
        // Give subscriptions time to update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Verify old subscriptions still work
        await MainActor.run {
            switch oldSubscription.result {
            case .success(let users):
                #expect(users.count >= 1, "Old subscription should work")
            case .failure(let error):
                Issue.record("Old subscription failed: \(error)")
            }
        }
    }
    
    @Test("Query-based subscriptions work with new API")
    func testQueryBasedSubscriptions() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: User.self)
        
        // Insert test data
        var activeUser = User(
            username: "activeuser",
            email: "active@example.com",
            firstName: "Active",
            lastName: "User",
            createdAt: Date(),
            isActive: true
        )
        
        var inactiveUser = User(
            username: "inactiveuser",
            email: "inactive@example.com",
            firstName: "Inactive",
            lastName: "User",
            createdAt: Date(),
            isActive: false
        )
        
        _ = await repo.insert(&activeUser)
        _ = await repo.insert(&inactiveUser)
        
        // Test query subscription with filter
        let activeQuery = ORMQueryBuilder<User>().where("isActive", .equal, true)
        let activeSubscription = repo.subscribeQuery(query: activeQuery)
        
        // Test single subscription with query
        let firstActiveQuery = ORMQueryBuilder<User>().where("isActive", .equal, true)
        let firstActiveSubscription = repo.subscribeSingle(query: firstActiveQuery)
        
        // Test count subscription with query
        let activeCountQuery = ORMQueryBuilder<User>().where("isActive", .equal, true)
        let activeCountSubscription = repo.subscribeCountQuery(query: activeCountQuery)
        
        // Give subscriptions time to load data
        try await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds
        
        // Verify filtered results
        await MainActor.run {
            switch activeSubscription.result {
            case .success(let users):
                #expect(users.count == 1, "Should find only active user")
                #expect(users.first?.isActive == true, "Should be active user")
            case .failure(let error):
                Issue.record("Active query subscription failed: \(error)")
            }
            
            switch firstActiveSubscription.result {
            case .success(let user):
                #expect(user != nil, "Should find first active user")
                #expect(user?.isActive == true, "Should be active user")
            case .failure(let error):
                Issue.record("First active subscription failed: \(error)")
            }
            
            switch activeCountSubscription.result {
            case .success(let count):
                #expect(count == 1, "Should count only active user")
            case .failure(let error):
                Issue.record("Active count subscription failed: \(error)")
            }
        }
    }
}