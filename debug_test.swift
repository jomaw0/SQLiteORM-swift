import Foundation
@testable import SwiftSync

@ORMTable
struct TestAuthor: ORMTable {
    typealias IDType = Int
    
    var id: Int = 0
    var name: String = ""
    var email: String = ""
    
    // Sync properties
    var lastSyncTimestamp: Date? = nil
    var isDirty: Bool = false
    var syncStatus: SyncStatus = .synced
    var serverID: String? = nil
    
    init() {}
    
    init(id: Int = 0, name: String = "", email: String = "") {
        self.id = id
        self.name = name
        self.email = email
        self.lastSyncTimestamp = nil
        self.isDirty = false
        self.syncStatus = .synced
        self.serverID = nil
    }
}

print("Creating test author...")
let author = TestAuthor(id: 1, name: "Test", email: "test@example.com")
print("Author created: \(author)")

print("Testing hash...")
let hash = author.hashValue
print("Hash computed: \(hash)")

print("Testing equality...")
let author2 = TestAuthor(id: 1, name: "Test", email: "test@example.com")
let isEqual = author == author2
print("Equality test: \(isEqual)")

print("Done!")