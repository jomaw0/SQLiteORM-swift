//
//  SQLiteORMDemoApp.swift
//  SQLiteORMDemo
//
//  Created by Jonas Wolf on 05.06.25.
//

import SwiftUI

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
@main
struct SQLiteORMDemoApp: App {
    @StateObject private var databaseManager = DatabaseManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(databaseManager)
        }
    }
}
