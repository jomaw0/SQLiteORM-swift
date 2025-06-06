//
//  ShoppingListsView.swift
//  SQLiteORMDemo
//
//  Created by Jonas Wolf on 05.06.25.
//

import SwiftUI

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct ShoppingListsView: View {
    @EnvironmentObject var databaseManager: DatabaseManager
    @State private var showingAddList = false
    @State private var searchText = ""
    @State private var showingDeleteAlert = false
    @State private var listToDelete: ShoppingList?
    
    var body: some View {
        NavigationStack {
            Group {
                if databaseManager.isLoading {
                    LoadingView()
                } else if let errorMessage = databaseManager.errorMessage {
                    ErrorView(message: errorMessage)
                } else {
                    listContent
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
    }
    
    private var filteredLists: [ShoppingList] {
        if searchText.isEmpty {
            return databaseManager.shoppingLists
        } else {
            return databaseManager.shoppingLists.filter { 
                $0.name.localizedCaseInsensitiveContains(searchText) 
            }
        }
    }
    
    private var listContent: some View {
        Group {
            if filteredLists.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filteredLists, id: \.id) { list in
                        NavigationLink(destination: ShoppingItemsView(shoppingList: list)) {
                            ShoppingListRowView(
                                list: list,
                                statistics: databaseManager.getListStatistics(list.id),
                                onDelete: { confirmDelete(list) }
                            )
                        }
                    }
                    .onDelete(perform: deleteItems)
                }
                .listStyle(PlainListStyle())
            }
        }
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
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Setting up database...")
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
}

struct ErrorView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundColor(.red)
            
            VStack(spacing: 8) {
                Text("Database Error")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}

#Preview {
    if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
        ShoppingListsView()
            .environmentObject(DatabaseManager())
    }
}
