import SwiftUI

@main
struct WorkLogApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var store: WorkLogStore
    @State private var selectedTab: AppTab = .log

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: WorkLogStore(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                LogView()
                    .tabItem {
                        Label("Log", systemImage: "calendar.badge.plus")
                    }
                    .tag(AppTab.log)

                HistoryView(selectedTab: $selectedTab)
                    .tabItem {
                        Label("History", systemImage: "clock")
                    }
                    .tag(AppTab.history)

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .tag(AppTab.settings)
            }
            .tint(.mint)
            .toolbarColorScheme(.dark, for: .navigationBar, .tabBar)
            .toolbarBackground(.visible, for: .navigationBar, .tabBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar, .tabBar)
            .environmentObject(store)
            .environmentObject(settings)
        }
    }
}

enum AppTab: Hashable {
    case log
    case history
    case settings
}
