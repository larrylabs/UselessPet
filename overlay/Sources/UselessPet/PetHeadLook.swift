import RealityKit
import simd

/// Adds cursor rotation to the evaluated head joint, leaving every other local
/// joint and the scene root unchanged. Runs after RealityKit evaluates clips.
@MainActor
final class PetHeadLook {
    private struct Binding {
        let entity: Entity
        let poseID: String
        let head: Int
        let parents: [Int]
        var lastBase: Transform?
        var lastApplied: Transform?
    }
    private var bindings: [Binding] = []
    private(set) var applications = 0
    private(set) var nonHeadChanges = 0
    var isBound: Bool { !bindings.isEmpty }

    init(root: Entity) {
        func visit(_ entity: Entity) {
            if let model = entity.components[ModelComponent.self] {
                var poses = entity.components[SkeletalPosesComponent.self]
                    ?? SkeletalPosesComponent(poses: model.mesh.contents.skeletons.map { SkeletalPose(id: $0.id, from: $0) })
                for skeleton in model.mesh.contents.skeletons {
                    guard let pose = poses.poses[skeleton.id] ?? poses.poses.default,
                          let head = pose.jointNames.firstIndex(where: { $0.split(separator: "/").last == "head" }),
                          let skeletonHead = skeleton.joints.firstIndex(where: { $0.name == pose.jointNames[head] }) else { continue }
                    var parent = skeleton.joints[skeletonHead].parentIndex
                    var ancestors: [Int] = []
                    while let index = parent {
                        if let mapped = pose.jointNames.firstIndex(of: skeleton.joints[index].name) { ancestors.insert(mapped, at: 0) }
                        parent = skeleton.joints[index].parentIndex
                    }
                    poses.poses.set(pose)
                    bindings.append(.init(entity: entity, poseID: pose.id, head: head, parents: ancestors))
                }
                if !poses.poses.isEmpty { entity.components.set(poses) }
            }
            entity.children.forEach(visit)
        }
        visit(root)
    }

    /// Convert screen/world axes into the head parent's coordinate space.
    /// Import conversion, the authored parent pose, and rest axes all participate.
    static func rotatedHead(_ head: Transform, parentWorld: simd_quatf,
                            yaw: Float, pitch: Float) -> Transform {
        let yaw = yaw.isFinite ? max(-.pi / 12, min(.pi / 12, yaw)) : 0
        let pitch = pitch.isFinite ? max(-.pi * 8 / 180, min(.pi * 8 / 180, pitch)) : 0
        let world = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: pitch, axis: [1, 0, 0])
        var result = head
        result.rotation = simd_normalize(parentWorld.inverse * world * parentWorld * head.rotation)
        return result
    }

    func apply(yaw: Float, pitch: Float) {
        for index in bindings.indices {
            var binding = bindings[index]
            guard var component = binding.entity.components[SkeletalPosesComponent.self],
                  var pose = component.poses[binding.poseID] ?? component.poses.default,
                  pose.jointTransforms.indices.contains(binding.head) else { continue }
            let before = pose.jointTransforms
            var head = before[binding.head]
            // A paused or unanimated pose may still contain our previous result.
            // Reuse its unmodified base so a fixed cursor never accumulates spin.
            if head == binding.lastApplied, let base = binding.lastBase { head = base }
            var parentWorld = binding.entity.orientation(relativeTo: nil)
            for parent in binding.parents { parentWorld *= pose.jointTransforms[parent].rotation }
            let changed = Self.rotatedHead(head, parentWorld: parentWorld, yaw: yaw, pitch: pitch)
            pose.jointTransforms[binding.head] = changed
            for joint in before.indices where joint != binding.head {
                if before[joint] != pose.jointTransforms[joint] { nonHeadChanges += 1 }
            }
            if component.poses.contains(binding.poseID) { component.poses[binding.poseID] = pose }
            else { component.poses.default = pose }
            binding.entity.components.set(component)
            binding.lastBase = head
            binding.lastApplied = changed
            bindings[index] = binding
            applications += 1
        }
    }

    var diagnostics: [String: Any] {
        ["boundHeads": bindings.count, "applications": applications, "nonHeadChanges": nonHeadChanges,
         "joints": bindings.map { ["entity": $0.entity.name, "pose": $0.poseID, "headIndex": $0.head] },
         "livePoseIDs": bindings.map { $0.entity.components[SkeletalPosesComponent.self]?.poses.map(\.id) ?? [] },
         "poses": bindings.map { binding -> [String: Any] in
             guard let component = binding.entity.components[SkeletalPosesComponent.self],
                   let pose = component.poses[binding.poseID] ?? component.poses.default else { return [:] }
             return Dictionary(uniqueKeysWithValues: pose.jointNames.enumerated().map { index, name in
                 let t = pose.jointTransforms[index]
                 return (name, [t.translation.x, t.translation.y, t.translation.z,
                                t.rotation.vector.x, t.rotation.vector.y, t.rotation.vector.z, t.rotation.vector.w,
                                t.scale.x, t.scale.y, t.scale.z])
             })
         }]
    }
}
