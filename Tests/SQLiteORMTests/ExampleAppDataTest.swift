import Foundation
import Testing
@testable import SQLiteORM

// Mirror the exact models from the example app
@ORMTable
struct TestShoppingList: ORMTable, Identifiable, Equatable, Hashable {
    typealias IDType = Int
    
    var id: Int = 0
    var name: String
    var createdAt: Date
    var isActive: Bool = true
    
    init(name: String) {
        self.name = name
        self.createdAt = Date()
    }
    
    init(id: Int = 0, name: String, createdAt: Date, isActive: Bool = true) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.isActive = isActive
    }
    
    static func == (lhs: TestShoppingList, rhs: TestShoppingList) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@ORMTable
struct TestShoppingItem: ORMTable, Identifiable {
    typealias IDType = Int
    
    var id: Int = 0
    var listId: Int
    var name: String
    var quantity: Int = 1
    var price: Double = 0.0
    var isChecked: Bool = false
    var category: String = "Other"
    var notes: String = ""
    var addedAt: Date
    
    init(listId: Int, name: String, quantity: Int = 1, price: Double = 0.0, category: String = "Other", notes: String = "") {
        self.listId = listId
        self.name = name
        self.quantity = quantity
        self.price = price
        self.category = category
        self.notes = notes
        self.addedAt = Date()
    }
    
    init(id: Int = 0, listId: Int, name: String, quantity: Int = 1, price: Double = 0.0, isChecked: Bool = false, category: String = "Other", notes: String = "", addedAt: Date) {
        self.id = id
        self.listId = listId
        self.name = name
        self.quantity = quantity
        self.price = price
        self.isChecked = isChecked
        self.category = category
        self.notes = notes
        self.addedAt = addedAt
    }
}

@Suite("Example App Data Test")
struct ExampleAppDataTest {
    
    @Test("Test exact example app data creation and retrieval")
    func testExampleAppData() async throws {
        let orm = createInMemoryORM()
        
        let openResult = await orm.open()
        #expect(openResult.toOptional() != nil)
        
        let createResult = await orm.createTables(for: [TestShoppingList.self, TestShoppingItem.self])
        #expect(createResult.toOptional() != nil)
        
        let listRepo = await orm.repository(for: TestShoppingList.self)
        let itemRepo = await orm.repository(for: TestShoppingItem.self)
        
        // Create sample data exactly like the example app
        print("🏗️ Creating sample data...")
        var sampleList = TestShoppingList(name: "Grocery Shopping")
        print("Sample list created at: \(sampleList.createdAt)")
        print("Sample list timestamp: \(sampleList.createdAt.timeIntervalSince1970)")
        
        let result = await listRepo.insert(&sampleList)
        #expect(result.toOptional() != nil)
        
        print("✅ Sample list inserted with ID: \(sampleList.id)")
        
        // Add some sample items exactly like the example app
        let sampleItems = [
            TestShoppingItem(listId: sampleList.id, name: "Apples", quantity: 6, price: 3.99, category: "Groceries"),
            TestShoppingItem(listId: sampleList.id, name: "Bread", quantity: 1, price: 2.50, category: "Groceries"),
            TestShoppingItem(listId: sampleList.id, name: "Milk", quantity: 1, price: 4.25, category: "Groceries")
        ]
        
        for var item in sampleItems {
            print("Item \(item.name) created at: \(item.addedAt)")
            print("Item \(item.name) timestamp: \(item.addedAt.timeIntervalSince1970)")
            
            let itemResult = await itemRepo.insert(&item)
            #expect(itemResult.toOptional() != nil)
            print("✅ Sample item created: \(item.name) with ID: \(item.id)")
        }
        
        // Now retrieve all data and check dates
        print("\n📋 Retrieving data...")
        let listsResult = await listRepo.findAll()
        switch listsResult {
        case .success(let lists):
            for list in lists {
                print("Retrieved list: \(list.name)")
                print("  Created at: \(list.createdAt)")
                print("  Timestamp: \(list.createdAt.timeIntervalSince1970)")
                
                // Check if the date is reasonable (not 1994!)
                let year = Calendar.current.component(.year, from: list.createdAt)
                print("  Year: \(year)")
                #expect(year >= 2024) // Should be current year or later
            }
        case .failure(let error):
            Issue.record("Failed to retrieve lists: \(error)")
        }
        
        let itemsResult = await itemRepo.findAll()
        switch itemsResult {
        case .success(let items):
            for item in items {
                print("Retrieved item: \(item.name)")
                print("  Added at: \(item.addedAt)")
                print("  Timestamp: \(item.addedAt.timeIntervalSince1970)")
                
                // Check if the date is reasonable (not 1994!)
                let year = Calendar.current.component(.year, from: item.addedAt)
                print("  Year: \(year)")
                #expect(year >= 2024) // Should be current year or later
            }
        case .failure(let error):
            Issue.record("Failed to retrieve items: \(error)")
        }
        
        _ = await orm.close()
    }
}