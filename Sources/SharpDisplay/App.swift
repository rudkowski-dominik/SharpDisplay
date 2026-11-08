import AppKit
import SwiftUI

@main
struct SharpDisplayApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    init() {
        // `SharpDisplay --print-plist` prints the override it would install, without touching the system.
        if CommandLine.arguments.contains("--print-plist") {
            for display in Displays.external() where display.isEligible {
                print("# \(display.name) -> \(Override.path(for: display))")
                if let data = try? Override.plist(for: display) { print(String(decoding: data, as: UTF8.self)) }
            }
            exit(0)
        }
    }

    var body: some Scene {
        Window("SharpDisplay", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor
final class Model: ObservableObject {
    enum Status { case on, off }

    @Published var displays: [ExternalDisplay] = []
    @Published var selectedID: CGDirectDisplayID?
    @Published var busy = false
    @Published var message: String?
    /// The "looks like" width Turn On switches to. Nil means the largest.
    @Published var preferredWidth: Int?

    var selected: ExternalDisplay? { displays.first { $0.id == selectedID } ?? displays.first }

    var status: Status {
        guard let display = selected, let mode = Displays.currentMode(of: display.id) else { return .off }
        return mode.pixelWidth == mode.width * 2 && mode.width * 2 > display.nativeWidth ? .on : .off
    }

    /// Sizes to choose from: the installed HiDPI modes, or the ones Turn On will install.
    var sizes: [(width: Int, height: Int)] {
        guard let display = selected else { return [] }
        let installed = Displays.hiDPIModes(of: display).map { (width: $0.width, height: $0.height) }
        return Override.isInstalled(for: display) && !installed.isEmpty ? installed : Override.sizes(for: display).map(display.oriented)
    }

    var selectedWidth: Int? {
        guard let display = selected else { return nil }
        if status == .on, let mode = Displays.currentMode(of: display.id) { return mode.width }
        return preferredWidth ?? sizes.first?.width
    }

    var currentSize: String? {
        guard let display = selected, let mode = Displays.currentMode(of: display.id) else { return nil }
        return "\(mode.width) × \(mode.height)"
    }

    init() {
        refresh()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        displays = Displays.external().filter(\.isEligible)
        if selectedID == nil || !displays.contains(where: { $0.id == selectedID }) {
            selectedID = displays.first?.id
        }
        objectWillChange.send()
    }

    /// Picks a size. While sharp text is on it switches right away; no password is needed for that.
    func choose(width: Int) {
        preferredWidth = width
        guard status == .on, let display = selected,
              let mode = Displays.hiDPIModes(of: display).first(where: { $0.width == width })
        else { return }
        Displays.apply(mode, to: display.id)
        refresh()
    }

    func toggle() {
        guard let display = selected, !busy else { return }
        message = nil
        busy = true
        Task {
            defer { busy = false; refresh() }
            do {
                if status == .on { try await turnOff(display) } else { try await turnOn(display) }
            } catch let failure as Privileged.Failure where failure.cancelled {
                // The user closed the password prompt; nothing changed.
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func turnOn(_ display: ExternalDisplay) async throws {
        if !Override.isInstalled(for: display) {
            try Override.install(for: display)
        }
        // Reconnect until macOS has read the override; HiDPI modes it offers on its own don't count.
        let expected = Override.sizes(for: display).map(display.oriented).map(\.width)
        if !Displays.hiDPIModes(of: display).contains(where: { expected.contains($0.width) }) {
            let id = display.id
            _ = await Task.detached { Displays.reconnect(id) }.value
        }
        // The display ID survives a reconnect, so look the modes up again on the same display.
        let modes = Displays.hiDPIModes(of: display)
        guard let mode = modes.first(where: { $0.width == preferredWidth }) ?? modes.first else {
            message = "Almost there. Unplug the monitor cable and plug it back in, then press Turn On again."
            return
        }
        Displays.apply(mode, to: display.id)
    }

    private func turnOff(_ display: ExternalDisplay) async throws {
        if let native = Displays.nativeMode(of: display) {
            Displays.apply(native, to: display.id)
        }
        if Override.isInstalled(for: display) {
            try Override.uninstall(for: display)
        }
    }
}

struct ContentView: View {
    @StateObject private var model = Model()

    var body: some View {
        VStack(spacing: 0) {
            if let display = model.selected {
                header(display)
                Spacer(minLength: 28)
                button
                Spacer(minLength: 20)
                footer(display)
            } else {
                ContentUnavailableView(
                    "No Compatible Display",
                    systemImage: "display.trianglebadge.exclamationmark",
                    description: Text("Connect an external monitor below 4K. Retina and 4K displays are already sharp.")
                )
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .frame(width: 340, height: 450)
        .background(.background)
    }

    private func header(_ display: ExternalDisplay) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Image(systemName: "display")
                    .font(.system(size: 76, weight: .thin))
                    .foregroundStyle(model.status == .on ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                Text("Aa")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .blur(radius: model.status == .on ? 0 : 1.2)
                    .foregroundStyle(model.status == .on ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .offset(y: -6)
            }
            .animation(.smooth(duration: 0.4), value: model.status)

            if model.displays.count > 1 {
                Picker("", selection: $model.selectedID) {
                    ForEach(model.displays) { Text($0.name).tag(Optional($0.id)) }
                }
                .labelsHidden()
                .fixedSize()
            } else {
                Text(display.name)
                    .font(.title2.weight(.semibold))
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(model.status == .on ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
                Text(model.status == .on ? "Sharp text is on" : "Sharp text is off")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)

            if model.sizes.count > 1 {
                sizePicker
            }
        }
    }

    private var sizePicker: some View {
        let sizes = model.sizes
        return Picker("Size", selection: Binding(
            get: { model.selectedWidth ?? 0 },
            set: { model.choose(width: $0) }
        )) {
            ForEach(Array(sizes.enumerated()), id: \.element.width) { index, size in
                Text(sizeLabel(size, index: index, count: sizes.count)).tag(size.width)
            }
        }
        .labelsHidden()
        .fixedSize()
        .disabled(model.busy)
    }

    private func sizeLabel(_ size: (width: Int, height: Int), index: Int, count: Int) -> String {
        let label = "\(size.width) × \(size.height)"
        switch index {
        case 0: return "\(label) — More Space"
        case count - 1: return "\(label) — Larger Text"
        default: return label
        }
    }

    private var button: some View {
        Button(action: model.toggle) {
            ZStack {
                Text(model.status == .on ? "Turn Off" : "Turn On").opacity(model.busy ? 0 : 1)
                if model.busy { ProgressView().controlSize(.small) }
            }
            .frame(width: 180)
        }
        .buttonStyle(.borderedProminent)
        .tint(model.status == .on ? .secondary : .accentColor)
        .controlSize(.extraLarge)
        .keyboardShortcut(.defaultAction)
        .disabled(model.busy)
    }

    private func footer(_ display: ExternalDisplay) -> some View {
        VStack(spacing: 8) {
            if let message = model.message {
                Text(message)
                    .foregroundStyle(.orange)
            } else if let size = model.currentSize {
                Text(model.status == .on
                     ? "Looks like \(size), rendered at twice the resolution."
                     : "\(display.nativeWidth) × \(display.nativeHeight) without HiDPI. Text is rendered at 1x.")
                    .foregroundStyle(.secondary)
            }
            Button("Display Settings…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!)
            }
            .buttonStyle(.link)
            Text("© 2026 Dominik Rudkowski")
                .foregroundStyle(.tertiary)
        }
        .font(.footnote)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
}
