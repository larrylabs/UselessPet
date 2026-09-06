import XCTest
@testable import UselessPet

final class CompanionTests: XCTestCase {
    func testWireSnapshotSelectsExactlyOneCompanion() throws {
        let raw = Data(#"{"species_id":"lumi","species_name":"Lumi","schema_version":1}"#.utf8)
        let pet = try JSONDecoder().decode(PetState.self, from: raw)
        let model = ConsoleViewModel.build(pet: pet, connected: true)
        XCTAssertEqual(model.petName, "Lumi")
        XCTAssertEqual(model.roster.filter(\.selected).map(\.id), ["lumi"])
        XCTAssertEqual(model.roster.count, 4)
    }

    func testEveryReactionReturnsToNeutralAndRespectsReducedMotion() {
        for reaction in CompanionReaction.allCases {
            for t in [0.0, 3.0, 4.0, Double.nan] {
                let frame = reaction.frame(at: t)
                XCTAssertEqual(frame.expression, .neutral)
                XCTAssertEqual(frame.hop, 0)
                XCTAssertEqual(frame.tilt, 0)
                XCTAssertEqual(frame.scale, SIMD3<Float>(repeating: 1))
            }
            for step in 1..<30 {
                let frame = reaction.frame(at: Double(step) / 10, reducedMotion: true)
                XCTAssertEqual(frame.hop, 0)
                XCTAssertEqual(frame.tilt, 0)
                XCTAssertEqual(frame.scale, SIMD3<Float>(repeating: 1))
            }
        }
    }

    func testAllCharactersHavePortraitsAndRuntimeResources() {
        for species in SpeciesCatalog.pickableSpecies {
            XCTAssertNotNil(loadBundledImage(named: species.imageName!))
            let prefix = species.id == "nara" ? "nara_hybrid" : species.id
            for clip in ["idle", "eat", "play", "celebrate", "sad", "sleep"] {
                XCTAssertNotNil(Bundle.uselesspetResources.url(forResource: "\(prefix)_\(clip)", withExtension: "usdz"))
            }
        }
    }
}
