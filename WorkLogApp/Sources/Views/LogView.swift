import SwiftUI

struct LogView: View {
    @EnvironmentObject private var store: WorkLogStore

    @State private var day: Date = Date().startOfLocalDay()
    @State private var startTime: Date = Date.at(day: Date(), hour: 8, minute: 0)
    @State private var endTime: Date = Date.at(day: Date(), hour: 16, minute: 30)

    var body: some View {
        NavigationStack {
            ZStack {
                background

                ScrollView {
                    VStack(spacing: 16) {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Work Log")
                                    .font(.title2.weight(.semibold))

                                DatePicker("Day", selection: $day, displayedComponents: [.date])
                                    .datePickerStyle(.compact)
                                    .onChange(of: day) { _, newValue in
                                        loadForDay(newValue)
                                    }
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Quick templates")
                                    .font(.headline)

                                HStack(spacing: 10) {
                                    TemplateButton(label: "08:00–16:30") {
                                        applyTemplate(startHour: 8, startMinute: 0, endHour: 16, endMinute: 30)
                                    }

                                    TemplateButton(label: "08:30–17:00") {
                                        applyTemplate(startHour: 8, startMinute: 30, endHour: 17, endMinute: 0)
                                    }

                                    TemplateButton(label: "10:10–19:00") {
                                        applyTemplate(startHour: 10, startMinute: 10, endHour: 19, endMinute: 0)
                                    }
                                }
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Times")
                                    .font(.headline)

                                DatePicker("Start", selection: $startTime, displayedComponents: [.hourAndMinute])
                                    .datePickerStyle(.compact)

                                DatePicker("End", selection: $endTime, displayedComponents: [.hourAndMinute])
                                    .datePickerStyle(.compact)
                            }
                        }

                        if let message = store.lastSaveMessage {
                            GlassCard {
                                Label(message, systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }

                        if let error = store.lastErrorMessage {
                            GlassCard {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }

                        Button {
                            Task {
                                await store.upsertLog(day: day, start: startTime, end: endTime)
                                loadForDay(day)
                            }
                        } label: {
                            Text("Save")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.white.opacity(0.12))
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Log")
            .onAppear {
                loadForDay(day)
            }
            .onChange(of: store.requestedEditDay) { _, newValue in
                guard let newValue else { return }
                day = newValue
                loadForDay(newValue)
                store.requestedEditDay = nil
            }
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.09, blue: 0.12),
                Color(red: 0.04, green: 0.05, blue: 0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay(
            RadialGradient(
                colors: [Color.white.opacity(0.10), Color.clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 420
            )
            .ignoresSafeArea()
        )
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

private struct TemplateButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .tint(Color.white.opacity(0.14))
    }
}
