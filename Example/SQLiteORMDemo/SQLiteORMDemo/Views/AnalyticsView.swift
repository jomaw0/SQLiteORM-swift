//
//  AnalyticsView.swift
//  SQLiteORMDemo
//
//  Created by Jonas Wolf on 06.06.25.
//
//  This view demonstrates various subscription and date query patterns:
//  - Real-time analytics using Combine subscriptions
//  - Date-based filtering (today, this week, this month, last 7 days)
//  - Category breakdowns using grouping operations
//  - Recent items display with sorting and limiting
//

import SwiftUI
import SQLiteORM

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct AnalyticsView: View {
    @EnvironmentObject var databaseManager: DatabaseManager
    @StateObject private var viewModel = AnalyticsViewModel()
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // Overview Cards
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                        StatCard(
                            title: "Total Lists",
                            value: "\(viewModel.totalListsCount)",
                            icon: "list.bullet",
                            color: .blue
                        )
                        
                        StatCard(
                            title: "Active Lists",
                            value: "\(viewModel.activeListsCount)",
                            icon: "checkmark.circle",
                            color: .green
                        )
                        
                        StatCard(
                            title: "Total Items",
                            value: "\(viewModel.totalItemsCount)",
                            icon: "tag",
                            color: .orange
                        )
                        
                        StatCard(
                            title: "Items Checked",
                            value: "\(viewModel.checkedItemsCount)",
                            icon: "checkmark.square",
                            color: .purple
                        )
                    }
                    
                    // Date-based Analytics
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Recent Activity")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .padding(.horizontal)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 1), spacing: 12) {
                            AnalyticsCard(
                                title: "Today's Lists",
                                count: viewModel.todayListsCount,
                                subtitle: "Lists created today",
                                icon: "calendar",
                                color: .blue
                            )
                            
                            AnalyticsCard(
                                title: "This Week",
                                count: viewModel.thisWeekListsCount,
                                subtitle: "Lists created this week",
                                icon: "calendar.badge.plus",
                                color: .green
                            )
                            
                            AnalyticsCard(
                                title: "This Month",
                                count: viewModel.thisMonthListsCount,
                                subtitle: "Lists created this month",
                                icon: "calendar.badge.clock",
                                color: .orange
                            )
                            
                            AnalyticsCard(
                                title: "Last 7 Days Items",
                                count: viewModel.lastSevenDaysItemsCount,
                                subtitle: "Items added in last 7 days",
                                icon: "tag.circle",
                                color: .purple
                            )
                        }
                    }
                    
                    // Recent Items
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Recent Items")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .padding(.horizontal)
                        
                        ForEach(viewModel.recentItems, id: \.id) { item in
                            RecentItemRow(item: item)
                        }
                    }
                    
                    // Categories Analytics
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Category Breakdown")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .padding(.horizontal)
                        
                        ForEach(viewModel.categoryStats, id: \.category) { stat in
                            CategoryStatsRow(stat: stat)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Analytics")
            .onAppear {
                viewModel.setupSubscriptions(databaseManager: databaseManager)
            }
        }
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

struct AnalyticsCard: View {
    let title: String
    let count: Int
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("\(count)")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

struct RecentItemRow: View {
    let item: ShoppingItem
    
    var body: some View {
        HStack {
            Image(systemName: item.categoryIcon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text("Added \(timeAgoString(from: item.addedAt))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("$\(item.totalPrice, specifier: "%.2f")")
                    .font(.body)
                    .fontWeight(.medium)
                
                if item.isChecked {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .cornerRadius(8)
    }
    
    private func timeAgoString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct CategoryStatsRow: View {
    let stat: CategoryStat
    
    var body: some View {
        HStack {
            Image(systemName: stat.icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            Text(stat.category)
                .font(.body)
                .fontWeight(.medium)
            
            Spacer()
            
            Text("\(stat.count) items")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .cornerRadius(8)
    }
}

// MARK: - Data Models

struct CategoryStat {
    let category: String
    let count: Int
    let icon: String
    
    init(category: String, count: Int) {
        self.category = category
        self.count = count
        
        // Set icon based on category
        switch category {
        case "Groceries":
            self.icon = "cart.fill"
        case "Electronics":
            self.icon = "laptopcomputer"
        case "Clothing":
            self.icon = "tshirt.fill"
        case "Health & Beauty":
            self.icon = "heart.fill"
        case "Home & Garden":
            self.icon = "house.fill"
        case "Sports & Outdoors":
            self.icon = "figure.run"
        case "Books & Media":
            self.icon = "book.fill"
        default:
            self.icon = "tag.fill"
        }
    }
}

#Preview {
    if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
        AnalyticsView()
            .environmentObject(DatabaseManager())
    }
}