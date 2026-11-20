import RedLightCore
import SwiftUI

/// Accent that stays visible when the screen is red-only (system blue would turn black).
let brandRed = Color(red: 1.0, green: 0.267, blue: 0.2)        // NH red   #FF4433
let brandTeal = Color(red: 0.063, green: 0.110, blue: 0.251)   // icon navy #101C40
let brandBeige = Color(red: 1.0, green: 0.86, blue: 0.62)       // warm amber-cream, readable on navy

enum Fmt {
    private static let hm: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static func time(_ d: Date) -> String { hm.string(from: d) }

    static func minutes(_ m: Int) -> String {
        let n = ((m % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", n / 60, n % 60)
    }
}

extension AppState {
    func timeBinding(_ key: WritableKeyPath<RedLightCore.Settings, Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: self.settings[keyPath: key] / 60,
                                      minute: self.settings[keyPath: key] % 60, second: 0, of: Date()) ?? Date()
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                self.settings[keyPath: key] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }

    var phaseColor: Color {
        switch result.phase {
        case .morning: return .cyan
        case .day: return .yellow
        case .evening: return .orange
        case .night: return brandRed
        case .off: return .secondary
        }
    }

    var phaseSubtitle: String {
        if isPaused, let p = pausedUntil { return "Paused until \(Fmt.time(p))" }
        if effectiveMode == .manual { return "Manual · \(Int((settings.manualLevel * 100).rounded()))% filter" }
        let next = effectiveMode == .auto ? result.nextChange.map(Fmt.time) : nil
        switch result.phase {
        case .morning: return next.map { "Cool, unfiltered until \($0)" } ?? "Cool, unfiltered"
        case .day: return next.map { "Unfiltered · next change \($0)" } ?? "Unfiltered"
        case .evening: return next.map { "Blue reduced · next change \($0)" } ?? "Blue reduced"
        case .night: return next.map { "Green and blue off until \($0)" } ?? "Green and blue off"
        case .off: return "Filter is off"
        }
    }
}

struct MenuView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            TimelineBar(settings: state.settings)
                .opacity(state.effectiveMode == .auto ? 1 : 0.4)
                .help(state.effectiveMode == .auto ? "Today's schedule" : "Schedule is not in use. Choose Auto to follow it.")

            ModeSwitch(state: state)

            StrengthSlider(state: state)

            if state.filterLevel > 0.5 {
                HStack(spacing: 8) {
                    Image(systemName: "sun.min").foregroundStyle(.secondary)
                    Slider(value: Binding(get: { state.settings.redLevel },
                                          set: { state.settings.redLevel = $0 }), in: 0.3...1.0)
                    Image(systemName: "sun.max").foregroundStyle(.secondary)
                }
                .help("Brightness of the red screen")
            }

            if let warn = state.gammaWarning {
                Label(warn, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(spacing: 1) {
                MenuRow(title: state.isPaused ? "Resume" : "Pause for 1 Hour", shortcut: "⌃⌥⌘R") {
                    if state.isPaused { state.pausedUntil = nil } else { state.pauseOneHour() }
                }
                MenuRow(title: "Settings…", shortcut: "⌘,") { state.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
                MenuRow(title: "Quit NH Red Light Block", shortcut: "⌘Q") { state.quit() }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, -6)

            Text("NH  ·  PRIVATE HEALTH OFFICE")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(width: 320)
        .tint(brandRed)
    }

    private var header: some View {
        HStack(spacing: 12) {
            PhaseBadge(symbol: state.menuBarSymbol, active: state.result.phase != .off)
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(state.result.phase.title.uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.3)
                Text(state.phaseSubtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

/// The NH pillar-icon look: a teal disc with a red line icon.
struct PhaseBadge: View {
    let symbol: String
    let active: Bool

    var body: some View {
        ZStack {
            Circle().fill(brandTeal)
            Circle().strokeBorder(brandRed.opacity(active ? 0.55 : 0.2), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(active ? brandRed : brandBeige.opacity(0.7))
        }
        .accessibilityHidden(true)
    }
}

/// Full-width Auto / Manual / Off switch in the NH colours.
struct ModeSwitch: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 2) {
            ForEach([Mode.auto, .manual, .off], id: \.self) { m in
                let selected = state.mode == m
                Button {
                    state.pausedUntil = nil
                    state.mode = m
                } label: {
                    Text(m.title)
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? brandBeige : Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(selected ? brandTeal : Color.clear)
                                .overlay(RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(brandRed.opacity(selected ? 0.55 : 0), lineWidth: 1))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.07)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mode")
    }
}

/// One continuous control from unfiltered through amber to red only. Dragging it switches to Manual.
struct StrengthSlider: View {
    @ObservedObject var state: AppState

    var body: some View {
        let level = state.filterLevel
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Filter strength")
                Spacer()
                Text("\(Int((level * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.callout)

            Slider(value: Binding(get: { state.filterLevel }, set: { state.setFilterLevel($0) }), in: 0...1) {
                Text("Filter strength")
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 0.1).map {
                let g = ColorGains.filter(level: $0)
                return Color(red: g.r, green: g.g, blue: g.b)
            }, startPoint: .leading, endPoint: .trailing)
                .frame(height: 4)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15)))

            HStack {
                Text("Unfiltered")
                Spacer()
                Text("Amber")
                Spacer()
                Text("Red only")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
    }
}

/// A full-width row that highlights on hover, like a native menu item.
struct MenuRow: View {
    let title: String
    let shortcut: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(shortcut).foregroundStyle(.secondary).font(.callout)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(hovering ? 0.1 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Today's 24 hours drawn in the colour the screen will actually show, with a "now" marker.
struct TimelineBar: View {
    let settings: RedLightCore.Settings
    private let samples = 144

    var body: some View {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let sun = Schedule.sun(for: Date(), settings: settings, calendar: cal)
        let colors: [Color] = (0..<samples).map { i in
            let t = start.addingTimeInterval((Double(i) + 0.5) * 86400 / Double(samples))
            let g = Schedule.evaluate(mode: .auto, now: t, settings: settings, calendar: cal).gains
            return Color(red: g.r, green: g.g, blue: g.b)
        }
        let nowFraction = min(max(Date().timeIntervalSince(start) / 86400, 0), 1)

        return VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        ForEach(0..<samples, id: \.self) { i in colors[i] }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))

                    Capsule()
                        .fill(Color.black)
                        .overlay(Capsule().strokeBorder(Color.white, lineWidth: 1.5))
                        .frame(width: 6, height: geo.size.height + 6)
                        .offset(x: geo.size.width * nowFraction - 3, y: 0)
                }
            }
            .frame(height: 18)

            HStack {
                Label(Fmt.time(sun.sunrise), systemImage: "sunrise")
                Spacer()
                Text(sun.isFallback ? "No location set" : "Today")
                Spacer()
                Label(Fmt.time(sun.sunset), systemImage: "sunset")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today's screen colour schedule. Sunrise \(Fmt.time(sun.sunrise)), sunset \(Fmt.time(sun.sunset)).")
    }
}
