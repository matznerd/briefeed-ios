//
//  BriefViewV2.swift
//  Briefeed
//
//  Fixed version without singleton @StateObject references
//

import SwiftUI

struct FilteredBriefViewV2: View {
    @EnvironmentObject var appViewModel: AppViewModel
    
    var body: some View {
        NavigationView {
            VStack {
                if appViewModel.queueCount == 0 {
                    Text("Queue is empty")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    List {
                        ForEach(Array(appViewModel.queueItems.enumerated()), id: \.element.id) { index, item in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                    
                                    Text(item.author ?? "Unknown")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if index == appViewModel.currentQueueIndex {
                                    Image(systemName: "speaker.wave.2")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Play this item
                            }
                        }
                        .onDelete { indexSet in
                            indexSet.forEach { index in
                                appViewModel.removeFromQueue(at: index)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Brief (\(appViewModel.queueCount))")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") {
                        appViewModel.clearQueue()
                    }
                    .disabled(appViewModel.queueCount == 0)
                }
            }
        }
    }
}