//
//  ShoppingListsSidebarView.swift
//  SwiftSyncDemo
//
//  Created by Jonas Wolf on 05.06.25.
//

import SwiftUI

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct ShoppingListsSidebarView: View {
    @EnvironmentObject var databaseManager: DatabaseManager
    @Binding var selectedList: ShoppingList?
    @State private var showingAddList = false
    @State private var searchText = ""
    @State private var showingDeleteAlert = false
    @State private var listToDelete: ShoppingList?
    
    private var filteredLists: [ShoppingList] {
        if searchText.isEmpty {
            return databaseManager.shoppingLists
        } else {
            return databaseManager.shoppingLists.filter { 
                $0.name.localizedCaseInsensitiveContains(searchText) 
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if databaseManager.isLoading {
                    LoadingView()
                } else if let errorMessage = databaseManager.errorMessage {
                    ErrorView(message: errorMessage)
                } else {
                    sidebarContent
                }
            }
            .navigationTitle("Shopping Lists")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddList = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search lists")
            .sheet(isPresented: $showingAddList) {
                AddEditListView(databaseManager: databaseManager)
            }
            .alert("Delete List", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let listToDelete = listToDelete {
                        Task {
                            await deleteList(listToDelete)
                        }
                    }
                }
            } message: {
                Text("Are you sure you want to delete this list and all its items?")
            }
        }
        .onAppear {
            // Auto-select first list if none selected
            if selectedList == nil && !filteredLists.isEmpty {
                selectedList = filteredLists.first
            }
        }
        .onChange(of: filteredLists) { _, lists in
            // Update selection if current selection is no longer available
            if let selectedList = selectedList, !lists.contains(where: { $0.id == selectedList.id }) {
                self.selectedList = lists.first
            }
        }
    }
    
    @ViewBuilder
    private var sidebarContent: some View {
        if filteredLists.isEmpty {
            emptyState
        } else {
            List(filteredLists, id: \.id, selection: $selectedList) { list in
                ShoppingListSidebarRowView(
                    list: list,
                    statistics: databaseManager.getListStatistics(list.id),
                    onDelete: { confirmDelete(list) }
                )
                .tag(list)
                .onTapGesture {
                    selectedList = list
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "list.bullet.circle")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No Shopping Lists")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Create your first shopping list to get started")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Create List") {
                showingAddList = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    private func confirmDelete(_ list: ShoppingList) {
        listToDelete = list
        showingDeleteAlert = true
    }
    
    private func deleteList(_ list: ShoppingList) async {
        let result = await databaseManager.deleteList(list)
        if case .failure(let error) = result {
            print("Failed to delete list: \(error)")
        }
    }
    
    private func deleteItems(offsets: IndexSet) {
        for index in offsets {
            let list = filteredLists[index]
            Task {
                await deleteList(list)
            }
        }
    }
}

struct ShoppingListSidebarRowView: View {
    let list: ShoppingList
    let statistics: (total: Int, checked: Int, totalCost: Double, purchasedCost: Double)
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(list.name)
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Menu {
                    Button("Delete", role: .destructive) {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                Label("\(statistics.total) items", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if statistics.total > 0 {
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(statistics.checked) completed")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                if statistics.totalCost > 0 {
                    Text(statistics.totalCost, format: .currency(code: "USD"))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct ShoppingListsSidebarView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationSplitView {
            ShoppingListsSidebarView(selectedList: .constant(nil))
                .environmentObject(DatabaseManager())
        } detail: {
            EmptySelectionView()
        }
        .previewDisplayName("Split View")
        
        // Preview for iPhone (stack navigation)
        NavigationStack {
            ShoppingListsSidebarView(selectedList: .constant(nil))
                .environmentObject(DatabaseManager())
        }
        .previewDisplayName("Stack Navigation")
        .previewDevice("iPhone 15 Pro")
    }
}
