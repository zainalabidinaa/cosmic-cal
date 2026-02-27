import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showingAddTemplate = false
    @State private var appPassword = ""
    @State private var passwordLoaded = false

    var body: some View {
        NavigationStack {
            ZStack {
                CosmicBackground()

                Form {
                    Section {
                        TextField("Apple ID Email", text: $settings.iCloudEmail)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)

                        SecureField("App-Specific Password", text: $appPassword)
                            .textContentType(.password)
                            .onChange(of: appPassword) { _, newValue in
                                guard !settings.iCloudEmail.isEmpty else { return }
                                if newValue.isEmpty {
                                    KeychainHelper.deletePassword(account: settings.iCloudEmail)
                                } else {
                                    KeychainHelper.savePassword(newValue, account: settings.iCloudEmail)
                                }
                            }

                        if settings.calDAVConfigured {
                            Label("CalDAV enabled -- events will include travel time.", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Text("Enter your Apple ID and an app-specific password (appleid.apple.com) to sync events via CalDAV with full travel time support.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("iCloud CalDAV")
                    }

                    Section("Calendar Event") {
                        TextField("Event Title", text: $settings.eventTitle)
                        TextField("Calendar Name", text: $settings.calendarName)
                    }

                    Section("Location") {
                        TextField("Destination Address", text: $settings.destinationAddress)
                        TextField("Fallback Origin Address", text: $settings.originFallbackAddress)
                    }

                    Section("Shift Templates") {
                        ForEach(settings.shiftTemplates) { template in
                            Text(template.label)
                        }
                        .onDelete { offsets in
                            settings.shiftTemplates.remove(atOffsets: offsets)
                        }

                        Button {
                            showingAddTemplate = true
                        } label: {
                            Label("Add Template", systemImage: "plus")
                        }
                    }

                    Section {
                        Button("Reset to Defaults", role: .destructive) {
                            settings.resetToDefaults()
                            appPassword = ""
                        }
                    }
                }
                .scrollContentBackground(.hidden)
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
    }
}
