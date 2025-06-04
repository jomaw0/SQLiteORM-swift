import Foundation
import Testing
@testable import SQLiteORM

@Suite("Predicate-Based Query System")
struct PredicateQueryTests {
    
    private func setupDatabaseWithTestData() async -> ORM {
        let orm = createInMemoryORM()
        
        let openResult = await orm.open()
        #expect(openResult.toOptional() != nil)
        
        let createResult = await orm.createTables(for: [User.self])
        #expect(createResult.toOptional() != nil)
        
        // Insert test data
        let repo = await orm.repository(for: User.self)
        let users = [
            User(username: "john_doe", email: "john@example.com", firstName: "John", lastName: "Doe", createdAt: Date(), score: 85.5),
            User(username: "jane_smith", email: "jane@example.com", firstName: "Jane", lastName: "Smith", createdAt: Date(), score: 92.0),
            User(username: "bob_jones", email: "bob@example.com", firstName: "Bob", lastName: "Jones", createdAt: Date(), score: 78.3),
            User(username: "alice_wonder", email: "alice@example.com", firstName: "Alice", lastName: "Wonder", createdAt: Date(), score: 95.0),
            User(username: "charlie_brown", email: "charlie@example.com", firstName: "Charlie", lastName: "Brown", createdAt: Date(), score: 88.7)
        ]
        
        for var user in users {
            _ = await repo.insert(&user)
        }
        
        return orm
    }
    
    @Test("Complex predicate query with AND/OR")
    func testComplexPredicateQuery() async throws {
        let orm = await setupDatabaseWithTestData()
        defer { Task { _ = await orm.close() } }
        
        // Complex query with AND/OR conditions
        let query = await orm.query(User.self)
            .where(.and([
                .column("score", .greaterThan, .real(80.0)),
                .or([
                    .column("firstName", .like, .text("J%")),
                    .isNotNull("updatedAt")
                ])
            ]))
            .orderBy("score", .descending)
            .limit(50)
        
        let result = await query.fetch()
        
        switch result {
        case .success(let users):
            // Should find users with score > 80 AND (firstName starts with J OR updatedAt is not null)
            // Since updatedAt is null for all, should only find John and Jane
            #expect(users.count == 2)
            #expect(users[0].firstName == "Jane") // Highest score with J
            #expect(users[1].firstName == "John") // Second highest with J
        case .failure(let error):
            Issue.record("Query failed: \(error)")
        }
    }
    
    @Test("Model static query methods")
    func testModelStaticQuery() async throws {
        let orm = await setupDatabaseWithTestData()
        defer { Task { _ = await orm.close() } }
        
        // Query directly from model type
        let query = await User.query(using: orm)
            .where(.and([
                .column("isActive", .equal, .bool(true)),
                .column("email", .like, .text("%@example.com"))
            ]))
            .orderBy("username", .ascending)
        
        let result = await query.fetch()
        
        switch result {
        case .success(let users):
            #expect(users.count == 5) // All users have @example.com email and are active
            #expect(users[0].username == "alice_wonder") // First alphabetically
        case .failure(let error):
            Issue.record("Query failed: \(error)")
        }
    }
    
    @Test("Where shorthand on model")
    func testWhereShorthand() async throws {
        let orm = await setupDatabaseWithTestData()
        defer { Task { _ = await orm.close() } }
        
        // Using where shorthand on model
        let query = await User.where(
            .between("score", .real(85.0), .real(93.0)),
            using: orm
        )
        .orderBy("score", .ascending)
        
        let result = await query.fetch()
        
        switch result {
        case .success(let users):
            #expect(users.count == 3) // John (85.5), Charlie (88.7), Jane (92.0)
            #expect(users[0].firstName == "John")
            #expect(users[1].firstName == "Charlie")
            #expect(users[2].firstName == "Jane")
        case .failure(let error):
            Issue.record("Query failed: \(error)")
        }
    }
    
    @Test("IN predicate")
    func testInPredicate() async throws {
        let orm = await setupDatabaseWithTestData()
        defer { Task { _ = await orm.close() } }
        
        let query = await orm.query(User.self)
            .where(.in("firstName", [.text("John"), .text("Jane"), .text("Bob")]))
            .orderBy("firstName", .ascending)
        
        let result = await query.fetch()
        
        switch result {
        case .success(let users):
            #expect(users.count == 3)
            #expect(users.map { $0.firstName } == ["Bob", "Jane", "John"])
        case .failure(let error):
            Issue.record("Query failed: \(error)")
        }
    }
    
    @Test("NOT predicate")
    func testNotPredicate() async throws {
        let orm = await setupDatabaseWithTestData()
        defer { Task { _ = await orm.close() } }
        
        let query = await orm.query(User.self)
            .where(.not(.column("firstName", .equal, .text("John"))))
            .orderBy("username", .ascending)
        
        let result = await query.fetch()
        
        switch result {
        case .success(let users):
            #expect(users.count == 4) // Everyone except John
            #expect(!users.contains { $0.firstName == "John" })
        case .failure(let error):
            Issue.record("Query failed: \(error)")
        }
    }
    
    @Test("Count with predicate")
    func testCountWithPredicate() async throws {
        let orm = await setupDatabaseWithTestData()
        defer { Task { _ = await orm.close() } }
        
        let query = await orm.query(User.self)
            .where(.column("score", .greaterThanOrEqual, .real(90.0)))
        
        let countResult = await query.count()
        
        switch countResult {
        case .success(let count):
            #expect(count == 2) // Jane (92.0) and Alice (95.0)
        case .failure(let error):
            Issue.record("Count failed: \(error)")
        }
    }
    
    @Test("Fetch first with predicate")
    func testFetchFirst() async throws {
        let orm = await setupDatabaseWithTestData()
        defer { Task { _ = await orm.close() } }
        
        let query = await orm.query(User.self)
            .where(.column("score", .greaterThan, .real(90.0)))
            .orderBy("score", .descending)
        
        let result = await query.fetchFirst()
        
        switch result {
        case .success(let user):
            #expect(user != nil)
            #expect(user?.firstName == "Alice") // Highest score > 90
        case .failure(let error):
            Issue.record("Fetch first failed: \(error)")
        }
    }
    
    @Test("Raw predicate")
    func testRawPredicate() async throws {
        let orm = await setupDatabaseWithTestData()
        defer { Task { _ = await orm.close() } }
        
        // For complex SQL that doesn't fit the predicate model
        let query = await orm.query(User.self)
            .where(.raw("score > ? AND LENGTH(user_name) > ?", [.real(85.0), .integer(8)]))
            .orderBy("username", .ascending)
        
        let result = await query.fetch()
        
        switch result {
        case .success(let users):
            // jane_smith (92.0), alice_wonder (95.0), charlie_brown (88.7)
            #expect(users.count == 3)
        case .failure(let error):
            Issue.record("Raw query failed: \(error)")
        }
    }
}