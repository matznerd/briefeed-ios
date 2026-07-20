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
    @EnvironmentObject private var audioPlayerViewModel: AudioPlayerViewModelV2
    @ObservedObject private var statusService = ProcessingStatusService.shared

    var body: some View {
        VStack(spacing: 0) {
            if statusService.showStatusBanner {
                ProcessingStatusBanner()
                    .padding(.horizontal)
                    .padding(.top, 5)
                    .zIndex(1)
            }

            TabView(selection: $selectedTab) {
                RadioHomeView()
                    .appSettingsToolbar { showingSettings = true }
                    .tabItem {
                        Label(AppTab.radio.title, systemImage: AppTab.radio.systemImage)
                    }
                    .tag(AppTab.radio)

                FilteredBriefView()
                    .appSettingsToolbar { showingSettings = true }
                    .tabItem {
                        Label(AppTab.brief.title, systemImage: AppTab.brief.systemImage)
                    }
                    .tag(AppTab.brief)

                FeedView()
                    .appSettingsToolbar { showingSettings = true }
                    .tabItem {
                        Label(AppTab.feed.title, systemImage: AppTab.feed.systemImage)
                    }
                    .tag(AppTab.feed)
            }
            .toolbar(.hidden, for: .tabBar)
            .tint(.briefeedRed)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AppBottomChrome(
                selection: $selectedTab,
                showsMiniPlayer: shouldShowMiniPlayer
            )
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

    private var shouldShowMiniPlayer: Bool {
        !audioPlayerViewModel.radioEntries.isEmpty
            || !audioPlayerViewModel.queueItems.isEmpty
            || audioPlayerViewModel.radioState == .exhausted
    }

    private func applyThemePreference() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.windows.forEach { window in
                window.overrideUserInterfaceStyle = userDefaultsManager.isDarkMode ? .dark : .light
            }
        }
    }
}

struct FeedView: View {
    var body: some View {
        CombinedFeedView()
    }
}

private struct AppSettingsToolbarModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AppSettingsButton(action: action)
            }
        }
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
                .overlay(settingsBoundary)
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

private extension View {
    func appSettingsToolbar(action: @escaping () -> Void) -> some View {
        modifier(AppSettingsToolbarModifier(action: action))
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(UserDefaultsManager.shared)
        .environmentObject(AudioPlayerViewModelV2())
        .environmentObject(AppViewModel(audioPlayerViewModel: AudioPlayerViewModelV2()))
}
