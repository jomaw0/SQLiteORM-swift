import Foundation
import Testing
@testable import SQLiteORM

@Suite("ORM Initialization Tests")
struct InitializationTests {
    
    @Test("Default initialization works")
    func testDefaultInitialization() async throws {
        let orm = ORM(.test("default_test_\(UUID().uuidString)"))
        
        let openResult = await orm.open()
        #expect(openResult.toOptional() != nil)
        
        // Verify it can create tables
        let createResult = await orm.createTables(for: [User.self])
        #expect(createResult.toOptional() != nil)
        
        _ = await orm.close()
    }
    
    @Test("Relative path initialization works")
    func testRelativePathInitialization() async throws {
        let orm = ORM(.test("test_database_\(UUID().uuidString)"))
        
        let openResult = await orm.open()
        #expect(openResult.toOptional() != nil)
        
        // Verify it can create tables
        let createResult = await orm.createTables(for: [User.self])
        #expect(createResult.toOptional() != nil)
        
        _ = await orm.close()
    }
    
    @Test("Memory database initialization works")
    func testMemoryInitialization() async throws {
        let orm = ORM(.memory)
        
        let openResult = await orm.open()
        #expect(openResult.toOptional() != nil)
        
        // Verify it can create tables
        let createResult = await orm.createTables(for: [User.self])
        #expect(createResult.toOptional() != nil)
        
        _ = await orm.close()
    }
    
    @Test("Convenience function initialization works")
    func testConvenienceFunctionInitialization() async throws {
        let orm = createInMemoryORM()
        
        let openResult = await orm.open()
        #expect(openResult.toOptional() != nil)
        
        // Verify it can create tables
        let createResult = await orm.createTables(for: [User.self])
        #expect(createResult.toOptional() != nil)
        
        _ = await orm.close()
    }
    
    @Test("File convenience function initialization works")
    func testFileConvenienceFunctionInitialization() async throws {
        let orm = createTestORM(filename: "test_app_\(UUID().uuidString)")
        
        let openResult = await orm.open()
        #expect(openResult.toOptional() != nil)
        
        // Verify it can create tables
        let createResult = await orm.createTables(for: [User.self])
        #expect(createResult.toOptional() != nil)
        
        _ = await orm.close()
    }
    
    @Test("SQLite extension is automatically added")
    func testSQLiteExtensionAutomatic() async throws {
        // Test that .sqlite extension is added automatically
        let uuid = UUID().uuidString
        let orm1 = ORM(.test("test_without_extension_\(uuid)"))
        let orm2 = ORM(.test("test_with_extension_\(uuid).sqlite"))
        
        // Both should work the same way
        let openResult1 = await orm1.open()
        #expect(openResult1.toOptional() != nil)
        
        let openResult2 = await orm2.open()
        #expect(openResult2.toOptional() != nil)
        
        _ = await orm1.close()
        _ = await orm2.close()
    }
    
    @Test("Variadic createTables method works")
    func testVariadicCreateTables() async throws {
        let orm = createInMemoryORM()
        
        let openResult = await orm.open()
        #expect(openResult.toOptional() != nil)
        
        // Test variadic method
        let createResult = await orm.createTables(User.self)
        #expect(createResult.toOptional() != nil)
        
        _ = await orm.close()
    }
    
    @Test("Open and create tables in one step works")
    func testOpenAndCreateTables() async throws {
        let orm = ORM(.memory)
        
        // Test the combined method
        let result = await orm.openAndCreateTables(User.self)
        #expect(result.toOptional() != nil)
        
        // Verify we can use the repository
        let repo = await orm.repository(for: User.self)
        var user = User(
            username: "testuser",
            email: "test@example.com",
            firstName: "Test",
            lastName: "User",
            createdAt: Date()
        )
        
        let insertResult = await repo.insert(&user)
        #expect(insertResult.toOptional() != nil)
        #expect(user.id > 0)
        
        _ = await orm.close()
    }
    
    @Test("Convenience functions with tables work")
    func testConvenienceFunctionsWithTables() async throws {
        // Test in-memory convenience function
        let memoryORMResult = await createInMemoryORMWithTables(User.self)
        #expect(memoryORMResult.toOptional() != nil)
        
        if case .success(let orm) = memoryORMResult {
            // Verify the tables are created and ready to use
            let repo = await orm.repository(for: User.self)
            var user = User(
                username: "testuser2",
                email: "test2@example.com",
                firstName: "Test",
                lastName: "User2",
                createdAt: Date()
            )
            
            let insertResult = await repo.insert(&user)
            #expect(insertResult.toOptional() != nil)
            #expect(user.id > 0)
            
            _ = await orm.close()
        }
        
        // Test file-based convenience function
        let fileORMResult = await createTestORMWithTables("test_convenience_\(UUID().uuidString)", User.self)
        #expect(fileORMResult.toOptional() != nil)
        
        if case .success(let orm) = fileORMResult {
            // Verify the tables are created and ready to use
            let repo = await orm.repository(for: User.self)
            var user = User(
                username: "testuser3",
                email: "test3@example.com",
                firstName: "Test",
                lastName: "User3",
                createdAt: Date()
            )
            
            let insertResult = await repo.insert(&user)
            #expect(insertResult.toOptional() != nil)
            #expect(user.id > 0)
            
            _ = await orm.close()
        }
    }
} 