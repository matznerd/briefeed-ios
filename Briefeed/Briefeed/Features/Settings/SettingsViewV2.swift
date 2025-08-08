//
//  SettingsViewV2.swift
//  Briefeed
//
//  Fixed version without singleton @StateObject references
//

import SwiftUI

struct SettingsViewV2: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var userDefaultsManager: UserDefaultsManager
    
    var body: some View {
        NavigationView {
            Form {
                Section("Appearance") {
                    Toggle("Dark Mode", isOn: $userDefaultsManager.isDarkMode)
                }
                
                Section("Audio") {
                    HStack {
                        Text("Playback Speed")
                        Spacer()
                        Text("\(appViewModel.playbackRate, specifier: "%.1f")x")
                    }
                    
                    Slider(value: $appViewModel.volume, in: 0...1) {
                        Text("Volume")
                    }
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}