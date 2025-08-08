//
//  TestSimpleContentView.swift
//  Briefeed
//
//  Test view to isolate UI freeze issue
//

import SwiftUI

struct TestSimpleContentView: View {
    @State private var counter = 0
    @State private var selectedTab = 0
    
    var body: some View {
        VStack {
            Text("Test View - Counter: \(counter)")
                .font(.largeTitle)
            
            TabView(selection: $selectedTab) {
                Text("Tab 1")
                    .tabItem {
                        Label("Tab 1", systemImage: "1.circle")
                    }
                    .tag(0)
                
                Text("Tab 2")
                    .tabItem {
                        Label("Tab 2", systemImage: "2.circle")
                    }
                    .tag(1)
            }
            
            Button("Increment") {
                counter += 1
            }
            .padding()
        }
        .onAppear {
            print("TestSimpleContentView appeared")
        }
    }
}