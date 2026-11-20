import Foundation

public enum Mode: String, CaseIterable, Sendable {
    case auto, manual, off

    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .manual: return "Manual"
        case .off: return "Off"
        }
    }
}

public enum Phase: String, Sendable {
    case morning, day, evening, night, off

    public var title: String {
        switch self {
        case .morning: return "Morning"
        case .day: return "Day"
        case .evening: return "Evening amber"
        case .night: return "Night red"
        case .off: return "Off"
        }
    }
}

public struct Settings: Equatable, Sendable {
    /// Minutes after local midnight.
    public var wakeMinutes: Int
    public var bedtimeMinutes: Int
    /// 0.3 ... 1.0
    public var redLevel: Double
    public var morningBoost: Bool
    /// Filter strength used in manual mode: 0 = unfiltered, 0.5 = amber, 1 = red only.
    public var manualLevel: Double = 1.0
    public var latitude: Double?
    public var longitude: Double?

    public init(
        wakeMinutes: Int = 6 * 60 + 30,
        bedtimeMinutes: Int = 22 * 60 + 30,
        redLevel: Double = 1.0,
        morningBoost: Bool = true,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.wakeMinutes = wakeMinutes
        self.bedtimeMinutes = bedtimeMinutes
        self.redLevel = redLevel
        self.morningBoost = morningBoost
        self.latitude = latitude
        self.longitude = longitude
    }

    public var hasLocation: Bool { latitude != nil && longitude != nil }
}

public struct ScheduleResult: Equatable, Sendable {
    public var phase: Phase
    public var gains: ColorGains
    /// Start of the next phase (nil for manual modes).
    public var nextChange: Date?

    public init(phase: Phase, gains: ColorGains, nextChange: Date?) {
        self.phase = phase
        self.gains = gains
        self.nextChange = nextChange
    }
}

/// Sunrise/sunset actually used by the schedule for one day.
public struct DaySun: Equatable, Sendable {
    public var sunrise: Date
    public var sunset: Date
    /// True when the fixed 07:00 / 19:00 fallback was used.
    public var isFallback: Bool
}

public enum Schedule {
    public static let fallbackSunriseMinutes = 7 * 60
    public static let fallbackSunsetMinutes = 19 * 60

    static let morningRamp: TimeInterval = 20 * 60
    static let morningLength: TimeInterval = 2 * 3600
    static let amberLead: TimeInterval = 30 * 60   // amber starts this long before sunset
    static let amberRamp: TimeInterval = 30 * 60
    static let redRamp: TimeInterval = 30 * 60
    static let windDownLead: TimeInterval = 2 * 3600 // wind-down = bedtime - 2 h

    /// Sun times for the calendar day containing `date`, with fallback when there is
    /// no location or the sun does not rise/set (polar day/night).
    public static func sun(for date: Date, settings: Settings, calendar: Calendar) -> DaySun {
        let day = calendar.startOfDay(for: date)
        let fbRise = at(fallbackSunriseMinutes, on: day, calendar)
        let fbSet = at(fallbackSunsetMinutes, on: day, calendar)
        guard let lat = settings.latitude, let lon = settings.longitude else {
            return DaySun(sunrise: fbRise, sunset: fbSet, isFallback: true)
        }
        let t = SunCalculator.sunTimes(for: date, latitude: lat, longitude: lon, timeZone: calendar.timeZone)
        guard let rise = t.sunrise, let set = t.sunset else {
            return DaySun(sunrise: fbRise, sunset: fbSet, isFallback: true)
        }
        return DaySun(sunrise: rise, sunset: set, isFallback: false)
    }

    /// Automatic schedule at `now`.
    public static func evaluate(now: Date, settings: Settings, calendar: Calendar) -> ScheduleResult {
        let today = calendar.startOfDay(for: now)
        var wake = at(settings.wakeMinutes, on: today, calendar)
        if now < wake {
            // Still in last night's cycle.
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
            wake = at(settings.wakeMinutes, on: yesterday, calendar)
        }
        let cycleDay = calendar.startOfDay(for: wake)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: cycleDay)!
        let nextWake = at(settings.wakeMinutes, on: nextDay, calendar)

        // Wind-down: first (bedtime - 2 h) after this wake. Handles bedtimes after midnight.
        var windDown = at(settings.bedtimeMinutes, on: cycleDay, calendar).addingTimeInterval(-windDownLead)
        while windDown <= wake { windDown = calendar.date(byAdding: .day, value: 1, to: windDown)! }
        let morningEnd = min(wake.addingTimeInterval(morningLength), windDown)

        let sunset = sun(for: cycleDay, settings: settings, calendar: calendar).sunset
        let eveningStart = max(sunset.addingTimeInterval(-amberLead), morningEnd)

        let night = ColorGains.red(level: settings.redLevel)
        let morning = settings.morningBoost ? ColorGains.morningBoost : ColorGains.neutral

        // Gains of the pre-night segment at time t (day -> amber ramp -> amber).
        func eveningGains(_ t: Date) -> ColorGains {
            guard t >= eveningStart else { return .neutral }
            return ColorGains.lerp(.neutral, .amber, t.timeIntervalSince(eveningStart) / amberRamp)
        }

        let phase: Phase
        let gains: ColorGains
        if now < morningEnd {
            phase = .morning
            gains = ColorGains.lerp(night, morning, now.timeIntervalSince(wake) / morningRamp)
        } else if now < eveningStart && eveningStart < windDown {
            phase = .day
            gains = .neutral
        } else if now < windDown {
            phase = eveningStart < windDown ? .evening : .day
            gains = eveningGains(now)
        } else {
            phase = .night
            let from = eveningGains(windDown)
            gains = ColorGains.lerp(from, night, now.timeIntervalSince(windDown) / redRamp)
        }

        let boundaries = [wake, morningEnd, eveningStart < windDown ? eveningStart : nil, windDown, nextWake]
            .compactMap { $0 }
            .sorted()
        let next = boundaries.first { $0 > now }
        return ScheduleResult(phase: phase, gains: gains, nextChange: next)
    }

    /// Schedule including manual modes.
    public static func evaluate(mode: Mode, now: Date, settings: Settings, calendar: Calendar) -> ScheduleResult {
        switch mode {
        case .auto: return evaluate(now: now, settings: settings, calendar: calendar)
        case .manual:
            let level = min(max(settings.manualLevel, 0), 1)
            let phase: Phase = level >= 0.75 ? .night : (level >= 0.1 ? .evening : .day)
            return ScheduleResult(phase: phase,
                                  gains: .filter(level: level, brightness: settings.redLevel), nextChange: nil)
        case .off: return ScheduleResult(phase: .off, gains: .neutral, nextChange: nil)
        }
    }

    static func at(_ minutes: Int, on day: Date, _ calendar: Calendar) -> Date {
        let m = ((minutes % 1440) + 1440) % 1440
        return calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: day)
            ?? day.addingTimeInterval(TimeInterval(m * 60))
    }
}
