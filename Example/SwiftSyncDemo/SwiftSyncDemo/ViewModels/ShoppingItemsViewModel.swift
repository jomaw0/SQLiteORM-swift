//
//  ShoppingItemsViewModel.swift
//  SwiftSyncDemo
//
//  Created by Jonas Wolf on 05.06.25.
//

import Foundation
import SwiftUI
import Combine

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@MainActor
class ShoppingItemsViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var selectedCategory = "All"
    @Published var showCheckedItems = true
    @Published var showingAddItem = false
    @Published var selectedItem: ShoppingItem?
    @Published var showingDeleteAlert = false
    @Published var itemToDelete: ShoppingItem?
    
    let shoppingList: ShoppingList
    var databaseManager: DatabaseManager!
    private var cancellables = Set<AnyCancellable>()
    
    init(shoppingList: ShoppingList) {
        self.shoppingList = shoppingList
    }
    
    func getAllCategories() -> [String] {
        var categories = ["All"]
        let usedCategories = Set(databaseManager.getItemsForList(shoppingList.id).map { $0.category })
        categories.append(contentsOf: usedCategories.sorted())
        return categories
    }
    
    func getFilteredItems() -> [ShoppingItem] {
        var items = databaseManager.getItemsForList(shoppingList.id)
        
        // Filter by search text
        if !searchText.isEmpty {
            items = items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        
        // Filter by category
        if selectedCategory != "All" {
            items = items.filter { $0.category == selectedCategory }
        }
        
        // Filter by checked status
        if !showCheckedItems {
            items = items.filter { !$0.isChecked }
        }
        
        // Sort: unchecked items first, then by date added
        return items.sorted { first, second in
            if first.isChecked != second.isChecked {
                return !first.isChecked
            }
            return first.addedAt > second.addedAt
        }
    }
    
    func getStatistics() -> (total: Int, checked: Int, totalCost: Double, purchasedCost: Double) {
        return databaseManager.getListStatistics(shoppingList.id)
    }
    
    func getCompletionPercentage() -> Double {
        let stats = getStatistics()
        guard stats.total > 0 else { return 0 }
        return Double(stats.checked) / Double(stats.total) * 100
    }
    
    func createItem(name: String, quantity: Int, price: Double, category: String, notes: String) async {
        var newItem = ShoppingItem(
            listId: shoppingList.id,
            name: name,
            quantity: quantity,
            price: price,
            category: category,
            notes: notes
        )
        
        let result = await databaseManager.createItem(&newItem)
        if case .failure(let error) = result {
            print("Failed to create item: \(error)")
        }
    }
    
    func updateItem(_ item: ShoppingItem, name: String, quantity: Int, price: Double, category: String, notes: String) async {
        await databaseManager.updateItem(item, name: name, quantity: quantity, price: price, category: category, notes: notes)
    }
    
    func toggleItemChecked(_ item: ShoppingItem) async {
        await databaseManager.toggleItemChecked(item)
    }
    
    func deleteItem(_ item: ShoppingItem) async {
        let result = await databaseManager.deleteItem(item)
        if case .failure(let error) = result {
            print("Failed to delete item: \(error)")
        }
    }
    
    func confirmDelete(_ item: ShoppingItem) {
        itemToDelete = item
        showingDeleteAlert = true
    }
}