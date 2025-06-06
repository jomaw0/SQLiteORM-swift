//
//  EmptySelectionView.swift
//  SQLiteORMDemo
//
//  Created by Jonas Wolf on 05.06.25.
//

import SwiftUI

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct EmptySelectionView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("Select a Shopping List")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                
                Text("Choose a list from the sidebar to view and manage your shopping items")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .background(Color(.systemGroupedBackground))
        #else
        .background(Color(NSColor.controlBackgroundColor))
        #endif
        .navigationTitle("Shopping Items")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
}

struct EmptySelectionView_Previews: PreviewProvider {
    static var previews: some View {
        EmptySelectionView()
    }
}