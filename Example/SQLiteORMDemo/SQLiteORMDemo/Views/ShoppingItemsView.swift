//
//  ShoppingItemsView.swift
//  SQLiteORMDemo
//
//  Created by Jonas Wolf on 05.06.25.
//

import SwiftUI

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct ShoppingItemsView: View {
    let shoppingList: ShoppingList
    @EnvironmentObject var databaseManager: DatabaseManager
    @State private var showingAddItem = false
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var showCheckedItems = true
    @State private var selectedItem: ShoppingItem?
    @State private var showingDeleteAlert = false
    @State private var itemToDelete: ShoppingItem?
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress header
            if !filteredItems.isEmpty {
                progressHeader
                    .padding()
                    .background(Color(.systemGroupedBackground))
            }
            
            // Items list
            Group {
                if filteredItems.isEmpty {
                    emptyState
                } else {
                    itemsList
                }
            }
        }
        .navigationTitle(shoppingList.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(allCategories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    
                    Toggle("Show Checked Items", isOn: $showCheckedItems)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                
                Button {
                    showingAddItem = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search items")
        .sheet(isPresented: $showingAddItem) {
            AddEditItemView(shoppingList: shoppingList, databaseManager: databaseManager)
        }
        .sheet(item: $selectedItem) { item in
            AddEditItemView(shoppingList: shoppingList, itemToEdit: item, databaseManager: databaseManager)
        }
        .alert("Delete Item", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let itemToDelete = itemToDelete {
                    Task {
                        await deleteItem(itemToDelete)
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete this item?")
        }
    }
    
    private var filteredItems: [ShoppingItem] {
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
    
    private var allCategories: [String] {
        var categories = ["All"]
        let usedCategories = Set(databaseManager.getItemsForList(shoppingList.id).map { $0.category })
        categories.append(contentsOf: usedCategories.sorted())
        return categories
    }
    
    private var statistics: (total: Int, checked: Int, totalCost: Double, purchasedCost: Double) {
        databaseManager.getListStatistics(shoppingList.id)
    }
    
    private var completionPercentage: Double {
        let stats = statistics
        guard stats.total > 0 else { return 0 }
        return Double(stats.checked) / Double(stats.total) * 100
    }
    
    private func confirmDelete(_ item: ShoppingItem) {
        itemToDelete = item
        showingDeleteAlert = true
    }
    
    private func deleteItem(_ item: ShoppingItem) async {
        let result = await databaseManager.deleteItem(item)
        if case .failure(let error) = result {
            print("Failed to delete item: \(error)")
        }
    }
    
    private func toggleItemChecked(_ item: ShoppingItem) async {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0)) {
            // The UI will animate based on the state change
        }
        await databaseManager.toggleItemChecked(item)
    }
    
    private var progressHeader: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Progress")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("\(statistics.checked) of \(statistics.total) items completed")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("\(Int(completionPercentage))%")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(completionPercentage == 100 ? .green : .primary)
            }
            
            ProgressView(value: completionPercentage / 100)
                .progressViewStyle(LinearProgressViewStyle(tint: completionPercentage == 100 ? .green : .blue))
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Cost")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(statistics.totalCost, format: .currency(code: "USD"))
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Purchased")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(statistics.purchasedCost, format: .currency(code: "USD"))
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var itemsList: some View {
        List {
            ForEach(filteredItems, id: \.id) { item in
                ShoppingItemRowView(
                    item: item,
                    onToggle: {
                        Task {
                            await toggleItemChecked(item)
                        }
                    },
                    onEdit: {
                        selectedItem = item
                    },
                    onDelete: {
                        confirmDelete(item)
                    }
                )
            }
        }
        .listStyle(PlainListStyle())
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "cart.circle")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No Items")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Add items to your shopping list to get started")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Add Item") {
                showingAddItem = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
        NavigationStack {
            ShoppingItemsView(shoppingList: ShoppingList(name: "Grocery Shopping"))
                .environmentObject(DatabaseManager())
        }
    }
}