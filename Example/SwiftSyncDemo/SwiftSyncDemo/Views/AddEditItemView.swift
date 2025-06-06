//
//  AddEditItemView.swift
//  SwiftSyncDemo
//
//  Created by Jonas Wolf on 05.06.25.
//

import SwiftUI

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct AddEditItemView: View {
    @Environment(\.dismiss) private var dismiss
    let shoppingList: ShoppingList
    let itemToEdit: ShoppingItem?
    let databaseManager: DatabaseManager
    
    @State private var itemName = ""
    @State private var quantity = 1
    @State private var price = ""
    @State private var selectedCategory = "Other"
    @State private var notes = ""
    @State private var isLoading = false
    
    private var isEditing: Bool {
        itemToEdit != nil
    }
    
    private var isValidName: Bool {
        !itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var priceValue: Double {
        Double(price) ?? 0.0
    }
    
    init(shoppingList: ShoppingList, itemToEdit: ShoppingItem? = nil, databaseManager: DatabaseManager) {
        self.shoppingList = shoppingList
        self.itemToEdit = itemToEdit
        self.databaseManager = databaseManager
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Item name", text: $itemName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                } header: {
                    Text("Item Details")
                }
                
                Section {
                    HStack {
                        Text("Quantity")
                        Spacer()
                        Stepper(value: $quantity, in: 1...99) {
                            Text("\(quantity)")
                                .fontWeight(.medium)
                        }
                    }
                    
                    HStack {
                        Text("Price")
                        TextField("0.00", text: $price)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(ShoppingItem.categories, id: \.self) { category in
                            HStack {
                                Image(systemName: iconForCategory(category))
                                Text(category)
                            }
                            .tag(category)
                        }
                    }
                } header: {
                    Text("Quantity & Pricing")
                }
                
                Section {
                    TextField("Add notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Notes")
                } footer: {
                    Text("Optional notes about this item")
                }
                
                if priceValue > 0 && quantity > 0 {
                    Section {
                        HStack {
                            Text("Total Price")
                                .fontWeight(.medium)
                            Spacer()
                            Text(priceValue * Double(quantity), format: .currency(code: "USD"))
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Item" : "New Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Save" : "Add") {
                        Task {
                            await saveItem()
                        }
                    }
                    .disabled(!isValidName || isLoading)
                }
            }
            .onAppear {
                setupInitialValues()
            }
        }
    }
    
    private func setupInitialValues() {
        if let itemToEdit = itemToEdit {
            itemName = itemToEdit.name
            quantity = itemToEdit.quantity
            price = itemToEdit.price > 0 ? String(itemToEdit.price) : ""
            selectedCategory = itemToEdit.category
            notes = itemToEdit.notes
        }
    }
    
    private func saveItem() async {
        isLoading = true
        
        let trimmedName = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let itemToEdit = itemToEdit {
            // Edit existing item
            await databaseManager.updateItem(
                itemToEdit,
                name: trimmedName,
                quantity: quantity,
                price: priceValue,
                category: selectedCategory,
                notes: trimmedNotes
            )
        } else {
            // Create new item
            var newItem = ShoppingItem(
                listId: shoppingList.id,
                name: trimmedName,
                quantity: quantity,
                price: priceValue,
                category: selectedCategory,
                notes: trimmedNotes
            )
            
            let result = await databaseManager.createItem(&newItem)
            if case .failure(let error) = result {
                print("Failed to create item: \(error)")
            }
        }
        
        isLoading = false
        dismiss()
    }
    
    private func iconForCategory(_ category: String) -> String {
        switch category {
        case "Groceries":
            return "cart.fill"
        case "Electronics":
            return "laptopcomputer"
        case "Clothing":
            return "tshirt.fill"
        case "Health & Beauty":
            return "heart.fill"
        case "Home & Garden":
            return "house.fill"
        case "Sports & Outdoors":
            return "figure.run"
        case "Books & Media":
            return "book.fill"
        default:
            return "tag.fill"
        }
    }
}

#Preview {
    AddEditItemView(
        shoppingList: ShoppingList(name: "Grocery Shopping"),
        databaseManager: DatabaseManager()
    )
}