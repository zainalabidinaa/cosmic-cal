import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: WorkLogStore
    @Binding var selectedTab: AppTab

    var body: some View {
        NavigationStack {
            Group {
                if store.logs.isEmpty {
                    ContentUnavailableView(
                        "No Work Logs Yet",
                        systemImage: "clock",
                        description: Text("Save a shift in the Log tab and it’ll show up here.")
                    )
                    .padding(.horizontal, 24)
                } else {
                    List {
                        Section {
                            ForEach(store.logs) { log in
                                Button {
                                    store.requestEdit(day: log.day)
                                    selectedTab = .log
                                } label: {
                                    HistoryRow(day: dayLabel(for: log.day), time: "\(timeLabel(for: log.start)) – \(timeLabel(for: log.end))")
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    store.deleteLog(store.logs[index])
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .scrollContentBackground(.hidden)
            .background(background)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                EditButton()
            }
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.06, green: 0.07, blue: 0.10),
                Color(red: 0.02, green: 0.03, blue: 0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay {
            RadialGradient(
                colors: [Color.white.opacity(0.10), Color.clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 520
            )
            .ignoresSafeArea()
        }
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

private struct HistoryRow: View {
    let day: String
    let time: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(day)
                    .font(.headline)

                Text(time)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 10)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
