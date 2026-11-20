import AppKit
import Charts
import RedLightCore
import SwiftUI

/// Estimates the light spectrum the display is emitting right now.
///
/// What is read live from this Mac: the per-channel output (gamma table readback), the
/// luminance of each primary from the display's colour profile, and the brightness setting.
/// What is modelled: the spectral shape of each primary, using the emission peaks of the
/// MacBook Pro Liquid Retina XDR panel (blue LED ~449 nm, green phosphor ~532 nm, KSF red
/// phosphor lines ~613-648 nm). A Mac has no spectrometer, so this is not a measurement.
enum SpectrumModel {
    static let wavelengths: [Double] = Array(stride(from: 380.0, through: 750.0, by: 2.0))

    private static func gauss(_ x: Double, _ mu: Double, _ sigma: Double) -> Double {
        exp(-0.5 * pow((x - mu) / sigma, 2))
    }

    static func blue(_ l: Double) -> Double { gauss(l, 449, 8.5) }
    static func green(_ l: Double) -> Double { gauss(l, 532, 21) }
    static func red(_ l: Double) -> Double {
        0.35 * gauss(l, 613, 2.8) + 1.0 * gauss(l, 631, 2.8) + 0.55 * gauss(l, 635, 2.8) + 0.30 * gauss(l, 648, 2.8)
    }

    /// Photopic luminosity V(lambda), Wyman et al. 2013 analytic fit to the CIE 1931 y-bar.
    static func photopic(_ l: Double) -> Double {
        let a = (l - 568.8) * (l < 568.8 ? 0.0213 : 0.0247)
        let b = (l - 530.9) * (l < 530.9 ? 0.0613 : 0.0322)
        return 0.821 * exp(-0.5 * a * a) + 0.286 * exp(-0.5 * b * b)
    }

    /// Melanopic sensitivity (body-clock photoreceptor), approximating CIE S 026: peak 490 nm.
    static func melanopic(_ l: Double) -> Double {
        gauss(l, 490, l < 490 ? 36.5 : 35)
    }

    /// Relative luminance (Y) of the red, green and blue primaries from the display's profile.
    static func primaryLuminance() -> (r: Double, g: Double, b: Double, fromProfile: Bool) {
        let fallback = (r: 0.229, g: 0.692, b: 0.079, fromProfile: false) // Display P3
        guard let cs = NSScreen.main?.colorSpace?.cgColorSpace, cs.numberOfComponents == 3,
              let xyz = CGColorSpace(name: CGColorSpace.genericXYZ) else { return fallback }
        func y(_ c: [CGFloat]) -> Double? {
            guard let color = CGColor(colorSpace: cs, components: c),
                  let conv = color.converted(to: xyz, intent: .absoluteColorimetric, options: nil),
                  let comps = conv.components, comps.count >= 3 else { return nil }
            return Double(comps[1])
        }
        guard let r = y([1, 0, 0, 1]), let g = y([0, 1, 0, 1]), let b = y([0, 0, 1, 1]), r + g + b > 0 else {
            return fallback
        }
        return (r, g, b, true)
    }

    struct Reading {
        var points: [(wavelength: Double, now: Double, unfiltered: Double)]
        var melanopicPercent: Double   // body-clock light vs. unfiltered screen
        var visiblePercent: Double     // visible brightness vs. unfiltered screen
        var channel: ColorGains        // linear light output per channel, 0...1
        var fromProfile: Bool
    }

    /// `gains` are the gamma-table maxima (encoded signal); light output is roughly gain^2.2.
    static func reading(gains: ColorGains) -> Reading {
        let lum = primaryLuminance()
        let lin = ColorGains(r: pow(gains.r, 2.2), g: pow(gains.g, 2.2), b: pow(gains.b, 2.2))
        func integral(_ f: (Double) -> Double) -> Double { wavelengths.reduce(0) { $0 + f($1) } }
        // Scale each primary so its luminance matches the display profile.
        let ar = lum.r / integral { red($0) * photopic($0) }
        let ag = lum.g / integral { green($0) * photopic($0) }
        let ab = lum.b / integral { blue($0) * photopic($0) }
        func full(_ l: Double) -> Double { ar * red(l) + ag * green(l) + ab * blue(l) }
        func now(_ l: Double) -> Double { lin.r * ar * red(l) + lin.g * ag * green(l) + lin.b * ab * blue(l) }
        let peak = wavelengths.map(full).max() ?? 1
        let melFull = integral { full($0) * melanopic($0) }
        let visFull = integral { full($0) * photopic($0) }
        return Reading(
            points: wavelengths.map { ($0, now($0) / peak * 100, full($0) / peak * 100) },
            melanopicPercent: integral { now($0) * melanopic($0) } / melFull * 100,
            visiblePercent: integral { now($0) * photopic($0) } / visFull * 100,
            channel: lin,
            fromProfile: lum.fromProfile
        )
    }

    /// Built-in display brightness setting (0...1), if the system exposes it.
    static func displayBrightness() -> Double? {
        typealias Fn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let sym = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        var value: Float = 0
        let fn = unsafeBitCast(sym, to: Fn.self)
        guard fn(CGMainDisplayID(), &value) == 0 else { return nil }
        return Double(value)
    }

    /// Approximate on-screen colour of a wavelength, for the rainbow fill.
    static func color(_ l: Double) -> Color {
        var r = 0.0, g = 0.0, b = 0.0
        switch l {
        case ..<440: r = (440 - l) / 60; b = 1
        case ..<490: g = (l - 440) / 50; b = 1
        case ..<510: g = 1; b = (510 - l) / 20
        case ..<580: r = (l - 510) / 70; g = 1
        case ..<645: r = 1; g = (645 - l) / 65
        default: r = 1
        }
        let fade = l < 420 ? 0.3 + 0.7 * (l - 380) / 40 : (l > 700 ? 0.3 + 0.7 * (750 - l) / 50 : 1)
        return Color(red: max(r, 0) * fade, green: max(g, 0) * fade, blue: max(b, 0) * fade)
    }

    static let rainbow = LinearGradient(
        stops: stride(from: 380.0, through: 750.0, by: 10).map {
            Gradient.Stop(color: color($0), location: ($0 - 380) / 370)
        },
        startPoint: .leading, endPoint: .trailing
    )
}

struct SpectrumView: View {
    @ObservedObject var state: AppState

    var body: some View {
        // Read what the display is actually using; fall back to what we asked for.
        let live = GammaController.readBack().first?.last ?? state.result.gains
        let reading = SpectrumModel.reading(gains: live)
        let brightness = SpectrumModel.displayBrightness()

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(percent(reading.melanopicPercent))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(reading.melanopicPercent < 5 ? brandRed : .primary)
                    Text("body-clock light vs. unfiltered screen")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    channelRow("Blue", reading.channel.b)
                    channelRow("Green", reading.channel.g)
                    channelRow("Red", reading.channel.r)
                }
            }

            Chart {
                ForEach(reading.points, id: \.wavelength) { p in
                    AreaMark(x: .value("Wavelength", p.wavelength), y: .value("Intensity", p.now),
                             series: .value("Series", "Now"))
                        .foregroundStyle(SpectrumModel.rainbow.opacity(0.85))
                        .interpolationMethod(.monotone)
                }
                ForEach(reading.points, id: \.wavelength) { p in
                    LineMark(x: .value("Wavelength", p.wavelength), y: .value("Intensity", p.unfiltered),
                             series: .value("Series", "Unfiltered"))
                        .foregroundStyle(Color.primary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .interpolationMethod(.monotone)
                }
                ForEach(SpectrumModel.wavelengths, id: \.self) { l in
                    LineMark(x: .value("Wavelength", l), y: .value("Intensity", SpectrumModel.melanopic(l) * 100),
                             series: .value("Series", "Sensitivity"))
                        .foregroundStyle(Color.primary.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.2))
                        .interpolationMethod(.monotone)
                }
            }
            .chartXScale(domain: 380...750)
            .chartYScale(domain: 0...105)
            .chartXAxis {
                AxisMarks(values: [400, 450, 500, 550, 600, 650, 700, 750]) { v in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel(anchor: .top) { if let n = v.as(Int.self) { Text("\(n)") } }
                }
            }
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { _ in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel()
                }
            }
            .chartXAxisLabel("Wavelength (nm)", alignment: .center)
            .frame(height: 170)
            .accessibilityLabel("Estimated spectrum of the display. Body-clock light is \(percent(reading.melanopicPercent)) of the unfiltered screen.")

            HStack(spacing: 14) {
                legend("Screen now") { RoundedRectangle(cornerRadius: 2).fill(SpectrumModel.rainbow) }
                legend("Unfiltered") { DashLine().stroke(Color.primary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
                legend("Body-clock sensitivity") { DashLine().stroke(Color.primary.opacity(0.7), lineWidth: 1.2) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(footnote(reading: reading, brightness: brightness))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func percent(_ v: Double) -> String {
        v < 0.05 ? "0%" : (v < 10 ? String(format: "%.1f%%", v) : String(format: "%.0f%%", v))
    }

    private func channelRow(_ name: String, _ value: Double) -> some View {
        HStack(spacing: 6) {
            Text(name).foregroundStyle(.secondary)
            Text(String(format: "%.0f%%", value * 100)).monospacedDigit().frame(width: 42, alignment: .trailing)
        }
        .font(.callout)
    }

    private func legend<S: View>(_ title: String, @ViewBuilder swatch: () -> S) -> some View {
        HStack(spacing: 5) {
            swatch().frame(width: 18, height: 6)
            Text(title)
        }
    }

    private func footnote(reading: SpectrumModel.Reading, brightness: Double?) -> String {
        var parts = ["Live from this Mac: channel output read back from the display"]
        if reading.fromProfile { parts.append("primary brightness from its colour profile") }
        if let b = brightness { parts.append(String(format: "brightness setting %.0f%%", b * 100)) }
        return parts.joined(separator: ", ")
            + String(format: ". Visible brightness is %.0f%% of unfiltered. ", reading.visiblePercent)
            + "The curve shapes are the known emission peaks of the MacBook Pro panel, not a sensor measurement: a Mac cannot measure its own light."
    }
}

private struct DashLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}
