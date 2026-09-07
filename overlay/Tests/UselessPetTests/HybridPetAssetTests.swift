import XCTest
@testable import UselessPet

final class HybridPetAssetTests: XCTestCase {
    @MainActor
    func testDistributedHybridAssetsHaveIndependentFacesAndCachedSources() async throws {
        var hashes = Set<String>()
        for species in ["nara", "mochi", "pando", "lumi"] {
            let first = try HybridPetAsset.load(species: species)
            XCTAssertTrue(hashes.insert(first.assetSHA256).inserted, "Different pets must have different source models")
            XCTAssertEqual(Set(first.clips.keys), Set(HybridPetAsset.clipNames))
            XCTAssertEqual(first.clipSHA256.count, 6)
            XCTAssertEqual(Set(first.clipSHA256.values).count, 6, "Each motion must use its own authored asset")
            for clip in first.clips.values {
                XCTAssertTrue(clip.definition.duration.isFinite && clip.definition.duration > 0)
            }
            let loads = HybridPetAsset.sourceLoadCount
            let second = try HybridPetAsset.load(species: species)
            XCTAssertEqual(HybridPetAsset.sourceLoadCount, loads, "Loading another instance must reuse the immutable source")
            XCTAssertFalse(first.entity === second.entity)
            let pose = NaraFacePose(blinkLeft: 0.5, gazeX: 0.7, gazeY: -0.4, smile: 0.8)
            first.faceRig.apply(pose)
            var mapped: [String: Float] = [:]
            for (name, weight) in first.faceRig.importedWeights() {
                if let target = NaraFacePose.target(for: name) { mapped[target] = weight }
            }
            XCTAssertEqual(Set(mapped.keys), NaraFacePose.targetNames)
            for (name, expected) in pose.weights {
                XCTAssertEqual(try XCTUnwrap(mapped[name]), expected, accuracy: 0.0001)
            }
            XCTAssertTrue(second.faceRig.importedWeights().values.allSatisfy { $0 == 0 },
                          "A sibling's face must not mutate when another clone blinks or looks")
            first.faceRig.apply(.init())
        }
    }
}
