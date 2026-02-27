import SwiftUI
import EventKit

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showingAddTemplate = false
    @State private var appPassword = ""
    @State private var passwordLoaded = false
    @StateObject private var calendarCatalog = CalendarCatalog()
    @Namespace private var settingsNamespace

    var body: some View {
        NavigationStack {
            ScrollView {
                AdaptiveGlassGroup(spacing: 14) {
                    VStack(spacing: 14) {
                        GlassCard(style: .elevated) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("LMB")
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(.white)
                                Text("Calendar-first shift logging with a cleaner liquid interface.")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.82))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .adaptiveGlassUnion(id: "settingssurfaces", namespace: settingsNamespace)

                        SettingsGlassSection(title: "iCloud CalDAV", icon: "icloud") {
                            SettingsTextFieldRow(title: "Apple ID Email") {
                                TextField("name@icloud.com", text: $settings.iCloudEmail)
                                    .textContentType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.emailAddress)
                            }

                            SettingsTextFieldRow(title: "App-Specific Password") {
                                SecureField("Required for CalDAV sync", text: $appPassword)
                                    .textContentType(.password)
                                    .onChange(of: appPassword) { _, newValue in
                                        guard !settings.iCloudEmail.isEmpty else { return }
                                        if newValue.isEmpty {
                                            KeychainHelper.deletePassword(account: settings.iCloudEmail)
                                        } else {
                                            KeychainHelper.savePassword(newValue, account: settings.iCloudEmail)
                                        }
                                    }
                            }

                            if settings.calDAVConfigured {
                                Label("CalDAV enabled — travel time included.", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.green)
                            } else {
                                Text("Enter your Apple ID and app-specific password to sync with travel time via CalDAV.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        SettingsGlassSection(title: "Calendar Event", icon: "calendar.badge.clock") {
                            SettingsTextFieldRow(title: "Event Title") {
                                TextField("LMB", text: $settings.eventTitle)
                            }
                            SettingsValueRow(title: "Calendar Name") {
                                if calendarCatalog.calendarNames.isEmpty {
                                    HStack {
                                        Text(calendarCatalog.statusText)
                                            .font(.subheadline)
                                            .foregroundStyle(.white.opacity(0.86))
                                        Spacer()
                                        Button("Reload") {
                                            Task { await refreshCalendars() }
                                        }
                                        .adaptiveSecondaryButtonStyle()
                                    }
                                } else {
                                    Picker("Calendar", selection: $settings.calendarName) {
                                        ForEach(calendarCatalog.calendarNames, id: \.self) { name in
                                            Text(name).tag(name)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(.white)
                                }
                            }
                        }

                        SettingsGlassSection(title: "Location", icon: "location") {
                            SettingsTextFieldRow(title: "Destination") {
                                TextField("Destination address", text: $settings.destinationAddress)
                            }
                            SettingsTextFieldRow(title: "Fallback Origin") {
                                TextField("Origin fallback", text: $settings.originFallbackAddress)
                            }
                        }

                        SettingsGlassSection(title: "Shift Templates", icon: "clock.badge") {
                            ForEach(settings.shiftTemplates) { template in
                                HStack {
                                    Text(template.label)
                                        .font(.body.monospacedDigit())
                                    Spacer()
                                    Button(role: .destructive) {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            settings.shiftTemplates.removeAll { $0.id == template.id }
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .adaptiveSecondaryButtonStyle()
                                }
                            }

                            Button {
                                showingAddTemplate = true
                            } label: {
                                Label("Add Template", systemImage: "plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .adaptivePrimaryButtonStyle()
                            .tint(.orange)
                        }

                        GlassCard(style: .subtle) {
                            Button("Reset to Defaults", role: .destructive) {
                                settings.resetToDefaults()
                                appPassword = ""
                            }
                            .frame(maxWidth: .infinity)
                            .adaptiveSecondaryButtonStyle()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background {
                LiquidBackdrop()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                guard !passwordLoaded else { return }
                passwordLoaded = true
                if !settings.iCloudEmail.isEmpty {
                    appPassword = KeychainHelper.loadPassword(account: settings.iCloudEmail) ?? ""
                }
                Task { await refreshCalendars() }
            }
            .sheet(isPresented: $showingAddTemplate) {
                AddTemplateSheet(settings: settings)
            }
        }
    }

    private func refreshCalendars() async {
        await calendarCatalog.load()
        if !calendarCatalog.calendarNames.contains(settings.calendarName), let first = calendarCatalog.calendarNames.first {
            settings.calendarName = first
        }
    }
}

@MainActor
private final class CalendarCatalog: ObservableObject {
    @Published var calendarNames: [String] = []
    @Published var statusText = "No calendars available"

    private let eventStore = EKEventStore()

    func load() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .notDetermined:
            _ = try? await eventStore.requestFullAccessToEvents()
        case .authorized, .fullAccess, .writeOnly:
            break
        case .denied, .restricted:
            calendarNames = []
            statusText = "Calendar access is denied"
            return
        @unknown default:
            calendarNames = []
            statusText = "Calendar permission unavailable"
            return
        }

        let writable = eventStore.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .map(\.title)
        let uniqueSorted = Array(Set(writable)).sorted()

        calendarNames = uniqueSorted
        statusText = uniqueSorted.isEmpty ? "No writable calendars found" : ""
    }
}

private struct SettingsGlassSection<Content: View>: View {
    let title: String
    let icon: String
    private let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))

                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SettingsTextFieldRow<Content: View>: View {
    let title: String
    private let field: Content

    init(title: String, @ViewBuilder field: () -> Content) {
        self.title = title
        self.field = field()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.78))
            field
                .foregroundStyle(.white)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.24), lineWidth: 1)
                        .allowsHitTesting(false)
                }
        }
    }
}

private struct SettingsValueRow<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.78))
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.24), lineWidth: 1)
                        .allowsHitTesting(false)
                }
        }
    }
}

private struct AddTemplateSheet: View {
    let settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var startTime = Date.at(day: Date(), hour: 8, minute: 0)
    @State private var endTime = Date.at(day: Date(), hour: 16, minute: 30)

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
            }
            .formStyle(.grouped)
            .navigationTitle("New Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let cal = Calendar.current
                        let template = ShiftTemplate(
                            startHour: cal.component(.hour, from: startTime),
                            startMinute: cal.component(.minute, from: startTime),
                            endHour: cal.component(.hour, from: endTime),
                            endMinute: cal.component(.minute, from: endTime)
                        )
                        settings.shiftTemplates.append(template)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(.regularMaterial)
    }
}
