import AppKit
import CoreGraphics

/// An external, non-Retina monitor that SharpDisplay can add HiDPI modes to.
struct ExternalDisplay: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let vendorID: UInt32
    let productID: UInt32
    /// Native size as the screen is turned now, which is how display modes report it.
    let nativeWidth: Int
    let nativeHeight: Int
    /// Turned 90° or 270° in Displays settings, for example a monitor standing upright.
    let isRotated: Bool

    /// Native size of the panel as it was built, before rotation. Display overrides use this orientation.
    var panelWidth: Int { isRotated ? nativeHeight : nativeWidth }
    var panelHeight: Int { isRotated ? nativeWidth : nativeHeight }

    /// Panels 2160 pixels tall and up (4K, 5K) already get HiDPI modes from macOS.
    /// Judging by height keeps wide low-density panels such as 3440 × 1440 and 5120 × 1440.
    var isEligible: Bool { panelHeight < 2160 }

    /// A size in panel orientation, turned the way the screen is turned now.
    func oriented(_ size: (width: Int, height: Int)) -> (width: Int, height: Int) {
        isRotated ? (size.height, size.width) : size
    }
}

enum Displays {
    static func external() -> [ExternalDisplay] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)

        return ids.prefix(Int(count))
            .filter { CGDisplayIsBuiltin($0) == 0 }
            .compactMap { id in
                guard let native = nativeSize(of: id) else { return nil }
                return ExternalDisplay(
                    id: id,
                    name: name(of: id),
                    vendorID: CGDisplayVendorNumber(id),
                    productID: CGDisplayModelNumber(id),
                    nativeWidth: native.width,
                    nativeHeight: native.height,
                    isRotated: Int(CGDisplayRotation(id)) % 180 == 90
                )
            }
    }

    static func modes(of id: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        return CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? []
    }

    static func currentMode(of id: CGDirectDisplayID) -> CGDisplayMode? {
        CGDisplayCopyDisplayMode(id)
    }

    /// HiDPI modes (rendered at 2x) larger than half the native size and in the screen's aspect ratio,
    /// best refresh rate per size, largest first. macOS adds a few small HiDPI modes of its own, some in other
    /// aspect ratios (600 × 800 on a 1080 × 1920 screen); those are left out.
    static func hiDPIModes(of display: ExternalDisplay) -> [CGDisplayMode] {
        let aspect = Double(display.nativeWidth) / Double(display.nativeHeight)
        let candidates = modes(of: display.id).filter {
            $0.pixelWidth == $0.width * 2 && $0.width * 2 > display.nativeWidth && $0.height * 2 > display.nativeHeight
                && abs(Double($0.width) / Double($0.height) - aspect) < 0.01
        }
        var best: [Int: CGDisplayMode] = [:]
        for mode in candidates {
            if let current = best[mode.width], !isBetter(mode, than: current, on: display.id) { continue }
            best[mode.width] = mode
        }
        return best.values.sorted { $0.width > $1.width }
    }

    /// The native 1x mode at the highest refresh rate.
    static func nativeMode(of display: ExternalDisplay) -> CGDisplayMode? {
        modes(of: display.id)
            .filter { $0.width == display.nativeWidth && $0.pixelWidth == display.nativeWidth }
            .reduce(nil) { best, mode in
                guard let best else { return mode }
                return isBetter(mode, than: best, on: display.id) ? mode : best
            }
    }

    /// Higher refresh rate wins; at the same rate the variable refresh (Adaptive Sync) variant wins,
    /// so switching modes keeps VRR on instead of falling back to a fixed rate.
    private static func isBetter(_ mode: CGDisplayMode, than other: CGDisplayMode, on id: CGDirectDisplayID) -> Bool {
        if mode.refreshRate != other.refreshRate { return mode.refreshRate > other.refreshRate }
        return isVariableRefresh(mode, on: id) && !isVariableRefresh(other, on: id)
    }

    /// macOS lists every refresh rate twice, as a fixed and a variable variant that look identical
    /// through the public API. A private SkyLight call tells them apart; without it, every mode counts as fixed.
    static func isVariableRefresh(_ mode: CGDisplayMode, on id: CGDirectDisplayID) -> Bool {
        guard let isModeVRR else { return false }
        return isModeVRR(id, mode.ioDisplayModeID)
    }

    private static let isModeVRR: (@convention(c) (CGDirectDisplayID, Int32) -> Bool)? = {
        guard let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let symbol = dlsym(skyLight, "SLSIsDisplayModeVRR")
        else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (CGDirectDisplayID, Int32) -> Bool).self)
    }()

    @discardableResult
    static func apply(_ mode: CGDisplayMode, to id: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        CGConfigureDisplayWithDisplayMode(config, id, mode, nil)
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    /// Makes macOS re-read the display overrides by switching the display off and on (the screen goes dark for a moment).
    /// Uses a private CoreGraphics call; returns false when it is unavailable, so the caller can ask for a cable replug instead.
    static func reconnect(_ id: CGDirectDisplayID) -> Bool {
        typealias SetEnabled = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSConfigureDisplayEnabled") else { return false }
        let setEnabled = unsafeBitCast(symbol, to: SetEnabled.self)

        func toggle(_ enabled: Bool) -> Bool {
            var config: CGDisplayConfigRef?
            guard CGBeginDisplayConfiguration(&config) == .success else { return false }
            guard setEnabled(config, id, enabled) == .success else {
                CGCancelDisplayConfiguration(config)
                return false
            }
            return CGCompleteDisplayConfiguration(config, .forSession) == .success
        }

        guard toggle(false) else { return false }
        Thread.sleep(forTimeInterval: 1.5)
        // Re-enabling must happen even if something above went wrong, or the screen stays dark.
        for _ in 0..<5 where !toggle(true) {
            Thread.sleep(forTimeInterval: 1)
        }
        Thread.sleep(forTimeInterval: 2)
        return true
    }

    private static func nativeSize(of id: CGDirectDisplayID) -> (width: Int, height: Int)? {
        let kDisplayModeNativeFlag: UInt32 = 0x0200_0000
        let all = modes(of: id)
        if let native = all.first(where: { $0.ioFlags & kDisplayModeNativeFlag != 0 }) {
            return (native.pixelWidth, native.pixelHeight)
        }
        return all
            .filter { $0.pixelWidth == $0.width }
            .max { $0.width * $0.height < $1.width * $1.height }
            .map { ($0.width, $0.height) }
    }

    private static func name(of id: CGDirectDisplayID) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let screen = NSScreen.screens.first { ($0.deviceDescription[key] as? NSNumber)?.uint32Value == id }
        // Virtual displays, such as the one macOS creates for remote sessions, have an empty name.
        guard let name = screen?.localizedName, !name.isEmpty else { return "External Display" }
        return name
    }
}
