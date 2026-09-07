import XCTest
@testable import UselessPet

final class CompanionFaceRigTests: XCTestCase {
    func testSmileAndGazeSurviveAnOverlaidBlink() {
        let original = NaraFacePose(blinkLeft: 0.1, gazeX: -0.4, gazeY: 0.2, smile: 0.7)
        let blink = original.addingBlink(0.75).weights
        XCTAssertEqual(blink["blink_left"], 0.75)
        XCTAssertEqual(blink["blink_right"], 0.75)
        XCTAssertEqual(blink["blink_left_arc"], 0.75)
        XCTAssertEqual(blink["look_left"], 0.4)
        XCTAssertEqual(blink["look_right"], 0)
        XCTAssertEqual(blink["look_up"], 0.2)
        XCTAssertEqual(blink["smile"], 0.7)
        XCTAssertEqual(original.blinkLeft, 0.1)
    }

    func testManualClosedEyeIsNotReopenedByAutomaticBlink() {
        let pose = NaraFacePose(blinkLeft: 1, blinkRight: 0.2).addingBlink(0.5)
        XCTAssertEqual(pose.weights["blink_left"], 1)
        XCTAssertEqual(pose.weights["blink_left_arc"], 0)
        XCTAssertEqual(pose.weights["blink_right"], 0.5)
        XCTAssertEqual(pose.weights["blink_right_arc"], 1)
    }

    func testInvalidAndOutOfRangeInputCannotEscapeWeightLimits() {
        let pose = NaraFacePose(blinkLeft: -2, blinkRight: 4, gazeX: .nan,
                                gazeY: -.infinity, smile: 10)
        for weight in pose.weights.values { XCTAssertTrue(weight.isFinite && (0...1).contains(weight)) }
        XCTAssertEqual(pose.weights["blink_right"], 1)
        XCTAssertEqual(pose.weights["look_down"], 0)
    }

    func testImportedNamesResolveWithoutDependingOnExportOrder() {
        let reordered = ["Rig/NaraHybridBodyMesh.smile", "look_down", "Rig:blink_right", "unknown"]
        XCTAssertEqual(reordered.compactMap(NaraFacePose.target(for:)), ["smile", "look_down", "blink_right"])
        XCTAssertNil(NaraFacePose.target(for: "smile_unrelated"))
    }

    func testBlinkCurveUsesElapsedTimeAndReturnsToRest() {
        XCTAssertEqual(NaraBlinkCurve.value(at: 0), 0)
        XCTAssertEqual(NaraBlinkCurve.value(at: 0.075), 1)
        XCTAssertEqual(NaraBlinkCurve.value(at: 0.095), 1)
        XCTAssertEqual(NaraBlinkCurve.value(at: 0.24), 0)
        XCTAssertEqual(NaraBlinkCurve.value(at: 3), 0)
        XCTAssertEqual(NaraBlinkCurve.value(at: .nan), 0)
        XCTAssertGreaterThan(NaraBlinkCurve.value(at: 0.05), NaraBlinkCurve.value(at: 0.025))
        XCTAssertGreaterThan(NaraBlinkCurve.value(at: 0.12), NaraBlinkCurve.value(at: 0.2))
    }

    func testQAMatrixCoversContinuousClosureAndCombinedChannels() {
        let poses = Dictionary(uniqueKeysWithValues: NaraFacePose.qaStates.map { ($0.name, $0.pose.weights) })
        XCTAssertEqual(Set(poses.keys).count, 11)
        XCTAssertEqual(poses["blink50"]?["blink_left_arc"], 1)
        XCTAssertEqual(poses["closed"]?["blink_left_arc"], 0)
        XCTAssertEqual(poses["smile_blink"]?["smile"], 1)
        XCTAssertEqual(poses["smile_blink"]?["blink_left"], 0.5)
    }
}
