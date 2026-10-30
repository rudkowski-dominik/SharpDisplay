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

    var selected: ExternalDisplay? { displays.first { $0.id == selectedID } ?? displays.first }

    var status: Status {
        guard let display = selected, let mode = Displays.currentMode(of: display.id) else { return .off }
        return mode.pixelWidth == mode.width * 2 && mode.width * 2 > display.nativeWidth ? .on : .off
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
        if Displays.hiDPIModes(of: display).isEmpty {
            let id = display.id
            _ = await Task.detached { Displays.reconnect(id) }.value
        }
        // The display ID survives a reconnect, so look the modes up again on the same display.
        guard let mode = Displays.hiDPIModes(of: display).first else {
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
        .frame(width: 340, height: 420)
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
        }
        .font(.footnote)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
}
