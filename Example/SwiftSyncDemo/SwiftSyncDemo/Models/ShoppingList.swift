//
//  ShoppingList.swift
//  SwiftSyncDemo
//
//  Created by Jonas Wolf on 05.06.25.
//

import Foundation
import SwiftSync

@ORMTable
struct ShoppingList: ORMTable, Identifiable, Equatable, Hashable {
    typealias IDType = Int
    
    var id: Int = 0
    var name: String
    var createdAt: Date
    var isActive: Bool = true
    
    init(name: String) {
        self.name = name
        self.createdAt = Date()
    }
    
    init(id: Int = 0, name: String, createdAt: Date, isActive: Bool = true) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.isActive = isActive
    }
}

// MARK: - Computed Properties for UI
extension ShoppingList {
    var totalItems: Int {
        // This will be calculated by the view model
        0
    }
    
    var checkedItems: Int {
        // This will be calculated by the view model
        0
    }
    
    var totalCost: Double {
        // This will be calculated by the view model
        0.0
    }
    
    var purchasedCost: Double {
        // This will be calculated by the view model
        0.0
    }
    
    var completionPercentage: Double {
        guard totalItems > 0 else { return 0 }
        return Double(checkedItems) / Double(totalItems) * 100
    }
}

// MARK: - Equatable & Hashable
extension ShoppingList {
    static func == (lhs: ShoppingList, rhs: ShoppingList) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}