import AppKit
import Combine
import Foundation
import RedLightCore
import ServiceManagement

/// UserDefaults keys and loading, shared by the UI and the CLI flags.
enum Store {
    static let d = UserDefaults.standard
    static let wake = "wakeMinutes", bed = "bedtimeMinutes", red = "redLevel", boost = "morningBoost"
    static let manual = "manualLevel"
    static let lat = "latitude", lon = "longitude", mode = "mode", pausedUntil = "pausedUntil"

    static func loadSettings() -> Settings {
        var s = Settings()
        if d.object(forKey: wake) != nil { s.wakeMinutes = d.integer(forKey: wake) }
        if d.object(forKey: bed) != nil { s.bedtimeMinutes = d.integer(forKey: bed) }
        if d.object(forKey: red) != nil { s.redLevel = min(max(d.double(forKey: red), 0.3), 1.0) }
        if d.object(forKey: boost) != nil { s.morningBoost = d.bool(forKey: boost) }
        if d.object(forKey: manual) != nil { s.manualLevel = min(max(d.double(forKey: manual), 0), 1) }
        if d.object(forKey: lat) != nil, d.object(forKey: lon) != nil {
            s.latitude = d.double(forKey: lat)
            s.longitude = d.double(forKey: lon)
        }
        return s
    }

    static func save(_ s: Settings) {
        d.set(s.wakeMinutes, forKey: wake)
        d.set(s.bedtimeMinutes, forKey: bed)
        d.set(s.redLevel, forKey: red)
        d.set(s.morningBoost, forKey: boost)
        d.set(s.manualLevel, forKey: manual)
        if let la = s.latitude, let lo = s.longitude {
            d.set(la, forKey: lat); d.set(lo, forKey: lon)
        } else {
            d.removeObject(forKey: lat); d.removeObject(forKey: lon)
        }
    }

    static func loadMode() -> Mode { Mode(rawValue: d.string(forKey: mode) ?? "") ?? .auto }
    static func loadPausedUntil() -> Date? { d.object(forKey: pausedUntil) as? Date }

    /// Mode actually in force: a pause means Off until it ends, then Auto.
    static func effectiveMode(mode: Mode, pausedUntil: Date?, now: Date) -> Mode {
        if let p = pausedUntil, now < p { return .off }
        return mode
    }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    func openSettings() { SettingsWindow.shared.show(state: self) }

    @Published var settings: Settings { didSet { Store.save(settings); refresh(force: false) } }
    @Published var mode: Mode { didSet { Store.d.set(mode.rawValue, forKey: Store.mode); refresh(force: false) } }
    @Published var pausedUntil: Date? {
        didSet { Store.d.set(pausedUntil, forKey: Store.pausedUntil); refresh(force: false) }
    }

    @Published private(set) var result = ScheduleResult(phase: .day, gains: .neutral, nextChange: nil)
    @Published private(set) var gammaWarning: String?
    @Published private(set) var locationMessage: String?
    @Published private(set) var launchAtLogin = false
    @Published private(set) var launchMessage: String?

    private let gamma = GammaController()
    private let location = LocationProvider()
    private var timer: Timer?
    private var hotKey: HotKey?
    private var observers: [NSObjectProtocol] = []
    private var signalSources: [DispatchSourceSignal] = []

    init() {
        settings = Store.loadSettings()
        mode = Store.loadMode()
        pausedUntil = Store.loadPausedUntil()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        start()
    }

    var effectiveMode: Mode { Store.effectiveMode(mode: mode, pausedUntil: pausedUntil, now: Date()) }
    var isPaused: Bool { pausedUntil.map { Date() < $0 } ?? false }

    var menuBarSymbol: String {
        switch result.phase {
        case .morning: return "sunrise.fill"
        case .day: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .night: return "moon.fill"
        case .off: return "circle.slash"
        }
    }

    private func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        let forceNames: [(NotificationCenter, Notification.Name)] = [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidWakeNotification),
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
        ]
        for (center, name) in forceNames {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh(force: true) }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.gamma.restore() }
        })
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler {
                CGDisplayRestoreColorSyncSettings()
                exit(0)
            }
            src.resume()
            signalSources.append(src)
        }
        hotKey = HotKey { [weak self] in
            MainActor.assumeIsolated { self?.toggleOffAuto() }
        }
        refresh(force: true)
    }

    /// Re-asserts the gamma every tick while a filter is active (macOS can reset it silently).
    private func tick() {
        if let p = pausedUntil, Date() >= p {
            pausedUntil = nil
            mode = .auto
        }
        refresh(force: !result.gains.isNeutral)
    }

    func refresh(force: Bool) {
        let m = effectiveMode
        let r = Schedule.evaluate(mode: m, now: Date(), settings: settings, calendar: .current)
        result = r
        show(r.gains, force: force)
    }

    /// Filter strength currently in force, 0 = unfiltered ... 1 = red only.
    var filterLevel: Double {
        effectiveMode == .manual ? settings.manualLevel : result.gains.filterLevel
    }

    /// Dragging the strength slider takes over from the schedule.
    func setFilterLevel(_ level: Double) {
        pausedUntil = nil
        settings.manualLevel = min(max(level, 0), 1)
        if mode != .manual { mode = .manual }
    }

    // MARK: Smooth changes

    private var shown: ColorGains?
    private var fadeTarget: ColorGains = .neutral
    private var fade: Timer?

    /// Moves the display to `target` without a visible jump: large changes glide over about half a second.
    private func show(_ target: ColorGains, force: Bool) {
        fadeTarget = target
        guard let from = shown, !from.isClose(to: target, tolerance: 0.004) else {
            fade?.invalidate(); fade = nil
            shown = target
            write(target, force: force)
            return
        }
        if force { write(from, force: true) }
        guard fade == nil else { return }
        fade = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.stepFade() }
        }
    }

    private func stepFade() {
        guard let from = shown else { return }
        var next = ColorGains.lerp(from, fadeTarget, 0.22)
        if next.isClose(to: fadeTarget, tolerance: 0.004) {
            next = fadeTarget
            fade?.invalidate(); fade = nil
        }
        shown = next
        write(next, force: false)
    }

    private func write(_ gains: ColorGains, force: Bool) {
        if force { gamma.invalidate() }
        if let ok = gamma.apply(gains, force: force) {
            gammaWarning = ok ? nil
                : "The display did not accept the colour filter (gamma readback mismatch). Known on some macOS 26 setups (M5 Pro/Max, HDR + auto-brightness)."
        }
    }

    func toggleOffAuto() {
        if mode == .off || isPaused {
            pausedUntil = nil
            mode = .auto
        } else {
            mode = .off
        }
    }

    func pauseOneHour() {
        pausedUntil = Date().addingTimeInterval(3600)
        mode = .auto
    }

    func useMyLocation() {
        locationMessage = "Locating..."
        location.requestOnce { [weak self] result in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch result {
                case .success(let c):
                    self.settings.latitude = (c.latitude * 1000).rounded() / 1000
                    self.settings.longitude = (c.longitude * 1000).rounded() / 1000
                    self.locationMessage = nil
                case .failure(let e):
                    self.locationMessage = e.localizedDescription
                }
            }
        }
    }

    func setManualLocation(lat: String, lon: String) {
        let clean = { (s: String) in Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }
        guard let la = clean(lat), let lo = clean(lon), (-90...90).contains(la), (-180...180).contains(lo) else {
            locationMessage = "Latitude must be -90...90 and longitude -180...180."
            return
        }
        settings.latitude = la
        settings.longitude = lo
        locationMessage = nil
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchMessage = nil
        } catch {
            launchMessage = "Could not change login item: \(error.localizedDescription) (move the app to /Applications and try again)."
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func quit() {
        gamma.restore()
        NSApplication.shared.terminate(nil)
    }
}
