import Foundation
import simd

/// The daemon chooses the emotion. This maps it to a coordinated, three-second
/// performance; it does not choose pet behavior or mutate companion state.
enum CompanionReaction: String, CaseIterable {
    case joy, delight, surprise, silly, cuddle

    static let duration: TimeInterval = 3
    var clip: String { self == .delight ? "celebrate" : "play" }
    var expression: PetExpression {
        switch self {
        case .joy: return .happy
        case .delight: return .star
        case .surprise: return .surprised
        case .silly: return .dizzy
        case .cuddle: return .blink
        }
    }
    var feedback: L10nKey {
        switch self {
        case .joy: return .reactionJoy
        case .delight: return .reactionDelight
        case .surprise: return .reactionSurprise
        case .silly: return .reactionSilly
        case .cuddle: return .reactionCuddle
        }
    }

    struct Frame {
        var expression: PetExpression = .neutral
        var face = NaraFacePose()
        var scale = SIMD3<Float>(repeating: 1)
        var hop: Float = 0
        var tilt: Float = 0
    }

    func frame(at seconds: TimeInterval, reducedMotion: Bool = false) -> Frame {
        guard seconds.isFinite, seconds > 0, seconds < Self.duration else { return Frame() }
        let t = seconds
        func pulse(_ center: Double, _ width: Double) -> Float {
            let x = max(0, 1 - abs(t - center) / width)
            return Float(x * x * (3 - 2 * x))
        }
        let envelope = min(1, Float(t / 0.18), Float((Self.duration - t) / 0.35))
        var result = Frame(expression: expression, face: .expression(expression))
        switch self {
        case .joy:
            let peak = max(pulse(0.75, 0.42), pulse(1.95, 0.42))
            let squash = max(pulse(0.36, 0.18), pulse(1.15, 0.16), pulse(2.35, 0.16))
            result.hop = 0.035 * peak
            result.scale = [1 - 0.06 * peak + 0.1 * squash, 1 + 0.12 * peak - 0.16 * squash, 1]
            result.face = .init(blinkLeft: peak * 0.4, blinkRight: peak * 0.4, smile: 1)
        case .delight:
            let peak = max(pulse(0.7, 0.45), pulse(2.15, 0.42))
            result.hop = 0.018 * peak
            result.scale = [1 - 0.06 * peak, 1 + 0.1 * peak, 1]
            result.tilt = sin(Float(t) * 6) * 0.13 * envelope
            result.face = .init(blinkLeft: peak * 0.55, blinkRight: peak * 0.55, gazeY: 0.35, smile: 1)
        case .surprise:
            let pop = pulse(0.55, 0.4)
            result.hop = 0.038 * pop
            result.scale = [1 - 0.08 * pop, 1 + 0.18 * pop, 1]
            result.tilt = -0.12 * pulse(1.4, 0.65)
            result.expression = t < 1.25 ? .surprised : .happy
            result.face = t < 1.25 ? .init(gazeY: 0.65) : .init(blinkLeft: 0.25, blinkRight: 0.25, smile: 1)
        case .silly:
            let wobble = sin(Float(t) * 10) * envelope
            result.tilt = wobble * 0.2
            result.scale = [1 + 0.055 * abs(wobble), 1 - 0.07 * abs(wobble), 1]
            result.face = .init(blinkLeft: max(0, wobble) * 0.8,
                                blinkRight: max(0, -wobble) * 0.8,
                                gazeX: wobble * 0.8, smile: 0.8)
        case .cuddle:
            let lean = pulse(1.1, 0.95)
            result.tilt = -0.18 * lean
            result.scale = [1 + 0.06 * lean, 1 - 0.09 * lean, 1]
            result.expression = t < 1.8 ? .blink : .happy
            result.face = .init(blinkLeft: lean, blinkRight: lean * 0.65, smile: 1)
        }
        if reducedMotion {
            result.hop = 0
            result.scale = SIMD3(repeating: 1)
            result.tilt = 0
        }
        return result
    }
}
