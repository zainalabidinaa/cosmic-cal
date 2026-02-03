import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: WorkLogStore
    @Binding var selectedTab: AppTab

    var body: some View {
        NavigationStack {
            ZStack {
                background

                List {
                    if store.logs.isEmpty {
                        Text("No logs yet")
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    }

                    ForEach(store.logs) { log in
                        Button {
                            store.requestEdit(day: log.day)
                            selectedTab = .log
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(dayLabel(for: log.day))
                                        .font(.headline)

                                    Text("\(timeLabel(for: log.start)) – \(timeLabel(for: log.end))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            store.deleteLog(store.logs[index])
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("History")
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.07, green: 0.08, blue: 0.11),
                Color(red: 0.03, green: 0.04, blue: 0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func timeLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
