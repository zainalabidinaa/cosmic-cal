import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showingAddTemplate = false

    var body: some View {
        NavigationStack {
            ZStack {
                CosmicBackground()

                Form {
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
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
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
