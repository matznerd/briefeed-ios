//
//  AddFeedView.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/21/25.
//

import SwiftUI

struct AddFeedView: View {
    @ObservedObject var viewModel: FeedViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var feedName = ""
    @State private var feedType = "subreddit"
    @State private var isSearching = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Enter subreddit name", text: $feedName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: feedName) { _, newValue in
                            if !newValue.isEmpty {
                                Task {
                                    await viewModel.searchSubreddits(query: newValue)
                                }
                            }
                        }
                } header: {
                    Text("Feed Name")
                } footer: {
                    Text("Example: technology, worldnews, science")
                        .font(.caption)
                }
                
                if !viewModel.searchResults.isEmpty {
                    Section("Search Results") {
                        ForEach(viewModel.searchResults, id: \.displayName) { subreddit in
                            Button {
                                feedName = subreddit.displayName
                                viewModel.searchResults = []
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("r/\(subreddit.displayName)")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    if !subreddit.title.isEmpty {
                                        Text(subreddit.title)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                    
                                    Text("\(subreddit.subscribers) subscribers")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addFeed()
                    }
                    .disabled(feedName.isEmpty || viewModel.isLoading)
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView("Adding feed...")
                        .padding()
                        .background(Color.briefeedSecondaryBackground)
                        .cornerRadius(10)
                        .shadow(radius: 5)
                }
            }
        }
    }
    
    private func addFeed() {
        let cleanedName = feedName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "r/", with: "")
            .replacingOccurrences(of: "/r/", with: "")
        
        let path = "/r/\(cleanedName)"
        
        Task {
            await viewModel.addFeed(name: cleanedName, type: feedType, path: path)
            if viewModel.errorMessage == nil {
                dismiss()
            }
        }
    }
}

#Preview {
    AddFeedView(viewModel: FeedViewModel())
}