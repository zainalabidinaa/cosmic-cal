import SwiftUI

struct LogView: View {
    @EnvironmentObject private var store: WorkLogStore

    @State private var day: Date = Date().startOfLocalDay()
    @State private var startTime: Date = Date.at(day: Date(), hour: 8, minute: 0)
    @State private var endTime: Date = Date.at(day: Date(), hour: 16, minute: 30)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Day", selection: $day, displayedComponents: [.date])
                        .datePickerStyle(.compact)
                        .onChange(of: day) { newValue in
                            loadForDay(newValue)
                        }
                        .listRowBackground(rowBackground)
                } header: {
                    Text("Day")
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            TemplateChip("08:00–16:30") {
                                applyTemplate(startHour: 8, startMinute: 0, endHour: 16, endMinute: 30)
                            }

                            TemplateChip("08:30–17:00") {
                                applyTemplate(startHour: 8, startMinute: 30, endHour: 17, endMinute: 0)
                            }

                            TemplateChip("10:10–19:00") {
                                applyTemplate(startHour: 10, startMinute: 10, endHour: 19, endMinute: 0)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(rowBackground)
                } header: {
                    Text("Quick Templates")
                }

                Section {
                    DatePicker("Start", selection: $startTime, displayedComponents: [.hourAndMinute])
                        .datePickerStyle(.compact)
                        .listRowBackground(rowBackground)

                    DatePicker("End", selection: $endTime, displayedComponents: [.hourAndMinute])
                        .datePickerStyle(.compact)
                        .listRowBackground(rowBackground)
                } header: {
                    Text("Times")
                }

                if let message = store.lastSaveMessage {
                    Section {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .listRowBackground(rowBackground)
                    }
                }

                if let error = store.lastErrorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .listRowBackground(rowBackground)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listRowSeparator(.hidden)
            .scrollContentBackground(.hidden)
            .background(background)
            .navigationTitle("LMB Lund")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom) {
                SaveBar {
                    Task {
                        await store.upsertLog(day: day, start: startTime, end: endTime)
                        loadForDay(day)
                    }
                }
            }
            .onAppear {
                loadForDay(day)
            }
            .onChange(of: store.requestedEditDay) { newValue in
                guard let newValue else { return }
                day = newValue
                loadForDay(newValue)
                store.requestedEditDay = nil
            }
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
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
                colors: [Color.white.opacity(0.14), Color.clear],
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

    private func applyTemplate(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) {
        let dayStart = day.startOfLocalDay()
        startTime = Date.at(day: dayStart, hour: startHour, minute: startMinute)
        endTime = Date.at(day: dayStart, hour: endHour, minute: endMinute)
    }

    private func loadForDay(_ value: Date) {
        let dayStart = value.startOfLocalDay()

        if let log = store.log(for: dayStart) {
            startTime = log.start
            endTime = log.end
        } else {
            day = dayStart
            applyTemplate(startHour: 8, startMinute: 0, endHour: 16, endMinute: 30)
        }
    }
}

private struct TemplateChip: View {
    private let label: String
    private let action: () -> Void

    init(_ label: String, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
        }
        .buttonStyle(.bordered)
        .tint(Color.white.opacity(0.18))
    }
}

private struct SaveBar: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.white.opacity(0.08))
            Button(action: action) {
                Text("Save")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.white.opacity(0.14))
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .background(.ultraThinMaterial)
        .overlay {
            Rectangle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.16), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        }
    }
}
