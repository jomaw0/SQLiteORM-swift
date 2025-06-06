//
//  ContentView.swift
//  SQLiteORMDemo
//
//  Created by Jonas Wolf on 05.06.25.
//

import SwiftUI

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct ContentView: View {
    @EnvironmentObject var databaseManager: DatabaseManager
    @State private var selectedList: ShoppingList?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        #if os(iOS)
        TabView {
            Group {
                if horizontalSizeClass == .regular {
                    // iPad: NavigationSplitView with persistent selection
                    NavigationSplitView {
                        ShoppingListsSidebarView(selectedList: $selectedList)
                    } detail: {
                        if let selectedList = selectedList {
                            ShoppingItemsView(shoppingList: selectedList)
                        } else {
                            EmptySelectionView()
                        }
                    }
                } else {
                    // iPhone: NavigationStack with clean navigation
                    NavigationStack {
                        ShoppingListsView()
                    }
                }
            }
            .tabItem {
                Label("Lists", systemImage: "list.bullet")
            }
            
            AnalyticsView()
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar.fill")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        #else
        // macOS
        NavigationSplitView {
            ShoppingListsSidebarView(selectedList: $selectedList)
        } detail: {
            if let selectedList = selectedList {
                ShoppingItemsView(shoppingList: selectedList)
            } else {
                EmptySelectionView()
            }
        }
        #endif
    }
}

#Preview {
    if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
        ContentView()
            .environmentObject(DatabaseManager())
    }
}
