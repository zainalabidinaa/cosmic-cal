import SwiftUI

@main
struct WorkLogApp: App {
    @StateObject private var store = WorkLogStore()
    @State private var selectedTab: AppTab = .log

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
            }
            .tint(.mint)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
            .environmentObject(store)
        }
    }
}

enum AppTab: Hashable {
    case log
    case history
}
