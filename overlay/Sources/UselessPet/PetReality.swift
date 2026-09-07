import AppKit
import Combine
import CoreGraphics
import RealityKit
import SwiftUI
import simd

// MARK: - Procedural body plan

/// How a species' procedural creature is assembled. Derived from the stat
/// family so each pet reads differently even with zero bundled art.
private enum EarKind { case none, round, tall, pointy }

private struct PetBodyPlan {
    var body: NSColor
    var belly: NSColor
    var accent: NSColor
    var ears: EarKind
    var antennae: Bool
    var tail: Bool
    var squash: Float          // vertical scale of the body sphere (1 = round)
    var metallic: Float

    static func plan(for species: SpeciesInfo) -> PetBodyPlan {
        let tint = species.nsTint
        let belly = tint.blended(to: .white, fraction: 0.62)
        let accent = tint.blended(to: .black, fraction: 0.34)

        switch species.family {
        case "debugging":
            // Ladybug / frog energy — antennae, round body, no ears.
            return PetBodyPlan(body: tint, belly: belly, accent: accent,
                               ears: .none, antennae: true, tail: false,
                               squash: 0.92, metallic: 0.0)
        case "wisdom":
            return PetBodyPlan(body: tint, belly: belly, accent: accent,
                               ears: .round, antennae: false, tail: false,
                               squash: 0.96, metallic: 0.0)
        case "creativity":
            return PetBodyPlan(body: tint, belly: belly, accent: accent,
                               ears: .pointy, antennae: false, tail: false,
                               squash: 0.94, metallic: 0.0)
        case "speed":
            // Long ears — hare / shiba / pingu.
            return PetBodyPlan(body: tint, belly: belly, accent: accent,
                               ears: .tall, antennae: false, tail: false,
                               squash: 1.04, metallic: 0.0)
        case "chaos":
            // Slime / mecha — flatter blob, a metallic sheen, single accent spike.
            return PetBodyPlan(body: tint, belly: belly, accent: accent,
                               ears: .none, antennae: true, tail: false,
                               squash: 0.80, metallic: 0.45)
        case "curiosity":
            // Fox / bunny — pointy ears plus a tail.
            return PetBodyPlan(body: tint, belly: belly, accent: accent,
                               ears: .pointy, antennae: false, tail: true,
                               squash: 0.95, metallic: 0.0)
        default:
            return PetBodyPlan(body: tint, belly: belly, accent: accent,
                               ears: .round, antennae: false, tail: false,
                               squash: 0.95, metallic: 0.0)
        }
    }
}

// MARK: - Facial expressions (2.5D face decal)

/// The pet's face is a flat decal plane on the front of the head. Each emotion
/// is a texture **drawn procedurally with Core Graphics** (zero art assets),
/// cached once per (species, expression) and swapped at runtime.
@available(macOS 14.0, *)
enum PetExpression: String, CaseIterable {
    case neutral, happy, surprised, star, dizzy, sad, sleepy, blink, eat
}

/// Per-character facial styling so each of the four friends keeps their
/// reference-sheet identity across every expression.
@available(macOS 14.0, *)
struct FaceStyle {
    var eyeRadius: CGFloat = 17     // base eye size
    var eyeSquash: CGFloat = 1.25   // vertical eye stretch
    var eyeSpacing: CGFloat = 76    // gap between eye centers
    var eyeHeight: CGFloat = 118    // eye row (canvas is 256x196, origin bottom-left)
    var brows = false               // short brow strokes above the eyes
    var browTilt: CGFloat = 0       // >0 = playful raised outer brow
    var whiskers = false            // three light whiskers per side
    var whiskerColor = CGColor(srgbRed: 0.92, green: 0.92, blue: 0.95, alpha: 0.9)
    var winkHappy = false           // happy closes one eye
    var blushScale: CGFloat = 1.0
    var blushColor = CGColor(srgbRed: 1.0, green: 0.46, blue: 0.5, alpha: 0.42)
    var mouthY: CGFloat = 64
    /// Canvas width in px (height is fixed at 196). Must match the petFace
    /// plane's aspect ratio or the decal stretches: width = 196 * (w / h).
    var canvasWidth: Int = 256
    /// Big drawn nose between the eyes and mouth . 0 = no nose.
    var noseScale: CGFloat = 0

    static func style(for speciesId: String) -> FaceStyle {
        switch speciesId {
        case "nara":
            var s = FaceStyle()
            s.eyeRadius = 14          // smaller eyes
            s.eyeSquash = 1.3
            s.eyeSpacing = 72         // closer together
            s.eyeHeight = 125         // slightly higher up on the canvas
            s.brows = true
            s.browTilt = 0
            s.blushScale = 1.2
            s.mouthY = 70             // move mouth up slightly
            return s
        default:
            return FaceStyle()
        }
    }
}

@available(macOS 14.0, *)
enum FaceTextureFactory {
    private static var cache: [String: TextureResource] = [:]

    static func texture(for e: PetExpression, species: String) -> TextureResource? {
        let key = "\(species)|\(e.rawValue)"
        if let t = cache[key] { return t }
        guard let cg = render(e, style: FaceStyle.style(for: species)),
            let t = try? TextureResource.generate(from: cg, options: .init(semantic: .color))
        else { return nil }
        cache[key] = t
        return t
    }

    /// Testable entry to the pure decal renderer (no RealityKit / Metal).
    static func renderFace(_ e: PetExpression, species: String) -> CGImage? {
        render(e, style: FaceStyle.style(for: species))
    }

    /// QA hook: write every (species, expression) face texture as PNG so the
    /// asset pipeline can eyeball decal layouts without launching the UI.
    /// Triggered by USELESSPET_DUMP_FACES=<dir> at app startup.
    static func dumpAll(to dir: String) {
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        for species in SpeciesCatalog.pickableIds {
            for e in PetExpression.allCases {
                guard let cg = render(e, style: FaceStyle.style(for: species)) else { continue }
                let rep = NSBitmapImageRep(cgImage: cg)
                guard let png = rep.representation(using: .png, properties: [:]) else { continue }
                let url = URL(fileURLWithPath: dir)
                    .appendingPathComponent("\(species)_\(e.rawValue).png")
                try? png.write(to: url)
            }
        }
        print("FaceTextureFactory: dumped faces to \(dir)")
    }

    // Canvas (Core Graphics origin is bottom-left). Width varies per style.
    private static let H = 196
    private static let ink = CGColor(srgbRed: 0.13, green: 0.13, blue: 0.17, alpha: 1)
    private static let glintCol = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95)
    private static let tongueCol = CGColor(srgbRed: 0.95, green: 0.42, blue: 0.52, alpha: 1)

    private static func render(_ e: PetExpression, style: FaceStyle) -> CGImage? {
        let w = style.canvasWidth
        guard let ctx = CGContext(
            data: nil, width: w, height: H, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: H))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let cx = CGFloat(w) / 2
        let eyeL = CGPoint(x: cx - style.eyeSpacing / 2, y: style.eyeHeight)
        let eyeR = CGPoint(x: cx + style.eyeSpacing / 2, y: style.eyeHeight)
        let mouth = CGPoint(x: cx, y: style.mouthY)
        let f = Face(ctx: ctx, style: style, eyeL: eyeL, eyeR: eyeR, mouth: mouth)

        switch e {
        case .neutral:
            f.roundEyes(r: style.eyeRadius, squashY: style.eyeSquash, glint: true)
            f.brows(); f.whiskers(); f.nose(); f.cheeks()
            f.smile(width: 34, depth: 12, thickness: 7)
        case .happy:
            f.roundEyes(r: style.eyeRadius * 1.1, squashY: style.eyeSquash * 0.95,
                        glint: true, winkRight: style.winkHappy)
            f.brows(); f.whiskers(); f.nose(); f.cheeks()
            f.smile(width: 46, depth: 20, thickness: 8)
        case .eat:
            f.arcEyes(droopy: false)
            f.whiskers(); f.nose(); f.cheeks()
            f.openMouth(w: 34, h: 30, tongue: true)
        case .surprised:
            f.roundEyes(r: style.eyeRadius * 1.25, squashY: 1.0, glint: true)
            f.brows(lift: 8); f.whiskers(); f.nose()
            f.openMouth(w: 22, h: 24, tongue: false)
        case .star:
            f.starEyes(); f.whiskers(); f.nose(); f.cheeks()
            f.smile(width: 44, depth: 20, thickness: 8)
        case .dizzy:
            f.crossEyes(); f.whiskers(); f.nose(); f.wavyMouth()
        case .sad:
            f.arcEyes(droopy: true); f.brows(lift: -6)
            f.whiskers(); f.nose(); f.frown(); f.tear()
        case .sleepy:
            f.arcEyes(droopy: true); f.whiskers(); f.nose()
            f.smile(width: 20, depth: 6, thickness: 6)
        case .blink:
            f.blinkEyes(); f.whiskers(); f.nose()
            f.smile(width: 30, depth: 10, thickness: 7)
        }
        return ctx.makeImage()
    }

    /// Feature painter bound to one canvas + style.
    private struct Face {
        let ctx: CGContext
        let style: FaceStyle
        let eyeL: CGPoint
        let eyeR: CGPoint
        let mouth: CGPoint

        func roundEyes(r: CGFloat, squashY: CGFloat, glint: Bool, winkRight: Bool = false) {
            ctx.setFillColor(ink)
            let open = winkRight ? [eyeL] : [eyeL, eyeR]
            for c in open {
                ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r * squashY, width: r * 2, height: r * 2 * squashY))
            }
            if glint {
                ctx.setFillColor(glintCol)
                for c in open {
                    ctx.fillEllipse(in: CGRect(x: c.x - r * 0.05, y: c.y + r * 0.3, width: r * 0.7, height: r * 0.7))
                }
            }
            if winkRight {
                // Closed happy eye: a ^ arc.
                ctx.setStrokeColor(ink); ctx.setLineWidth(8)
                let w = r * 0.95
                let p = CGMutablePath()
                p.move(to: CGPoint(x: eyeR.x - w, y: eyeR.y - 4))
                p.addQuadCurve(to: CGPoint(x: eyeR.x + w, y: eyeR.y - 4),
                               control: CGPoint(x: eyeR.x, y: eyeR.y + r * 0.9))
                ctx.addPath(p); ctx.strokePath()
            }
        }

        func arcEyes(droopy: Bool) {
            ctx.setStrokeColor(ink); ctx.setLineWidth(8)
            let w = max(18, style.eyeRadius * 1.2)
            for c in [eyeL, eyeR] {
                let p = CGMutablePath()
                if droopy {
                    p.move(to: CGPoint(x: c.x - w, y: c.y + 6))
                    p.addQuadCurve(to: CGPoint(x: c.x + w, y: c.y + 6), control: CGPoint(x: c.x, y: c.y - 14))
                } else {
                    p.move(to: CGPoint(x: c.x - w, y: c.y - 6))
                    p.addQuadCurve(to: CGPoint(x: c.x + w, y: c.y - 6), control: CGPoint(x: c.x, y: c.y + 16))
                }
                ctx.addPath(p); ctx.strokePath()
            }
        }

        func blinkEyes() {
            ctx.setStrokeColor(ink); ctx.setLineWidth(8)
            let w = max(18, style.eyeRadius * 1.1)
            for c in [eyeL, eyeR] {
                ctx.move(to: CGPoint(x: c.x - w, y: c.y))
                ctx.addLine(to: CGPoint(x: c.x + w, y: c.y))
            }
            ctx.strokePath()
        }

        func crossEyes() {
            ctx.setStrokeColor(ink); ctx.setLineWidth(7)
            for c in [eyeL, eyeR] {
                ctx.move(to: CGPoint(x: c.x - 16, y: c.y - 16)); ctx.addLine(to: CGPoint(x: c.x + 16, y: c.y + 16))
                ctx.move(to: CGPoint(x: c.x - 16, y: c.y + 16)); ctx.addLine(to: CGPoint(x: c.x + 16, y: c.y - 16))
            }
            ctx.strokePath()
        }

        func starEyes() {
            ctx.setFillColor(ink)
            for c in [eyeL, eyeR] {
                let path = CGMutablePath()
                for i in 0..<10 {
                    let radius = max(20, style.eyeRadius * 1.2) * (i.isMultiple(of: 2) ? 1 : 0.45)
                    let angle = CGFloat(i) * .pi / 5 - .pi / 2
                    let point = CGPoint(x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius)
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath(); ctx.addPath(path); ctx.fillPath()
            }
        }

        func wavyMouth() {
            ctx.setStrokeColor(ink); ctx.setLineWidth(6)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: mouth.x - 22, y: mouth.y))
            path.addCurve(to: CGPoint(x: mouth.x + 22, y: mouth.y),
                          control1: CGPoint(x: mouth.x - 6, y: mouth.y + 12),
                          control2: CGPoint(x: mouth.x + 6, y: mouth.y - 12))
            ctx.addPath(path); ctx.strokePath()
        }

        func brows(lift: CGFloat = 0) {
            guard style.brows else { return }
            ctx.setStrokeColor(ink); ctx.setLineWidth(7)
            let y = style.eyeHeight + style.eyeRadius * style.eyeSquash + 16 + lift
            let w: CGFloat = 16
            for (c, side) in [(eyeL, CGFloat(-1)), (eyeR, CGFloat(1))] {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: c.x - w, y: y - side * style.browTilt * 0))
                p.addQuadCurve(
                    to: CGPoint(x: c.x + w, y: y + (side > 0 ? -1 : 1) * 0),
                    control: CGPoint(x: c.x, y: y + 7 + style.browTilt))
                ctx.addPath(p); ctx.strokePath()
            }
        }

        func whiskers() {
            guard style.whiskers else { return }
            ctx.setStrokeColor(style.whiskerColor); ctx.setLineWidth(4)
            let baseY = style.eyeHeight - 24
            let cx = (eyeL.x + eyeR.x) / 2
            for side: CGFloat in [-1, 1] {
                let xIn = cx + side * 86
                let xOut = cx + side * (cx - 10)   // reach almost to the canvas edge
                for (i, dy) in [14, 0, -14].enumerated() {
                    let p = CGMutablePath()
                    p.move(to: CGPoint(x: xIn, y: baseY + CGFloat(dy)))
                    p.addQuadCurve(
                        to: CGPoint(x: xOut, y: baseY + CGFloat(dy) + CGFloat(6 - i * 6)),
                        control: CGPoint(x: (xIn + xOut) / 2, y: baseY + CGFloat(dy) + 8))
                    ctx.addPath(p); ctx.strokePath()
                }
            }
        }

        func nose() {
            guard style.noseScale > 0 else { return }
            let w = 42 * style.noseScale
            let h = 30 * style.noseScale
            let cy = style.mouthY + (style.eyeHeight - style.mouthY) * 0.40
            let c = CGPoint(x: (eyeL.x + eyeR.x) / 2, y: cy)
            ctx.setFillColor(ink)
            ctx.fillEllipse(in: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
            ctx.setFillColor(glintCol)
            ctx.fillEllipse(in: CGRect(x: c.x - w * 0.28, y: c.y + h * 0.08, width: w * 0.22, height: h * 0.22))
        }

        func cheeks(scale: CGFloat = 1.0) {
            ctx.setFillColor(style.blushColor)
            let w = 34 * style.blushScale * scale
            let h = 22 * style.blushScale * scale
            ctx.fillEllipse(in: CGRect(x: eyeL.x - style.eyeRadius - w * 0.7, y: 78, width: w, height: h))
            ctx.fillEllipse(in: CGRect(x: eyeR.x + style.eyeRadius - w * 0.3, y: 78, width: w, height: h))
        }

        func smile(width: CGFloat, depth: CGFloat, thickness: CGFloat) {
            ctx.setStrokeColor(ink); ctx.setLineWidth(thickness)
            let p = CGMutablePath()
            p.move(to: CGPoint(x: mouth.x - width / 2, y: mouth.y + depth * 0.3))
            p.addQuadCurve(to: CGPoint(x: mouth.x + width / 2, y: mouth.y + depth * 0.3),
                control: CGPoint(x: mouth.x, y: mouth.y - depth))
            ctx.addPath(p); ctx.strokePath()
        }

        func frown() {
            ctx.setStrokeColor(ink); ctx.setLineWidth(7)
            let p = CGMutablePath()
            p.move(to: CGPoint(x: mouth.x - 16, y: mouth.y - 6))
            p.addQuadCurve(to: CGPoint(x: mouth.x + 16, y: mouth.y - 6), control: CGPoint(x: mouth.x, y: mouth.y + 12))
            ctx.addPath(p); ctx.strokePath()
        }

        func openMouth(w: CGFloat, h: CGFloat, tongue: Bool) {
            ctx.setFillColor(ink)
            ctx.fillEllipse(in: CGRect(x: mouth.x - w / 2, y: mouth.y - h / 2, width: w, height: h))
            if tongue {
                ctx.setFillColor(tongueCol)
                ctx.fillEllipse(in: CGRect(x: mouth.x - w * 0.3, y: mouth.y - h / 2, width: w * 0.6, height: h * 0.5))
            }
        }

        func tear() {
            ctx.setFillColor(CGColor(srgbRed: 0.4, green: 0.7, blue: 1.0, alpha: 0.85))
            ctx.fillEllipse(in: CGRect(x: eyeL.x - 6, y: eyeL.y - 42, width: 12, height: 18))
        }
    }
}

/// Expression textures for baked-face characters (Rodin-generated models).
/// Instead of a petFace decal, every expression is a full pre-baked variant of
/// the model's base texture (built by scripts/blender/mochi_faces.py) that
/// gets swapped onto the body material at runtime.
@available(macOS 14.0, *)
enum BakedFaceTextureFactory {
    private static var cache: [String: TextureResource] = [:]
    private static let aliases: [PetExpression: PetExpression] = [
        .eat: .happy,
        .sleepy: .blink,
    ]
    /// Whether a dedicated baked PNG for this exact expression ships in the
    /// bundle (no alias/reuse fallback). Metal-free → lets QA/tests confirm the
    /// pilot art actually shipped without building a `TextureResource`.
    static func hasDedicatedFace(_ e: PetExpression, species: String) -> Bool {
        Bundle.uselesspetResources.url(forResource: "\(species)_face_\(e.rawValue)",
                          withExtension: "png") != nil
    }

    static func texture(for e: PetExpression, species: String) -> TextureResource? {
        // Dedicated natural expression art, followed by eat/sleep aliases.
        if let t = load(e, species: species) { return t }
        if let a = aliases[e], let t = load(a, species: species) { return t }
        NSLog("UselessPet bakedFace: no texture for %@_face_%@", species, e.rawValue)
        // Missing art must restore the source face, not strand the last emotion.
        return e == .neutral ? nil : load(.neutral, species: species)
    }

    private static func load(_ e: PetExpression, species: String) -> TextureResource? {
        let key = "\(species)|\(e.rawValue)"
        if let t = cache[key] { return t }
        guard let url = Bundle.uselesspetResources.url(
                forResource: "\(species)_face_\(e.rawValue)", withExtension: "png"),
            let t = try? TextureResource.load(
                contentsOf: url, options: .init(semantic: .color))
        else { return nil }
        cache[key] = t
        return t
    }
}

// MARK: - Click-through ARView

/// ARView that renders the pet but is invisible to the mouse: `hitTest` returns
/// nil so left-drags fall through to the panel (`isMovableByWindowBackground`)
/// and right-clicks reach SwiftUI's `.contextMenu`, exactly like the 2D sprite.
@available(macOS 14.0, *)
final class PetARView: ARView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var mouseDownCanMoveWindow: Bool { true }
    override var acceptsFirstResponder: Bool { false }
}

// MARK: - 3D controller

/// Owns the RealityKit entity graph and drives idle + per-event motion.
///
/// Hierarchy:
///   anchor → pivot → creature
/// `pivot` carries the continuous idle pose (bob + gentle look-around + mood
/// scale), updated every frame. `creature` carries discrete event animations
/// (nibbles, hops, leaps, wobbles) via `move(to:)`, so events never fight the
/// idle loop — they simply ride on top of it.
@available(macOS 14.0, *)
@MainActor
final class Pet3DController {
    let arView: PetARView

    private let anchor = AnchorEntity(world: .zero)
    private let pivot = Entity()
    private var creature = Entity()
    private var animationCarrier = Entity()
    private var snapshotPlayback: AnimationPlaybackController?
    private var skeletalPlayback: AnimationPlaybackController?
    private var hybridAsset: HybridPetAsset?
    private var naraTimeline: NaraPresentationTimeline?
    private var naraFaceAnimator = NaraFaceAnimator()
    private var naraPresentation: NaraPresentation?
    private var naraRenderedFace = NaraFacePose()
    private var playbackStarts = 0
    private var rebuildCount = 0
    private var renderedFrames = 0
    private var renderedSeconds: TimeInterval = 0
    private var maximumFrameGap: TimeInterval = 0
    private var frameGapsOver100ms = 0
    /// Synthetic cursor input for the isolated production-renderer QA only.
    var qaGaze: SIMD2<Float>?

    private var idleSub: Cancellable?
    private var headSub: Cancellable?
    private var headLook: PetHeadLook?

    // Idle drivers.
    private var bobPhase: Float = 0
    private var swayPhase: Float = 1.3
    private var moodScale: Float = 1.0       // target from mood band
    private var renderedScale: Float = 1.0   // eased toward moodScale
    /// User-chosen size from the popover slider (0.5...1.0), on top of the
    /// mood scale. 1.0 = the pet fills the 200pt viewport as before.
    var userScale: Float = 1.0
    /// Popover toggle: when false the gaze eases back to center instead of
    /// tracking the mouse (some users find the constant stare distracting).
    var followsCursor: Bool = true
    private var bobAmp: Float = 0.008
    private var moodYOffset: Float = 0
    private var lookYaw: Float = 0           // eased toward cursor direction
    private var lookPitch: Float = 0

    // Face / expression layer. The decal lives at `faceMaterialIndex` inside
    // `faceCarrier`'s ModelComponent: procedural pets use a dedicated petFace
    // mesh (index 0); skinned usdz pets merge all submeshes into the SkelRoot's
    // single ModelComponent, so the face is one material slot among the body's.
    private var faceCarrier: Entity?
    private var faceMaterialIndex: Int = 0
    private var usesBakedFace = false
    private var currentExpression: PetExpression = .neutral
    private var baseExpression: PetExpression = .neutral   // resting face from mood/hunger
    private var framesUntilBlink = 140
    private var blinkFramesLeft = 0
    private var playingEvent = false
    private var companionReaction: CompanionReaction?
    private var companionReactionTime: TimeInterval = 0
    private var lastCompanionInput: BridgeClient.TransientEvent?
    private var reactionReducesMotion = false

    // Skeletal clip layer (authored .usdz pets; empty for procedural creatures).
    private var clipLibrary: [String: AnimationResource] = [:]
    private var currentAmbientClip: String?
    private var currentMood: MoodBand = .neutral
    private var currentHunger: HungerBand = .content
    private var currentActivity: ActivityState = .idle

    /// Authored clip lengths in seconds (24 fps source). Used to time the
    /// return to the ambient loop, mirroring the transform-path choreography.
    private static let clipDurations: [String: Double] = [
        "idle": 2.0, "eat": 1.5, "play": 1.67,
        "celebrate": 2.0, "sad": 2.0, "sleep": 3.0,
    ]

    /// How long the reaction face stays on AFTER the event action finishes
    /// (total reaction ≈ clip 1.5–3 s + linger ≈ 7–8.5 s) before easing back
    /// to the neutral resting face.

    // Last-applied inputs (so `update` only reacts to real changes).
    private var currentSpeciesId: String?
    private var lastTransient: BridgeClient.TransientEvent?

    init() {
        let view = PetARView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        view.environment.background = .color(.clear)
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = .clear
        self.arView = view

        // Camera, framed head-on.
        let cam = PerspectiveCamera()
        cam.camera.fieldOfViewInDegrees = 38
        cam.position = [0, 0.01, 0.62]
        anchor.addChild(cam)

        // Three-point-ish lighting for soft, toy-like shading.
        let key = DirectionalLight()
        key.light.intensity = 1700
        key.look(at: .zero, from: [0.5, 0.7, 1.0], relativeTo: nil)
        anchor.addChild(key)

        let fill = DirectionalLight()
        fill.light.intensity = 600
        fill.look(at: .zero, from: [-0.8, 0.1, 0.6], relativeTo: nil)
        anchor.addChild(fill)

        let rim = DirectionalLight()
        rim.light.intensity = 400
        rim.look(at: .zero, from: [0, 0.4, -1.0], relativeTo: nil)
        anchor.addChild(rim)

        anchor.addChild(pivot)
        arView.scene.addAnchor(anchor)
        headSub = arView.scene.subscribe(to: AnimationEvents.SkeletalPoseUpdateComplete.self) { [weak self] _ in
            guard let self else { return }
            self.headLook?.apply(yaw: self.lookYaw, pitch: self.lookPitch)
        }

        // QA hook: USELESSPET_SNAPSHOT_DIR=<dir> saves a frame every 2 s — lets the
        // asset pipeline verify clips/expressions without screen recording.
        if let dir = ProcessInfo.processInfo.environment["USELESSPET_SNAPSHOT_DIR"] {
            startSnapshotLoop(dir: dir)
        }
    }

    private func startSnapshotLoop(dir: String) {
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        NSLog("UselessPet snapshot loop armed, dir=%@", dir)
        Task { @MainActor [weak self] in
            for i in 0..<300 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self else { return }
                self.arView.snapshot(saveToHDR: false) { image in
                    guard let image,
                          let tiff = image.tiffRepresentation,
                          let rep = NSBitmapImageRep(data: tiff),
                          let png = rep.representation(using: .png, properties: [:])
                    else {
                        NSLog("UselessPet snapshot %d: no image", i)
                        return
                    }
                    let url = URL(fileURLWithPath: dir)
                        .appendingPathComponent(String(format: "snap_%03d.png", i))
                    do {
                        try png.write(to: url)
                        NSLog("UselessPet snapshot %d: saved %@", i, url.lastPathComponent)
                    } catch {
                        NSLog("UselessPet snapshot %d: write failed %@", i, "\(error)")
                    }
                }
            }
        }
    }

    // MARK: lifecycle

    /// Deterministic asset QA through the production renderer, with no daemon.
    func prepareSnapshot(species: SpeciesInfo, expression: PetExpression, yaw: Float, clip: String? = nil) {
        idleSub?.cancel()
        followsCursor = false
        currentExpression = expression
        if currentSpeciesId != species.id { rebuild(for: species, animated: false) }
        creature.stopAllAnimations(recursive: true)
        snapshotPlayback = nil
        applyFaceTexture(expression)
        pivot.transform = Transform(rotation: simd_quatf(angle: yaw, axis: [0, 1, 0]))
        if let clip, let animation = clipLibrary[clip] {
            let playback = animationCarrier.playAnimation(animation, transitionDuration: 0, startsPaused: false)
            snapshotPlayback = playback
        }
    }

    func setFaceForQA(_ pose: NaraFacePose) {
        idleSub?.cancel()
        creature.stopAllAnimations(recursive: true)
        snapshotPlayback?.stop()
        skeletalPlayback?.stop()
        hybridAsset?.faceRig.apply(pose)
        naraRenderedFace = pose
    }
    var qaUseBaselineAsset = false
    var snapshotHasHybridFace: Bool { hybridAsset != nil }

    var snapshotHasBoundFace: Bool { hybridAsset != nil || (usesBakedFace && faceCarrier != nil) }
    var snapshotHasAllClips: Bool { Set(clipLibrary.keys) == Set(Self.clipDurations.keys) }
    func pauseSnapshotAnimation() {
        if let playback = snapshotPlayback {
            NSLog("UselessPet QA animation: time=%f playing=%@",
                  playback.time, playback.isPlaying ? "yes" : "no")
            playback.pause()
        }
    }

    /// First-time setup: build the creature and start the idle loop.
    func bootstrap(species: SpeciesInfo, mood: MoodBand, hunger: HungerBand,
                   activity: ActivityState = .idle) {
        currentActivity = activity
        applyMood(mood)
        currentHunger = hunger
        baseExpression = Self.restingExpression(activity: currentActivity)
        currentExpression = baseExpression
        renderedScale = moodScale
        rebuild(for: species, animated: false)
        startIdleLoop()
    }

    /// Called on every SwiftUI update; only acts on genuine changes.
    func update(species: SpeciesInfo, mood: MoodBand, hunger: HungerBand,
                transient: BridgeClient.TransientEvent?, activity: ActivityState) {
        if activity != currentActivity {
            currentActivity = activity
            // Log the state change only; the actual base-clip swap (and any
            // fallback) is logged in startAmbientClip when it really happens —
            // which may be deferred while a transient reaction is playing.
            NSLog("UselessPet activity: %@", activity.rawValue)
        }
        applyMood(mood)
        currentHunger = hunger
        baseExpression = Self.restingExpression(activity: currentActivity)

        if species.id != currentSpeciesId {
            rebuild(for: species, animated: true)
        }

        if transient != lastCompanionInput {
            lastCompanionInput = transient
            if case .petted(_, let reaction) = transient {
                beginCompanionReaction(reaction)
                return
            } else if transient != nil {
                companionReaction = nil
            }
        }
        if companionReaction != nil { return }

        if var timeline = naraTimeline {
            timeline.receive(activity: activity, mood: mood, hunger: hunger, transient: transient)
            naraTimeline = timeline
            synchronizeNaraPresentation()
            return
        }

        if transient != lastTransient {
            lastTransient = transient
            if transient == nil { settleToIdle() }
        } else if !playingEvent {
            if currentExpression != baseExpression {
                // Mood / hunger shifted while idle → refresh the resting face.
                setExpression(baseExpression)
            }
            if ambientClipName() != currentAmbientClip {
                // Mood / hunger band moved → swap the ambient skeletal loop.
                startAmbientClip()
            }
        }
    }

    private func applyMood(_ mood: MoodBand) {
        currentMood = mood
        switch mood {
        case .happy:   moodScale = 1.05; bobAmp = 0.012; moodYOffset = 0.004
        case .neutral: moodScale = 1.00; bobAmp = 0.008; moodYOffset = 0
        case .sad:     moodScale = 0.94; bobAmp = 0.003; moodYOffset = -0.018
        }
    }

    /// Working activities share the modeled resting face; natural emotions
    /// remain available for sleep, success, attention, and error states.
    private static func restingExpression(activity: ActivityState) -> PetExpression {
        PetActivityMap.expression(for: activity)
    }

    // MARK: expression swapping

    private func setExpression(_ e: PetExpression) {
        if e != currentExpression {
            NSLog("UselessPet expression: %@", e.rawValue)
        }
        currentExpression = e
        if hybridAsset == nil { applyFaceTexture(e) }
    }

    /// Species whose expressions are baked whole-texture variants (no decal).
    static let bakedFaceSpecies: Set<String> = ["nara", "mochi", "pando", "lumi"]

    /// Swap the face texture (used for both expressions and blinks).
    /// Decal species retexture the transparent petFace slot; baked-face
    /// species swap the body material's entire base texture. Both arrive as
    /// UnlitMaterial: decals so they never pick up shading seams, baked
    /// textures because Rodin's "shaded" maps already contain their lighting.
    private func applyFaceTexture(_ e: PetExpression) {
        if let asset = hybridAsset {
            // Used by the paused face QA. The live path eases the same target
            // through NaraFaceAnimator on each RealityKit update.
            asset.faceRig.apply(.expression(e))
            return
        }
        let species = currentSpeciesId ?? "nara"
        let baked = usesBakedFace
        guard let carrier = faceCarrier,
              let tex = baked
                  ? BakedFaceTextureFactory.texture(for: e, species: species)
                  : FaceTextureFactory.texture(for: e, species: species),
              var model = carrier.components[ModelComponent.self],
              model.materials.indices.contains(faceMaterialIndex) else { return }
        var mat = UnlitMaterial()
        if species == "nara", baked {
            // The source already has baked lighting. Preserve its display colors
            // instead of applying a second tone curve (Nara fidelity pilot only).
            if #available(macOS 15.0, *) {
                mat = UnlitMaterial(applyPostProcessToneMap: false)
            }
        }
        mat.color = .init(tint: .white, texture: .init(tex))
        if !baked {
            mat.blending = .transparent(opacity: 1.0)
        }
        model.materials[faceMaterialIndex] = mat
        carrier.components.set(model)
    }

    // MARK: build

    private func rebuild(for species: SpeciesInfo, animated: Bool) {
        playingEvent = false
        companionReaction = nil
        companionReactionTime = 0
        lastCompanionInput = nil
        lastTransient = nil
        snapshotPlayback?.stop()
        snapshotPlayback = nil
        skeletalPlayback?.stop()
        skeletalPlayback = nil
        creature.stopAllAnimations(recursive: true)
        hybridAsset = nil
        naraTimeline = nil
        naraPresentation = nil
        naraFaceAnimator = NaraFaceAnimator()
        naraRenderedFace = .init()
        framesUntilBlink = 140
        blinkFramesLeft = 0
        rebuildCount += 1
        currentSpeciesId = species.id
        creature.removeFromParent()

        let loaded = Self.loadBundledModel(species, allowHybrid: !qaUseBaselineAsset)
        hybridAsset = loaded?.hybrid
        clipLibrary = loaded?.clips ?? [:]
        currentAmbientClip = nil
        let built = loaded?.entity
            ?? Self.buildProcedural(PetBodyPlan.plan(for: species), speciesId: species.id)
        creature = built
        // Direct skeletal clips bind to the mesh-bearing Rig, not a display
        // wrapper or an imported scene timeline. Other pets retain their route.
        animationCarrier = hybridAsset != nil ? (loaded?.animationEntity ?? built) : built
        creature.transform = .identity
        pivot.addChild(creature)
        headLook = PetHeadLook(root: creature)
        if hybridAsset != nil {
            naraTimeline = NaraPresentationTimeline(activity: currentActivity, mood: currentMood,
                hunger: currentHunger, durations: clipLibrary.mapValues { $0.definition.duration })
            currentExpression = naraTimeline!.presentation.expression
            naraFaceAnimator = NaraFaceAnimator(expression: currentExpression)
        } else {
            currentExpression = baseExpression
        }

        // Both procedural creatures and authored .usdz models expose a "petFace"
        // mesh for the expression decal; faceCarrier stays nil if absent and the
        // expression code guards on it. Baked-face species have no petFace at
        // all — their "face slot" is the body's whole material.
        // Choose the route from what actually loaded. A procedural fallback
        // needs a transparent decal, never a whole-body UV atlas.
        usesBakedFace = loaded != nil && hybridAsset == nil && Self.bakedFaceSpecies.contains(species.id)
        let faceSlot = usesBakedFace
            ? Self.bodyFaceSlot(in: creature, species: species.id)
            : Self.findFaceSlot(in: creature)
        faceCarrier = faceSlot?.carrier
        faceMaterialIndex = faceSlot?.index ?? 0
        applyFaceTexture(currentExpression)
        startAmbientClip()
        NSLog(
            "UselessPet rebuild %@: source=%@ clips=%d face=%@ ambient=%@",
            species.id, loaded == nil ? "procedural" : "usdz",
            clipLibrary.count,
            faceCarrier == nil ? "absent" : "slot \(faceMaterialIndex)",
            currentAmbientClip ?? "none")

        if animated {
            creature.scale = [0.25, 0.25, 0.25]
            var grown = creature.transform
            grown.scale = .one
            creature.move(to: grown, relativeTo: pivot, duration: 0.5, timingFunction: .easeOut)
        }
    }

    /// Locate (carrier entity, material slot) of the face decal.
    /// Procedural path: the petFace ModelEntity itself, slot 0.
    /// Skinned usdz path: submeshes merge into the SkelRoot's ModelComponent —
    /// match the mesh model named "petFace*" and use its part's materialIndex.
    private static func findFaceSlot(in root: Entity) -> (carrier: Entity, index: Int)? {
        if let slot = root.findEntity(named: "petFace"),
           let mesh = firstMeshEntity(under: slot) {
            return (mesh, 0)
        }
        return faceSlotInMergedModel(under: root)
    }

    private static func firstMeshEntity(under entity: Entity) -> Entity? {
        if entity.components[ModelComponent.self] != nil { return entity }
        for child in entity.children {
            if let nested = firstMeshEntity(under: child) { return nested }
        }
        return nil
    }

    private static func bodyFaceSlot(in root: Entity, species: String) -> (carrier: Entity, index: Int)? {
        // Nara exports a stable body mesh name. Resolve its material index
        // explicitly; a merged skeleton's first material may be an accessory.
        func namedSlot(_ entity: Entity) -> (Entity, Int)? {
            if let model = entity.components[ModelComponent.self] {
                for mesh in model.mesh.contents.models
                where mesh.id.localizedCaseInsensitiveContains("\(species)body") {
                    for part in mesh.parts { return (entity, part.materialIndex) }
                }
            }
            for child in entity.children {
                if let slot = namedSlot(child) { return slot }
            }
            return nil
        }
        if let slot = namedSlot(root) { return slot }
        // Retain the single-shell contract of existing assets. The new Nara
        // pipeline must expose its named body, never silently use a face plane.
        guard species != "nara", let mesh = firstMeshEntity(under: root) else { return nil }
        return (mesh, 0)
    }

    private static func faceSlotInMergedModel(under entity: Entity) -> (Entity, Int)? {
        if let model = entity.components[ModelComponent.self] {
            for meshModel in model.mesh.contents.models
            where meshModel.id.localizedCaseInsensitiveContains("petface") {
                for part in meshModel.parts {
                    return (entity, part.materialIndex)
                }
            }
        }
        for child in entity.children {
            if let nested = faceSlotInMergedModel(under: child) { return nested }
        }
        return nil
    }

    /// Try a bundled `.usdz` first (drop-in real art); nil means go procedural.
    /// Sibling clip files (`<name>_idle.usdz`, …) feed the skeletal clip library —
    /// their animations retarget onto the base model (identical rig + prim names).
    private struct LoadedPetModel {
        let entity: Entity
        let animationEntity: Entity
        let clips: [String: AnimationResource]
        var hybrid: HybridPetAsset? = nil
    }

    private static func loadBundledModel(_ species: SpeciesInfo, allowHybrid: Bool = true) -> LoadedPetModel? {
        if allowHybrid && ["nara", "mochi", "pando", "lumi"].contains(species.id) {
            do {
                let asset = try HybridPetAsset.load(species: species.id)
                let container = Entity()
                container.addChild(asset.entity)
                return .init(entity: container, animationEntity: asset.faceRig.animationCarrier,
                             clips: asset.clips, hybrid: asset)
            } catch {
                // Keep the established bundled fallback if an installation is
                // incomplete. The isolated acceptance run rejects this route.
                NSLog("UselessPet %@ hybrid unavailable: %@", species.id, error.localizedDescription)
            }
        }
        guard let name = species.model3DName else { return nil }
        guard let entity = try? Entity.load(named: name, in: Bundle.uselesspetResources) else { return nil }

        // Normalize: scale the loaded model so its bounds roughly match the
        // procedural creatures (~0.26 m tall), and recentre it vertically —
        // authored usdz pets have their origin at the FEET (ground plane), so
        // without the shift the head/ears poke out of the viewport top.
        let bounds = entity.visualBounds(relativeTo: nil)
        let height = max(bounds.extents.y, 0.0001)
        let target: Float = 0.26
        let s = target / height
        entity.scale = .init(repeating: s)
        entity.position.y -= bounds.center.y * s
        let container = Entity()
        container.addChild(entity)

        var clips: [String: AnimationResource] = [:]
        for clip in clipDurations.keys {
            if let clipEntity = try? Entity.load(named: "\(name)_\(clip)", in: Bundle.uselesspetResources) {
                let animation = species.id == "nara"
                    ? Self.skeletalAnimation(in: clipEntity)
                    : clipEntity.availableAnimations.first
                if let animation { clips[clip] = animation }
            }
        }
        let rig = species.id == "nara" ? firstMeshEntity(under: entity) : nil
        return .init(entity: container, animationEntity: rig ?? entity, clips: clips)
    }

    private static func skeletalAnimation(in root: Entity) -> AnimationResource? {
        guard let rig = firstMeshEntity(under: root) else { return nil }
        if #available(macOS 15.0, *),
           let library = rig.components[AnimationLibraryComponent.self] {
            return library.animations.first {
                $0.key.localizedCaseInsensitiveContains("skeletal")
            }?.value
        }
        // Older systems keep the existing transform-motion fallback if the
        // importer does not expose the direct joint clip through this API.
        return rig.availableAnimations.first {
            $0.name?.localizedCaseInsensitiveContains("skeletal") == true
        }
    }

    // MARK: skeletal clips

    /// Resting loop chosen from mood + hunger (mirrors `expression(mood:hunger:)`).
    private func ambientClipName() -> String? {
        guard !clipLibrary.isEmpty else { return nil }
        // The current presentation selects the base loop.
        let activityClip = PetActivityMap.clip(for: currentActivity)
        // Resting presentation keeps the companion content between interactions.
        if currentActivity == .idle || currentActivity == .sleeping {
            if currentHunger == .stuffed { return "sleep" }
            if currentMood == .sad || currentHunger == .hungry { return "sad" }
        }
        return activityClip
    }

    private func startAmbientClip() {
        if naraTimeline != nil {
            synchronizeNaraPresentation()
            return
        }
        guard let name = ambientClipName() else { return }
        // Record the desired name up front so update() doesn't re-enter every
        // SwiftUI tick when the mapped clip happens to be unavailable.
        currentAmbientClip = name
        // Fall back to a guaranteed clip if the mapped one failed to load, so a
        // species missing e.g. play/celebrate can't freeze the loop; idle is the
        // near-universal base.
        let key: String? = clipLibrary[name] != nil ? name
            : (clipLibrary["idle"] != nil ? "idle" : clipLibrary.keys.first)
        guard let key, let animation = clipLibrary[key] else { return }
        if key != name {
            NSLog("UselessPet clip: %@ unavailable, fell back to %@", name, key)
        }
        NSLog("UselessPet clip: %@ (activity %@)", key, currentActivity.rawValue)
        skeletalPlayback?.stop()
        skeletalPlayback = animationCarrier.playAnimation(animation.repeat(), transitionDuration: 0.35, startsPaused: false)
    }

    private func synchronizeNaraPresentation() {
        guard let desired = naraTimeline?.presentation else { return }
        currentExpression = desired.expression
        currentAmbientClip = desired.loops ? desired.clip : nil
        guard desired.playbackID != naraPresentation?.playbackID else {
            naraPresentation = desired
            return
        }
        guard let animation = clipLibrary[desired.clip] else { return }
        skeletalPlayback?.stop()
        animationCarrier.stopAllAnimations(recursive: false)
        skeletalPlayback = animationCarrier.playAnimation(desired.loops ? animation.repeat() : animation,
                                                          transitionDuration: 0.18, startsPaused: false)
        playbackStarts += 1
        naraPresentation = desired
        NSLog("UselessPet Nara: %@ %@", desired.clip, desired.phase)
    }

    // MARK: procedural geometry

    private static func material(_ color: NSColor, roughness: Float = 0.5, metallic: Float = 0.0) -> SimpleMaterial {
        SimpleMaterial(color: color, roughness: .float(roughness), isMetallic: metallic > 0.5)
    }

    private static func sphere(_ radius: Float, _ color: NSColor, roughness: Float = 0.5, metallic: Float = 0.0) -> ModelEntity {
        ModelEntity(mesh: .generateSphere(radius: radius),
                    materials: [material(color, roughness: roughness, metallic: metallic)])
    }

    private static func box(_ size: SIMD3<Float>, _ color: NSColor, corner: Float = 0.004, roughness: Float = 0.5) -> ModelEntity {
        ModelEntity(mesh: .generateBox(size: size, cornerRadius: corner),
                    materials: [material(color, roughness: roughness)])
    }

    private static func buildProcedural(_ plan: PetBodyPlan, speciesId: String) -> Entity {
        let root = Entity()

        // Body — a gently squashed sphere.
        let body = sphere(0.12, plan.body, roughness: plan.metallic > 0 ? 0.3 : 0.5, metallic: plan.metallic)
        body.scale = [1.0, plan.squash, 0.96]
        root.addChild(body)

        // Belly patch.
        let belly = sphere(0.072, plan.belly, roughness: 0.6)
        belly.position = [0, -0.012, 0.072]
        belly.scale = [1.0, 1.05, 0.6]
        root.addChild(belly)

        // Face — a flat decal plane on the front of the head. The eyes / mouth /
        // cheeks live in a procedurally-drawn texture that gets swapped per emotion
        // (see FaceTextureFactory). Named so the controller can find + retexture it.
        let faceMesh = MeshResource.generatePlane(width: 0.17, height: 0.13, cornerRadius: 0)
        var faceMat = UnlitMaterial()
        if let tex = FaceTextureFactory.texture(for: .neutral, species: speciesId) {
            faceMat.color = .init(tint: .white, texture: .init(tex))
        }
        faceMat.blending = .transparent(opacity: 1.0)
        let face = ModelEntity(mesh: faceMesh, materials: [faceMat])
        face.name = "petFace"
        face.position = [0, 0.022, 0.116]
        root.addChild(face)

        // Ears.
        switch plan.ears {
        case .none:
            break
        case .round:
            for sx: Float in [-1, 1] {
                let ear = sphere(0.044, plan.accent, roughness: 0.5)
                ear.position = [0.072 * sx, 0.10, -0.005]
                root.addChild(ear)
            }
        case .tall:
            for sx: Float in [-1, 1] {
                let ear = box([0.04, 0.13, 0.035], plan.accent, corner: 0.018)
                ear.position = [0.05 * sx, 0.155, 0]
                ear.orientation = simd_quatf(angle: 0.18 * sx, axis: [0, 0, 1])
                root.addChild(ear)
            }
        case .pointy:
            for sx: Float in [-1, 1] {
                let ear = box([0.058, 0.072, 0.025], plan.accent, corner: 0.006)
                ear.position = [0.066 * sx, 0.12, -0.004]
                ear.orientation = simd_quatf(angle: 0.5 * sx, axis: [0, 0, 1])
                root.addChild(ear)
            }
        }

        // Antennae (bug / chaos) — thin stalks with a bright bulb tip.
        if plan.antennae {
            for sx: Float in [-1, 1] {
                let stalk = box([0.011, 0.085, 0.011], plan.accent, corner: 0.005)
                stalk.position = [0.03 * sx, 0.155, 0.01]
                stalk.orientation = simd_quatf(angle: 0.28 * sx, axis: [0, 0, 1])
                root.addChild(stalk)

                let bulb = sphere(0.019, plan.body.blended(to: .white, fraction: 0.15), roughness: 0.3)
                bulb.position = [0.052 * sx, 0.2, 0.012]
                root.addChild(bulb)
            }
        }

        // Tail (curiosity) — a stubby angled tail behind.
        if plan.tail {
            let tail = box([0.04, 0.04, 0.12], plan.accent, corner: 0.02)
            tail.position = [0, -0.01, -0.12]
            tail.orientation = simd_quatf(angle: -0.6, axis: [1, 0, 0])
            root.addChild(tail)

            let tip = sphere(0.03, plan.belly, roughness: 0.6)
            tip.position = [0, 0.05, -0.17]
            root.addChild(tip)
        }

        return root
    }

    // MARK: idle loop

    private func startIdleLoop() {
        idleSub?.cancel()
        idleSub = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.tickIdle(delta: event.deltaTime)
        }
    }

    private func tickIdle(delta: TimeInterval) {
        let delta = delta.isFinite ? max(0, delta) : 0
        renderedFrames += 1
        renderedSeconds += delta
        maximumFrameGap = max(maximumFrameGap, delta)
        if delta > 0.1 { frameGapsOver100ms += 1 }
        var reactionFrame: CompanionReaction.Frame?
        if let reaction = companionReaction {
            companionReactionTime += delta
            if companionReactionTime >= CompanionReaction.duration {
                companionReaction = nil
                playingEvent = false
                setExpression(baseExpression)
                naraPresentation = nil
                if var timeline = naraTimeline {
                    timeline.receive(activity: currentActivity, mood: currentMood, hunger: currentHunger, transient: nil)
                    naraTimeline = timeline
                }
                startAmbientClip()
            } else {
                reactionFrame = reaction.frame(at: companionReactionTime, reducedMotion: reactionReducesMotion)
                if let frame = reactionFrame, currentExpression != frame.expression { setExpression(frame.expression) }
            }
        }
        if companionReaction == nil, var timeline = naraTimeline {
            timeline.advance(by: delta)
            naraTimeline = timeline
            synchronizeNaraPresentation()
        }
        bobPhase += Float(delta) * 3
        if bobPhase > .pi * 2 { bobPhase -= .pi * 2 }
        swayPhase += Float(delta) * 0.72
        if swayPhase > .pi * 2 { swayPhase -= .pi * 2 }

        // Ease the rendered scale toward the mood target so mood shifts glide.
        renderedScale += (moodScale - renderedScale) * Float(1 - exp(-delta * 3.71))
        updateLook(delta: delta)
        if let asset = hybridAsset {
            naraRenderedFace = naraFaceAnimator.advance(by: delta, expression: currentExpression,
                gazeX: lookYaw / (.pi / 12), gazeY: -lookPitch / (.pi * 8 / 180),
                reactionClip: naraPresentation?.phase == "reaction" ? naraPresentation?.clip : nil,
                clipTime: skeletalPlayback?.time ?? 0,
                clipDuration: clipLibrary[naraPresentation?.clip ?? ""]?.definition.duration ?? 3,
                companionFace: reactionFrame?.face)
            asset.faceRig.apply(naraRenderedFace)
        } else {
            updateBlink()
        }

        let sleeping = hybridAsset != nil && currentExpression == .sleepy
        let bob = sin(bobPhase) * bobAmp * (sleeping ? 0.2 : 1)

        var tf = Transform()
        // Shrinking happens about the pet's center; the -0.115·(1-userScale)
        // drop keeps its feet near the same baseline instead of floating.
        tf.translation = [0, bob + moodYOffset - (1 - userScale) * 0.115, 0]
        // Cursor input belongs to the head joint; the torso and feet never
        // inherit cursor rotation. Authored action/breathing clips stay intact.
        tf.rotation = simd_quatf(angle: 0, axis: [0, 1, 0])
        tf.scale = SIMD3(repeating: renderedScale * userScale)
        if let frame = reactionFrame {
            tf.rotation = simd_quatf(angle: frame.tilt, axis: [0, 0, 1])
            // Mochi's ears sit farther forward in perspective. Keep the
            // procedural bounce subtle alongside its authored skeletal hops.
            let motionStrength: Float = currentSpeciesId == "mochi" ? 0.4 : 1
            let reactionScale = SIMD3<Float>(repeating: 1) + (frame.scale - SIMD3<Float>(repeating: 1)) * motionStrength
            tf.scale *= reactionScale
            let foot = SIMD3<Float>(0, -0.115 * renderedScale * userScale, 0)
            tf.translation += foot - tf.rotation.act(foot * reactionScale)
            tf.translation.y += frame.hop * userScale * motionStrength
        }
        pivot.transform = tf
    }

    /// Gently turn the head toward the mouse cursor (eased). With the
    /// follow-cursor toggle off, the gaze eases back to center instead —
    /// the same easing, so flipping the toggle never snaps the head.
    private func updateLook(delta: TimeInterval) {
        var targetYaw: Float = 0
        var targetPitch: Float = 0
        if let qaGaze {
            targetYaw = max(-1, min(1, qaGaze.x)) * (.pi / 12)
            targetPitch = max(-1, min(1, -qaGaze.y)) * (.pi * 8 / 180)
        } else if followsCursor, let window = arView.window {
            let m = NSEvent.mouseLocation
            let f = window.frame
            let dx = Float(m.x - f.midX)
            let dy = Float(m.y - f.midY)
            targetYaw = max(-.pi / 12, min(.pi / 12, dx / 1000))
            // Positive rotation about +X tips the face DOWN, so the pitch that
            // follows a mouse ABOVE the window (dy > 0) must be negative.
            targetPitch = max(-.pi * 8 / 180, min(.pi * 8 / 180, -dy / 1000))
        }
        if currentExpression == .sleepy || playingEvent || naraPresentation?.phase == "reaction" { targetYaw = 0; targetPitch = 0 }
        let amount = Float(1 - exp(-delta / 0.17))
        lookYaw += (targetYaw - lookYaw) * amount
        lookPitch += (targetPitch - lookPitch) * amount
    }

    /// Occasional eye-blink while idle (skipped during event animations).
    private func updateBlink() {
        guard !playingEvent else { return }
        if blinkFramesLeft > 0 {
            blinkFramesLeft -= 1
            if blinkFramesLeft == 0 { applyFaceTexture(currentExpression) }
            return
        }
        framesUntilBlink -= 1
        if framesUntilBlink <= 0 {
            applyFaceTexture(.blink)
            blinkFramesLeft = 6
            framesUntilBlink = 130 + Int((sin(swayPhase) + 1) * 60)   // vary the cadence
        }
    }

    // MARK: event motion

    private func beginCompanionReaction(_ reaction: CompanionReaction) {
        creature.stopAllAnimations(recursive: true)
        creature.transform = .identity
        companionReaction = reaction
        companionReactionTime = 0
        playingEvent = true
        reactionReducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        naraFaceAnimator = NaraFaceAnimator()
        setExpression(.neutral)
        currentAmbientClip = nil
        skeletalPlayback?.stop()
        let clip = reactionReducesMotion ? "idle" : reaction.clip
        if let animation = clipLibrary[clip] {
            skeletalPlayback = animationCarrier.playAnimation(animation, transitionDuration: 0.08, startsPaused: false)
            skeletalPlayback?.speed = Float(animation.definition.duration / CompanionReaction.duration)
            playbackStarts += 1
        }
        NSLog("UselessPet companion reaction: %@", reaction.rawValue)
    }

    private func settleToIdle() {
        guard !playingEvent else { return }
        setExpression(baseExpression)
        creature.move(to: .identity, relativeTo: pivot, duration: 0.4, timingFunction: .easeInOut)
        startAmbientClip()
    }

    /// Explicit teardown is also used when SwiftUI replaces this coordinator.
    /// No previous species may retain a task that later changes the new view.
    func shutdown() {
        companionReaction = nil
        lastCompanionInput = nil
        headSub?.cancel()
        headSub = nil
        headLook = nil
        idleSub?.cancel()
        idleSub = nil
        skeletalPlayback?.stop()
        skeletalPlayback = nil
        snapshotPlayback?.stop()
        snapshotPlayback = nil
        creature.stopAllAnimations(recursive: true)
        naraTimeline = nil
        naraPresentation = nil
        naraFaceAnimator = NaraFaceAnimator()
    }

    var runtimeDiagnostics: [String: Any] {
        var count = 0
        func visit(_ entity: Entity) { count += 1; entity.children.forEach(visit) }
        visit(creature)
        return [
            "visual_bounds": [creature.visualBounds(relativeTo: nil).center.x,
                              creature.visualBounds(relativeTo: nil).center.y,
                              creature.visualBounds(relativeTo: nil).center.z,
                              creature.visualBounds(relativeTo: nil).extents.x,
                              creature.visualBounds(relativeTo: nil).extents.y,
                              creature.visualBounds(relativeTo: nil).extents.z],
            "head_tracking": headLook?.diagnostics ?? [:],
            "pivot_rotation": [pivot.orientation.vector.x, pivot.orientation.vector.y, pivot.orientation.vector.z, pivot.orientation.vector.w],
            "species": currentSpeciesId ?? "", "hybrid": hybridAsset != nil,
            "clip": companionReaction?.clip ?? naraPresentation?.clip ?? currentAmbientClip ?? "",
            "expression": currentExpression.rawValue,
            "phase": companionReaction != nil ? "reaction" : naraPresentation?.phase ?? "legacy",
            "playback_id": naraPresentation?.playbackID ?? "",
            "companion_reaction": companionReaction?.rawValue ?? "",
            "companion_reaction_time": companionReactionTime,
            "reaction_reduced_motion": reactionReducesMotion,
            "clip_time": skeletalPlayback?.time ?? 0,
            "clip_duration": clipLibrary[naraPresentation?.clip ?? ""]?.definition.duration ?? 0,
            "is_playing": skeletalPlayback?.isPlaying ?? false,
            "active_playback_count": skeletalPlayback?.isPlaying == true ? 1 : 0,
            "playback_starts": playbackStarts, "rebuild_count": rebuildCount,
            "entity_count": count, "source_load_count": HybridPetAsset.sourceLoadCount,
            "weights": naraRenderedFace.weights, "imported_weights": hybridAsset?.faceRig.importedWeights() ?? [:],
            "asset_sha256": hybridAsset?.assetSHA256 ?? "",
            "clip_asset_sha256": hybridAsset?.clipSHA256 ?? [:],
            "clip_durations": clipLibrary.mapValues { $0.definition.duration },
            "user_scale": userScale, "transparent": true,
            "render_frame_count": renderedFrames, "render_seconds": renderedSeconds,
            "render_average_fps": renderedSeconds > 0 ? Double(renderedFrames) / renderedSeconds : 0,
            "render_max_gap_seconds": maximumFrameGap, "render_gaps_over_100ms": frameGapsOver100ms,
        ]
    }

    func resetFrameStatistics() {
        renderedFrames = 0
        renderedSeconds = 0
        maximumFrameGap = 0
        frameGapsOver100ms = 0
    }

    /// Freeze one evaluated body pose for isolated head/body invariance QA.
    func freezeBodyForHeadQA() {
        idleSub?.cancel()
        idleSub = nil
        skeletalPlayback?.pause()
        lookYaw = 0; lookPitch = 0
        pivot.transform = .identity
        headLook?.apply(yaw: 0, pitch: 0)
    }

    func setHeadForQA(yaw: Float, pitch: Float) {
        lookYaw = yaw; lookPitch = pitch
        headLook?.apply(yaw: yaw, pitch: pitch)
    }
}

// MARK: - SwiftUI bridge

/// SwiftUI wrapper around the RealityKit `ARView`. Builds the scene once and
/// forwards `pet` / `transient` changes into the controller.
@available(macOS 14.0, *)
struct PetRealityView: NSViewRepresentable {
    let pet: PetState
    let transient: BridgeClient.TransientEvent?
    var userScale: Float = 1.0
    var followsCursor: Bool = true
    var activity: ActivityState = .idle

    func makeCoordinator() -> Pet3DController {
        Pet3DController()
    }

    func makeNSView(context: Context) -> PetARView {
        let c = context.coordinator
        c.userScale = userScale
        c.followsCursor = followsCursor
        c.bootstrap(
            species: SpeciesCatalog.info(for: pet.speciesId),
            mood: MoodBand(pet.renderedMood),
            hunger: HungerBand(pet.renderedHunger),
            activity: activity
        )
        return c.arView
    }

    func updateNSView(_ nsView: PetARView, context: Context) {
        context.coordinator.userScale = userScale
        context.coordinator.followsCursor = followsCursor
        context.coordinator.update(
            species: SpeciesCatalog.info(for: pet.speciesId),
            mood: MoodBand(pet.renderedMood),
            hunger: HungerBand(pet.renderedHunger),
            transient: transient,
            activity: activity
        )
    }

    static func dismantleNSView(_ nsView: PetARView, coordinator: Pet3DController) {
        coordinator.shutdown()
    }
}
