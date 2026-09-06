// overlay/Tests/UselessPetTests/PetWindowFrameTests.swift
import XCTest
import CoreGraphics
@testable import UselessPet

final class PetWindowFrameTests: XCTestCase {
    private let size = CGSize(width: 200, height: 200)
    private let mainScreen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func testNoSavedOriginReturnsNil() {
        XCTAssertNil(PetWindowController.onScreenOrigin(nil, size: size, screens: [mainScreen]))
    }

    func testSavedOriginOnScreenIsHonored() {
        // a window whose center lands inside the screen is restored verbatim
        let saved = CGPoint(x: 1680, y: 40)   // center (1780, 140) ∈ mainScreen
        XCTAssertEqual(
            PetWindowController.onScreenOrigin(saved, size: size, screens: [mainScreen]),
            saved)
    }

    func testSavedOriginOffAllScreensIsRejected() {
        // monitor was unplugged: the saved origin's center is on no current screen
        let saved = CGPoint(x: 3000, y: 2000)  // center (3100, 2100) ∉ any screen
        XCTAssertNil(
            PetWindowController.onScreenOrigin(saved, size: size, screens: [mainScreen]))
    }

    func testSavedOriginHonoredOnSecondaryScreen() {
        let secondary = CGRect(x: 1920, y: 0, width: 1440, height: 900)
        let saved = CGPoint(x: 3200, y: 100)   // center (3300, 200) ∈ secondary
        XCTAssertEqual(
            PetWindowController.onScreenOrigin(saved, size: size, screens: [mainScreen, secondary]),
            saved)
    }

    func testNoScreensReturnsNil() {
        let saved = CGPoint(x: 100, y: 100)
        XCTAssertNil(PetWindowController.onScreenOrigin(saved, size: size, screens: []))
    }

    // MARK: reveal / summon decision (the "Show" control)

    private let active = CGRect(x: 0, y: 0, width: 1920, height: 1050)        // primary visibleFrame
    private let other = CGRect(x: -1920, y: 0, width: 1920, height: 1080)     // a second monitor

    private func frame(at origin: CGPoint) -> CGRect { CGRect(origin: origin, size: size) }

    func testVisibleAndOnActiveScreenHides() {
        // pet is right in front of the user → "Show/Hide" hides it (real toggle)
        let f = frame(at: CGPoint(x: 848, y: 105))   // center (948,205) ∈ active
        XCTAssertEqual(
            PetWindowController.revealAction(currentFrame: f, isVisible: true,
                                             activeScreenVisibleFrame: active),
            .hide)
    }

    func testHiddenOnActiveScreenRevealsInPlace() {
        // hidden but already parked on the active screen → reveal without moving
        let f = frame(at: CGPoint(x: 848, y: 105))
        XCTAssertEqual(
            PetWindowController.revealAction(currentFrame: f, isVisible: false,
                                             activeScreenVisibleFrame: active),
            .show(relocateTo: nil))
    }

    func testParkedOnOtherScreenRelocatesToActive() {
        // pet lives on another monitor; user (cursor) is on `active` → summon it over
        let f = frame(at: CGPoint(x: -1200, y: 200))   // center on `other`, not `active`
        let expected = PetWindowController.cornerOrigin(in: active, size: size)
        XCTAssertEqual(
            PetWindowController.revealAction(currentFrame: f, isVisible: false,
                                             activeScreenVisibleFrame: active),
            .show(relocateTo: expected))
    }

    func testVisibleButOnOtherScreenSummonsRatherThanHides() {
        // visible, but on a display the user isn't on → bring it here, don't hide
        let f = frame(at: CGPoint(x: -1200, y: 200))
        let expected = PetWindowController.cornerOrigin(in: active, size: size)
        XCTAssertEqual(
            PetWindowController.revealAction(currentFrame: f, isVisible: true,
                                             activeScreenVisibleFrame: active),
            .show(relocateTo: expected))
    }

    func testUnknownActiveScreenFallsBackToPlainToggle() {
        let f = frame(at: CGPoint(x: 848, y: 105))
        XCTAssertEqual(
            PetWindowController.revealAction(currentFrame: f, isVisible: true,
                                             activeScreenVisibleFrame: nil),
            .hide)
        XCTAssertEqual(
            PetWindowController.revealAction(currentFrame: f, isVisible: false,
                                             activeScreenVisibleFrame: nil),
            .show(relocateTo: nil))
    }

    func testCornerOriginIsInsetBottomRight() {
        let o = PetWindowController.cornerOrigin(in: active, size: size)
        XCTAssertEqual(o.x, active.maxX - size.width - 40)
        XCTAssertEqual(o.y, active.minY + 40)
    }
}
