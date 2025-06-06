import Foundation
import Testing
@testable import SwiftSync

@Suite("Macro Bug Test")
struct MacroBugTest {
    
    // Test with @ORMTable macro
    @ORMTable
    struct MacroUser: ORMTable {
        typealias IDType = Int
        
        var id: Int = 0
        var name: String = ""
        
        // Sync properties with explicit values - might conflict with macro
        var lastSyncTimestamp: Date? = nil
        var isDirty: Bool = false
        var syncStatus: SyncStatus = .synced
        var serverID: String? = nil
        
        init() {}
        
        init(id: Int = 0, name: String = "") {
            self.id = id
            self.name = name
            self.lastSyncTimestamp = nil
            self.isDirty = false
            self.syncStatus = .synced
            self.serverID = nil
        }
    }
    
    // Test without @ORMTable macro
    struct PlainUser: ORMTable {
        typealias IDType = Int
        
        var id: Int = 0
        var name: String = ""
        
        init() {}
        
        init(id: Int = 0, name: String = "") {
            self.id = id
            self.name = name
        }
    }
    
    @Test("Plain user (no macro) creates table successfully")
    func testPlainUserCreateTable() async throws {
        let orm = createInMemoryORM()
        
        let openResult = await orm.open()
        #expect(openResult.isSuccess, "ORM should open successfully")
        
        let createResult = await orm.createTables(PlainUser.self)
        #expect(createResult.isSuccess, "Should create table successfully")
        
        _ = await orm.close()
    }
    
    @Test("Macro user creates table successfully")
    func testMacroUserCreateTable() async throws {
        let orm = createInMemoryORM()
        
        let openResult = await orm.open()
        #expect(openResult.isSuccess, "ORM should open successfully")
        
        let createResult = await orm.createTables(MacroUser.self)
        #expect(createResult.isSuccess, "Should create table successfully")
        
        _ = await orm.close()
    }
}