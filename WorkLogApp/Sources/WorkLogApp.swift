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
                Tab("Log", systemImage: "calendar.badge.plus", value: .log) {
                    LogView()
                }

                Tab("History", systemImage: "clock", value: .history) {
                    HistoryView(selectedTab: $selectedTab)
                }

                Tab("Settings", systemImage: "gearshape", value: .settings) {
                    SettingsView()
                }
            }
            .tint(.mint)
            .environmentObject(store)
            .environmentObject(settings)
        }
    }
}

enum AppTab: Hashable {
    case log, history, settings
}
