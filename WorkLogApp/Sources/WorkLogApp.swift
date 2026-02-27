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
                Tab("Log", systemImage: "calendar.badge.plus", value: AppTab.log) {
                    LogView()
                }

                Tab("History", systemImage: "clock", value: AppTab.history) {
                    HistoryView(selectedTab: $selectedTab)
                }

                Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                    SettingsView()
                }
            }
            .tint(.mint)
            .preferredColorScheme(.dark)
            .adaptiveTabBarBehavior()
            .background {
                LiquidBackdrop()
            }
            .environmentObject(store)
            .environmentObject(settings)
        }
    }
}

enum AppTab: Hashable {
    case log, history, settings
}
