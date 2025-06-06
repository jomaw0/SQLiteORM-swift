import Foundation
import Testing
@testable import SwiftSync

@Suite("Date Handling Tests")
struct DateTests {
    
    @Test("Date conversion to and from SQLite")
    func testDateConversion() async throws {
        let now = Date()
        print("Original date: \(now)")
        print("Original timestamp: \(now.timeIntervalSince1970)")
        
        // Convert to SQLite value
        let sqliteValue = now.sqliteValue
        print("SQLite value: \(sqliteValue)")
        
        // Convert back to Date
        let convertedDate = Date(sqliteValue: sqliteValue)
        print("Converted date: \(String(describing: convertedDate))")
        
        #expect(convertedDate != nil)
        if let convertedDate = convertedDate {
            print("Converted timestamp: \(convertedDate.timeIntervalSince1970)")
            // Allow for small floating point differences
            #expect(abs(now.timeIntervalSince1970 - convertedDate.timeIntervalSince1970) < 0.001)
        }
    }
    
    @Test("Date storage and retrieval from database")
    func testDateStorageRetrieval() async throws {
        let orm = createInMemoryORM()
        
        let openResult = await orm.open()
        #expect(openResult.toOptional() != nil)
        
        let createResult = await orm.createTables(for: [User.self])
        #expect(createResult.toOptional() != nil)
        
        let repo = await orm.repository(for: User.self)
        
        let originalDate = Date()
        print("Original date before storage: \(originalDate)")
        print("Original timestamp: \(originalDate.timeIntervalSince1970)")
        
        var user = User(
            username: "datetest",
            email: "date@example.com",
            firstName: "Date",
            lastName: "Test",
            createdAt: originalDate
        )
        
        // Insert user
        let insertResult = await repo.insert(&user)
        #expect(insertResult.toOptional() != nil)
        
        // Retrieve user
        let findResult = await repo.find(id: user.id)
        switch findResult {
        case .success(let foundUser):
            #expect(foundUser != nil)
            if let foundUser = foundUser {
                print("Retrieved date: \(foundUser.createdAt)")
                print("Retrieved timestamp: \(foundUser.createdAt.timeIntervalSince1970)")
                
                // Check if dates match (allowing for small floating point differences)
                let timeDifference = abs(originalDate.timeIntervalSince1970 - foundUser.createdAt.timeIntervalSince1970)
                print("Time difference: \(timeDifference) seconds")
                #expect(timeDifference < 0.001)
            }
        case .failure(let error):
            Issue.record("Find failed: \(error)")
        }
        
        _ = await orm.close()
    }
}