import AppKit
import SwiftUI

/// Menu-bar 🐾 — left-click opens the full status popover, right-click
/// (or Control-click) opens a quick action menu. The popover is the
/// primary surface for preferences and interactions while the desktop pet is
/// chrome-free.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private weak var window: PetWindowController?
    private let bridge: BridgeClient

    init(window: PetWindowController, bridge: BridgeClient) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.window = window
        self.bridge = bridge

        self.popover = NSPopover()
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        // Use the system appearance for both the content and the popover chrome.
        let hostingController = NSHostingController(
            rootView: PetConsolePanel(
                bridge: bridge,
                visibility: window.visibility,
                onTogglePet: { [weak self] in self?.toggleWindow() }
            )
        )
        if #available(macOS 13.0, *) {
            hostingController.sizingOptions = .preferredContentSize
        }
        popover.contentViewController = hostingController

        if let button = statusItem.button {
            button.title = "🐾"
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func handleClick() {
        guard let button = statusItem.button else { return }
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showQuickMenu(under: button)
        } else {
            togglePopover(relativeTo: button)
        }
    }

    private func togglePopover(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Temporarily allow regular activation so the popover can take focus
            // and accept clicks; we drop back to .accessory on close.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            window?.refreshEyeIntent()   // eye button reflects the pet's real next action
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // NSPopover's window defaults to the active Space only, so the panel
            // never appears while another app is fullscreen (a Space of its own).
            // Give it the same fullscreen-auxiliary behavior as PetPanel so it
            // renders over fullscreen apps too.
            if let win = popover.contentViewController?.view.window {
                win.collectionBehavior.insert(.canJoinAllSpaces)
                win.collectionBehavior.insert(.fullScreenAuxiliary)
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private func showQuickMenu(under button: NSStatusBarButton) {
        let menu = NSMenu()
        window?.refreshEyeIntent()
        let intent = window?.visibility.eyeIntent ?? .show
        let toggleTitle: L10nKey = intent == .hide ? .hidePet : intent == .summon ? .summonPet : .showPet
        let toggle = NSMenuItem(title: L10n.text(toggleTitle), action: #selector(toggleWindow), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        // These shortcuts share the settings panel's preferences and language.
        let gaze = NSMenuItem(title: L10n.text(.headTracking), action: #selector(toggleGaze), keyEquivalent: "")
        gaze.target = self
        gaze.state = Self.followsCursor ? .on : .off
        menu.addItem(gaze)

        let sizeItem = NSMenuItem(title: L10n.text(.sizeTitle), action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for (title, value) in [(L10nKey.sizeSmall, 0.5), (.sizeMedium, 0.75), (.sizeLarge, 1.0)] {
            let it = NSMenuItem(title: L10n.text(title), action: #selector(setSize(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = value
            it.state = abs(Self.petScale - value) < 0.01 ? .on : .off
            sizeMenu.addItem(it)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: L10n.text(.quit), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: button.bounds.height + 4),
                   in: button)
    }

    @objc private func toggleWindow() {
        // Keep the popover open on the eye toggle so its icon flips live
        // (eye ⇄ eye.slash). The quick-menu path runs with no popover shown.
        window?.toggleVisibility()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - pet preferences (mirror PetView/@AppStorage UserDefaults keys)

    private static var followsCursor: Bool {
        UserDefaults.standard.object(forKey: "uselesspet.petFollowsCursor") as? Bool ?? true
    }
    private static var petScale: Double {
        let v = UserDefaults.standard.object(forKey: "uselesspet.petScale") as? Double
        return v ?? 1.0
    }

    @objc private func toggleGaze() {
        UserDefaults.standard.set(!Self.followsCursor, forKey: "uselesspet.petFollowsCursor")
    }

    @objc private func setSize(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? Double else { return }
        UserDefaults.standard.set(v, forKey: "uselesspet.petScale")
    }
}
