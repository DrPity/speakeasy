import AppKit
import SwiftUI

@main
struct LocalSTTApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var model: AppModel { AppModel.shared }

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The status-item icon: the coupe, redrawn whenever the model's icon clock
/// ticks (only while dictating) or its mode changes.
private struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        Image(nsImage: MenuBarIcon.image(
            mode: model.coupeMode,
            level: Double(model.engine.level),
            time: model.iconTime
        ))
        .accessibilityLabel("Speakeasy")
    }
}

/// Runs the startup sequence from `applicationDidFinishLaunching`, which fires
/// after the application is completely loaded — the right moment to ask for TCC
/// permissions (asking sooner may fail without any error).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"),
           CommandLine.arguments.indices.contains(index + 1) {
            MainActor.assumeIsolated {
                SnapshotRenderer.run(into: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            }
            exit(0)
        }
        #endif
        Task { @MainActor in
            await AppModel.shared.onLaunch()
        }
    }
}
