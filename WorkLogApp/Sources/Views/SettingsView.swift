import SwiftUI
import EventKit

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showingAddTemplate = false
    @State private var appPassword = ""
    @State private var passwordLoaded = false
    @State private var isRunningTravelTest = false
    @State private var travelTestReport: String?
    @StateObject private var calendarCatalog = CalendarCatalog()
    @Namespace private var settingsNamespace

    var body: some View {
        NavigationStack {
            ScrollView {
                AdaptiveGlassGroup(spacing: 14) {
                    VStack(spacing: 14) {
                        GlassCard(style: .elevated) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("labmedicin")
                                        .font(.title2.weight(.bold))
                                    Spacer()
                                    Text(settings.calendarName)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(GraphiteCopperTheme.copper.opacity(0.16), in: Capsule(style: .continuous))
                                }
                                    .foregroundStyle(GraphiteCopperTheme.textPrimary)
                                Text("Calendar-first shift logging with graphite surfaces and focused copper highlights.")
                                    .font(.subheadline)
                                    .foregroundStyle(GraphiteCopperTheme.textSecondary)
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
                                Label("CalDAV credentials saved — use Travel Metadata Test for CalDAV checks.", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.green)
                            } else {
                                Text("EventKit is used for normal saves. Add Apple ID + app-specific password only to run CalDAV travel metadata tests.")
                                    .font(.caption)
                                    .foregroundStyle(GraphiteCopperTheme.textSecondary)
                            }

                            SettingsStatusRow(
                                title: "Sync Path",
                                value: syncPathLabel,
                                isHealthy: true
                            )

                            SettingsStatusRow(
                                title: "Calendar Compatibility",
                                value: calendarCompatibilityLabel,
                                isHealthy: calendarSupportsTravelMetadata
                            )
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
                            SettingsValueRow(title: "Travel Origin") {
                                Picker("Travel Origin", selection: $settings.travelOriginMode) {
                                    ForEach(TravelOriginMode.allCases) { mode in
                                        Text(mode.title).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            SettingsValueRow(title: "Travel Time") {
                                Picker("Travel Time", selection: $settings.travelTimeMode) {
                                    ForEach(TravelTimeMode.allCases) { mode in
                                        Text(mode.title).tag(mode)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(.white)
                            }

                            SettingsTextFieldRow(title: "Destination") {
                                TextField("Destination address", text: $settings.destinationAddress)
                            }

                            if settings.travelOriginMode == .customAddress {
                                SettingsTextFieldRow(title: "Custom Origin") {
                                    TextField("Origin address", text: $settings.originFallbackAddress)
                                }
                            } else {
                                Text("Current mode uses your device location for travel-time routing.")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.78))
                            }

                            if settings.travelTimeMode == .dynamicDriving {
                                Text("Dynamic driving uses Apple travel metadata and works best with an iCloud calendar + CalDAV sync.")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.72))
                            }

                            Button {
                                guard !isRunningTravelTest else { return }
                                Task {
                                    isRunningTravelTest = true
                                    let sync = CalendarSync(settings: settings)
                                    travelTestReport = await sync.runTravelMetadataTest()
                                    isRunningTravelTest = false
                                }
                            } label: {
                                HStack {
                                    if isRunningTravelTest {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "checkmark.shield")
                                    }
                                    Text(isRunningTravelTest ? "Running travel test…" : "Run Travel Metadata Test")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .adaptivePrimaryButtonStyle()
                            .tint(GraphiteCopperTheme.copper)

                            if let travelTestReport {
                                ScrollView {
                                    Text(travelTestReport)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.white.opacity(0.9))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 140)
                                .padding(10)
                                .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                            .tint(GraphiteCopperTheme.copper)
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

    private var syncPathLabel: String {
        settings.calDAVConfigured ? "EventKit primary · CalDAV optional" : "EventKit primary"
    }

    private var calendarCompatibilityLabel: String {
        if calendarSupportsTravelMetadata {
            return "iCloud/CalDAV calendar selected"
        }
        return "Travel metadata may be limited"
    }

    private var calendarSupportsTravelMetadata: Bool {
        calendarCatalog.calendarSupportsTravelMetadata(named: settings.calendarName)
    }
}

@MainActor
private final class CalendarCatalog: ObservableObject {
    struct CalendarOption {
        let title: String
        let type: EKCalendarType
    }

    @Published var calendarOptions: [CalendarOption] = []
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
        let options = writable.map { CalendarOption(title: $0.title, type: $0.type) }
        let uniqueSorted = Array(Set(options.map(\.title))).sorted()

        calendarOptions = options
        calendarNames = uniqueSorted
        statusText = uniqueSorted.isEmpty ? "No writable calendars found" : ""
    }

    func calendarSupportsTravelMetadata(named calendarName: String) -> Bool {
        guard let option = calendarOptions.first(where: { $0.title == calendarName }) else {
            return false
        }
        return option.type == .calDAV
    }
}

private struct SettingsStatusRow: View {
    let title: String
    let value: String
    let isHealthy: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(GraphiteCopperTheme.textSecondary)

            Spacer()

            Text(value)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background((isHealthy ? Color.green : GraphiteCopperTheme.copper).opacity(0.24), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(GraphiteCopperTheme.hairline, lineWidth: 1)
                        .allowsHitTesting(false)
                }
        }
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
                    .foregroundStyle(GraphiteCopperTheme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(GraphiteCopperTheme.copper.opacity(0.10), in: Capsule(style: .continuous))

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
                .foregroundStyle(GraphiteCopperTheme.textSecondary)
            field
                .foregroundStyle(.white)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(GraphiteCopperTheme.graphite900.opacity(0.58), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(GraphiteCopperTheme.hairline, lineWidth: 1)
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
                .foregroundStyle(GraphiteCopperTheme.textSecondary)
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(GraphiteCopperTheme.graphite900.opacity(0.58), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(GraphiteCopperTheme.hairline, lineWidth: 1)
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
