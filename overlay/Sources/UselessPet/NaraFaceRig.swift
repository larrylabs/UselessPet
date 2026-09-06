import Foundation
import RealityKit

/// Independent facial channels for the opt-in Nara asset pilot. Gaze uses
/// screen directions; positive X looks right and positive Y looks up.
struct NaraFacePose: Equatable {
    var blinkLeft: Float = 0
    var blinkRight: Float = 0
    var gazeX: Float = 0
    var gazeY: Float = 0
    var smile: Float = 0

    static let targetNames: Set<String> = [
        "blink_left", "blink_right", "look_left", "look_right",
        "look_up", "look_down", "smile", "blink_left_arc", "blink_right_arc",
    ]

    var weights: [String: Float] {
        let left = Self.unit(blinkLeft)
        let right = Self.unit(blinkRight)
        return ["blink_left": left, "blink_right": right,
         "blink_left_arc": 4 * left * (1 - left),
         "blink_right_arc": 4 * right * (1 - right),
         "look_left": Self.unit(-gazeX), "look_right": Self.unit(gazeX),
         "look_up": Self.unit(gazeY), "look_down": Self.unit(-gazeY),
         "smile": Self.unit(smile)]
    }

    func addingBlink(_ value: Float) -> Self {
        var result = self
        result.blinkLeft = max(Self.unit(blinkLeft), Self.unit(value))
        result.blinkRight = max(Self.unit(blinkRight), Self.unit(value))
        return result
    }

    static func unit(_ value: Float) -> Float {
        value.isFinite ? min(1, max(0, value)) : 0
    }

    /// Importers may prefix a target with its USD prim path or namespace.
    static func target(for importedName: String) -> String? {
        let name = importedName.components(separatedBy: CharacterSet(charactersIn: "/:."))
            .last ?? importedName
        return targetNames.contains(name) ? name : nil
    }

    static let qaStates: [(name: String, pose: Self)] = [
        ("neutral", .init()),
        ("blink25", .init(blinkLeft: 0.25, blinkRight: 0.25)),
        ("blink50", .init(blinkLeft: 0.5, blinkRight: 0.5)),
        ("blink75", .init(blinkLeft: 0.75, blinkRight: 0.75)),
        ("closed", .init(blinkLeft: 1, blinkRight: 1)),
        ("look_left", .init(gazeX: -1)), ("look_right", .init(gazeX: 1)),
        ("look_up", .init(gazeY: 1)), ("look_down", .init(gazeY: -1)),
        ("smile", .init(smile: 1)),
        ("smile_blink", .init(blinkLeft: 0.5, blinkRight: 0.5, smile: 1)),
    ]

    /// Body actions choose a natural starting face. The demo's sliders remain
    /// independent afterwards, so the user can combine expressions freely.
    static func startingPose(for action: String) -> Self {
        switch action {
        case "sleep": return .init(blinkLeft: 1, blinkRight: 1)
        case "sad": return .init(blinkLeft: 0.2, blinkRight: 0.2)
        case "eat", "play", "celebrate": return .init(smile: 1)
        default: return .init()
        }
    }
}

/// A blink lasts 240 ms, independent of render frame rate. Closing is faster
/// than opening; the short hold makes the closure readable at desktop size.
enum NaraBlinkCurve {
    static let duration: TimeInterval = 0.24

    static func value(at elapsed: TimeInterval) -> Float {
        guard elapsed.isFinite, elapsed >= 0, elapsed < duration else { return 0 }
        if elapsed < 0.075 { return smooth(Float(elapsed / 0.075)) }
        if elapsed < 0.1 { return 1 }
        return 1 - smooth(Float((elapsed - 0.1) / 0.14))
    }

    private static func smooth(_ t: Float) -> Float { t * t * (3 - 2 * t) }
}

@MainActor
final class NaraFaceRig {
    private let carriers: [Entity]
    let importedNames: [String]
    let animationCarrier: Entity

    init(root: Entity) throws {
        var mapped: [Entity] = []
        var names = Set<String>()
        var foundBody = false

        func visit(_ entity: Entity) {
            if let model = entity.components[ModelComponent.self] {
                foundBody = foundBody || model.mesh.contents.models.contains {
                    $0.id.localizedCaseInsensitiveContains("NaraHybridBodyMesh")
                } || entity.name == "NaraHybridBodyMesh"
                let mapping = BlendShapeWeightsMapping(meshResource: model.mesh)
                let component = BlendShapeWeightsComponent(weightsMapping: mapping)
                let weightNames = component.weightSet.flatMap(\.weightNames)
                names.formUnion(weightNames)
                if weightNames.contains(where: { NaraFacePose.target(for: $0) != nil }) {
                    entity.components.set(component)
                    mapped.append(entity)
                }
            }
            entity.children.forEach(visit)
        }
        visit(root)

        guard foundBody else { throw RigError.missingBody }
        let supported = Set(names.compactMap(NaraFacePose.target(for:)))
        let missing = NaraFacePose.targetNames.subtracting(supported)
        guard missing.isEmpty, let carrier = mapped.first else {
            throw RigError.missingTargets(missing.sorted(), names.sorted())
        }
        carriers = mapped
        importedNames = names.sorted()
        animationCarrier = carrier
        apply(.init())
    }

    /// Resolve every index from that imported set's names. No index is assumed
    /// to have a particular semantic meaning, even when the exporter reorders it.
    func apply(_ pose: NaraFacePose) {
        let values = pose.weights
        for entity in carriers {
            guard var component = entity.components[BlendShapeWeightsComponent.self] else { continue }
            for setIndex in component.weightSet.indices {
                var data = component.weightSet[setIndex]
                for (index, name) in data.weightNames.enumerated() {
                    guard let target = NaraFacePose.target(for: name) else { continue }
                    data.weights[index] = values[target] ?? 0
                }
                component.weightSet[setIndex] = data
            }
            entity.components.set(component)
        }
    }

    func importedWeights() -> [String: Float] {
        var result: [String: Float] = [:]
        for entity in carriers {
            guard let component = entity.components[BlendShapeWeightsComponent.self] else { continue }
            for data in component.weightSet {
                for (index, name) in data.weightNames.enumerated() { result[name] = data.weights[index] }
            }
        }
        return result
    }

    enum RigError: LocalizedError {
        case missingBody
        case missingTargets([String], [String])

        var errorDescription: String? {
            switch self {
            case .missingBody:
                return "Nara hybrid asset has no NaraHybridBodyMesh. Rebuild the demo asset."
            case let .missingTargets(missing, imported):
                return "Nara Blend Shapes missing: \(missing.joined(separator: ", ")). Imported: \(imported.joined(separator: ", "))."
            }
        }
    }
}
