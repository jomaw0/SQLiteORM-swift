import Foundation
import Testing
@testable import SwiftSync

@Suite("Basic CRUD Operations")
struct BasicCRUDTests {
    
    private func setupDatabase() async -> ORM {
        let orm = createInMemoryORM()
        
        let openResult = await orm.open()
        #expect(openResult.toOptional() != nil)
        
        let createResult = await orm.createTables(for: [User.self])
        #expect(createResult.toOptional() != nil)
        
        return orm
    }
    
    @Test("Insert and find model")
    func testInsertAndFind() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: User.self)
        
        // Create
        var user = User(
            username: "johndoe",
            email: "john@example.com",
            firstName: "John",
            lastName: "Doe",
            createdAt: Date()
        )
        
        let insertResult = await repo.insert(&user)
        #expect(insertResult.toOptional() != nil)
        #expect(user.id > 0)
        
        // Read
        let findResult = await repo.find(id: user.id)
        switch findResult {
        case .success(let foundUser):
            #expect(foundUser != nil)
            #expect(foundUser?.username == "johndoe")
        case .failure(let error):
            Issue.record("Find failed: \(error)")
        }
    }
    
    @Test("Update model")
    func testUpdate() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: User.self)
        
        // Insert initial user
        var user = User(
            username: "janedoe",
            email: "jane@example.com",
            firstName: "Jane",
            lastName: "Doe",
            createdAt: Date()
        )
        
        let insertResult = await repo.insert(&user)
        #expect(insertResult.toOptional() != nil)
        
        // Update
        user.email = "newemail@example.com"
        user.updatedAt = Date()
        
        let updateResult = await repo.update(user)
        #expect(updateResult.toOptional() != nil)
        
        // Verify update
        let findResult = await repo.find(id: user.id)
        switch findResult {
        case .success(let foundUser):
            #expect(foundUser?.email == "newemail@example.com")
        case .failure(let error):
            Issue.record("Find after update failed: \(error)")
        }
    }
    
    @Test("Delete model")
    func testDelete() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: User.self)
        
        // Insert user to delete
        var user = User(
            username: "deleteme",
            email: "delete@example.com",
            firstName: "Delete",
            lastName: "Me",
            createdAt: Date()
        )
        
        let insertResult = await repo.insert(&user)
        #expect(insertResult.toOptional() != nil)
        
        // Delete
        let deleteResult = await repo.delete(id: user.id)
        switch deleteResult {
        case .success(let rowsDeleted):
            #expect(rowsDeleted == 1)
        case .failure(let error):
            Issue.record("Delete failed: \(error)")
        }
        
        // Verify deletion
        let findResult = await repo.find(id: user.id)
        switch findResult {
        case .success(let foundUser):
            #expect(foundUser == nil)
        case .failure(let error):
            Issue.record("Find after delete failed: \(error)")
        }
    }
    
    @Test("Save method with new model")
    func testSaveNew() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: User.self)
        
        var user = User(
            username: "savetest",
            email: "save@example.com",
            firstName: "Save",
            lastName: "Test",
            createdAt: Date()
        )
        
        let saveResult = await repo.save(&user)
        #expect(saveResult.toOptional() != nil)
        #expect(user.id > 0)
    }
    
    @Test("Save method with existing model")
    func testSaveExisting() async throws {
        let orm = await setupDatabase()
        defer { Task { _ = await orm.close() } }
        
        let repo = await orm.repository(for: User.self)
        
        // First insert
        var user = User(
            username: "updatetest",
            email: "update@example.com",
            firstName: "Update",
            lastName: "Test",
            createdAt: Date()
        )
        
        let insertResult = await repo.insert(&user)
        #expect(insertResult.toOptional() != nil)
        
        // Modify and save
        user.email = "updated@example.com"
        let saveResult = await repo.save(&user)
        #expect(saveResult.toOptional() != nil)
        
        // Verify update
        let findResult = await repo.find(id: user.id)
        switch findResult {
        case .success(let foundUser):
            #expect(foundUser?.email == "updated@example.com")
        case .failure(let error):
            Issue.record("Find after save failed: \(error)")
        }
    }
}