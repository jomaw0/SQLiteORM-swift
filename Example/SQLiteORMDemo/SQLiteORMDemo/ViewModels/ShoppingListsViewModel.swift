//
//  ShoppingListsViewModel.swift
//  SQLiteORMDemo
//
//  Created by Jonas Wolf on 05.06.25.
//

import Foundation
import SwiftUI
import Combine

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@MainActor
class ShoppingListsViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var showingAddList = false
    @Published var selectedList: ShoppingList?
    @Published var showingDeleteAlert = false
    @Published var listToDelete: ShoppingList?
    
    var databaseManager: DatabaseManager!
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        
    }
    
    func getFilteredLists() -> [ShoppingList] {
        let lists = databaseManager.shoppingLists
        if searchText.isEmpty {
            return lists
        } else {
            return lists.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    func getIsLoading() -> Bool {
        databaseManager.isLoading
    }
    
    func getErrorMessage() -> String? {
        databaseManager.errorMessage
    }
    
    func createList(name: String) async {
        var newList = ShoppingList(name: name)
        let result = await databaseManager.createList(&newList)
        
        if case .failure(let error) = result {
            print("Failed to create list: \(error)")
        }
    }
    
    func updateList(_ list: ShoppingList, newName: String) async {
        var updatedList = list
        updatedList.name = newName
        
        let result = await databaseManager.updateList(updatedList)
        if case .failure(let error) = result {
            print("Failed to update list: \(error)")
        }
    }
    
    func deleteList(_ list: ShoppingList) async {
        let result = await databaseManager.deleteList(list)
        if case .failure(let error) = result {
            print("Failed to delete list: \(error)")
        }
    }
    
    func confirmDelete(_ list: ShoppingList) {
        listToDelete = list
        showingDeleteAlert = true
    }
    
    func getListStatistics(_ list: ShoppingList) -> (total: Int, checked: Int, totalCost: Double, purchasedCost: Double) {
        return databaseManager.getListStatistics(list.id)
    }
}