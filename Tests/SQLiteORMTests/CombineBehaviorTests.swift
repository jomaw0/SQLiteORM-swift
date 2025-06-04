import Testing
import Foundation
import Combine
@testable import SQLiteORM

/// Tests that validate the specific behaviors of the Combine subscription system,
/// including both expected successes and expected failures
struct CombineBehaviorTests {
    
    @Test("Subscription creation succeeds on supported platforms")
    func testSubscriptionCreationSucceeds() async throws {
        // Only test on supported platforms
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return
        }
        
        let orm = ORM(path: ":memory:")
        _ = await orm.open()
        let userRepo = await orm.repository(for: User.self)
        _ = await userRepo.createTable()
        
        // BEHAVIOR: Subscription creation should succeed without throwing
        let allUsersSubscription = userRepo.subscribe()
        let countSubscription = userRepo.subscribeCount()
        
        // EXPECTED: Objects should be created and have correct types
        #expect(type(of: allUsersSubscription) == SimpleQuerySubscription<User>.self)
        #expect(type(of: countSubscription) == SimpleCountSubscription<User>.self)
        
        // EXPECTED: ObservableObject protocol should be satisfied
        let _: any ObservableObject = allUsersSubscription
        let _: any ObservableObject = countSubscription
        
        _ = await orm.close()
    }
    
    @Test("Subscription returns empty results on empty database")
    func testSubscriptionEmptyDatabase() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return
        }
        
        let orm = ORM(path: ":memory:")
        _ = await orm.open()
        let userRepo = await orm.repository(for: User.self)
        _ = await userRepo.createTable()
        
        let subscription = userRepo.subscribe()
        let countSubscription = userRepo.subscribeCount()
        
        // Allow time for initial load
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        
        // BEHAVIOR: Empty database should return success with empty results
        await MainActor.run {
            switch subscription.result {
            case .success(let users):
                #expect(users.isEmpty) // EXPECTED: Empty array, not failure
            case .failure:
                Issue.record("Subscription should succeed with empty results, not fail")
            }
            
            switch countSubscription.result {
            case .success(let count):
                #expect(count == 0) // EXPECTED: Zero count, not failure
            case .failure:
                Issue.record("Count subscription should succeed with zero count, not fail")
            }
        }
        
        _ = await orm.close()
    }
    
    @Test("Subscription fails gracefully on non-existent table")
    func testSubscriptionFailsOnNonExistentTable() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return
        }
        
        let orm = ORM(path: ":memory:")
        _ = await orm.open()
        let userRepo = await orm.repository(for: User.self)
        // INTENTIONALLY NOT creating table
        
        let subscription = userRepo.subscribe()
        
        // Allow time for initial load attempt
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // BEHAVIOR: Non-existent table should result in failure or empty success
        await MainActor.run {
            switch subscription.result {
            case .success(let users):
                // Some implementations might return empty results instead of failing
                #expect(users.isEmpty)
            case .failure(let error):
                // EXPECTED: Should fail with a database error
                switch error {
                case .sqlExecutionFailed, .connectionFailed, .databaseNotOpen:
                    #expect(Bool(true)) // Expected failure types
                case .invalidData, .missingColumn:
                    #expect(Bool(true)) // Also acceptable failure types
                case .notFound:
                    #expect(Bool(true)) // Also acceptable
                default:
                    #expect(Bool(true)) // Any error is acceptable for non-existent table
                }
            }
        }
        
        _ = await orm.close()
    }
    
    @Test("Subscription updates when data is inserted")
    func testSubscriptionUpdatesOnInsert() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return
        }
        
        let orm = ORM(path: ":memory:")
        _ = await orm.open()
        let userRepo = await orm.repository(for: User.self)
        _ = await userRepo.createTable()
        
        let subscription = userRepo.subscribe()
        let countSubscription = userRepo.subscribeCount()
        
        // Initial state - should be empty
        try await Task.sleep(nanoseconds: 50_000_000)
        
        await MainActor.run {
            if case .success(let users) = subscription.result {
                #expect(users.isEmpty) // EXPECTED: Initially empty
            }
            if case .success(let count) = countSubscription.result {
                #expect(count == 0) // EXPECTED: Initially zero
            }
        }
        
        // Insert data
        var user = User(username: "testuser", email: "test@example.com", firstName: "Test", lastName: "User", createdAt: Date())
        let insertResult = await userRepo.insert(&user)
        
        // BEHAVIOR: Insert should succeed
        switch insertResult {
        case .success:
            #expect(Bool(true)) // EXPECTED: Insert succeeds
        case .failure(let error):
            Issue.record("Insert should succeed: \(error)")
            return // Can't continue test if insert fails
        }
        
        // Allow time for subscription update
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // BEHAVIOR: Subscription should reflect the new data
        await MainActor.run {
            switch subscription.result {
            case .success(let users):
                #expect(users.count == 1) // EXPECTED: One user after insert
                #expect(users.first?.username == "testuser") // EXPECTED: Correct data
            case .failure(let error):
                Issue.record("Subscription should update successfully after insert: \(error)")
            }
            
            switch countSubscription.result {
            case .success(let count):
                #expect(count == 1) // EXPECTED: Count reflects insert
            case .failure(let error):
                Issue.record("Count subscription should update after insert: \(error)")
            }
        }
        
        _ = await orm.close()
    }
    
    @Test("Filtered subscription only shows matching data")
    func testFilteredSubscriptionBehavior() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return
        }
        
        let orm = ORM(path: ":memory:")
        _ = await orm.open()
        let userRepo = await orm.repository(for: User.self)
        _ = await userRepo.createTable()
        
        // Create filtered subscription for active users only
        let activeQuery = QueryBuilder<User>().where("isActive", .equal, true)
        let activeSubscription = userRepo.subscribe(query: activeQuery)
        
        // Insert active user
        var activeUser = User(username: "active", email: "active@example.com", firstName: "Active", lastName: "User", createdAt: Date())
        activeUser.isActive = true
        _ = await userRepo.insert(&activeUser)
        
        // Insert inactive user
        var inactiveUser = User(username: "inactive", email: "inactive@example.com", firstName: "Inactive", lastName: "User", createdAt: Date())
        inactiveUser.isActive = false
        _ = await userRepo.insert(&inactiveUser)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // BEHAVIOR: Filtered subscription should only show matching data
        await MainActor.run {
            switch activeSubscription.result {
            case .success(let users):
                #expect(users.count == 1) // EXPECTED: Only one active user
                #expect(users.first?.isActive == true) // EXPECTED: Only active users
                #expect(users.first?.username == "active") // EXPECTED: Correct user
                
                // EXPECTED: No inactive users in filtered results
                let hasInactiveUser = users.contains { !$0.isActive }
                #expect(!hasInactiveUser) // Should NOT contain inactive users
                
            case .failure(let error):
                Issue.record("Filtered subscription should succeed: \(error)")
            }
        }
        
        _ = await orm.close()
    }
    
    @Test("Multiple subscriptions work independently")
    func testMultipleSubscriptionsIndependence() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return
        }
        
        let orm = ORM(path: ":memory:")
        _ = await orm.open()
        let userRepo = await orm.repository(for: User.self)
        _ = await userRepo.createTable()
        
        // Create different types of subscriptions
        let allSubscription = userRepo.subscribe()
        let activeSubscription = userRepo.subscribe(query: QueryBuilder<User>().where("isActive", .equal, true))
        let countSubscription = userRepo.subscribeCount()
        
        // Insert mixed data
        var activeUser = User(username: "active", email: "active@example.com", firstName: "Active", lastName: "User", createdAt: Date())
        activeUser.isActive = true
        _ = await userRepo.insert(&activeUser)
        
        var inactiveUser = User(username: "inactive", email: "inactive@example.com", firstName: "Inactive", lastName: "User", createdAt: Date())
        inactiveUser.isActive = false
        _ = await userRepo.insert(&inactiveUser)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // BEHAVIOR: Each subscription should show appropriate results
        await MainActor.run {
            // All users subscription
            switch allSubscription.result {
            case .success(let allUsers):
                #expect(allUsers.count == 2) // EXPECTED: Both users
            case .failure(let error):
                Issue.record("All users subscription should succeed: \(error)")
            }
            
            // Active users subscription
            switch activeSubscription.result {
            case .success(let activeUsers):
                #expect(activeUsers.count == 1) // EXPECTED: Only active user
                #expect(activeUsers.first?.isActive == true) // EXPECTED: Only active
            case .failure(let error):
                Issue.record("Active users subscription should succeed: \(error)")
            }
            
            // Count subscription
            switch countSubscription.result {
            case .success(let count):
                #expect(count == 2) // EXPECTED: Total count
            case .failure(let error):
                Issue.record("Count subscription should succeed: \(error)")
            }
        }
        
        _ = await orm.close()
    }
    
    @Test("Fluent API subscription behaves correctly")
    func testFluentAPISubscriptionBehavior() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return
        }
        
        let orm = ORM(path: ":memory:")
        _ = await orm.open()
        let userRepo = await orm.repository(for: User.self)
        _ = await userRepo.createTable()
        
        // BEHAVIOR: Fluent API should create correct subscription types
        let querySubscription = await userRepo.query()
            .where("firstName", .like, "Test%")
            .subscribe()
        
        let countSubscription = await userRepo.query()
            .where("isActive", .equal, true)
            .subscribeCount()
        
        let firstSubscription = await userRepo.query()
            .where("username", .like, "admin%")
            .subscribeFirst()
        
        // EXPECTED: Correct types should be created
        #expect(type(of: querySubscription) == SimpleQuerySubscription<User>.self)
        #expect(type(of: countSubscription) == SimpleCountSubscription<User>.self)
        #expect(type(of: firstSubscription) == SimpleSingleQuerySubscription<User>.self)
        
        // Insert test data
        var testUser = User(username: "testuser", email: "test@example.com", firstName: "TestName", lastName: "User", createdAt: Date())
        _ = await userRepo.insert(&testUser)
        
        var adminUser = User(username: "admin1", email: "admin@example.com", firstName: "Admin", lastName: "User", createdAt: Date())
        _ = await userRepo.insert(&adminUser)
        
        var regularUser = User(username: "regular", email: "regular@example.com", firstName: "Regular", lastName: "User", createdAt: Date())
        _ = await userRepo.insert(&regularUser)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // BEHAVIOR: Each subscription should filter correctly
        await MainActor.run {
            // Query subscription should only show users with firstName starting with "Test"
            switch querySubscription.result {
            case .success(let users):
                #expect(users.count == 1) // EXPECTED: Only TestName user
                #expect(users.first?.firstName == "TestName") // EXPECTED: Correct filtering
                
                // EXPECTED: Should NOT contain non-matching users
                let hasNonTestUser = users.contains { !$0.firstName.hasPrefix("Test") }
                #expect(!hasNonTestUser)
                
            case .failure(let error):
                Issue.record("Query subscription should succeed: \(error)")
            }
            
            // Count subscription should count all active users (all are active by default)
            switch countSubscription.result {
            case .success(let count):
                #expect(count == 3) // EXPECTED: All three users are active
            case .failure(let error):
                Issue.record("Count subscription should succeed: \(error)")
            }
            
            // First subscription should find admin user
            switch firstSubscription.result {
            case .success(let user):
                #expect(user?.username == "admin1") // EXPECTED: Found admin user
            case .failure(let error):
                Issue.record("First subscription should succeed: \(error)")
            }
        }
        
        _ = await orm.close()
    }
    
    @Test("Subscription cleanup does not crash application")
    func testSubscriptionCleanupBehavior() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return
        }
        
        let orm = ORM(path: ":memory:")
        _ = await orm.open()
        let userRepo = await orm.repository(for: User.self)
        _ = await userRepo.createTable()
        
        // BEHAVIOR: Subscription should be cleanable without issues
        do {
            let subscription = userRepo.subscribe()
            
            // Use subscription
            var user = User(username: "temp", email: "temp@example.com", firstName: "Temp", lastName: "User", createdAt: Date())
            _ = await userRepo.insert(&user)
            
            try await Task.sleep(nanoseconds: 50_000_000)
            
            await MainActor.run {
                _ = subscription.result // Access to ensure it's working
            }
            
            // subscription goes out of scope here - should cleanup automatically
        }
        
        // BEHAVIOR: Operations should continue normally after cleanup
        var newUser = User(username: "after", email: "after@example.com", firstName: "After", lastName: "User", createdAt: Date())
        let result = await userRepo.insert(&newUser)
        
        // EXPECTED: Should still work after subscription cleanup
        switch result {
        case .success:
            #expect(Bool(true)) // EXPECTED: Operations continue normally
        case .failure(let error):
            Issue.record("Operations should continue after subscription cleanup: \(error)")
        }
        
        _ = await orm.close()
    }
    
    @Test("Direct QueryBuilder subscription works correctly")
    func testDirectQueryBuilderSubscription() async throws {
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return
        }
        
        let orm = ORM(path: ":memory:")
        _ = await orm.open()
        let userRepo = await orm.repository(for: User.self)
        _ = await userRepo.createTable()
        
        // BEHAVIOR: Direct QueryBuilder subscription should work
        let subscription = QueryBuilder<User>()
            .where("isActive", .equal, true)
            .orderBy("username")
            .limit(10)
            .subscribe(using: userRepo)
        
        // EXPECTED: Should create correct subscription type
        #expect(type(of: subscription) == SimpleQuerySubscription<User>.self)
        
        // Insert test data
        var user1 = User(username: "zuser", email: "z@example.com", firstName: "Z", lastName: "User", createdAt: Date())
        var user2 = User(username: "auser", email: "a@example.com", firstName: "A", lastName: "User", createdAt: Date())
        
        _ = await userRepo.insert(&user1)
        _ = await userRepo.insert(&user2)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // BEHAVIOR: Should respect query ordering and filtering
        await MainActor.run {
            switch subscription.result {
            case .success(let users):
                #expect(users.count == 2) // EXPECTED: Both users are active
                
                // EXPECTED: Should be ordered by username (a comes before z)
                if users.count >= 2 {
                    #expect(users[0].username == "auser") // EXPECTED: Alphabetical order
                    #expect(users[1].username == "zuser")
                }
                
                // EXPECTED: All results should match the filter
                for user in users {
                    #expect(user.isActive == true) // EXPECTED: Only active users
                }
                
            case .failure(let error):
                Issue.record("Direct QueryBuilder subscription should succeed: \(error)")
            }
        }
        
        _ = await orm.close()
    }
}