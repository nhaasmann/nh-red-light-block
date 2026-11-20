import CoreGraphics
import Foundation
import RedLightCore

/// Writes per-channel gamma formulas to every active display and reads them back.
/// The window server restores the tables itself when this process exits.
final class GammaController {
    struct Readback {
        let display: CGDirectDisplayID
        let last: ColorGains
    }

    private(set) var lastApplied: ColorGains?

    static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    /// Applies `gains`. Skips the call when unchanged unless `force` is set.
    /// Returns nil when skipped, otherwise whether the readback matched on all displays.
    @discardableResult
    func apply(_ gains: ColorGains, force: Bool) -> Bool? {
        if !force, let last = lastApplied, last == gains { return nil }
        lastApplied = gains
        if gains.isNeutral {
            CGDisplayRestoreColorSyncSettings()
            return true
        }
        for id in Self.activeDisplays() {
            CGSetDisplayTransferByFormula(
                id,
                0, CGGammaValue(gains.r), 1,
                0, CGGammaValue(gains.g), 1,
                0, CGGammaValue(gains.b), 1
            )
        }
        return Self.verify(gains)
    }

    func restore() {
        lastApplied = .neutral
        CGDisplayRestoreColorSyncSettings()
    }

    /// Invalidate the cache so the next apply always writes.
    func invalidate() { lastApplied = nil }

    static func readBack() -> [Readback] {
        activeDisplays().compactMap { id in
            let n = 256
            var r = [CGGammaValue](repeating: 0, count: n)
            var g = [CGGammaValue](repeating: 0, count: n)
            var b = [CGGammaValue](repeating: 0, count: n)
            var count: UInt32 = 0
            guard CGGetDisplayTransferByTable(id, UInt32(n), &r, &g, &b, &count) == .success, count > 0 else {
                return nil
            }
            let i = Int(count) - 1
            return Readback(display: id, last: ColorGains(r: Double(r[i]), g: Double(g[i]), b: Double(b[i])))
        }
    }

    /// True when every display's last table sample is close to the requested gains.
    static func verify(_ gains: ColorGains) -> Bool {
        let rb = readBack()
        return !rb.isEmpty && rb.allSatisfy { $0.last.isClose(to: gains, tolerance: 0.02) }
    }
}
