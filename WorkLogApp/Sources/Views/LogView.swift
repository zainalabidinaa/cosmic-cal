import SwiftUI

struct LogView: View {
    @EnvironmentObject private var store: WorkLogStore
    @EnvironmentObject private var settings: AppSettings

    @State private var day = Date().startOfLocalDay()
    @State private var startTime = Date.at(day: Date(), hour: 8, minute: 0)
    @State private var endTime = Date.at(day: Date(), hour: 16, minute: 30)
    @State private var isSaving = false
    @State private var successHapticTrigger = 0
    @State private var errorHapticTrigger = 0
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Day", selection: $day, displayedComponents: .date)
                        .onChange(of: day) { _, newValue in loadForDay(newValue) }
                }

                if !settings.shiftTemplates.isEmpty {
                    Section("Templates") {
                        ForEach(settings.shiftTemplates) { template in
                            Button {
                                applyTemplate(template)
                            } label: {
                                HStack {
                                    Text(template.label)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if isTemplateActive(template) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.mint)
                                            .fontWeight(.semibold)
                                    }
                                }
                            }
                            .accessibilityLabel("Shift \(template.label)")
                        }
                    }
                }

                Section {
                    DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                }

                if let message = store.lastSaveMessage {
                    Section {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline)
                    }
                }

                if let error = store.lastErrorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    guard !isSaving else { return }
                    Task { await save() }
                } label: {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark.seal.fill")
                        }
                        Text(isSaving ? "Saving…" : "Save Shift")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .glassEffect(.regular.interactive().tint(.mint.opacity(0.4)), in: .capsule)
                .disabled(isSaving)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .accessibilityLabel(isSaving ? "Saving shift" : "Save shift")
            }
            .navigationTitle(settings.eventTitle)
            .sensoryFeedback(.success, trigger: successHapticTrigger)
            .sensoryFeedback(.error, trigger: errorHapticTrigger)
            .animation(.default, value: store.lastSaveMessage)
            .animation(.default, value: store.lastErrorMessage)
            .onAppear { loadForDay(day) }
            .onChange(of: store.requestedEditDay) { _, newValue in
                guard let newValue else { return }
                day = newValue
                loadForDay(newValue)
                store.requestedEditDay = nil
            }
        }
    }

    // MARK: - Actions

    private func save() async {
        isSaving = true
        await store.upsertLog(day: day, start: startTime, end: endTime)
        isSaving = false
        loadForDay(day)

        if store.lastSaveMessage != nil {
            successHapticTrigger += 1
        } else if store.lastErrorMessage != nil {
            errorHapticTrigger += 1
        }
        scheduleMessageDismissal()
    }

    private func isTemplateActive(_ template: ShiftTemplate) -> Bool {
        let cal = Calendar.current
        return template.startHour == cal.component(.hour, from: startTime)
            && template.startMinute == cal.component(.minute, from: startTime)
            && template.endHour == cal.component(.hour, from: endTime)
            && template.endMinute == cal.component(.minute, from: endTime)
    }

    private func applyTemplate(_ template: ShiftTemplate) {
        let dayStart = day.startOfLocalDay()
        startTime = Date.at(day: dayStart, hour: template.startHour, minute: template.startMinute)
        endTime = Date.at(day: dayStart, hour: template.endHour, minute: template.endMinute)
    }

    private func loadForDay(_ value: Date) {
        let dayStart = value.startOfLocalDay()

        if let log = store.log(for: dayStart) {
            startTime = log.start
            endTime = log.end
        } else {
            day = dayStart
            if let first = settings.shiftTemplates.first {
                applyTemplate(first)
            } else {
                startTime = Date.at(day: dayStart, hour: 8, minute: 0)
                endTime = Date.at(day: dayStart, hour: 16, minute: 30)
            }
        }
    }

    private func scheduleMessageDismissal() {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            store.lastSaveMessage = nil
            store.lastErrorMessage = nil
        }
    }
}
