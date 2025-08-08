//
//  LiveNewsViewV2.swift
//  Briefeed
//
//  Fixed version without singleton @StateObject references
//

import SwiftUI

struct LiveNewsViewV2: View {
    @EnvironmentObject var appViewModel: AppViewModel
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Live News")
                    .font(.largeTitle)
                    .bold()
                
                Text("RSS podcast episodes will appear here")
                    .foregroundColor(.secondary)
                
                Button(action: {
                    Task {
                        await appViewModel.playLiveNews()
                    }
                }) {
                    Label("Play Live News", systemImage: "play.circle.fill")
                        .font(.title2)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Live News")
        }
    }
}