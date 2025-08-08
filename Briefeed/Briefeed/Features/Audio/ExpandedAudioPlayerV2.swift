//
//  ExpandedAudioPlayerV2.swift
//  Briefeed
//
//  Stub for now - will be updated to use AppViewModel
//

import SwiftUI

struct ExpandedAudioPlayerV2: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack {
            Text("Expanded Audio Player")
                .font(.largeTitle)
            
            Text("Coming Soon")
                .font(.title2)
            
            Button("Close") {
                dismiss()
            }
            .padding()
        }
    }
}