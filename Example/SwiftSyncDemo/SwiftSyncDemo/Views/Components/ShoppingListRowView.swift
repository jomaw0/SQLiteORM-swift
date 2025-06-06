//
//  ShoppingListRowView.swift
//  SwiftSyncDemo
//
//  Created by Jonas Wolf on 05.06.25.
//

import SwiftUI

struct ShoppingListRowView: View {
    let list: ShoppingList
    let statistics: (total: Int, checked: Int, totalCost: Double, purchasedCost: Double)
    let onDelete: () -> Void
    
    private var completionPercentage: Double {
        guard statistics.total > 0 else { return 0 }
        return Double(statistics.checked) / Double(statistics.total)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(list.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(list.createdAt, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Menu {
                    Button("Delete", role: .destructive) {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                        .padding(8)
                }
            }
            
            if statistics.total > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(statistics.checked) of \(statistics.total) items")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("\(Int(completionPercentage * 100))%")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(completionPercentage == 1.0 ? .green : .primary)
                    }
                    
                    ProgressView(value: completionPercentage)
                        .progressViewStyle(LinearProgressViewStyle(tint: completionPercentage == 1.0 ? .green : .blue))
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(statistics.totalCost, format: .currency(code: "USD"))
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Purchased")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(statistics.purchasedCost, format: .currency(code: "USD"))
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                        }
                    }
                }
            } else {
                HStack {
                    Image(systemName: "cart")
                        .foregroundColor(.secondary)
                    Text("No items yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

#Preview {
    List {
        ShoppingListRowView(
            list: ShoppingList(name: "Grocery Shopping"),
            statistics: (total: 5, checked: 2, totalCost: 45.50, purchasedCost: 18.25),
            onDelete: {}
        )
        
        ShoppingListRowView(
            list: ShoppingList(name: "Hardware Store"),
            statistics: (total: 0, checked: 0, totalCost: 0, purchasedCost: 0),
            onDelete: {}
        )
        
        ShoppingListRowView(
            list: ShoppingList(name: "Completed List"),
            statistics: (total: 3, checked: 3, totalCost: 25.99, purchasedCost: 25.99),
            onDelete: {}
        )
    }
    .listStyle(PlainListStyle())
}