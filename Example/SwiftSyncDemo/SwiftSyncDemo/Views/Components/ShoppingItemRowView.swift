//
//  ShoppingItemRowView.swift
//  SwiftSyncDemo
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
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Checkbox with animation
                ZStack {
                    Circle()
                        .stroke(item.isChecked ? Color.green : Color.secondary, lineWidth: 2)
                        .frame(width: 24, height: 24)
                        .scaleEffect(item.isChecked ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: item.isChecked)
                    
                    if item.isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.green)
                            .scaleEffect(item.isChecked ? 1.0 : 0.0)
                            .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.1), value: item.isChecked)
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        // Category icon
                        Image(systemName: item.categoryIcon)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 16)
                        
                        // Item name with animated strikethrough
                        Text(item.name)
                            .font(.headline)
                            .fontWeight(.medium)
                            .strikethrough(item.isChecked)
                            .foregroundColor(item.isChecked ? .secondary : .primary)
                            .animation(.easeInOut(duration: 0.3), value: item.isChecked)
                        
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
                        .onTapGesture {
                            // Prevent the menu button from triggering the cell toggle
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
                                    .animation(.easeInOut(duration: 0.4), value: item.isChecked)
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
            .buttonStyle(PlainButtonStyle())
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(item.isChecked ? Color.green.opacity(0.05) : Color.clear)
                    .animation(.easeInOut(duration: 0.3), value: item.isChecked)
            )
            .scaleEffect(item.isChecked ? 0.98 : 1.0)
            .opacity(item.isChecked ? 0.8 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: item.isChecked)
        }
    }
    
    struct ShoppingItemRowView_Previews: PreviewProvider {
        static var previews: some View {
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
    }
}
