import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @EnvironmentObject private var store: WorkLogStore
    @EnvironmentObject private var settings: AppSettings
    @Binding var selectedTab: AppTab

    @State private var logToDelete: WorkLog?
    @State private var showDeleteConfirmation = false
    @Namespace private var summaryNamespace

    var body: some View {
        NavigationStack {
            Group {
                if store.logs.isEmpty {
                    VStack {
                        Spacer(minLength: 40)
                        GlassCard(style: .subtle) {
                            ContentUnavailableView(
                                "No Shifts Yet",
                                systemImage: "clock",
                                description: Text("Save a shift in the Log tab to get started.")
                            )
                        }
                        .padding(.horizontal, 16)
                        Spacer()
                    }
                } else {
                    List {
                        Section {
                            AdaptiveGlassGroup(spacing: 12) {
                                GlassCard(style: .elevated) {
                                    HStack(spacing: 0) {
                                        SummaryItem(title: "This Week", value: formatHours(hoursThisWeek))
                                            .adaptiveGlassUnion(id: "historysummary", namespace: summaryNamespace)
                                        Spacer()
                                        SummaryItem(title: "This Month", value: formatHours(hoursThisMonth))
                                            .adaptiveGlassUnion(id: "historysummary", namespace: summaryNamespace)
                                    }
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .accessibilityElement(children: .combine)
                        }

                        Section {
                            ForEach(store.logs) { log in
                                GlassCard(style: .regular) {
                                    Button {
                                        store.requestEdit(day: log.day)
                                        selectedTab = .log
                                    } label: {
                                        HistoryRow(
                                            day: Formatters.day.string(from: log.day),
                                            time: "\(Formatters.time.string(from: log.start)) – \(Formatters.time.string(from: log.end))",
                                            duration: log.durationLabel
                                        )
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button("Delete", role: .destructive) {
                                        logToDelete = log
                                        showDeleteConfirmation = true
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background {
                LiquidBackdrop()
            }
            .navigationTitle(settings.eventTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !store.logs.isEmpty {
                        ShareLink(
                            item: CSVFile(content: generateCSV()),
                            preview: SharePreview("worklogs.csv")
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .adaptivePrimaryButtonStyle()
                        .tint(.teal)
                    }
                }
            }
            .alert("Delete Shift?", isPresented: $showDeleteConfirmation, presenting: logToDelete) { log in
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    withAnimation { store.deleteLog(log) }
                }
            } message: { log in
                Text("Remove the shift on \(Formatters.day.string(from: log.day))?")
            }
        }
    }

    // MARK: - Calculations

    private var hoursThisWeek: Double {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return store.logs.filter { $0.day >= start }.reduce(0) { $0 + $1.duration / 3600 }
    }

    private var hoursThisMonth: Double {
        let start = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
        return store.logs.filter { $0.day >= start }.reduce(0) { $0 + $1.duration / 3600 }
    }

    private func formatHours(_ hours: Double) -> String {
        if hours == 0 { return "0h" }
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    // MARK: - CSV Export

    private func generateCSV() -> String {
        var csv = "Date,Start,End,Duration (hours)\n"
        for log in store.logs {
            let day = Formatters.day.string(from: log.day)
            let start = Formatters.time.string(from: log.start)
            let end = Formatters.time.string(from: log.end)
            let hours = String(format: "%.2f", log.duration / 3600)
            csv += "\"\(day)\",\"\(start)\",\"\(end)\",\(hours)\n"
        }
        return csv
    }
}

// MARK: - Subviews

private struct SummaryItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HistoryRow: View {
    let day: String
    let time: String
    let duration: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day)
                    .font(.headline)
                Text(time)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 10)

            Text(duration)
                .font(.subheadline.weight(.semibold).monospacedDigit())

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(day), \(time), \(duration)")
    }
}

// MARK: - CSV Transferable

private struct CSVFile: Transferable {
    let content: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in
            Data(file.content.utf8)
        }
    }
}
