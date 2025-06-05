//
//  ShoppingItemRowView.swift
//  SQLiteORMDemo
//
//  Created by Jonas Wolf on 05.06.25.
//

import SwiftUI

struct ShoppingItemRowView: View {
    let item: ShoppingItem
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button(action: onToggle) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(item.isChecked ? .green : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    // Category icon
                    Image(systemName: item.categoryIcon)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    
                    // Item name
                    Text(item.name)
                        .font(.headline)
                        .fontWeight(.medium)
                        .strikethrough(item.isChecked)
                        .foregroundColor(item.isChecked ? .secondary : .primary)
                    
                    Spacer()
                    
                    // Menu
                    Menu {
                        Button("Edit") {
                            onEdit()
                        }
                        
                        Button("Delete", role: .destructive) {
                            onDelete()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(.secondary)
                            .padding(4)
                    }
                }
                
                HStack {
                    // Quantity and price
                    HStack(spacing: 4) {
                        Text("Qty: \(item.quantity)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if item.price > 0 {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(item.totalPrice, format: .currency(code: "USD"))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(item.isChecked ? .green : .primary)
                        }
                    }
                    
                    Spacer()
                    
                    // Category
                    Text(item.category)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray6))
                        .cornerRadius(4)
                        .foregroundColor(.secondary)
                }
                
                // Notes (if any)
                if !item.notes.isEmpty {
                    Text(item.notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .opacity(item.isChecked ? 0.7 : 1.0)
    }
}

#Preview {
    List {
        ShoppingItemRowView(
            item: ShoppingItem(
                listId: 1,
                name: "Organic Apples",
                quantity: 6,
                price: 3.99,
                category: "Groceries",
                notes: "Red delicious variety"
            ),
            onToggle: {},
            onEdit: {},
            onDelete: {}
        )
        
        ShoppingItemRowView(
            item: ShoppingItem(
                id: 2,
                listId: 1,
                name: "Wireless Headphones",
                quantity: 1,
                price: 199.99,
                isChecked: true,
                category: "Electronics",
                notes: "Noise cancelling",
                addedAt: Date()
            ),
            onToggle: {},
            onEdit: {},
            onDelete: {}
        )
        
        ShoppingItemRowView(
            item: ShoppingItem(
                listId: 1,
                name: "Running Shoes",
                quantity: 1,
                price: 0,
                category: "Sports & Outdoors"
            ),
            onToggle: {},
            onEdit: {},
            onDelete: {}
        )
    }
    .listStyle(PlainListStyle())
}