import XCTest
@testable import RedLightCore

final class ScheduleTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }()

    /// Default settings, no location -> sunset fallback 19:00, amber from 18:30,
    /// wake 06:30, bedtime 22:30, wind-down 20:30.
    let defaults = Settings()

    func t(_ h: Int, _ m: Int, day: Int = 15, month: Int = 1, year: Int = 2025) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day, hour: h, minute: m))!
    }

    func eval(_ date: Date, _ s: Settings? = nil) -> ScheduleResult {
        Schedule.evaluate(now: date, settings: s ?? defaults, calendar: cal)
    }

    func assertGains(_ g: ColorGains, _ r: Double, _ gg: Double, _ b: Double,
                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(g.r, r, accuracy: 0.001, "r", file: file, line: line)
        XCTAssertEqual(g.g, gg, accuracy: 0.001, "g", file: file, line: line)
        XCTAssertEqual(g.b, b, accuracy: 0.001, "b", file: file, line: line)
    }

    func test2300IsRed() {
        let r = eval(t(23, 0))
        XCTAssertEqual(r.phase, .night)
        assertGains(r.gains, 1, 0, 0)
        XCTAssertEqual(r.nextChange, t(6, 30, day: 16))
    }

    func test0200IsRedAfterMidnight() {
        let r = eval(t(2, 0))
        XCTAssertEqual(r.phase, .night)
        assertGains(r.gains, 1, 0, 0)
        XCTAssertEqual(r.nextChange, t(6, 30))
    }

    func testOneMinuteBeforeWakeIsRed() {
        let r = eval(t(6, 29))
        XCTAssertEqual(r.phase, .night)
        assertGains(r.gains, 1, 0, 0)
        XCTAssertEqual(r.nextChange, t(6, 30))
    }

    func testWakePlus10IsMidMorningRamp() {
        let r = eval(t(6, 40))
        XCTAssertEqual(r.phase, .morning)
        // halfway from (1,0,0) to (0.88,0.96,1.0)
        assertGains(r.gains, 0.94, 0.48, 0.5)
        XCTAssertEqual(r.nextChange, t(8, 30))
    }

    func testMorningBoostAfterRamp() {
        assertGains(eval(t(7, 30)).gains, 0.88, 0.96, 1.0)
        var s = defaults; s.morningBoost = false
        assertGains(eval(t(7, 30), s).gains, 1, 1, 1)
    }

    func testMiddayIsNeutral() {
        let r = eval(t(12, 0))
        XCTAssertEqual(r.phase, .day)
        assertGains(r.gains, 1, 1, 1)
        XCTAssertEqual(r.nextChange, t(18, 30))
    }

    func testSunsetMinus15IsMidAmberRamp() {
        let r = eval(t(18, 45))
        XCTAssertEqual(r.phase, .evening)
        assertGains(r.gains, 1.0, 0.775, 0.575)
        XCTAssertEqual(r.nextChange, t(20, 30))
    }

    func testFullAmberBeforeWindDown() {
        let r = eval(t(20, 0))
        XCTAssertEqual(r.phase, .evening)
        assertGains(r.gains, 1.0, 0.55, 0.15)
    }

    func testWindDownPlus15IsMidRedRamp() {
        let r = eval(t(20, 45))
        XCTAssertEqual(r.phase, .night)
        assertGains(r.gains, 1.0, 0.275, 0.075)
        XCTAssertEqual(r.nextChange, t(6, 30, day: 16))
    }

    func testRedLevelDimsNight() {
        var s = defaults; s.redLevel = 0.5
        assertGains(eval(t(23, 0), s).gains, 0.5, 0, 0)
    }

    /// London on 21 June: sunset ~21:21, so amber would start at ~20:51, after
    /// wind-down (20:30). Red must still start at wind-down, ramping from neutral.
    func testSummerSunsetAfterWindDown() {
        var s = defaults; s.latitude = 51.5074; s.longitude = -0.1278
        let midday = eval(t(12, 0, day: 21, month: 6, year: 2024), s)
        XCTAssertEqual(midday.phase, .day)
        XCTAssertEqual(midday.nextChange, t(20, 30, day: 21, month: 6, year: 2024))

        let before = eval(t(20, 15, day: 21, month: 6, year: 2024), s)
        XCTAssertEqual(before.phase, .day)
        assertGains(before.gains, 1, 1, 1)

        let mid = eval(t(20, 45, day: 21, month: 6, year: 2024), s)
        XCTAssertEqual(mid.phase, .night)
        assertGains(mid.gains, 1, 0.5, 0.5)

        let late = eval(t(21, 30, day: 21, month: 6, year: 2024), s)
        XCTAssertEqual(late.phase, .night)
        assertGains(late.gains, 1, 0, 0)
    }

    func testBedtimeAfterMidnight() {
        var s = defaults; s.bedtimeMinutes = 30 // 00:30 -> wind-down 22:30
        XCTAssertEqual(eval(t(22, 0), s).phase, .evening)
        let r = eval(t(23, 30), s)
        XCTAssertEqual(r.phase, .night)
        assertGains(r.gains, 1, 0, 0)
    }

    func testFallbackWithoutLocationAndPolar() {
        let noLoc = Schedule.sun(for: t(12, 0), settings: defaults, calendar: cal)
        XCTAssertTrue(noLoc.isFallback)
        XCTAssertEqual(noLoc.sunset, t(19, 0))

        var polar = defaults; polar.latitude = 69.65; polar.longitude = 18.96
        let p = Schedule.sun(for: t(12, 0, day: 21, month: 12, year: 2024), settings: polar, calendar: cal)
        XCTAssertTrue(p.isFallback)
        XCTAssertEqual(p.sunrise, t(7, 0, day: 21, month: 12, year: 2024))
        XCTAssertEqual(p.sunset, t(19, 0, day: 21, month: 12, year: 2024))
    }

    func testManualModes() {
        XCTAssertEqual(Schedule.evaluate(mode: .off, now: t(23, 0), settings: defaults, calendar: cal).gains, .neutral)
        var s = defaults
        s.manualLevel = 0.5
        assertGains(Schedule.evaluate(mode: .manual, now: t(12, 0), settings: s, calendar: cal).gains, 1, 0.55, 0.15)
        s.manualLevel = 1
        assertGains(Schedule.evaluate(mode: .manual, now: t(12, 0), settings: s, calendar: cal).gains, 1, 0, 0)
        s.manualLevel = 0
        assertGains(Schedule.evaluate(mode: .manual, now: t(12, 0), settings: s, calendar: cal).gains, 1, 1, 1)
    }

    func testFilterLevelIsContinuousAndInvertible() {
        assertGains(ColorGains.filter(level: 0.25), 1, 0.775, 0.575)
        assertGains(ColorGains.filter(level: 0.75), 1, 0.275, 0.075)
        assertGains(ColorGains.filter(level: 1, brightness: 0.5), 0.5, 0, 0)
        assertGains(ColorGains.filter(level: 0.75, brightness: 0.5), 0.75, 0.20625, 0.05625)
        var previous = ColorGains.filter(level: 0)
        for i in 1...100 {
            let level = Double(i) / 100
            let g = ColorGains.filter(level: level, brightness: 0.6)
            XCTAssertLessThanOrEqual(abs(g.g - previous.g), 0.02, "green jumps at \(level)")
            XCTAssertLessThanOrEqual(abs(g.r - previous.r), 0.02, "red jumps at \(level)")
            XCTAssertEqual(g.filterLevel, level, accuracy: 0.0001)
            previous = g
        }
    }

    func testLerpClamps() {
        assertGains(ColorGains.lerp(.neutral, .amber, -1), 1, 1, 1)
        assertGains(ColorGains.lerp(.neutral, .amber, 2), 1, 0.55, 0.15)
        assertGains(ColorGains.red(level: 0.1), 0.3, 0, 0)
    }
}
