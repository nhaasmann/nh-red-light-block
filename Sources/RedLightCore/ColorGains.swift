import Foundation

/// Per-channel maximum output (0...1) for the display gamma formula.
public struct ColorGains: Equatable, Sendable, CustomStringConvertible {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public static let neutral = ColorGains(r: 1, g: 1, b: 1)
    public static let morningBoost = ColorGains(r: 0.88, g: 0.96, b: 1.00)
    public static let amber = ColorGains(r: 1.00, g: 0.55, b: 0.15)
    public static func red(level: Double) -> ColorGains {
        ColorGains(r: min(max(level, 0.3), 1.0), g: 0, b: 0)
    }

    /// Continuous filter strength: 0 = unfiltered, 0.5 = amber, 1 = red only.
    /// `brightness` (0.3...1) dims the red end, so level 1 equals `red(level: brightness)`.
    public static func filter(level: Double, brightness: Double = 1) -> ColorGains {
        let t = min(max(level, 0), 1)
        let full = ColorGains(r: 1, g: 0, b: 0)
        let base = t <= 0.5 ? lerp(.neutral, .amber, t * 2) : lerp(.amber, full, (t - 0.5) * 2)
        let dim = 1 - (1 - min(max(brightness, 0.3), 1)) * max(0, (t - 0.5) * 2)
        return ColorGains(r: base.r * dim, g: base.g * dim, b: base.b * dim)
    }

    /// Approximate filter strength (0...1) of any gains, from how much green is left relative to red.
    public var filterLevel: Double {
        guard r > 0 else { return 1 }
        let green = min(max(g / r, 0), 1)
        return green >= amberGreen ? 0.5 * (1 - green) / (1 - amberGreen) : 0.5 + 0.5 * (amberGreen - green) / amberGreen
    }
    private var amberGreen: Double { ColorGains.amber.g }

    /// Linear interpolation, t clamped to 0...1.
    public static func lerp(_ a: ColorGains, _ b: ColorGains, _ t: Double) -> ColorGains {
        let t = min(max(t, 0), 1)
        return ColorGains(
            r: a.r + (b.r - a.r) * t,
            g: a.g + (b.g - a.g) * t,
            b: a.b + (b.b - a.b) * t
        )
    }

    public func isClose(to other: ColorGains, tolerance: Double = 0.02) -> Bool {
        abs(r - other.r) <= tolerance && abs(g - other.g) <= tolerance && abs(b - other.b) <= tolerance
    }

    public var isNeutral: Bool { isClose(to: .neutral, tolerance: 0.0005) }

    public var description: String {
        String(format: "R %.2f  G %.2f  B %.2f", r, g, b)
    }
}
