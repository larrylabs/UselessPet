import XCTest
@testable import UselessPet

final class CompanionLocalizationTests: XCTestCase {
    func testFirstInstallAndUnknownPreferencesUseEnglish() {
        XCTAssertEqual(AppLanguage.resolve(nil), .english)
        XCTAssertEqual(AppLanguage.resolve("fr"), .english)
        XCTAssertEqual(AppLanguage.resolve("zh-Hant"), .traditionalChinese)
        XCTAssertEqual(L10n.text(.settings, language: .english), "Settings")
        XCTAssertEqual(L10n.text(.settings, language: .japanese), "設定")
    }

    func testEveryShippedLanguageHasEveryKeyAndResolvesPlaceholders() throws {
        for language in AppLanguage.allCases {
            let bundle = try XCTUnwrap(L10n.resourceBundle(for: language), "Missing \(language.rawValue)")
            let dictionary = try XCTUnwrap(NSDictionary(contentsOfFile: bundle.bundlePath + "/Localizable.strings") as? [String: String])
            XCTAssertEqual(Set(dictionary.keys), Set(L10nKey.allCases.map(\.rawValue)))
            for key in L10nKey.allCases {
                let text = L10n.text(key, language: language, name: "Nara")
                XCTAssertFalse(text.isEmpty)
                XCTAssertFalse(text.contains("{"))
                XCTAssertNotEqual(text, key.rawValue)
            }
        }
    }

    func testReactionFramesSettleAndHonorReducedMotion() {
        for reaction in CompanionReaction.allCases {
            for time in [0.0, 3.0, 100.0, Double.nan] {
                let frame = reaction.frame(at: time)
                XCTAssertEqual(frame.hop, 0)
                XCTAssertEqual(frame.tilt, 0)
                XCTAssertEqual(frame.scale, .init(repeating: 1))
                XCTAssertEqual(frame.expression, .neutral)
            }
            for time in stride(from: 0.1, through: 2.9, by: 0.1) {
                let frame = reaction.frame(at: time, reducedMotion: true)
                XCTAssertEqual(frame.hop, 0)
                XCTAssertEqual(frame.tilt, 0)
                XCTAssertEqual(frame.scale, .init(repeating: 1))
                XCTAssertNotEqual(frame.expression, .neutral)
            }
        }
    }

    func testDaemonReactionsHaveDistinctFacesAndSynchronizedHopAccents() {
        XCTAssertEqual(Set(CompanionReaction.allCases.map { $0.expression.rawValue }).count, 5)
        let first = CompanionReaction.joy.frame(at: 0.75)
        let landing = CompanionReaction.joy.frame(at: 1.15)
        XCTAssertGreaterThan(first.hop, landing.hop)
        XCTAssertGreaterThan(first.face.blinkLeft, landing.face.blinkLeft)
        XCTAssertLessThan(landing.scale.y, 1)
        XCTAssertEqual(CompanionReaction.surprise.frame(at: 0.6).expression, .surprised)
        XCTAssertEqual(CompanionReaction.surprise.frame(at: 2).expression, .happy)
    }
}
