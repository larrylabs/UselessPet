import AppKit
import SwiftUI

/// Observable mirror of what the console's eye button will do next, so its icon
/// and tooltip honestly reflect the real action (hide / show / summon-to-screen).
@MainActor
final class PetVisibility: ObservableObject {
    @Published var eyeIntent: ConsoleEyeIntent = .hide   // pet ordered front at launch
}

final class PetWindowController: NSWindowController {
    private let bridge: BridgeClient
    /// Drives the console eye button (eye / eye.slash + tooltip).
    let visibility = PetVisibility()

    /// 200×200: enough viewport for the characters' ears / quills / hop clips
    /// while still reading as "a creature on the desktop".
    static let panelSize = NSSize(width: 200, height: 200)
    private static let originKey = "uselesspet.petWindowOrigin"

    init(bridge: BridgeClient) {
        self.bridge = bridge
        let panel = PetPanel(contentRect: Self.startupFrame())
        panel.contentView = NSHostingView(rootView: PetView(bridge: bridge))
        super.init(window: panel)
        // Persist the pet's spot whenever the user drags it, so it returns to
        // the same place next launch (validated against live screens on restore).
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowMoved),
            name: NSWindow.didMoveNotification, object: panel)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func windowMoved() {
        guard let origin = window?.frame.origin else { return }
        UserDefaults.standard.set(NSStringFromPoint(origin), forKey: Self.originKey)
    }

    /// Restore the last-dragged origin if it is still on a connected screen,
    /// otherwise fall back to the default bottom-right corner.
    private static func startupFrame() -> NSRect {
        let saved = UserDefaults.standard.string(forKey: originKey)
            .flatMap { $0.isEmpty ? nil : NSPointFromString($0) }   // ignore a cleared/blank value
        let screens = NSScreen.screens.map(\.frame)
        if let origin = onScreenOrigin(saved, size: panelSize, screens: screens) {
            return NSRect(origin: origin, size: panelSize)
        }
        return defaultFrame()
    }

    /// Honor a saved window origin only if the window's CENTER would still land
    /// on some connected screen — guards against a monitor that was unplugged
    /// since last launch (which would otherwise strand the pet off-screen).
    /// Pure (takes screen frames, not `NSScreen`) so it is unit-testable.
    static func onScreenOrigin(_ saved: CGPoint?, size: CGSize, screens: [CGRect]) -> CGPoint? {
        guard let saved else { return nil }
        let center = CGPoint(x: saved.x + size.width / 2, y: saved.y + size.height / 2)
        return screens.contains(where: { $0.contains(center) }) ? saved : nil
    }

    /// Bottom-right corner of the screen the user is actively on — the one
    /// containing the mouse cursor AT LAUNCH, falling back to the primary
    /// menu-bar screen. Read ONCE (not dynamically): this still doesn't let
    /// the pet chase key-window focus across monitors (the old bug that
    /// stranded it on a secondary Mi Monitor), but it does start the pet on
    /// the display the user is actually looking at, instead of always pinning
    /// it to the primary where a second-monitor user never sees it.
    private static func defaultFrame() -> NSRect {
        let size = panelSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.screens.first
        guard let screen else {
            return NSRect(origin: .zero, size: size)
        }
        return NSRect(origin: cornerOrigin(in: screen.visibleFrame, size: size), size: size)
    }

    /// Bottom-right, inset corner of a screen's visible area — the canonical
    /// "a creature on the desktop" resting spot. Pure for testability.
    static func cornerOrigin(in visible: CGRect, size: CGSize, inset: CGFloat = 40) -> CGPoint {
        CGPoint(x: visible.maxX - size.width - inset, y: visible.minY + inset)
    }

    /// Show the panel. For an `.accessory` app, plain `showWindow` does not
    /// actually order the window front because the app isn't active — we
    /// must call `orderFrontRegardless` explicitly.
    func show() {
        guard let window else { return }
        window.orderFrontRegardless()
        refreshEyeIntent()
        let f = window.frame
        let screenInfo = (window.screen ?? NSScreen.main)
            .map { "\($0.localizedName) visible=\($0.visibleFrame)" } ?? "no screen"
        let all = NSScreen.screens
            .map { "\($0.localizedName)=\($0.frame)" }
            .joined(separator: " | ")
        FileHandle.standardError.write(Data(
            "UselessPet overlay: panel ordered front at \(f) on \(screenInfo); screens: \(all)\n".utf8
        ))
    }

    /// What the "Show / Hide" control should do. Hides only when the pet is
    /// already visible AND sitting on the screen the user is currently on;
    /// otherwise it reveals — relocating onto the active screen when parked on
    /// a different display, so "Show" always summons the pet to where the user
    /// is looking (the multi-monitor case where a blind toggle just hid the pet
    /// or revealed it on a monitor the user wasn't watching). Pure & testable.
    enum RevealAction: Equatable {
        case hide
        case show(relocateTo: CGPoint?)   // nil = reveal at the current origin
    }

    static func revealAction(currentFrame: CGRect, isVisible: Bool,
                             activeScreenVisibleFrame: CGRect?) -> RevealAction {
        guard let active = activeScreenVisibleFrame else {
            // no active screen known → behave as a plain toggle
            return isVisible ? .hide : .show(relocateTo: nil)
        }
        let center = CGPoint(x: currentFrame.midX, y: currentFrame.midY)
        let onActiveScreen = active.contains(center)
        if isVisible && onActiveScreen { return .hide }
        if onActiveScreen { return .show(relocateTo: nil) }
        return .show(relocateTo: cornerOrigin(in: active, size: currentFrame.size))
    }

    /// Visible frame of the screen the mouse is currently on (a good proxy for
    /// "where the user is", since they just clicked the control), else the main.
    private static func activeScreenVisibleFrame() -> CGRect? {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
        return screen?.visibleFrame
    }

    func toggleVisibility() {
        guard let window else { return }
        switch Self.revealAction(currentFrame: window.frame, isVisible: window.isVisible,
                                 activeScreenVisibleFrame: Self.activeScreenVisibleFrame()) {
        case .hide:
            window.orderOut(nil)
        case .show(let relocateTo):
            if let origin = relocateTo { window.setFrameOrigin(origin) }
            window.orderFrontRegardless()
        }
        refreshEyeIntent()   // the next click's action changed — update the icon
    }

    /// What clicking the eye button will do *right now*, given where the pet sits
    /// and which screen the user is on. Maps the same `revealAction` the click
    /// runs, so the icon/label can never contradict the resulting action.
    func currentEyeIntent() -> ConsoleEyeIntent {
        guard let window else { return .show }
        switch Self.revealAction(currentFrame: window.frame, isVisible: window.isVisible,
                                 activeScreenVisibleFrame: Self.activeScreenVisibleFrame()) {
        case .hide:                   return .hide
        case .show(let relocateTo):   return relocateTo == nil ? .show : .summon
        }
    }

    /// Recompute the eye intent into the observable — call when the pet's state or
    /// the active screen may have changed (toggle, launch, console opening).
    func refreshEyeIntent() {
        visibility.eyeIntent = currentEyeIntent()
    }
}
