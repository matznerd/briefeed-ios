//
//  ContentView.swift
//  Briefeed
//
//  Created by Eric M on 6/21/25.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab: AppTab = .radio
    @State private var showingSettings = false
    @EnvironmentObject private var userDefaultsManager: UserDefaultsManager
    @ObservedObject private var statusService = ProcessingStatusService.shared
    private let onRadioHomeAppear: @MainActor () -> Void

    init(onRadioHomeAppear: @escaping @MainActor () -> Void = {}) {
        self.onRadioHomeAppear = onRadioHomeAppear
    }

    var body: some View {
        VStack(spacing: 0) {
            if statusService.showStatusBanner {
                ProcessingStatusBanner()
                    .padding(.horizontal)
                    .padding(.top, 5)
                    .zIndex(1)
            }

            ZStack(alignment: .topTrailing) {
                Group {
                    switch selectedTab {
                    case .radio:
                        RadioHomeView(onAppearRefresh: onRadioHomeAppear)
                    case .brief:
                        FilteredBriefView()
                    case .feed:
                        FeedView()
                    }
                }
                .tint(.briefeedRed)

                AppSettingsButton { showingSettings = true }
                    .padding(.top, 4)
                    .padding(.trailing, 12)
                    .zIndex(2)
            }

            AppBottomChromeHost(selection: $selectedTab)
        }
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .presentationDetents([.large])
        }
        .onAppear {
            applyThemePreference()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ThemeChanged"))) { _ in
            applyThemePreference()
        }
    }

    private func applyThemePreference() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.windows.forEach { window in
                window.overrideUserInterfaceStyle = userDefaultsManager.isDarkMode ? .dark : .light
            }
        }
    }
}

private struct AppBottomChromeHost: View {
    @Binding var selection: AppTab
    @EnvironmentObject private var audioPlayerViewModel: AudioPlayerViewModelV2

    var body: some View {
        AppBottomChrome(
            selection: $selection,
            showsMiniPlayer: !audioPlayerViewModel.radioEntries.isEmpty
                || !audioPlayerViewModel.queueItems.isEmpty
                || audioPlayerViewModel.radioState == .exhausted
        )
    }
}

struct FeedView: View {
    var body: some View {
        CombinedFeedView()
    }
}

private struct AppSettingsButton: View {
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            settingsButton
                .buttonStyle(.glass)
        } else {
            settingsButton
                .buttonStyle(.plain)
                .background(
                    reduceTransparency ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground)) : AnyShapeStyle(.ultraThinMaterial),
                    in: Circle()
                )
                .overlay(settingsBoundary)
        }
    }

    private var settingsBoundary: some View {
        Circle()
            .stroke(
                Color.primary.opacity(colorSchemeContrast == .increased ? 0.42 : 0.12),
                lineWidth: colorSchemeContrast == .increased ? 1.5 : 0.5
            )
    }

    private var settingsButton: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(.body, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Settings")
        .accessibilityIdentifier(AccessibilityID.Navigation.settings)
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(UserDefaultsManager.shared)
        .environmentObject(AudioPlayerViewModelV2())
        .environmentObject(AppViewModel(audioPlayerViewModel: AudioPlayerViewModelV2()))
}
