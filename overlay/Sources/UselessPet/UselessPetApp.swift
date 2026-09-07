import AppKit
import SwiftUI

@main
struct UselessPetApp {
    static func main() {
        if let dir = ProcessInfo.processInfo.environment["USELESSPET_QA_HYBRID_FACE"] {
            let species = ProcessInfo.processInfo.environment["USELESSPET_QA_SPECIES"] ?? "mochi"
            MainActor.assumeIsolated { HybridFaceQA.run(directory: dir, speciesID: species) }
            return
        }
        if let dir = ProcessInfo.processInfo.environment["USELESSPET_QA_MOCHI_FACE"] {
            MainActor.assumeIsolated { HybridFaceQA.run(directory: dir) }
            exit(0)
        }
        if let dir = ProcessInfo.processInfo.environment["USELESSPET_QA_COMPANION"] {
            MainActor.assumeIsolated { CompanionRuntimeQA.run(directory: dir) }
            exit(0)
        }
        if let dir = ProcessInfo.processInfo.environment["USELESSPET_DUMP_CONSOLE"] {
            MainActor.assumeIsolated { ConsoleSnapshot.dumpAll(to: dir) }
            exit(0)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: PetWindowController?
    private var menuBarController: MenuBarController?
    private var bridgeClient: BridgeClient?
    private let devRuntime = DevAppRuntime()

    func applicationDidFinishLaunching(_ notification: Notification) {
        do { try devRuntime.start() }
        catch {
            let alert = NSAlert()
            alert.messageText = "UselessPet Dev could not start"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApplication.shared.terminate(nil)
            return
        }
        let bridge = BridgeClient()
        bridgeClient = bridge
        let controller = PetWindowController(bridge: bridge)
        controller.show()
        windowController = controller
        menuBarController = MenuBarController(window: controller, bridge: bridge)
        bridge.connect()
    }
    func applicationWillTerminate(_ notification: Notification) {
        bridgeClient?.disconnect()
        devRuntime.stop()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController?.show()
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
