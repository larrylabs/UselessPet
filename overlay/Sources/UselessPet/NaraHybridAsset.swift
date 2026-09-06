import AppKit
import CryptoKit
import RealityKit

/// The demo and production renderer use the same importer, normalization,
/// source colors, clip extraction, and dynamically mapped facial carrier.
@MainActor
struct NaraHybridAsset {
    let entity: Entity
    let faceRig: NaraFaceRig
    let clips: [String: AnimationResource]
    let assetSHA256: String
    let clipSHA256: [String: String]
    let materialNames: [String]

    static let clipNames = ["idle", "eat", "play", "celebrate", "sad", "sleep"]
    private static var sources: [String: Source] = [:]
    private(set) static var sourceLoadCount = 0

    private struct Source {
        let prototype: Entity
        let clips: [String: AnimationResource]
        let assetSHA256: String
        let clipSHA256: [String: String]
        let materialNames: [String]
    }

    static func load(in bundle: Bundle = .uselesspetResources) throws -> Self {
        let key = bundle.bundleURL.path
        let source: Source
        if let cached = sources[key] {
            source = cached
        } else {
            source = try loadSource(in: bundle)
            sources[key] = source
            sourceLoadCount += 1
        }
        let entity = source.prototype.clone(recursive: true)
        entity.stopAllAnimations(recursive: true)
        let rig = try NaraFaceRig(root: entity)
        return .init(entity: entity, faceRig: rig, clips: source.clips,
                     assetSHA256: source.assetSHA256, clipSHA256: source.clipSHA256,
                     materialNames: source.materialNames)
    }

    private static func loadSource(in bundle: Bundle) throws -> Source {
        guard let url = bundle.url(forResource: "nara_hybrid_demo", withExtension: "usdz") else {
            throw AssetError.missingAsset("nara_hybrid_demo.usdz")
        }
        let root = try Entity.load(contentsOf: url)
        root.stopAllAnimations(recursive: true)
        let sourceRig = try NaraFaceRig(root: root)
        guard let skeleton = sourceRig.animationCarrier.components[ModelComponent.self]?.mesh.contents.skeletons.first else {
            throw AssetError.emptyAsset
        }
        sourceRig.animationCarrier.components.set(SkeletalPosesComponent(poses: [SkeletalPose(id: skeleton.id, from: skeleton)]))
        let materialNames = preserveBakedColors(in: root)
        let bounds = root.visualBounds(relativeTo: nil)
        guard bounds.extents.y.isFinite, bounds.extents.y > 0 else { throw AssetError.emptyAsset }
        let scale: Float = 0.26 / bounds.extents.y
        root.scale = SIMD3(repeating: scale)
        root.position.y -= bounds.center.y * scale
        var clips: [String: AnimationResource] = [:]
        var hashes: [String: String] = [:]
        for name in clipNames {
            guard let clipURL = bundle.url(forResource: "nara_hybrid_\(name)", withExtension: "usdz") else {
                throw AssetError.missingAsset("nara_hybrid_\(name).usdz")
            }
            let clipEntity = try Entity.load(contentsOf: clipURL)
            guard let animation = skeletalAnimation(in: clipEntity),
                  animation.definition.duration.isFinite,
                  animation.definition.duration > 0 else { throw AssetError.missingClip(name) }
            // Bind direct clips to the imported model's named pose. A legacy
            // jointTransforms binding creates an unnamed pose at playback time;
            // writing that alias cannot reliably update this hybrid skinned mesh.
            var definition = animation.definition
            if ProcessInfo.processInfo.environment["USELESSPET_ANIMATION_DEBUG"] == "1" {
                print("Nara clip \(name): \(String(reflecting: type(of: definition))) duration=\(definition.duration) trim=\(String(describing: definition.trimStart))/\(String(describing: definition.trimEnd))/\(String(describing: definition.trimDuration)) speed=\(definition.speed) offset=\(definition.offset)")
            }
            definition.bindTarget = .skeletalPose(skeleton.id)
            clips[name] = try AnimationResource.generate(with: definition)
            hashes[name] = try digest(clipURL)
        }
        return Source(prototype: root, clips: clips, assetSHA256: try digest(url),
                      clipSHA256: hashes, materialNames: materialNames)
    }

    private static func preserveBakedColors(in entity: Entity) -> [String] {
        var names: [String] = []
        if var model = entity.components[ModelComponent.self] {
            for index in model.materials.indices {
                let material = model.materials[index]
                let name = material.name ?? "material_\(index)"
                names.append(name)
                guard name.localizedCaseInsensitiveContains("Nara"),
                      let source = material as? PhysicallyBasedMaterial else { continue }
                var unlit = UnlitMaterial(applyPostProcessToneMap: false)
                unlit.color = .init(tint: source.baseColor.tint, texture: source.baseColor.texture)
                unlit.faceCulling = source.faceCulling
                unlit.blending = source.blending
                unlit.opacityThreshold = source.opacityThreshold
                model.materials[index] = unlit
            }
            entity.components.set(model)
        }
        for child in entity.children { names += preserveBakedColors(in: child) }
        return names
    }

    private static func skeletalAnimation(in entity: Entity) -> AnimationResource? {
        if let library = entity.components[AnimationLibraryComponent.self],
           let animation = library.animations.first(where: {
               $0.key.localizedCaseInsensitiveContains("skeletal")
           })?.value { return animation }
        if let animation = entity.availableAnimations.first(where: {
            $0.name?.localizedCaseInsensitiveContains("skeletal") == true
        }) { return animation }
        for child in entity.children {
            if let animation = skeletalAnimation(in: child) { return animation }
        }
        return nil
    }

    private static func digest(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    enum AssetError: LocalizedError {
        case missingAsset(String), missingClip(String), emptyAsset
        var errorDescription: String? {
            switch self {
            case .missingAsset(let name): return "Missing Nara resource: \(name)."
            case .missingClip(let name): return "Nara's \(name) skeletal animation is missing."
            case .emptyAsset: return "Nara has empty or invalid geometry."
            }
        }
    }
}
