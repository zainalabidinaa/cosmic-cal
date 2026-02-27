import SwiftUI

struct LogView: View {
    @EnvironmentObject private var store: WorkLogStore
    @EnvironmentObject private var settings: AppSettings

    @State private var day: Date = Date().startOfLocalDay()
    @State private var startTime: Date = Date.at(day: Date(), hour: 8, minute: 0)
    @State private var endTime: Date = Date.at(day: Date(), hour: 16, minute: 30)
    @State private var isSaving = false
    @State private var successHapticTrigger = 0
    @State private var errorHapticTrigger = 0
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                CosmicBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Shift")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)

                                DatePicker("Day", selection: $day, displayedComponents: [.date])
                                    .datePickerStyle(.compact)
                                    .onChange(of: day) { _, newValue in
                                        loadForDay(newValue)
                                    }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if !settings.shiftTemplates.isEmpty {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Quick Templates")
                                        .font(.headline)
                                        .foregroundStyle(.secondary)

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 10) {
                                            ForEach(settings.shiftTemplates) { template in
                                                TemplateChip(
                                                    template.label,
                                                    isActive: isTemplateActive(template)
                                                ) {
                                                    applyTemplate(template)
                                                }
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Times")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)

                                DatePicker("Start", selection: $startTime, displayedComponents: [.hourAndMinute])
                                    .datePickerStyle(.compact)

                                DatePicker("End", selection: $endTime, displayedComponents: [.hourAndMinute])
                                    .datePickerStyle(.compact)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let message = store.lastSaveMessage {
                            GlassCard {
                                Label(message, systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        if let error = store.lastErrorMessage {
                            GlassCard {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        Button {
                            guard !isSaving else { return }
                            Task {
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
                        } label: {
                            HStack(spacing: 10) {
                                if isSaving {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.headline)
                                }
                                Text(isSaving ? "Saving…" : "Save")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.white.opacity(0.14))
                        .disabled(isSaving)
                        .accessibilityLabel(isSaving ? "Saving shift" : "Save shift")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .animation(.easeInOut(duration: 0.3), value: store.lastSaveMessage)
                    .animation(.easeInOut(duration: 0.3), value: store.lastErrorMessage)
                }
            }
            .navigationTitle(settings.eventTitle)
            .navigationBarTitleDisplayMode(.large)
            .sensoryFeedback(.success, trigger: successHapticTrigger)
            .sensoryFeedback(.error, trigger: errorHapticTrigger)
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

private struct TemplateChip: View {
    private let label: String
    private let isActive: Bool
    private let action: () -> Void

    init(_ label: String, isActive: Bool, action: @escaping () -> Void) {
        self.label = label
        self.isActive = isActive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isActive ? Color.mint : .primary)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background {
                    if isActive {
                        Capsule(style: .continuous).fill(Color.mint.opacity(0.15))
                    } else {
                        Capsule(style: .continuous).fill(.ultraThinMaterial)
                    }
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(
                            isActive
                                ? LinearGradient(
                                    colors: [Color.mint.opacity(0.6), Color.mint.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing)
                                : LinearGradient(
                                    colors: [Color.white.opacity(0.20), Color.white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Shift \(label)")
    }
}
