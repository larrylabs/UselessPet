import AppKit
import ApplicationServices
import RealityKit

/// Uses the production renderer with local inputs, never a daemon or saved pet.
@MainActor
enum CompanionRuntimeQA {
    static func run(directory: String) {
        setbuf(stdout, nil)
        let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
        guard session["CGSSessionScreenIsLocked"] as? Bool != true else {
            print("Native render QA requires an unlocked Mac; no acceptance screenshots were captured.")
            exit(3)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let runner = Runner(output: URL(fileURLWithPath: directory))
        DispatchQueue.global().asyncAfter(deadline: .now() + 240) { exit(2) }
        Task { @MainActor in
            do { try await runner.run(); exit(0) }
            catch { print("Companion QA failed: \(error)"); exit(1) }
        }
        withExtendedLifetime(runner) { app.run() }
    }

    @MainActor
    private final class Runner {
        let output: URL
        var controller = Pet3DController()
        let window = NSWindow(contentRect: .init(x: 80, y: 140, width: 400, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        var records: [[String: Any]] = []
        init(output: URL) { self.output = output }

        func run() async throws {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            window.title = "UselessPet companion render QA"
            window.contentView = controller.arView
            window.orderFrontRegardless()
            NSApplication.shared.activate(ignoringOtherApps: true)
            for species in SpeciesCatalog.pickableIds {
                controller.followsCursor = false
                controller.bootstrap(species: SpeciesCatalog.info(for: species), mood: .neutral, hunger: .content)
                try await pause(0.7)
                controller.freezeBodyForHeadQA()
                try await pause(0.15)
                let baseline = try headPose()
                try await capture("\(species)-head-center")
                let directions: [(String, Float, Float)] = [
                    ("left", -Float.pi / 12, 0), ("right", Float.pi / 12, 0),
                    ("up", 0, -Float.pi * 8 / 180), ("down", 0, Float.pi * 8 / 180),
                ]
                for (name, yaw, pitch) in directions {
                    controller.setHeadForQA(yaw: yaw, pitch: pitch)
                    try await pause(0.2)
                    let changed = try headPose()
                    try await capture("\(species)-head-\(name)")
                    try checkBody(baseline, changed, mustTurn: true)
                    try checkPixels(species: species, direction: name)
                }
                controller.setHeadForQA(yaw: 0, pitch: 0)
                try await pause(0.2)
                try checkBody(baseline, try headPose(), mustTurn: false)
                try await capture("\(species)-head-return")
                controller.shutdown()
                controller = Pet3DController()
                window.contentView = controller.arView
            }
            for species in SpeciesCatalog.pickableIds {
                let info = SpeciesCatalog.info(for: species)
                controller.followsCursor = false
                controller.bootstrap(species: info, mood: .neutral, hunger: .content)
                try await pause(0.4)
                for reaction in CompanionReaction.allCases {
                    controller.update(species: info, mood: .neutral, hunger: .content,
                                      transient: .petted(id: UUID(), reaction: reaction), activity: .idle)
                    let start = Date()
                    for (index, target) in [0.3, 0.75, 1.15, 1.95, 2.35, 3.4].enumerated() {
                        let wait = max(0.01, target - Date().timeIntervalSince(start))
                        try await pause(wait)
                        try await capture("\(species)-\(reaction.rawValue)-\(index)")
                    }
                    let final = controller.runtimeDiagnostics
                    guard final["companion_reaction"] as? String == "", final["clip"] as? String == "idle",
                          final["expression"] as? String == "neutral" else {
                        throw failure("\(species) \(reaction) did not settle to idle")
                    }
                }
                controller.shutdown()
                controller = Pet3DController()
                window.contentView = controller.arView
            }
            let data = try JSONSerialization.data(withJSONObject: ["status": "passed", "frames": records], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appendingPathComponent("manifest.json"))
            controller.shutdown()
            window.orderOut(nil)
            print("Companion QA passed: four head rigs, frozen-body invariance, twenty coordinated reactions and neutral return")
        }

        func headPose() throws -> [String: [Float]] {
            let report = controller.runtimeDiagnostics["head_tracking"] as? [String: Any] ?? [:]
            guard let count = report["boundHeads"] as? Int, count > 0,
                  let poses = report["poses"] as? [[String: [Float]]], let first = poses.first else {
                print("Head diagnostic: \(report)")
                throw failure("Head joint is not bound")
            }
            return first
        }

        func checkBody(_ before: [String: [Float]], _ after: [String: [Float]], mustTurn: Bool) throws {
            var headDelta: Float = 0
            for (joint, values) in before {
                guard let current = after[joint], values.count == current.count else { throw failure("Joint set changed") }
                let difference = zip(values, current).map { abs($0 - $1) }.max() ?? 0
                if joint.split(separator: "/").last == "head" { headDelta = difference }
                else if difference > 0.00001 { throw failure("Cursor changed body joint \(joint)") }
            }
            if mustTurn && headDelta < 0.03 { throw failure("Head did not turn") }
            if !mustTurn && headDelta > 0.00001 { throw failure("Head failed to return to the authored neutral pose") }
            let pivot = controller.runtimeDiagnostics["pivot_rotation"] as? [Float]
            guard pivot == [0, 0, 0, 1] else { throw failure("Cursor rotated the body pivot") }
        }

        func capture(_ name: String) async throws {
            let image: NSImage = try await withCheckedThrowingContinuation { continuation in
                controller.arView.snapshot(saveToHDR: false) { image in
                    if let image { continuation.resume(returning: image) }
                    else { continuation.resume(throwing: NSError(domain: "CompanionQA", code: 2)) }
                }
            }
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { throw failure("No rendered PNG") }
            try png.write(to: output.appendingPathComponent("\(name).png"))
            records.append(["name": name, "diagnostics": controller.runtimeDiagnostics])
            let progress = try JSONSerialization.data(withJSONObject: ["status": "capturing", "frames": records], options: [.prettyPrinted, .sortedKeys])
            try progress.write(to: output.appendingPathComponent("manifest.json"))
            var visible = 0
            var clipped = false
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
                for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                    if let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.1,
                       (color.usingColorSpace(.deviceRGB)?.redComponent ?? 0) > 0.05 {
                        visible += 1
                        if x < 4 || y < 4 || x >= bitmap.pixelsWide - 4 || y >= bitmap.pixelsHigh - 4 { clipped = true }
                    }
                }
            }
            if visible < 100 { throw failure("Pet vanished in rendered frame \(name)") }
            if clipped { throw failure("Pet touches the window edge in \(name)") }
            print("Captured \(name)")
        }

        func checkPixels(species: String, direction: String) throws {
            let centerData = try Data(contentsOf: output.appendingPathComponent("\(species)-head-center.png"))
            let movedData = try Data(contentsOf: output.appendingPathComponent("\(species)-head-\(direction).png"))
            guard let center = NSBitmapImageRep(data: centerData), let moved = NSBitmapImageRep(data: movedData) else {
                throw failure("Cannot read rendered head comparison")
            }
            var headChanges = 0
            var bodyChanges = 0
            for y in stride(from: 0, to: center.pixelsHigh, by: 4) {
                for x in stride(from: 0, to: center.pixelsWide, by: 4) {
                    guard let a = center.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                          let b = moved.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    let difference = max(abs(a.redComponent - b.redComponent), abs(a.greenComponent - b.greenComponent),
                                         abs(a.blueComponent - b.blueComponent), abs(a.alphaComponent - b.alphaComponent))
                    if difference > 0.08 {
                        if y < center.pixelsHigh * 68 / 100 { headChanges += 1 }
                        else { bodyChanges += 1 }
                    }
                }
            }
            guard headChanges > 20 else { throw failure("Joint data changed but the rendered head did not") }
            guard bodyChanges < 100 else { throw failure("Cursor changed too many lower-body pixels: \(bodyChanges)") }
            print("Pixels \(species) \(direction): head=\(headChanges), lower-body=\(bodyChanges)")
        }

        func pause(_ seconds: Double) async throws { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
        func failure(_ message: String) -> NSError { NSError(domain: "CompanionQA", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
}
