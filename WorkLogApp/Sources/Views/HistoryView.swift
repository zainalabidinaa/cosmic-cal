import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: WorkLogStore
    @Binding var selectedTab: AppTab

    var body: some View {
        NavigationStack {
            ZStack {
                background

                if store.logs.isEmpty {
                    ContentUnavailableView(
                        "No Work Logs Yet",
                        systemImage: "clock",
                        description: Text("Save a shift in the Log tab and it’ll show up here.")
                    )
                    .padding(.horizontal, 24)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(store.logs) { log in
                                GlassCard {
                                    Button {
                                        store.requestEdit(day: log.day)
                                        selectedTab = .log
                                    } label: {
                                        HistoryRow(day: dayLabel(for: log.day), time: "\(timeLabel(for: log.start)) – \(timeLabel(for: log.end))")
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button("Delete", role: .destructive) {
                                            store.deleteLog(log)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("LMB Lund")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.09),
                    Color(red: 0.01, green: 0.02, blue: 0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.white.opacity(0.12), Color.clear],
                center: .topTrailing,
                startRadius: 30,
                endRadius: 640
            )

            RadialGradient(
                colors: [Color.mint.opacity(0.10), Color.clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 560
            )
        }
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
