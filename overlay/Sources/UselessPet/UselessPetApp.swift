import AppKit
import SwiftUI

@main
struct UselessPetApp {
    static func main() {
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

    func applicationDidFinishLaunching(_ notification: Notification) {
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
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
