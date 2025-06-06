import Foundation
import Testing
@testable import SwiftSync

@Suite("Simple Debug Test")
struct SimpleDebugTest {
    
    // Test model with @ORMTable macro
    @ORMTable
    struct SimpleUser: ORMTable {
        typealias IDType = Int
        
        var id: Int = 0
        var name: String = ""
        
        // Sync properties with explicit implementations
        var lastSyncTimestamp: Date? = nil
        var isDirty: Bool = false
        var syncStatus: SyncStatus = .synced
        var serverID: String? = nil
        
        init() {}
        
        init(id: Int = 0, name: String = "") {
            self.id = id
            self.name = name
        }
    }
    
    @Test("Simple ORM creation test")
    func testSimpleORMCreation() async throws {
        let orm = createInMemoryORM()
        let openResult = await orm.open()
        #expect(openResult.isSuccess, "ORM should open successfully")
        _ = await orm.close()
    }
}