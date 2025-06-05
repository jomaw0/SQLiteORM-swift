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
    @StateObject private var viewModel: ShoppingItemsViewModel
    @State private var showingAddItem = false
    @State private var filteredItems: [ShoppingItem] = []
    @State private var allCategories: [String] = ["All"]
    @State private var statistics: (total: Int, checked: Int, totalCost: Double, purchasedCost: Double) = (0, 0, 0.0, 0.0)
    @State private var completionPercentage: Double = 0.0
    
    init(shoppingList: ShoppingList) {
        self.shoppingList = shoppingList
        self._viewModel = StateObject(wrappedValue: ShoppingItemsViewModel(shoppingList: shoppingList))
    }
    
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
                    Picker("Category", selection: $viewModel.selectedCategory) {
                        ForEach(allCategories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    
                    Toggle("Show Checked Items", isOn: $viewModel.showCheckedItems)
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
        .searchable(text: $viewModel.searchText, prompt: "Search items")
        .sheet(isPresented: $showingAddItem) {
            AddEditItemView(shoppingList: shoppingList, databaseManager: databaseManager)
        }
        .sheet(item: $viewModel.selectedItem) { item in
            AddEditItemView(shoppingList: shoppingList, itemToEdit: item, databaseManager: databaseManager)
        }
        .alert("Delete Item", isPresented: $viewModel.showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let itemToDelete = viewModel.itemToDelete {
                    Task {
                        await viewModel.deleteItem(itemToDelete)
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete this item?")
        }
        .onAppear {
            viewModel.databaseManager = databaseManager
        }
        .task {
            updateData()
        }
        .onChange(of: viewModel.searchText) { _ in
            updateFilteredItems()
        }
        .onChange(of: viewModel.selectedCategory) { _ in
            updateFilteredItems()
        }
        .onChange(of: viewModel.showCheckedItems) { _ in
            updateFilteredItems()
        }
    }
    
    private func updateData() {
        updateFilteredItems()
        updateCategories()
        updateStatistics()
    }
    
    private func updateFilteredItems() {
        filteredItems = viewModel.getFilteredItems()
    }
    
    private func updateCategories() {
        allCategories = viewModel.getAllCategories()
    }
    
    private func updateStatistics() {
        statistics = viewModel.getStatistics()
        completionPercentage = viewModel.getCompletionPercentage()
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
                            await viewModel.toggleItemChecked(item)
                            updateData()
                        }
                    },
                    onEdit: {
                        viewModel.selectedItem = item
                    },
                    onDelete: {
                        viewModel.confirmDelete(item)
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