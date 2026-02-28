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
            .tint(.orange)
            .preferredColorScheme(.dark)
            .adaptiveBottomAccessory {
                HStack(spacing: 8) {
                    Image(systemName: selectedTab == .log ? "sparkles" : "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .imageScale(.small)
                    Text(selectedTab == .log ? "LMB quick capture" : "LMB archive")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.1), in: Capsule(style: .continuous))
            }
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
