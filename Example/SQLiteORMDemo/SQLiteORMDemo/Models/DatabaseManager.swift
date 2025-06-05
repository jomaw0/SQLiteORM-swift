//
//  DatabaseManager.swift
//  SQLiteORMDemo
//
//  Created by Jonas Wolf on 05.06.25.
//

import Foundation
import SQLiteORM
import Combine

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
class DatabaseManager: ObservableObject {
    @Published var shoppingLists: [ShoppingList] = []
    @Published var shoppingItems: [ShoppingItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var orm: ORM?
    private var listRepository: Repository<ShoppingList>?
    private var itemRepository: Repository<ShoppingItem>?
    
    // Combine subscriptions for real-time updates
    private var listSubscription: SimpleQuerySubscription<ShoppingList>?
    private var itemSubscription: SimpleQuerySubscription<ShoppingItem>?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        Task {
            await setupDatabase()
        }
    }
    
    func setupDatabase() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        // Create ORM (this can run off main actor)
        let newOrm = ORM(.relative("database"))
        
        // Open database and create tables in one step
        let setupResult = await newOrm.openAndCreateTables(ShoppingList.self, ShoppingItem.self)
        if case .failure(let error) = setupResult {
            await MainActor.run {
                self.errorMessage = "Failed to setup database: \(error)"
                self.isLoading = false
            }
            return
        }
        
        // Get repositories
        let newListRepository = await newOrm.repository(for: ShoppingList.self)
        let newItemRepository = await newOrm.repository(for: ShoppingItem.self)
        
        // Update properties on main actor
        await MainActor.run {
            self.orm = newOrm
            self.listRepository = newListRepository
            self.itemRepository = newItemRepository
        }
        
        // Database and tables are now set up
        
        // Setup subscriptions for real-time updates
        await setupSubscriptions()
        
        // Load initial data
        await loadInitialData()
        
        // Set loading complete on main actor
        await MainActor.run {
            isLoading = false
        }
    }
    
    @MainActor
    private func setupSubscriptions() async {
        guard let listRepository = listRepository,
              let itemRepository = itemRepository else { return }
        
        // Subscribe to all active lists
        listSubscription = listRepository.subscribe(
            query: QueryBuilder<ShoppingList>()
                .where("isActive", .equal, true)
                .orderBy("createdAt", ascending: false)
        )
        
        listSubscription?.$result
            .compactMap { result -> [ShoppingList]? in
                if case .success(let lists) = result {
                    return lists
                }
                return nil
            }
            .receive(on: DispatchQueue.main)
            .assign(to: \.shoppingLists, on: self)
            .store(in: &cancellables)
        
        // Subscribe to all items
        itemSubscription = itemRepository.subscribe(
            query: QueryBuilder<ShoppingItem>()
                .orderBy("addedAt", ascending: false)
        )
        
        itemSubscription?.$result
            .compactMap { result -> [ShoppingItem]? in
                if case .success(let items) = result {
                    return items
                }
                return nil
            }
            .receive(on: DispatchQueue.main)
            .assign(to: \.shoppingItems, on: self)
            .store(in: &cancellables)
    }
    
    @MainActor
    private func loadInitialData() async {
        // Check if any lists exist in the database (not just in memory)
        guard let listRepository = listRepository else { return }
        
        let allListsResult = await listRepository.findAll()
        let hasExistingData = switch allListsResult {
        case .success(let lists): !lists.isEmpty
        case .failure: false
        }
        
        // Only create sample data if no lists exist in the database
        if !hasExistingData {
            await createSampleData()
        }
    }
    
    @MainActor
    private func createSampleData() async {
        var sampleList = ShoppingList(name: "Grocery Shopping")
        let result = await createList(&sampleList)
        
        if case .success = result {
            // Add some sample items
            let sampleItems = [
                ShoppingItem(listId: sampleList.id, name: "Apples", quantity: 6, price: 3.99, category: "Groceries"),
                ShoppingItem(listId: sampleList.id, name: "Bread", quantity: 1, price: 2.50, category: "Groceries"),
                ShoppingItem(listId: sampleList.id, name: "Milk", quantity: 1, price: 4.25, category: "Groceries")
            ]
            
            for var item in sampleItems {
                _ = await createItem(&item)
            }
        }
    }
}

// MARK: - Shopping List CRUD Operations
extension DatabaseManager {
    func createList(_ list: inout ShoppingList) async -> ORMResult<Void> {
        guard let repository = listRepository else {
            return .failure(.databaseNotOpen)
        }
        
        return await repository.insert(&list).map { _ in () }
    }
    
    func updateList(_ list: ShoppingList) async -> ORMResult<Void> {
        guard let repository = listRepository else {
            return .failure(.databaseNotOpen)
        }
        
        return await repository.update(list).map { _ in () }
    }
    
    func deleteList(_ list: ShoppingList) async -> ORMResult<Void> {
        guard let repository = listRepository else {
            return .failure(.databaseNotOpen)
        }
        
        // First delete all items in the list
        let itemsToDelete = getItemsForList(list.id)
        for item in itemsToDelete {
            _ = await deleteItem(item)
        }
        
        // Then delete the list
        return await repository.delete(id: list.id).map { _ in () }
    }
    
    func getItemsForList(_ listId: Int) -> [ShoppingItem] {
        return shoppingItems.filter { $0.listId == listId }
    }
}

// MARK: - Shopping Item CRUD Operations
extension DatabaseManager {
    func createItem(_ item: inout ShoppingItem) async -> ORMResult<Void> {
        guard let repository = itemRepository else {
            return .failure(.databaseNotOpen)
        }
        
        return await repository.insert(&item).map { _ in () }
    }
    
    func createItem(name: String, quantity: Int, price: Double, category: String, notes: String) async {
        var newItem = ShoppingItem(
            listId: 0, // This should be set by the caller
            name: name,
            quantity: quantity,
            price: price,
            category: category,
            notes: notes
        )
        
        let result = await createItem(&newItem)
        if case .failure(let error) = result {
            print("Failed to create item: \(error)")
        }
    }
    
    func updateItem(_ item: ShoppingItem) async -> ORMResult<Void> {
        guard let repository = itemRepository else {
            return .failure(.databaseNotOpen)
        }
        
        return await repository.update(item).map { _ in () }
    }
    
    func updateItem(_ item: ShoppingItem, name: String, quantity: Int, price: Double, category: String, notes: String) async {
        var updatedItem = item
        updatedItem.name = name
        updatedItem.quantity = quantity
        updatedItem.price = price
        updatedItem.category = category
        updatedItem.notes = notes
        
        let result = await updateItem(updatedItem)
        if case .failure(let error) = result {
            print("Failed to update item: \(error)")
        }
    }
    
    func deleteItem(_ item: ShoppingItem) async -> ORMResult<Void> {
        guard let repository = itemRepository else {
            return .failure(.databaseNotOpen)
        }
        
        return await repository.delete(id: item.id).map { _ in () }
    }
    
    func toggleItemChecked(_ item: ShoppingItem) async {
        var updatedItem = item
        updatedItem.isChecked.toggle()
        _ = await updateItem(updatedItem)
    }
}

// MARK: - Statistics
extension DatabaseManager {
    func getListStatistics(_ listId: Int) -> (total: Int, checked: Int, totalCost: Double, purchasedCost: Double) {
        let items = getItemsForList(listId)
        let checkedItems = items.filter { $0.isChecked }
        
        let totalCost = items.reduce(0) { $0 + $1.totalPrice }
        let purchasedCost = checkedItems.reduce(0) { $0 + $1.totalPrice }
        
        return (
            total: items.count,
            checked: checkedItems.count,
            totalCost: totalCost,
            purchasedCost: purchasedCost
        )
    }
}
