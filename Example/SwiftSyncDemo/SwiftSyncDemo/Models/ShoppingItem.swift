//
//  ShoppingItem.swift
//  SwiftSyncDemo
//
//  Created by Jonas Wolf on 05.06.25.
//

import Foundation
import SwiftSync

@ORMTable
struct ShoppingItem: ORMTable, Identifiable {
    typealias IDType = Int
    
    var id: Int = 0
    var listId: Int
    var name: String
    var quantity: Int = 1
    var price: Double = 0.0
    var isChecked: Bool = false
    var category: String = "Other"
    var notes: String = ""
    var addedAt: Date
    
    init(listId: Int, name: String, quantity: Int = 1, price: Double = 0.0, category: String = "Other", notes: String = "") {
        self.listId = listId
        self.name = name
        self.quantity = quantity
        self.price = price
        self.category = category
        self.notes = notes
        self.addedAt = Date()
    }
    
    init(id: Int = 0, listId: Int, name: String, quantity: Int = 1, price: Double = 0.0, isChecked: Bool = false, category: String = "Other", notes: String = "", addedAt: Date) {
        self.id = id
        self.listId = listId
        self.name = name
        self.quantity = quantity
        self.price = price
        self.isChecked = isChecked
        self.category = category
        self.notes = notes
        self.addedAt = addedAt
    }
}

// MARK: - Computed Properties
extension ShoppingItem {
    var totalPrice: Double {
        return price * Double(quantity)
    }
}

// MARK: - Categories
extension ShoppingItem {
    static let categories = [
        "Groceries",
        "Electronics",
        "Clothing",
        "Health & Beauty",
        "Home & Garden",
        "Sports & Outdoors",
        "Books & Media",
        "Other"
    ]
    
    var categoryIcon: String {
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