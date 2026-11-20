import Foundation

/// NOAA solar calculation (the algorithm behind the NOAA Solar Calculator),
/// using the standard sunrise/sunset zenith of 90.833 degrees.
public enum SunCalculator {
    public static let zenith = 90.833

    public enum Event { case sunrise, sunset }

    /// Sunrise and sunset for the local calendar day containing `date` in `timeZone`.
    /// Each value is nil when the sun does not rise or set that day (polar day/night).
    public static func sunTimes(
        for date: Date, latitude: Double, longitude: Double, timeZone: TimeZone
    ) -> (sunrise: Date?, sunset: Date?) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { return (nil, nil) }
        return (
            eventTime(.sunrise, year: y, month: m, day: d, latitude: latitude, longitude: longitude),
            eventTime(.sunset, year: y, month: m, day: d, latitude: latitude, longitude: longitude)
        )
    }

    /// Time of the event for the given calendar date (longitude east positive).
    public static func eventTime(
        _ event: Event, year: Int, month: Int, day: Int, latitude: Double, longitude: Double
    ) -> Date? {
        let jd0 = julianDay(year: year, month: month, day: day) // 0h UTC
        // First pass at approximate local solar noon, then refine at the event time.
        guard var minutes = utcMinutes(event, jd: jd0 + 0.5 - longitude / 360.0,
                                       latitude: latitude, longitude: longitude) else { return nil }
        guard let refined = utcMinutes(event, jd: jd0 + minutes / 1440.0,
                                       latitude: latitude, longitude: longitude) else { return nil }
        minutes = refined
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let midnight = utc.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        return midnight.addingTimeInterval(minutes * 60)
    }

    // MARK: - Internals

    static func julianDay(year: Int, month: Int, day: Int) -> Double {
        var y = year, m = month
        if m <= 2 { y -= 1; m += 12 }
        let a = Double(y / 100)
        let b = 2 - a + floor(a / 4)
        return floor(365.25 * Double(y + 4716)) + floor(30.6001 * Double(m + 1)) + Double(day) + b - 1524.5
    }

    /// Minutes after 0h UTC of the calendar day, computed with solar parameters at `jd`.
    private static func utcMinutes(_ event: Event, jd: Double, latitude: Double, longitude: Double) -> Double? {
        let t = (jd - 2451545.0) / 36525.0
        let (decl, eqTime) = declinationAndEquationOfTime(t)
        let latR = rad(latitude), declR = rad(decl)
        let cosHA = cos(rad(zenith)) / (cos(latR) * cos(declR)) - tan(latR) * tan(declR)
        guard cosHA >= -1, cosHA <= 1 else { return nil } // polar day or night
        let ha = deg(acos(cosHA))
        let noon = 720 - 4 * longitude - eqTime
        // jd carries the day; only the time-of-day offset is returned.
        switch event {
        case .sunrise: return noon - 4 * ha
        case .sunset: return noon + 4 * ha
        }
    }

    private static func declinationAndEquationOfTime(_ t: Double) -> (Double, Double) {
        let l0 = (280.46646 + t * (36000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let m = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let mR = rad(m)
        let c = sin(mR) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * mR) * (0.019993 - 0.000101 * t)
            + sin(3 * mR) * 0.000289
        let trueLong = l0 + c
        let omega = 125.04 - 1934.136 * t
        let lambda = trueLong - 0.00569 - 0.00478 * sin(rad(omega))
        let eps0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let eps = eps0 + 0.00256 * cos(rad(omega))
        let decl = deg(asin(sin(rad(eps)) * sin(rad(lambda))))
        var y = tan(rad(eps) / 2)
        y *= y
        let l0R = rad(l0)
        let eq = y * sin(2 * l0R) - 2 * e * sin(mR) + 4 * e * y * sin(mR) * cos(2 * l0R)
            - 0.5 * y * y * sin(4 * l0R) - 1.25 * e * e * sin(2 * mR)
        return (decl, 4 * deg(eq))
    }

    private static func rad(_ d: Double) -> Double { d * .pi / 180 }
    private static func deg(_ r: Double) -> Double { r * 180 / .pi }
}
