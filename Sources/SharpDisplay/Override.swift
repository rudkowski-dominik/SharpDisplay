import Foundation

/// Builds and installs the display override file that gives macOS extra HiDPI modes for one monitor model.
enum Override {
    static let root = "/Library/Displays/Contents/Resources/Overrides"
    static let backupDir = "/Library/Application Support/SharpDisplay/Backups"
    static let windowServerPrefs = "/Library/Preferences/com.apple.windowserver"
    static let marker = "SharpDisplayVersion"

    static func path(for display: ExternalDisplay) -> String {
        "\(root)/DisplayVendorID-\(hex(display.vendorID))/DisplayProductID-\(hex(display.productID))"
    }

    /// "Looks like" sizes in the panel's aspect ratio, from 97.5% down to 62.5% of the native width.
    /// macOS ignores a HiDPI mode equal to the native size, so 100% is never offered.
    static func sizes(for display: ExternalDisplay) -> [(width: Int, height: Int)] {
        let w = display.nativeWidth, h = display.nativeHeight
        let divisor = gcd(w, h)
        let stepW = w / divisor, stepH = h / divisor
        var result: [(Int, Int)] = []
        for fraction in [0.975, 0.9, 0.8, 0.75, 0.625] {
            let steps = Int((Double(w) * fraction / Double(stepW)).rounded())
            let size = (steps * stepW, steps * stepH)
            if size.0 < w, size.0 * 2 > w, !result.contains(where: { $0 == size }) {
                result.append(size)
            }
        }
        return result
    }

    static func plist(for display: ExternalDisplay) throws -> Data {
        var resolutions: [Data] = []
        for (w, h) in sizes(for: display) {
            resolutions.append(bigEndian([w * 2, h * 2, 0x9, 0x0020_0000]))  // HiDPI entry
            resolutions.append(bigEndian([w * 2, h * 2]))
            resolutions.append(bigEndian([w, h]))
        }
        let dict: [String: Any] = [
            "DisplayVendorID": Int(display.vendorID),
            "DisplayProductID": Int(display.productID),
            "scale-resolutions": resolutions,
            marker: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
        ]
        return try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    static func isInstalled(for display: ExternalDisplay) -> Bool {
        guard let data = FileManager.default.contents(atPath: path(for: display)),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return false }
        return dict[marker] != nil
    }

    /// Writes the override (backing up any existing one) and enables HiDPI in WindowServer. Asks for the admin password.
    static func install(for display: ExternalDisplay) throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("SharpDisplay-\(display.productID).plist")
        try plist(for: display).write(to: temp)
        let file = path(for: display)
        let backup = "\(backupDir)/\(backupName(for: display))"
        try Privileged.run("""
            set -e
            mkdir -p \(quote((file as NSString).deletingLastPathComponent)) \(quote(backupDir))
            if [ -f \(quote(file)) ] && ! grep -q \(marker) \(quote(file)) && [ ! -f \(quote(backup)) ]; then cp \(quote(file)) \(quote(backup)); fi
            cp \(quote(temp.path)) \(quote(file))
            chown root:wheel \(quote(file))
            chmod 644 \(quote(file))
            defaults write \(windowServerPrefs) DisplayResolutionEnabled -bool YES
            """)
        try? FileManager.default.removeItem(at: temp)
    }

    /// Removes SharpDisplay's override and restores the previous one, if there was any. Asks for the admin password.
    static func uninstall(for display: ExternalDisplay) throws {
        let file = path(for: display)
        let backup = "\(backupDir)/\(backupName(for: display))"
        try Privileged.run("""
            rm -f \(quote(file))
            if [ -f \(quote(backup)) ]; then mv \(quote(backup)) \(quote(file)); fi
            rmdir \(quote((file as NSString).deletingLastPathComponent)) 2>/dev/null || true
            true
            """)
    }

    private static func backupName(for display: ExternalDisplay) -> String {
        "DisplayVendorID-\(hex(display.vendorID))-DisplayProductID-\(hex(display.productID))"
    }

    private static func hex(_ value: UInt32) -> String { String(value, radix: 16) }

    private static func quote(_ path: String) -> String { "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    private static func bigEndian(_ values: [Int]) -> Data {
        var data = Data()
        for value in values {
            withUnsafeBytes(of: UInt32(value).bigEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
}

enum Privileged {
    struct Failure: LocalizedError {
        let message: String
        let cancelled: Bool
        var errorDescription: String? { message }
    }

    /// Runs a shell script as root behind the standard macOS administrator prompt.
    static func run(_ script: String) throws {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges "
            + "with prompt \"SharpDisplay needs your password to add sharper display modes.\""
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int
            throw Failure(
                message: error[NSAppleScript.errorMessage] as? String ?? "Unknown error",
                cancelled: code == -128
            )
        }
    }
}
