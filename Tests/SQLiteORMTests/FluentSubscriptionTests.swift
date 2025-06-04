import Testing
import Foundation
@testable import SQLiteORM

struct FluentSubscriptionTests {
    
    @Test("QueryBuilder subscription with using parameter")
    func testQueryBuilderSubscription() async throws {
        // Only test on supported platforms
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return
        }
        
        let orm = ORM(path: ":memory:")
        _ = await orm.open()
        let userRepo = await orm.repository(for: User.self)
        _ = await userRepo.createTable()
        
        // Test fluent subscription API
        let subscription = QueryBuilder<User>()
            .where("isActive", .equal, true)
            .orderBy("username")
            .limit(10)
            .subscribe(using: userRepo)
        
        // Verify subscription type
        #expect(type(of: subscription) == SimpleQuerySubscription<User>.self)
        
        _ = await orm.close()
    }
    
    @Test("QueryBuilderWithRepository fluent chaining")
    func testQueryBuilderWithRepositoryChaining() async throws {
        // Only test on supported platforms
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return
        }
        
        let orm = ORM(path: ":memory:")
        _ = await orm.open()
        let userRepo = await orm.repository(for: User.self)
        _ = await userRepo.createTable()
        
        // Test fluent query building with repository context
        let subscription = await userRepo.query()
            .where("isActive", .equal, true)
            .where("firstName", .like, "J%")
            .orderBy("username")
            .limit(5)
            .subscribe()
        
        // Verify subscription type
        #expect(type(of: subscription) == SimpleQuerySubscription<User>.self)
        
        // Test count subscription
        let countSubscription = await userRepo.query()
            .where("isActive", .equal, true)
            .subscribeCount()
        
        // Verify count subscription type
        #expect(type(of: countSubscription) == SimpleCountSubscription<User>.self)
        
        // Test first subscription
        let firstSubscription = await userRepo.query()
            .where("username", .like, "admin%")
            .orderBy("createdAt", ascending: false)
            .subscribeFirst()
        
        // Verify first subscription type
        #expect(type(of: firstSubscription) == SimpleSingleQuerySubscription<User>.self)
        
        _ = await orm.close()
    }
    
    @Test("QueryBuilderWithRepository execution methods")
    func testQueryBuilderWithRepositoryExecution() async throws {
        // Only test on supported platforms
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return
        }
        
        let orm = ORM(path: ":memory:")
        _ = await orm.open()
        let userRepo = await orm.repository(for: User.self)
        _ = await userRepo.createTable()
        
        // Insert test data
        var user1 = User(username: "john", email: "john@example.com", firstName: "John", lastName: "Doe", createdAt: Date())
        _ = await userRepo.insert(&user1)
        
        var user2 = User(username: "jane", email: "jane@example.com", firstName: "Jane", lastName: "Smith", createdAt: Date())
        _ = await userRepo.insert(&user2)
        
        // Test findAll through QueryBuilderWithRepository
        let allUsersResult = await userRepo.query()
            .where("isActive", .equal, true)
            .orderBy("username")
            .findAll()
        
        switch allUsersResult {
        case .success(let users):
            #expect(users.count == 2)
            #expect(users[0].username == "jane") // jane comes first alphabetically
            #expect(users[1].username == "john")
        case .failure:
            Issue.record("findAll should succeed")
        }
        
        // Test findFirst through QueryBuilderWithRepository
        let firstUserResult = await userRepo.query()
            .where("firstName", .equal, "John")
            .findFirst()
        
        switch firstUserResult {
        case .success(let user):
            #expect(user != nil)
            #expect(user?.username == "john")
        case .failure:
            Issue.record("findFirst should succeed")
        }
        
        // Test count through QueryBuilderWithRepository
        let countResult = await userRepo.query()
            .where("isActive", .equal, true)
            .count()
        
        switch countResult {
        case .success(let count):
            #expect(count == 2)
        case .failure:
            Issue.record("count should succeed")
        }
        
        _ = await orm.close()
    }
    
    @Test("Complex query chaining with subscriptions")
    func testComplexQueryChaining() async throws {
        // Only test on supported platforms
        guard #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) else {
            return
        }
        
        let orm = ORM(path: ":memory:")
        _ = await orm.open()
        let userRepo = await orm.repository(for: User.self)
        _ = await userRepo.createTable()
        
        // Test complex chaining with multiple conditions
        let complexSubscription = await userRepo.query()
            .select("username", "email", "firstName")
            .where("isActive", .equal, true)
            .whereLike("email", "%@example.com")
            .whereIn("firstName", ["John", "Jane", "Bob"])
            .orderBy("createdAt", ascending: false)
            .orderBy("username", ascending: true)
            .limit(50)
            .offset(0)
            .subscribe()
        
        // Verify it's the correct type
        #expect(type(of: complexSubscription) == SimpleQuerySubscription<User>.self)
        
        // Test that we can also get the underlying QueryBuilder
        let queryBuilder = await userRepo.query()
            .where("score", .greaterThan, 100.0)
            .asQueryBuilder()
        
        // Verify it's a QueryBuilder
        #expect(type(of: queryBuilder) == QueryBuilder<User>.self)
        
        _ = await orm.close()
    }
}