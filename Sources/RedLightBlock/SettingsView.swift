import AppKit
import RedLightCore
import SwiftUI

/// The Settings window. A menu-bar app has no main window, so this is also what opens
/// when the app is launched from Finder, Spotlight or Launchpad.
@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show(state: AppState) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(state: state)))
            w.title = "NH Red Light Block"
            w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var latText = ""
    @State private var lonText = ""
    var height: CGFloat = 680

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("NH Red Light Block").font(.title2.weight(.semibold))
                        Text("PRIVATE HEALTH OFFICE")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.6)
                            .foregroundStyle(brandRed)
                        Text("\(state.result.phase.title) · \(state.phaseSubtitle)")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                TimelineBar(settings: state.settings)
                    .opacity(state.effectiveMode == .auto ? 1 : 0.4)
                    .padding(.vertical, 4)
            } footer: {
                Text("NH Red Light Block lives in the menu bar at the top right of your screen. Click its icon for quick controls.")
            }

            Section("Light spectrum right now") {
                SpectrumView(state: state)
            }

            Section("Schedule") {
                DatePicker("Wake up", selection: state.timeBinding(\.wakeMinutes), displayedComponents: .hourAndMinute)
                DatePicker("Bedtime", selection: state.timeBinding(\.bedtimeMinutes), displayedComponents: .hourAndMinute)
                LabeledContent("Red-only starts", value: Fmt.minutes(state.settings.bedtimeMinutes - 120))
                Picker("Mode", selection: Binding(get: { state.mode },
                                                  set: { state.pausedUntil = nil; state.mode = $0 })) {
                    Text("Automatic").tag(Mode.auto)
                    Text("Manual").tag(Mode.manual)
                    Text("Off").tag(Mode.off)
                }
            }

            Section {
                StrengthSlider(state: state)
            } footer: {
                Text("Drag to set any strength between unfiltered and red only. Moving the slider switches to Manual; choose Automatic to follow the schedule again.")
            }

            Section {
                LabeledContent("Red brightness") {
                    HStack(spacing: 8) {
                        Image(systemName: "sun.min").foregroundStyle(.secondary)
                        Slider(value: Binding(get: { state.settings.redLevel },
                                              set: { state.settings.redLevel = $0 }), in: 0.3...1.0)
                            .frame(width: 180)
                        Image(systemName: "sun.max").foregroundStyle(.secondary)
                        Text("\(Int((state.settings.redLevel * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            } header: {
                Text("Night")
            } footer: {
                Text("From two hours before bedtime until you wake, green and blue are switched off completely. Only red light, which barely affects your body clock, is left.")
            }

            Section {
                Toggle("Cool tint after waking", isOn: Binding(get: { state.settings.morningBoost },
                                                              set: { state.settings.morningBoost = $0 }))
            } header: {
                Text("Morning")
            } footer: {
                Text("For two hours after waking the screen is unfiltered and slightly cooler. A display cannot add blue light, so go outside for real morning light.")
            }

            Section {
                LabeledContent("Coordinates") {
                    if let la = state.settings.latitude, let lo = state.settings.longitude {
                        Text(String(format: "%.3f, %.3f", la, lo)).monospacedDigit()
                    } else {
                        Text("Not set").foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("Use My Location") { state.useMyLocation() }
                    Spacer()
                    TextField("Latitude", text: $latText).frame(width: 90)
                    TextField("Longitude", text: $lonText).frame(width: 90)
                    Button("Set") { state.setManualLocation(lat: latText, lon: lonText) }
                }
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                if let msg = state.locationMessage {
                    Text(msg).font(.callout).foregroundStyle(.orange)
                }
            } header: {
                Text("Location")
            } footer: {
                Text("Used only on this Mac to work out today's sunset. Without a location, sunset is assumed at 19:00.")
            }

            Section("General") {
                Toggle("Open at login", isOn: Binding(get: { state.launchAtLogin },
                                                      set: { state.setLaunchAtLogin($0) }))
                if let msg = state.launchMessage {
                    Text(msg).font(.callout).foregroundStyle(.orange)
                }
                LabeledContent("Turn filter off or on", value: "⌃⌥⌘R")
                if let warn = state.gammaWarning {
                    Label(warn, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                LabeledContent("Version", value: version)
            }
        }
        .formStyle(.grouped)
        .tint(brandRed)
        .frame(width: 500, height: height)
        .onAppear(perform: syncFields)
        .onChange(of: state.settings.latitude) { _, _ in syncFields() }
        .onChange(of: state.settings.longitude) { _, _ in syncFields() }
    }

    private func syncFields() {
        latText = state.settings.latitude.map { String($0) } ?? ""
        lonText = state.settings.longitude.map { String($0) } ?? ""
    }
}
