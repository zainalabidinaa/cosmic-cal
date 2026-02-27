import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showingAddTemplate = false
    @State private var appPassword = ""
    @State private var passwordLoaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
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
                            TextField("LMB Lund", text: $settings.eventTitle)
                        }
                        SettingsTextFieldRow(title: "Calendar Name") {
                            TextField("Arbete", text: $settings.calendarName)
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
                                .buttonStyle(.bordered)
                            }
                        }

                        Button {
                            showingAddTemplate = true
                        } label: {
                            Label("Add Template", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)
                    }

                    GlassCard(style: .subtle) {
                        Button("Reset to Defaults", role: .destructive) {
                            settings.resetToDefaults()
                            appPassword = ""
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.bordered)
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
            }
            .sheet(isPresented: $showingAddTemplate) {
                AddTemplateSheet(settings: settings)
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
                    .foregroundStyle(.secondary)

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
                .foregroundStyle(.secondary)
            field
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
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
