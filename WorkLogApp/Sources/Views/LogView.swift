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
    @State private var animateIn = false
    @Namespace private var templateNamespace

    var body: some View {
        NavigationStack {
            ScrollView {
                AdaptiveGlassGroup(spacing: 18) {
                    VStack(spacing: 16) {
                        GlassCard(style: .elevated) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(Formatters.day.string(from: day))
                                    .font(.headline)
                                    .foregroundStyle(.secondary)

                                HStack(alignment: .firstTextBaseline) {
                                    Text(durationPreview)
                                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                                    Spacer()
                                    Image(systemName: "sparkles")
                                        .imageScale(.large)
                                        .foregroundStyle(.cyan)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GlassCard(style: .elevated) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Label("Shift", systemImage: "calendar")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    Text(durationPreview)
                                        .font(.subheadline.weight(.bold).monospacedDigit())
                                        .foregroundStyle(.primary)
                                }

                                DatePicker("Day", selection: $day, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .onChange(of: day) { _, newValue in loadForDay(newValue) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if !settings.shiftTemplates.isEmpty {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Label("Templates", systemImage: "clock.badge.checkmark")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(settings.shiftTemplates) { template in
                                                TemplateChip(
                                                    template.label,
                                                    isActive: isTemplateActive(template),
                                                    namespace: templateNamespace
                                                ) {
                                                    applyTemplate(template)
                                                }
                                            }
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Times", systemImage: "clock")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.compact)

                                DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.compact)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let message = store.lastSaveMessage {
                            GlassCard(style: .subtle) {
                                Label(message, systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.subheadline.weight(.medium))
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        if let error = store.lastErrorMessage {
                            GlassCard(style: .subtle) {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.subheadline.weight(.medium))
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100)
                .opacity(animateIn ? 1 : 0.6)
                .offset(y: animateIn ? 0 : 18)
                .animation(.easeOut(duration: 0.35), value: animateIn)
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
                .adaptivePrimaryButtonStyle()
                .controlSize(.large)
                .tint(.teal)
                .disabled(isSaving)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .accessibilityLabel(isSaving ? "Saving shift" : "Save shift")
            }
            .scrollContentBackground(.hidden)
            .background {
                LiquidBackdrop()
            }
            .navigationTitle(settings.eventTitle)
            .navigationBarTitleDisplayMode(.large)
            .sensoryFeedback(.success, trigger: successHapticTrigger)
            .sensoryFeedback(.error, trigger: errorHapticTrigger)
            .animation(.easeInOut(duration: 0.3), value: store.lastSaveMessage)
            .animation(.easeInOut(duration: 0.3), value: store.lastErrorMessage)
            .onAppear { loadForDay(day) }
            .onAppear { animateIn = true }
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

    private var durationPreview: String {
        let seconds = max(0, endTime.timeIntervalSince(startTime))
        let totalMinutes = Int(seconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Template Chip

private struct TemplateChip: View {
    private let label: String
    private let isActive: Bool
    private let namespace: Namespace.ID
    private let action: () -> Void

    init(_ label: String, isActive: Bool, namespace: Namespace.ID, action: @escaping () -> Void) {
        self.label = label
        self.isActive = isActive
        self.namespace = namespace
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .foregroundStyle(isActive ? .white : .primary)
                .background(
                    isActive ? Color.teal.opacity(0.75) : Color.white.opacity(0.12),
                    in: Capsule(style: .continuous)
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(isActive ? 0.18 : 0.1), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .adaptiveGlassUnion(id: "templatechips", namespace: namespace)
        .accessibilityLabel("Shift \(label)")
    }
}
