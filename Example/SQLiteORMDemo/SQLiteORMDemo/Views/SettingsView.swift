//
//  SettingsView.swift
//  SQLiteORMDemo
//
//  Created by Jonas Wolf on 05.06.25.
//

import SwiftUI

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct SettingsView: View {
    @EnvironmentObject var databaseManager: DatabaseManager
    @State private var showingAbout = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "list.bullet.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SQLiteORM Demo")
                                .font(.headline)
                                .fontWeight(.semibold)
                            Text("Shopping List Example")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("About") {
                            showingAbout = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                }
                
                Section {
                    HStack {
                        Image(systemName: "list.number")
                            .foregroundColor(.green)
                            .frame(width: 24)
                        Text("Total Lists")
                        Spacer()
                        Text("\(databaseManager.shoppingLists.count)")
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Image(systemName: "cart")
                            .foregroundColor(.orange)
                            .frame(width: 24)
                        Text("Total Items")
                        Spacer()
                        Text("\(databaseManager.shoppingItems.count)")
                            .fontWeight(.medium)
                    }
                } header: {
                    Text("Statistics")
                }
                
                Section {
                    HStack {
                        Image(systemName: "externaldrive")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        Text("Database")
                        Spacer()
                        Text("SQLite")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "swift")
                            .foregroundColor(.orange)
                            .frame(width: 24)
                        Text("Framework")
                        Spacer()
                        Text("SQLiteORM")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Technology")
                }
                
                Section {
                    Link(destination: URL(string: "https://github.com/jomaw0/SQLiteORM-swift")!) {
                        HStack {
                            Image(systemName: "link")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            Text("SQLiteORM on GitHub")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Resources")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "list.bullet.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)
                
                VStack(spacing: 8) {
                    Text("SQLiteORM Demo")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Shopping List Example")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                
                Text("This app demonstrates the capabilities of SQLiteORM, a comprehensive, type-safe SQLite Object-Relational Mapping framework for Swift.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(icon: "checkmark.circle.fill", title: "Type-safe ORM", description: "Compile-time validation")
                    FeatureRow(icon: "arrow.triangle.2.circlepath", title: "Real-time Updates", description: "Combine integration")
                    FeatureRow(icon: "bolt.fill", title: "Actor-based", description: "Thread-safe operations")
                    FeatureRow(icon: "swift", title: "Swift Macros", description: "Reduced boilerplate")
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                
                Spacer()
            }
            .padding()
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(DatabaseManager())
}