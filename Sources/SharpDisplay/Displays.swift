import AppKit
import CoreGraphics

/// An external, non-Retina monitor that SharpDisplay can add HiDPI modes to.
struct ExternalDisplay: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let vendorID: UInt32
    let productID: UInt32
    let nativeWidth: Int
    let nativeHeight: Int

    /// 4K and larger panels already get HiDPI modes from macOS.
    var isEligible: Bool { nativeWidth < 3840 }
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
                    nativeHeight: native.height
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

    /// HiDPI modes (rendered at 2x) larger than half the native width, best refresh rate per size, largest first.
    static func hiDPIModes(of display: ExternalDisplay) -> [CGDisplayMode] {
        let candidates = modes(of: display.id).filter {
            $0.pixelWidth == $0.width * 2 && $0.width * 2 > display.nativeWidth
        }
        var best: [Int: CGDisplayMode] = [:]
        for mode in candidates {
            if let current = best[mode.width], current.refreshRate >= mode.refreshRate { continue }
            best[mode.width] = mode
        }
        return best.values.sorted { $0.width > $1.width }
    }

    /// The native 1x mode at the highest refresh rate.
    static func nativeMode(of display: ExternalDisplay) -> CGDisplayMode? {
        modes(of: display.id)
            .filter { $0.width == display.nativeWidth && $0.pixelWidth == display.nativeWidth }
            .max { $0.refreshRate < $1.refreshRate }
    }

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
        return screen?.localizedName ?? "External Display"
    }
}
