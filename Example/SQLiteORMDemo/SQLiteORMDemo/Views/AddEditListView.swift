//
//  AddEditListView.swift
//  SQLiteORMDemo
//
//  Created by Jonas Wolf on 05.06.25.
//

import SwiftUI

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct AddEditListView: View {
    @Environment(\.dismiss) private var dismiss
    let databaseManager: DatabaseManager
    let listToEdit: ShoppingList?
    
    @State private var listName = ""
    @State private var isLoading = false
    
    private var isEditing: Bool {
        listToEdit != nil
    }
    
    private var isValidName: Bool {
        !listName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    init(databaseManager: DatabaseManager, listToEdit: ShoppingList? = nil) {
        self.databaseManager = databaseManager
        self.listToEdit = listToEdit
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("List name", text: $listName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                } header: {
                    Text("List Details")
                } footer: {
                    Text("Enter a name for your shopping list")
                }
            }
            .navigationTitle(isEditing ? "Edit List" : "New List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Save" : "Create") {
                        Task {
                            await saveList()
                        }
                    }
                    .disabled(!isValidName || isLoading)
                }
            }
            .onAppear {
                if let listToEdit = listToEdit {
                    listName = listToEdit.name
                }
            }
        }
    }
    
    private func saveList() async {
        isLoading = true
        
        let trimmedName = listName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let listToEdit = listToEdit {
            // Edit existing list
            var updatedList = listToEdit
            updatedList.name = trimmedName
            
            let result = await databaseManager.updateList(updatedList)
            if case .failure(let error) = result {
                print("Failed to update list: \(error)")
            }
        } else {
            // Create new list
            var newList = ShoppingList(name: trimmedName)
            let result = await databaseManager.createList(&newList)
            if case .failure(let error) = result {
                print("Failed to create list: \(error)")
            }
        }
        
        isLoading = false
        dismiss()
    }
}

#Preview {
    AddEditListView(databaseManager: DatabaseManager())
}