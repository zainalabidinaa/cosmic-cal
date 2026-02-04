import SwiftUI

struct LogView: View {
    @EnvironmentObject private var store: WorkLogStore

    @State private var day: Date = Date().startOfLocalDay()
    @State private var startTime: Date = Date.at(day: Date(), hour: 8, minute: 0)
    @State private var endTime: Date = Date.at(day: Date(), hour: 16, minute: 30)
    @State private var animateIn = false

    var body: some View {
        NavigationStack {
            ZStack {
                background

                ScrollView {
                    VStack(spacing: 18) {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Shift")
                                    .font(sectionTitleFont)
                                    .foregroundStyle(.secondary)

                                DatePicker("Day", selection: $day, displayedComponents: [.date])
                                    .datePickerStyle(.compact)
                                    .onChange(of: day) { _, newValue in
                                        loadForDay(newValue)
                                    }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Quick Templates")
                                    .font(sectionTitleFont)
                                    .foregroundStyle(.secondary)

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
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Times")
                                    .font(sectionTitleFont)
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
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.custom("Avenir Next", size: 16).weight(.semibold))
                                Text("Save")
                                    .font(.custom("Avenir Next", size: 16).weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.white.opacity(0.18))
                    }
                    .opacity(animateIn ? 1 : 0)
                    .offset(y: animateIn ? 0 : 12)
                    .animation(.easeOut(duration: 0.6), value: animateIn)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("LMB Lund")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                loadForDay(day)
                animateIn = true
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
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.09),
                    Color(red: 0.01, green: 0.02, blue: 0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.cyan.opacity(0.25), Color.clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 220
                    )
                )
                .frame(width: 260, height: 260)
                .offset(x: 120, y: -160)
                .blur(radius: 6)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.mint.opacity(0.22), Color.clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 240
                    )
                )
                .frame(width: 300, height: 300)
                .offset(x: -140, y: 180)
                .blur(radius: 8)

            RadialGradient(
                colors: [Color.white.opacity(0.14), Color.clear],
                center: .topTrailing,
                startRadius: 30,
                endRadius: 640
            )

            RadialGradient(
                colors: [Color.mint.opacity(0.12), Color.clear],
                center: .bottomLeading,
                startRadius: 30,
                endRadius: 620
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

    private var sectionTitleFont: Font {
        .custom("Avenir Next", size: 15).weight(.semibold)
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
                .font(.custom("Avenir Next", size: 14).weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(
                    .thinMaterial,
                    in: Capsule(style: .continuous)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.30), Color.white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        .blur(radius: 2)
                        .offset(y: 1)
                        .mask(
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white, Color.clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                )
        }
        .buttonStyle(.plain)
    }
}
