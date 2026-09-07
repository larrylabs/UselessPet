import AppKit
import ApplicationServices
import RealityKit

/// Deterministic before/after and fractional-face captures through the real renderer.
@MainActor
enum HybridFaceQA {
    static func run(directory: String, speciesID: String = "mochi") {
        setbuf(stdout, nil)
        let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
        guard session["CGSSessionScreenIsLocked"] as? Bool != true else {
            print("Native render QA requires an unlocked Mac; no acceptance screenshots were captured.")
            exit(3)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let runner = Runner(output: URL(fileURLWithPath: directory), speciesID: speciesID)
        DispatchQueue.global().asyncAfter(deadline: .now() + 180) { exit(2) }
        Task { @MainActor in
            do { try await runner.run(); exit(0) }
            catch { print("Hybrid face QA failed: \(error)"); exit(1) }
        }
        withExtendedLifetime(runner) { app.run() }
    }

    @MainActor
    private final class Runner {
        let output: URL
        let speciesID: String
        let window = NSWindow(contentRect: .init(x: 100, y: 150, width: 400, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        var controller = Pet3DController()
        var records: [[String: Any]] = []
        init(output: URL, speciesID: String) { self.output = output; self.speciesID = speciesID }
        let states: [(String, NaraFacePose)] = [
            ("neutral", .init()),
            ("blink25", .init(blinkLeft: 0.25, blinkRight: 0.25)),
            ("blink50", .init(blinkLeft: 0.5, blinkRight: 0.5)),
            ("blink75", .init(blinkLeft: 0.75, blinkRight: 0.75)),
            ("closed", .init(blinkLeft: 1, blinkRight: 1)),
            ("wink-left", .init(blinkLeft: 1)), ("wink-right", .init(blinkRight: 1)),
            ("look-left", .init(gazeX: -1)), ("look-right", .init(gazeX: 1)),
            ("look-up", .init(gazeY: 1)), ("look-down", .init(gazeY: -1)),
            ("look-diagonal", .init(gazeX: 0.7, gazeY: 0.7)),
            ("look-diagonal-blink", .init(blinkLeft: 0.5, blinkRight: 0.5, gazeX: -0.7, gazeY: -0.7)),
            ("smile", .init(smile: 1)),
            ("smile-blink", .init(blinkLeft: 0.4, blinkRight: 0.4, smile: 1))
        ]
        func run() async throws {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            window.title = "\(speciesID.capitalized) face refinement QA"
            window.contentView = controller.arView
            window.orderFrontRegardless()
            let species = SpeciesCatalog.info(for: speciesID)
            for baseline in [true, false] {
                controller.qaUseBaselineAsset = baseline
                for angle in [-30, 0, 30] {
                    let selected = baseline ? [("neutral", NaraFacePose())] : states
                    for (name, pose) in selected {
                        controller.prepareSnapshot(species: species, expression: .neutral,
                                                   yaw: Float(angle) * .pi / 180)
                        controller.setFaceForQA(pose)
                        if !baseline && !controller.snapshotHasHybridFace { throw fail("Hybrid face was not loaded") }
                        try await pause(0.16)
                        try await capture("\(baseline ? "before" : "after")-\(name)-\(angle)")
                        if !baseline { try checkWeights(pose) }
                    }
                }
                // Same source rendering at the real 200-point desktop viewport.
                window.setContentSize(.init(width: 200, height: 200))
                for (name, pose) in baseline ? [("neutral", NaraFacePose())] : states {
                    controller.prepareSnapshot(species: species, expression: .neutral, yaw: 0)
                    controller.setFaceForQA(pose)
                    try await pause(0.12)
                    try await capture("desktop-\(baseline ? "before" : "after")-\(name)")
                }
                controller.shutdown()
                controller = Pet3DController()
                window.setContentSize(.init(width: 400, height: 400))
                window.contentView = controller.arView
            }
            // A smooth, deterministic face sequence captured through RealityKit.
            // One idle instance lets the eyelids and gaze move without rebuilds.
            window.setContentSize(.init(width: 400, height: 400))
            controller.prepareSnapshot(species: species, expression: .neutral, yaw: 0)
            for frame in 0..<180 {
                let t = Double(frame) / 30
                let blink = max(NaraBlinkCurve.value(at: t - 0.6), NaraBlinkCurve.value(at: t - 4.7))
                let gaze = Float(sin(t * .pi / 3)) * 0.8
                let wink = Float(max(0, 1 - abs(t - 3.3) / 0.3))
                let pose = NaraFacePose(blinkLeft: max(blink, wink), blinkRight: blink,
                                        gazeX: gaze, gazeY: Float(sin(t * .pi / 1.5)) * 0.25,
                                        smile: Float(max(0, sin(t * .pi / 6))) * 0.5)
                controller.setFaceForQA(pose)
                try await pause(0.035)
                try await capture(String(format: "motion-%03d", frame))
                try checkWeights(pose)
            }
            try JSONSerialization.data(withJSONObject: ["status":"passed", "frames":records], options:[.prettyPrinted,.sortedKeys])
                .write(to: output.appendingPathComponent("manifest.json"))
            controller.shutdown()
            window.orderOut(nil)
            print("Hybrid face QA passed: source baseline, fractional lids, independent eyes, diagonal gaze, smiles and desktop size")
        }
        func checkWeights(_ expected: NaraFacePose) throws {
            guard let imported = controller.runtimeDiagnostics["imported_weights"] as? [String: Float], !imported.isEmpty else {
                throw fail("No imported face weights")
            }
            var mapped: [String: Float] = [:]
            for (name, value) in imported { if let target = NaraFacePose.target(for: name) { mapped[target] = value } }
            for (key, value) in expected.weights {
                guard let actual = mapped[key], abs(actual - value) < 0.0001 else { throw fail("Incorrect facial channel \(key)") }
            }
        }
        func capture(_ name: String) async throws {
            let image: NSImage = try await withCheckedThrowingContinuation { continuation in
                controller.arView.snapshot(saveToHDR: false) { image in
                    if let image { continuation.resume(returning: image) }
                    else { continuation.resume(throwing: self.fail("Missing render")) }
                }
            }
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data:tiff),
                  let png = bitmap.representation(using:.png,properties:[:]) else { throw fail("Missing PNG") }
            try png.write(to:output.appendingPathComponent(name+".png"))
            records.append(["name":name,"width":bitmap.pixelsWide,"height":bitmap.pixelsHigh,
                            "diagnostics":controller.runtimeDiagnostics])
            print("Captured \(name)")
        }
        func pause(_ seconds: Double) async throws { try await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000)) }
        func fail(_ message:String) -> NSError { NSError(domain:"HybridFaceQA",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
    }
}
