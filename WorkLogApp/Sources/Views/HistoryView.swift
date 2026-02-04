import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: WorkLogStore
    @Binding var selectedTab: AppTab
    @State private var animateIn = false

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
                    .opacity(animateIn ? 1 : 0)
                    .offset(y: animateIn ? 0 : 12)
                    .animation(.easeOut(duration: 0.6), value: animateIn)
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
                        .opacity(animateIn ? 1 : 0)
                        .offset(y: animateIn ? 0 : 12)
                        .animation(.easeOut(duration: 0.6), value: animateIn)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("LMB Lund")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                animateIn = true
            }
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

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.purple.opacity(0.22), Color.clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 220
                    )
                )
                .frame(width: 260, height: 260)
                .offset(x: 120, y: -160)
                .blur(radius: 6)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.indigo.opacity(0.20), Color.clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 240
                    )
                )
                .frame(width: 300, height: 300)
                .offset(x: -140, y: 180)
                .blur(radius: 8)

            RadialGradient(
                colors: [Color.white.opacity(0.12), Color.clear],
                center: .topTrailing,
                startRadius: 30,
                endRadius: 640
            )

            RadialGradient(
                colors: [Color.purple.opacity(0.12), Color.clear],
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
                    .font(.custom("Avenir Next", size: 16).weight(.semibold))

                Text(time)
                    .font(.custom("Avenir Next", size: 14))
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
