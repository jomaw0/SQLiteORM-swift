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
    
    var body: some View {
        TabView {
            ShoppingListsView()
                .tabItem {
                    Label("Lists", systemImage: "list.bullet")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

#Preview {
    if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
        ContentView()
            .environmentObject(DatabaseManager())
    }
}
