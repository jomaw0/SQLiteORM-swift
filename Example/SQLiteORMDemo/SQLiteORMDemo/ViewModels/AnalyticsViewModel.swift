//
//  AnalyticsViewModel.swift
//  SQLiteORMDemo
//
//  Created by Jonas Wolf on 06.06.25.
//
//  This ViewModel demonstrates the new SQLiteORM subscription features:
//  - Reactive data subscriptions using Combine
//  - Date-based analytics with Calendar operations
//  - Real-time category statistics
//  - Efficient data transformation using map/filter operations
//  - MainActor usage for UI-safe operations
//

import Foundation
import SQLiteORM
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
            await setupSubscriptions(databaseManager: databaseManager)
        }
    }
    
    private func setupSubscriptions(databaseManager: DatabaseManager) async {
        await setupBasicSubscriptions(databaseManager: databaseManager)
        await setupDateBasedSubscriptions(databaseManager: databaseManager)
        await setupCategorySubscriptions(databaseManager: databaseManager)
    }
    
    // MARK: - Basic Subscriptions
    private func setupBasicSubscriptions(databaseManager: DatabaseManager) async {
        // Subscribe to the DatabaseManager's published properties
        databaseManager.$shoppingLists
            .map { $0.count }
            .assign(to: \.totalListsCount, on: self)
            .store(in: &cancellables)
        
        databaseManager.$shoppingLists
            .map { lists in lists.filter { $0.isActive }.count }
            .assign(to: \.activeListsCount, on: self)
            .store(in: &cancellables)
        
        databaseManager.$shoppingItems
            .map { $0.count }
            .assign(to: \.totalItemsCount, on: self)
            .store(in: &cancellables)
        
        databaseManager.$shoppingItems
            .map { items in items.filter { $0.isChecked }.count }
            .assign(to: \.checkedItemsCount, on: self)
            .store(in: &cancellables)
        
        databaseManager.$shoppingItems
            .map { items in 
                Array(items.sorted { $0.addedAt > $1.addedAt }.prefix(10))
            }
            .assign(to: \.recentItems, on: self)
            .store(in: &cancellables)
    }
    
    // MARK: - Date-based Subscriptions
    private func setupDateBasedSubscriptions(databaseManager: DatabaseManager) async {
        let calendar = Calendar.current
        
        // Date-based filtering using existing data
        databaseManager.$shoppingLists
            .map { lists in
                lists.filter { calendar.isDateInToday($0.createdAt) }.count
            }
            .assign(to: \.todayListsCount, on: self)
            .store(in: &cancellables)
        
        databaseManager.$shoppingLists
            .map { lists in
                let weekInterval = calendar.dateInterval(of: .weekOfYear, for: Date()) ?? DateInterval()
                return lists.filter { weekInterval.contains($0.createdAt) }.count
            }
            .assign(to: \.thisWeekListsCount, on: self)
            .store(in: &cancellables)
        
        databaseManager.$shoppingLists
            .map { lists in
                let monthInterval = calendar.dateInterval(of: .month, for: Date()) ?? DateInterval()
                return lists.filter { monthInterval.contains($0.createdAt) }.count
            }
            .assign(to: \.thisMonthListsCount, on: self)
            .store(in: &cancellables)
        
        databaseManager.$shoppingItems
            .map { items in
                let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                return items.filter { $0.addedAt >= sevenDaysAgo }.count
            }
            .assign(to: \.lastSevenDaysItemsCount, on: self)
            .store(in: &cancellables)
    }
    
    // MARK: - Category Subscriptions
    private func setupCategorySubscriptions(databaseManager: DatabaseManager) async {
        databaseManager.$shoppingItems
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
    
    /// This demonstrates the patterns we're using in a real implementation
    /// Note: This is for documentation purposes - actual subscriptions use DatabaseManager data
    func demonstrateSubscriptionPatterns() {
        /*
         In this Analytics view, we demonstrate several subscription patterns:
         
         1. Basic Count Subscriptions:
            - Total lists/items count using .map on @Published properties
            - Active lists count using filter operations
            - Checked items count using filter operations
         
         2. Date-based Filtering:
            - Today's lists using Calendar.isDateInToday()
            - This week's lists using DateInterval
            - This month's lists using DateInterval  
            - Last 7 days items using date comparison
         
         3. Category Analytics:
            - Grouping items by category using Dictionary(grouping:by:)
            - Sorting by count for analytics display
         
         4. Recent Items:
            - Sorting by date and taking prefix for latest items
         
         In a more advanced implementation, you could use the ORM's subscription methods directly:
         
         // Direct ORM subscriptions (requires ORM access):
         // let todayItemsSubscription = await itemRepo.query().whereToday("addedAt").subscribe()
         // let expensiveItemsSubscription = await itemRepo.query().where("price", ComparisonOperator.greaterThan, 50.0).subscribe()
         // let existsSubscription = listRepo.subscribeExists()
         // let latestSubscription = listRepo.subscribeLatest()
         
         But for this demo, we leverage the existing DatabaseManager subscriptions for efficiency.
         */
    }
}