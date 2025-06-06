import Foundation
import Testing
@testable import SQLiteORM

@Suite("Convenient Subscription Methods Tests")
struct ConvenientSubscriptionTests {
    
    private func setupDatabase() async -> ORM {
        let orm = createInMemoryORM()
        
        let openResult = await orm.open()
        #expect(openResult.toOptional() != nil, "Database should open successfully")
        
        let createResult = await orm.createTables(for: [User.self, Post.self])
        #expect(createResult.toOptional() != nil, "Tables should be created successfully")
        
        return orm
    }
    
    @Test("subscribeExists() method works correctly")
    func testSubscribeExists() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: User.self)
        
        // Test existence subscription with no data
        let existsSubscription = repo.subscribeExists()
        
        // Give subscription time to load initial state
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        await MainActor.run {
            #expect(!existsSubscription.exists, "Should not exist initially")
            switch existsSubscription.result {
            case .success(let exists):
                #expect(!exists, "No users should exist initially")
            case .failure(let error):
                Issue.record("Exists subscription failed: \(error)")
            }
        }
        
        // Insert a user
        var user = User(
            username: "existstest",
            email: "exists@example.com",
            firstName: "Exists",
            lastName: "Test",
            createdAt: Date()
        )
        
        _ = await repo.insert(&user)
        
        // Give subscription time to update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        await MainActor.run {
            #expect(existsSubscription.exists, "Should exist after insert")
            switch existsSubscription.result {
            case .success(let exists):
                #expect(exists, "Users should exist after insert")
            case .failure(let error):
                Issue.record("Exists subscription update failed: \(error)")
            }
        }
    }
    
    @Test("subscribeExists(id:) method works correctly")
    func testSubscribeExistsById() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: User.self)
        
        // Test existence subscription for specific ID
        let existsByIdSubscription = repo.subscribeExists(id: 999)
        
        // Give subscription time to load initial state
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        await MainActor.run {
            #expect(!existsByIdSubscription.exists, "ID 999 should not exist initially")
        }
        
        // Insert a user with known ID
        var user = User(
            username: "specifictest",
            email: "specific@example.com",
            firstName: "Specific",
            lastName: "Test",
            createdAt: Date()
        )
        user.id = 999
        
        _ = await repo.insert(&user)
        
        // Give subscription time to update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        await MainActor.run {
            #expect(existsByIdSubscription.exists, "ID 999 should exist after insert")
        }
    }
    
    @Test("subscribeLatest() and subscribeOldest() methods work correctly")
    func testSubscribeLatestAndOldest() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: User.self)
        
        // Test latest and oldest subscriptions
        let latestSubscription = repo.subscribeLatest()
        let oldestSubscription = repo.subscribeOldest()
        
        // Insert users with different IDs
        var user1 = User(
            username: "first",
            email: "first@example.com",
            firstName: "First",
            lastName: "User",
            createdAt: Date()
        )
        user1.id = 1
        
        var user2 = User(
            username: "second",
            email: "second@example.com",
            firstName: "Second",
            lastName: "User",
            createdAt: Date()
        )
        user2.id = 2
        
        var user3 = User(
            username: "third",
            email: "third@example.com",
            firstName: "Third",
            lastName: "User",
            createdAt: Date()
        )
        user3.id = 3
        
        _ = await repo.insert(&user1)
        _ = await repo.insert(&user2)
        _ = await repo.insert(&user3)
        
        // Give subscriptions time to update
        try await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds
        
        await MainActor.run {
            // Test latest (highest ID)
            switch latestSubscription.result {
            case .success(let latestUser):
                #expect(latestUser != nil, "Should find latest user")
                #expect(latestUser?.id == 3, "Latest user should have ID 3")
                #expect(latestUser?.username == "third", "Latest user should be 'third'")
            case .failure(let error):
                Issue.record("Latest subscription failed: \(error)")
            }
            
            // Test oldest (lowest ID)
            switch oldestSubscription.result {
            case .success(let oldestUser):
                #expect(oldestUser != nil, "Should find oldest user")
                #expect(oldestUser?.id == 1, "Oldest user should have ID 1")
                #expect(oldestUser?.username == "first", "Oldest user should be 'first'")
            case .failure(let error):
                Issue.record("Oldest subscription failed: \(error)")
            }
        }
    }
    
    @Test("subscribeWhere() convenience methods work correctly")
    func testSubscribeWhereMethods() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: User.self)
        
        // Test subscribeWhere with equals
        let activeUsersSubscription = repo.subscribeWhere("isActive", equals: true)
        
        // Test subscribeWhere with contains
        let searchSubscription = repo.subscribeWhere("username", contains: "search")
        
        // Insert test data
        var activeUser = User(
            username: "searchactive",
            email: "active@example.com",
            firstName: "Active",
            lastName: "User",
            createdAt: Date(),
            isActive: true
        )
        
        var inactiveUser = User(
            username: "searchinactive",
            email: "inactive@example.com",
            firstName: "Inactive",
            lastName: "User",
            createdAt: Date(),
            isActive: false
        )
        
        var otherUser = User(
            username: "other",
            email: "other@example.com",
            firstName: "Other",
            lastName: "User",
            createdAt: Date(),
            isActive: true
        )
        
        _ = await repo.insert(&activeUser)
        _ = await repo.insert(&inactiveUser)
        _ = await repo.insert(&otherUser)
        
        // Give subscriptions time to update
        try await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds
        
        await MainActor.run {
            // Test active users subscription
            switch activeUsersSubscription.result {
            case .success(let users):
                #expect(users.count == 2, "Should find 2 active users")
                #expect(users.allSatisfy { $0.isActive }, "All users should be active")
            case .failure(let error):
                Issue.record("Active users subscription failed: \(error)")
            }
            
            // Test search subscription
            switch searchSubscription.result {
            case .success(let users):
                #expect(users.count == 2, "Should find 2 users with 'search' in username")
                #expect(users.allSatisfy { $0.username.contains("search") }, "All users should have 'search' in username")
            case .failure(let error):
                Issue.record("Search subscription failed: \(error)")
            }
        }
    }
    
    @Test("Relationship subscription methods work correctly")
    func testRelationshipSubscriptions() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let userRepo = await orm.repository(for: User.self)
        let postRepo = await orm.repository(for: Post.self)
        
        // Insert a user
        var user = User(
            username: "author",
            email: "author@example.com",
            firstName: "Author",
            lastName: "User",
            createdAt: Date()
        )
        
        _ = await userRepo.insert(&user)
        
        // Subscribe to posts related to this user
        let userPostsSubscription = userRepo.subscribeRelated(Post.self, foreignKey: "userId", parentId: user.id)
        let userPostsCountSubscription = userRepo.subscribeRelatedCount(Post.self, foreignKey: "userId", parentId: user.id)
        
        // Give subscriptions time to initialize
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        await MainActor.run {
            // Initially no posts
            switch userPostsSubscription.result {
            case .success(let posts):
                #expect(posts.count == 0, "Should find no posts initially")
            case .failure(let error):
                Issue.record("User posts subscription failed: \(error)")
            }
            
            switch userPostsCountSubscription.result {
            case .success(let count):
                #expect(count == 0, "Should count 0 posts initially")
            case .failure(let error):
                Issue.record("User posts count subscription failed: \(error)")
            }
        }
        
        // Insert posts for this user
        var post1 = Post(
            title: "First Post",
            content: "Content of first post",
            userId: user.id,
            createdAt: Date()
        )
        
        var post2 = Post(
            title: "Second Post", 
            content: "Content of second post",
            userId: user.id,
            createdAt: Date()
        )
        
        _ = await postRepo.insert(&post1)
        _ = await postRepo.insert(&post2)
        
        // Give subscriptions time to update
        try await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds
        
        await MainActor.run {
            // Should now find posts
            switch userPostsSubscription.result {
            case .success(let posts):
                #expect(posts.count == 2, "Should find 2 posts for user")
                #expect(posts.allSatisfy { $0.userId == user.id }, "All posts should belong to user")
            case .failure(let error):
                Issue.record("User posts subscription update failed: \(error)")
            }
            
            switch userPostsCountSubscription.result {
            case .success(let count):
                #expect(count == 2, "Should count 2 posts for user")
            case .failure(let error):
                Issue.record("User posts count subscription update failed: \(error)")
            }
        }
    }
    
    @Test("Query builder convenience methods work correctly")
    func testQueryBuilderConvenienceMethods() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let userRepo = await orm.repository(for: User.self)
        let postRepo = await orm.repository(for: Post.self)
        
        // Insert test data
        var user = User(
            username: "testuser",
            email: "test@example.com",
            firstName: "Test",
            lastName: "User",
            createdAt: Date(),
            isActive: true
        )
        
        _ = await userRepo.insert(&user)
        
        let now = Date()
        var post1 = Post(
            title: "Recent Post",
            content: "Recent content",
            userId: user.id,
            createdAt: now
        )
        
        var post2 = Post(
            title: "Old Post",
            content: "Old content", 
            userId: user.id,
            createdAt: now.addingTimeInterval(-86400) // 1 day ago
        )
        
        _ = await postRepo.insert(&post1)
        _ = await postRepo.insert(&post2)
        
        // Test belongs-to relationship query
        let userPostsSubscription = await postRepo.query()
            .belongsTo(user)
            .newestFirst()
            .subscribeQuery()
        
        // Test active filter
        let activeUsersSubscription = await userRepo.query()
            .whereActive(true)
            .subscribeQuery()
        
        // Test recent posts
        let recentPostsSubscription = await postRepo.query()
            .whereRecent(within: -3600) // Last hour
            .subscribeQuery()
        
        // Test exists query
        let postsExistSubscription = await postRepo.query()
            .belongsTo(user)
            .subscribeExists()
        
        // Give subscriptions time to load
        try await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds
        
        
        await MainActor.run {
            // Test belongs-to posts
            switch userPostsSubscription.result {
            case .success(let posts):
                #expect(posts.count == 2, "Should find 2 posts for user")
                #expect(posts.first?.title == "Recent Post", "Should be ordered newest first")
            case .failure(let error):
                Issue.record("User posts subscription failed: \(error)")
            }
            
            // Test active users
            switch activeUsersSubscription.result {
            case .success(let users):
                #expect(users.count == 1, "Should find 1 active user")
                #expect(users.first?.isActive == true, "User should be active")
            case .failure(let error):
                Issue.record("Active users subscription failed: \(error)")
            }
            
            // Test recent posts
            switch recentPostsSubscription.result {
            case .success(let posts):
                #expect(posts.count == 1, "Should find 1 recent post")
                #expect(posts.first?.title == "Recent Post", "Should find the recent post")
            case .failure(let error):
                Issue.record("Recent posts subscription failed: \(error)")
            }
            
            // Test posts exist
            #expect(postsExistSubscription.exists, "Posts should exist for user")
        }
    }
}

// Helper model for testing relationships
struct Post: ORMTable {
    typealias IDType = Int
    var id: Int = 0
    var title: String
    var content: String
    var userId: Int
    var createdAt: Date
    
    // Sync properties
    var lastSyncTimestamp: Date? = nil
    var isDirty: Bool = false
    var syncStatus: SyncStatus = .synced
    var serverID: String? = nil
    
    static let tableName = "posts"
}