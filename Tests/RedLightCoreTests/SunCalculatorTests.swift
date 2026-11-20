import XCTest
@testable import RedLightCore

final class SunCalculatorTests: XCTestCase {
    /// Local wall-clock date in a time zone.
    func local(_ tz: String, _ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz)!
        return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func assertWithin2Min(_ actual: Date?, _ expected: Date, file: StaticString = #filePath, line: UInt = #line) {
        guard let actual else { return XCTFail("nil sun time", file: file, line: line) }
        let diff = abs(actual.timeIntervalSince(expected))
        XCTAssertLessThanOrEqual(diff, 120, "off by \(Int(diff)) s: \(actual) vs \(expected)", file: file, line: line)
    }

    // London, summer solstice 2024: sunrise 04:43 BST, sunset 21:21 BST.
    func testLondonSummerSolstice() {
        let tz = TimeZone(identifier: "Europe/London")!
        let t = SunCalculator.sunTimes(for: local("Europe/London", 2024, 6, 21, 12, 0),
                                       latitude: 51.5074, longitude: -0.1278, timeZone: tz)
        assertWithin2Min(t.sunrise, local("Europe/London", 2024, 6, 21, 4, 43))
        assertWithin2Min(t.sunset, local("Europe/London", 2024, 6, 21, 21, 21))
    }

    // London, winter solstice 2024: sunrise 08:04 GMT, sunset 15:53 GMT.
    func testLondonWinterSolstice() {
        let tz = TimeZone(identifier: "Europe/London")!
        let t = SunCalculator.sunTimes(for: local("Europe/London", 2024, 12, 21, 12, 0),
                                       latitude: 51.5074, longitude: -0.1278, timeZone: tz)
        assertWithin2Min(t.sunrise, local("Europe/London", 2024, 12, 21, 8, 4))
        assertWithin2Min(t.sunset, local("Europe/London", 2024, 12, 21, 15, 53))
    }

    // Classic worked example (Almanac for Computers): Wayne, NJ, 25 June 1990,
    // sunrise 05:26 EDT, sunset 20:33 EDT.
    func testWayneNJ1990() {
        let tz = TimeZone(identifier: "America/New_York")!
        let t = SunCalculator.sunTimes(for: local("America/New_York", 1990, 6, 25, 12, 0),
                                       latitude: 40.9, longitude: -74.3, timeZone: tz)
        assertWithin2Min(t.sunrise, local("America/New_York", 1990, 6, 25, 5, 26))
        assertWithin2Min(t.sunset, local("America/New_York", 1990, 6, 25, 20, 33))
    }

    // Far-east longitude: the event must land on the right local day.
    func testTokyoEventsAreOnLocalDay() {
        let tz = TimeZone(identifier: "Asia/Tokyo")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let day = local("Asia/Tokyo", 2024, 3, 20, 12, 0)
        let t = SunCalculator.sunTimes(for: day, latitude: 35.68, longitude: 139.69, timeZone: tz)
        XCTAssertTrue(cal.isDate(t.sunrise!, inSameDayAs: day))
        XCTAssertTrue(cal.isDate(t.sunset!, inSameDayAs: day))
        XCTAssertLessThan(t.sunrise!, t.sunset!)
    }

    func testPolarNightAndDayReturnNil() {
        let tz = TimeZone(identifier: "Europe/Oslo")!
        let winter = SunCalculator.sunTimes(for: local("Europe/Oslo", 2024, 12, 21, 12, 0),
                                            latitude: 69.65, longitude: 18.96, timeZone: tz)
        XCTAssertNil(winter.sunrise); XCTAssertNil(winter.sunset)
        let summer = SunCalculator.sunTimes(for: local("Europe/Oslo", 2024, 6, 21, 12, 0),
                                            latitude: 69.65, longitude: 18.96, timeZone: tz)
        XCTAssertNil(summer.sunrise); XCTAssertNil(summer.sunset)
    }
}
