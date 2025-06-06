//
//  AnalyticsViewModel.swift
//  SwiftSyncDemo
//
//  Created by Jonas Wolf on 06.06.25.
//
//  This ViewModel demonstrates the new SwiftSync subscription features:
//  - Convenient subscription methods (subscribeCount, subscribeWhere)
//  - Date query convenience methods (whereToday, whereThisWeek, whereLastDays)
//  - Fluent query builder patterns with method chaining
//  - Atomic setup subscriptions to prevent race conditions
//  - MainActor usage for UI-safe operations
//

import Foundation
import SwiftSync
import Combine

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@MainActor
class AnalyticsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var totalListsCount: Int = 0
    @Published var activeListsCount: Int = 0
    @Published var totalItemsCount: Int = 0
    @Published var checkedItemsCount: Int = 0
    
    @Published var todayListsCount: Int = 0
    @Published var thisWeekListsCount: Int = 0
    @Published var thisMonthListsCount: Int = 0
    @Published var lastSevenDaysItemsCount: Int = 0
    
    @Published var recentItems: [ShoppingItem] = []
    @Published var categoryStats: [CategoryStat] = []
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Subscription Setup
    func setupSubscriptions(databaseManager: DatabaseManager) {
        Task {
            await setupORMSubscriptions(databaseManager: databaseManager)
        }
    }
    
    private func setupORMSubscriptions(databaseManager: DatabaseManager) async {
        guard let listRepo = databaseManager.shoppingListRepository,
              let itemRepo = databaseManager.shoppingItemRepository else {
            print("⚠️ Repositories not ready yet")
            return
        }
        
        await setupBasicORMSubscriptions(listRepo: listRepo, itemRepo: itemRepo)
        await setupDateBasedORMSubscriptions(listRepo: listRepo, itemRepo: itemRepo)
        await setupAdvancedORMSubscriptions(listRepo: listRepo, itemRepo: itemRepo)
    }
    
    // MARK: - Basic ORM Subscriptions (demonstrating convenient subscription methods)
    private func setupBasicORMSubscriptions(listRepo: Repository<ShoppingList>, itemRepo: Repository<ShoppingItem>) async {
        // 1. Using subscribeCount() convenience method
        let totalListsSubscription = listRepo.subscribeCount()
        totalListsSubscription.$result
            .compactMap { result -> Int? in
                if case .success(let count) = result {
                    return count
                }
                return nil
            }
            .assign(to: \.totalListsCount, on: self)
            .store(in: &cancellables)
        
        // 2. Using subscribeWhere() convenience method for active lists
        let activeListsSubscription = listRepo.subscribeWhere("isActive", equals: true)
        activeListsSubscription.$result
            .compactMap { result -> Int? in
                if case .success(let lists) = result {
                    return lists.count
                }
                return nil
            }
            .assign(to: \.activeListsCount, on: self)
            .store(in: &cancellables)
        
        // 3. Using subscribeCount() for total items
        let totalItemsSubscription = itemRepo.subscribeCount()
        totalItemsSubscription.$result
            .compactMap { result -> Int? in
                if case .success(let count) = result {
                    return count
                }
                return nil
            }
            .assign(to: \.totalItemsCount, on: self)
            .store(in: &cancellables)
        
        // 4. Using subscribeWhere() for checked items
        let checkedItemsSubscription = itemRepo.subscribeWhere("isChecked", equals: true)
        checkedItemsSubscription.$result
            .compactMap { result -> Int? in
                if case .success(let items) = result {
                    return items.count
                }
                return nil
            }
            .assign(to: \.checkedItemsCount, on: self)
            .store(in: &cancellables)
        
        // 5. Using fluent query builder with newestFirst() and limit()
        let recentItemsSubscription = await itemRepo.query()
            .newestFirst("addedAt")
            .limit(10)
            .subscribe()
        
        recentItemsSubscription.$result
            .compactMap { result -> [ShoppingItem]? in
                if case .success(let items) = result {
                    return items
                }
                return nil
            }
            .assign(to: \.recentItems, on: self)
            .store(in: &cancellables)
    }
    
    // MARK: - Date-based ORM Subscriptions (demonstrating new date query methods)
    private func setupDateBasedORMSubscriptions(listRepo: Repository<ShoppingList>, itemRepo: Repository<ShoppingItem>) async {
        // 1. Using whereToday() date convenience method
        let todayListsSubscription = await listRepo.query()
            .whereToday("createdAt")
            .subscribeCount()
        
        todayListsSubscription.$result
            .compactMap { result -> Int? in
                if case .success(let count) = result {
                    return count
                }
                return nil
            }
            .assign(to: \.todayListsCount, on: self)
            .store(in: &cancellables)
        
        // 2. Using whereThisWeek() date convenience method
        let thisWeekListsSubscription = await listRepo.query()
            .whereThisWeek("createdAt")
            .subscribeCount()
        
        thisWeekListsSubscription.$result
            .compactMap { result -> Int? in
                if case .success(let count) = result {
                    return count
                }
                return nil
            }
            .assign(to: \.thisWeekListsCount, on: self)
            .store(in: &cancellables)
        
        // 3. Using whereThisMonth() date convenience method
        let thisMonthListsSubscription = await listRepo.query()
            .whereThisMonth("createdAt")
            .subscribeCount()
        
        thisMonthListsSubscription.$result
            .compactMap { result -> Int? in
                if case .success(let count) = result {
                    return count
                }
                return nil
            }
            .assign(to: \.thisMonthListsCount, on: self)
            .store(in: &cancellables)
        
        // 4. Using whereLastDays() date convenience method
        let lastSevenDaysItemsSubscription = await itemRepo.query()
            .whereLastDays("addedAt", 7)
            .subscribeCount()
        
        lastSevenDaysItemsSubscription.$result
            .compactMap { result -> Int? in
                if case .success(let count) = result {
                    return count
                }
                return nil
            }
            .assign(to: \.lastSevenDaysItemsCount, on: self)
            .store(in: &cancellables)
    }
    
    // MARK: - Advanced ORM Subscriptions (demonstrating category analytics)
    private func setupAdvancedORMSubscriptions(listRepo: Repository<ShoppingList>, itemRepo: Repository<ShoppingItem>) async {
        // Using subscribe() to get all items for category analysis
        let allItemsSubscription = itemRepo.subscribe()
        
        allItemsSubscription.$result
            .compactMap { result -> [ShoppingItem]? in
                if case .success(let items) = result {
                    return items
                }
                return nil
            }
            .map { items in
                // Group items by category and count them
                let grouped = Dictionary(grouping: items, by: { $0.category })
                return grouped.map { category, items in
                    CategoryStat(category: category, count: items.count)
                }.sorted { $0.count > $1.count }
            }
            .assign(to: \.categoryStats, on: self)
            .store(in: &cancellables)
    }
}

// MARK: - Convenient Extensions for Demo
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension AnalyticsViewModel {
    
    /// This demonstrates the actual SwiftSync subscription patterns we're using
    func demonstrateSubscriptionPatterns() {
        /*
         This Analytics view demonstrates real SwiftSync subscription features:
         
         1. Convenient Subscription Methods:
            - subscribeCount() for total counts
            - subscribeWhere("column", equals: value) for filtered counts
            - fluent query builder with .newestFirst().limit().subscribe()
         
         2. Date Query Convenience Methods:
            - whereToday("createdAt") for today's records
            - whereThisWeek("createdAt") for this week's records
            - whereThisMonth("createdAt") for this month's records
            - whereLastDays("addedAt", 7) for last N days
         
         3. Fluent Query Builder Patterns:
            - await repo.query().whereToday().subscribeCount()
            - await repo.query().newestFirst().limit(10).subscribe()
            - Method chaining for complex queries
         
         4. Subscription Types:
            - subscribeCount() returns SimpleCountSubscription
            - subscribeWhere() returns SimpleQuerySubscription
            - subscribe() returns SimpleQuerySubscription
         
         All subscriptions use atomic setup to prevent race conditions and
         automatically update the UI when data changes in the database.
         */
    }
}