import CoreGraphics
import Foundation
import AppKit
import SwiftUI
import RedLightCore

// CLI flags are handled before any UI starts.
let args = CommandLine.arguments.dropFirst()

if args.contains("--status") {
    exit(CLI.status())
} else if args.contains("--probe") {
    exit(CLI.probe())
} else if let i = args.firstIndex(of: "--snapshot") {
    // Renders the UI to PNG files, for checking the design without a screen capture.
    let dir = args.index(after: i) < args.endIndex ? args[args.index(after: i)] : "."
    MainActor.assumeIsolated { Snapshot.run(directory: dir) }
    exit(0)
} else if args.contains("--help") || args.contains("-h") {
    print("Usage: RedLightBlock [--status | --probe]\n  no flag: run the menu-bar app")
    exit(0)
}

MainActor.assumeIsolated {
    RedLightBlockApp.main()
}

enum CLI {
    static let hm: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm zzz"
        return f
    }()

    static func fmt(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }

    static func status() -> Int32 {
        let s = Store.loadSettings()
        let now = Date()
        let mode = Store.loadMode()
        let paused = Store.loadPausedUntil()
        let effective = Store.effectiveMode(mode: mode, pausedUntil: paused, now: now)
        let sun = Schedule.sun(for: now, settings: s, calendar: .current)
        let r = Schedule.evaluate(mode: effective, now: now, settings: s, calendar: .current)

        print("RedLightBlock status  (\(hm.string(from: now)))")
        if let la = s.latitude, let lo = s.longitude {
            print(String(format: "Location:     %.4f, %.4f (saved)", la, lo))
        } else {
            print("Location:     none saved -> fallback sunrise 07:00 / sunset 19:00")
        }
        print("Sunrise:      \(hm.string(from: sun.sunrise))\(sun.isFallback ? "  (fallback)" : "")")
        print("Sunset:       \(hm.string(from: sun.sunset))\(sun.isFallback ? "  (fallback)" : "")")
        print("Wake / bed:   \(fmt(s.wakeMinutes)) / \(fmt(s.bedtimeMinutes))  (wind-down \(fmt(((s.bedtimeMinutes - 120) % 1440 + 1440) % 1440)))")
        print(String(format: "Red level:    %.2f   Morning tint: %@", s.redLevel, s.morningBoost ? "on" : "off"))
        var modeLine = "Mode:         \(mode.title)"
        if effective != mode { modeLine += "  (paused until \(hm.string(from: paused!)))" }
        print(modeLine)
        print("Phase:        \(r.phase.title)")
        print("Gains:        \(r.gains)")
        print("Next change:  \(r.nextChange.map { hm.string(from: $0) } ?? "-")")
        print("Displays:     \(GammaController.activeDisplays().count) active")
        for d in GammaController.readBack() {
            print(String(format: "  display %u current table end: R %.2f  G %.2f  B %.2f", d.display, d.last.r, d.last.g, d.last.b))
        }
        return 0
    }

    static func probe() -> Int32 {
        for sig in [SIGINT, SIGTERM] {
            signal(sig) { _ in
                CGDisplayRestoreColorSyncSettings()
                exit(1)
            }
        }
        let displays = GammaController.activeDisplays()
        guard !displays.isEmpty else {
            print("FAIL: no active displays")
            return 1
        }
        let target = ColorGains(r: 1, g: 0, b: 0)
        print("Applying pure red to \(displays.count) display(s) for 2 s...")
        let gamma = GammaController()
        gamma.apply(target, force: true)
        Thread.sleep(forTimeInterval: 2)
        let rb = GammaController.readBack()
        gamma.restore()
        for d in rb {
            print(String(format: "  display %u: last table sample R %.4f  G %.4f  B %.4f", d.display, d.last.r, d.last.g, d.last.b))
        }
        let after = GammaController.readBack()
        for d in after {
            print(String(format: "  restored %u:  last table sample R %.4f  G %.4f  B %.4f", d.display, d.last.r, d.last.g, d.last.b))
        }
        let pass = rb.count == displays.count && rb.allSatisfy { $0.last.isClose(to: target, tolerance: 0.02) }
        print(pass ? "PASS: green and blue read back as zero" : "FAIL: gamma table did not take")
        return pass ? 0 : 1
    }
}

@MainActor
enum Snapshot {
    static func run(directory: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let state = AppState.shared
        for dark in [true, false] {
            let suffix = dark ? "dark" : "light"
            render(SettingsView(state: state, height: 1900), size: nil, dark: dark, to: "\(directory)/settings-\(suffix).png")
            render(MenuView(state: state), size: nil, dark: dark, to: "\(directory)/menu-\(suffix).png")
        }
    }

    static func render<V: View>(_ view: V, size: CGSize?, dark: Bool, to path: String) {
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: host.fittingSize),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.setFrameOrigin(CGPoint(x: -20000, y: -20000))
        window.orderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        window.orderOut(nil)
        print("wrote \(path)")
    }
}
