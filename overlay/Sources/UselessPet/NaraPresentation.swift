import Foundation

/// A presentation of daemon-owned inputs. This owns animation timing only;
/// it never invents activity, care state, rewards, or persisted pet state.
struct NaraPresentation: Equatable {
    let clip: String
    let expression: PetExpression
    let loops: Bool
    let playbackID: String
    let phase: String
}

struct NaraPresentationTimeline {
    static let expressionLinger: TimeInterval = 1.25
    private(set) var activity: ActivityState
    private(set) var mood: MoodBand
    private(set) var hunger: HungerBand
    private let durations: [String: TimeInterval]
    private var lastTransient: BridgeClient.TransientEvent?
    private var serial = 0
    private var reaction: Reaction?

    private struct Reaction {
        let clip: String
        let expression: PetExpression
        let duration: TimeInterval
        let serial: Int
        var elapsed: TimeInterval = 0
    }

    init(activity: ActivityState, mood: MoodBand, hunger: HungerBand,
         durations: [String: TimeInterval]) {
        self.activity = activity
        self.mood = mood
        self.hunger = hunger
        self.durations = durations
    }

    mutating func receive(activity: ActivityState, mood: MoodBand, hunger: HungerBand,
                          transient: BridgeClient.TransientEvent?) {
        let enteredSleep = activity == .sleeping && self.activity != .sleeping
        self.activity = activity
        self.mood = mood
        self.hunger = hunger
        let changed = transient != lastTransient
        lastTransient = transient
        // Entering sleep can interrupt an old reaction. A new user event still
        // gets its full visual response even if the daemon was already asleep;
        // an interaction does not change the ambient animation state.
        if enteredSleep && !(changed && transient != nil) {
            reaction = nil
            return
        }
        guard changed, let transient else { return }
        let cue = Self.cue(for: transient)
        guard let duration = durations[cue.clip], duration.isFinite, duration > 0 else { return }
        serial += 1
        reaction = Reaction(clip: cue.clip, expression: cue.expression,
                            duration: duration, serial: serial)
    }

    mutating func advance(by delta: TimeInterval) {
        guard delta.isFinite, delta > 0, var active = reaction else { return }
        active.elapsed += delta
        reaction = active.elapsed < active.duration + Self.expressionLinger ? active : nil
    }

    var presentation: NaraPresentation {
        let ambient = Self.ambient(activity: activity, mood: mood, hunger: hunger)
        if let reaction, reaction.elapsed < reaction.duration {
            return .init(clip: reaction.clip, expression: reaction.expression,
                         loops: false, playbackID: "reaction-\(reaction.serial)", phase: "reaction")
        }
        // A sleeping body always has closed eyes, including a care-state nap
        // that begins as the just-completed event returns to its ambient loop.
        let face = ambient.clip == "sleep" ? PetExpression.sleepy : (reaction?.expression ?? ambient.expression)
        return .init(clip: ambient.clip, expression: face, loops: true,
                     playbackID: "ambient-\(ambient.clip)", phase: reaction == nil ? "ambient" : "linger")
    }

    static func ambient(activity: ActivityState, mood: MoodBand,
                        hunger: HungerBand) -> (clip: String, expression: PetExpression) {
        if activity == .sleeping { return ("sleep", .sleepy) }
        if activity == .idle {
            if hunger == .stuffed { return ("sleep", .sleepy) }
            if mood == .sad || hunger == .hungry { return ("sad", .sad) }
        }
        return (PetActivityMap.clip(for: activity), PetActivityMap.expression(for: activity))
    }

    static func cue(for event: BridgeClient.TransientEvent) -> (clip: String, expression: PetExpression) {
        switch event {
        case .petted(_, let reaction): return (reaction.clip, reaction.expression)
        }
    }

}

extension NaraFacePose {
    static func expression(_ expression: PetExpression) -> Self {
        switch expression {
        case .happy, .eat: return .init(smile: 1)
        case .sad: return .init(blinkLeft: 0.2, blinkRight: 0.2)
        case .sleepy, .blink: return .init(blinkLeft: 1, blinkRight: 1)
        case .neutral, .surprised: return .init()
        case .star: return .init(blinkLeft: 0.35, blinkRight: 0.35, gazeY: 0.3, smile: 1)
        case .dizzy: return .init(blinkLeft: 0.75, blinkRight: 0.15, gazeX: 0.5, smile: 0.8)
        }
    }
}

/// Continuous facial interpolation, independent of both skeletal channels and
/// display refresh rate. A natural blink preserves smile and gaze channels.
struct NaraFaceAnimator {
    private(set) var pose = NaraFacePose()
    private var clock: TimeInterval = 0
    private var nextBlinkAt: TimeInterval = 3.5
    private var blinkStart: TimeInterval?
    private var blinkCount = 0
    private static let cadence: [TimeInterval] = [4.7, 3.2, 5.6, 4.1]

    init(expression: PetExpression = .neutral) { pose = .expression(expression) }

    mutating func advance(by delta: TimeInterval, expression: PetExpression,
                          gazeX: Float, gazeY: Float, reactionClip: String? = nil,
                          clipTime: TimeInterval = 0, clipDuration: TimeInterval = 3,
                          companionFace: NaraFacePose? = nil) -> NaraFacePose {
        guard delta.isFinite, delta >= 0 else { return pose }
        clock += delta
        var target = NaraFacePose.expression(expression)
        if let reactionClip {
            target = Self.reactionPose(clip: reactionClip, time: clipTime,
                                       duration: clipDuration, fallback: target)
        }
        if let companionFace { target = companionFace }
        let isClosed = target.blinkLeft >= 0.99 && target.blinkRight >= 0.99
        if companionFace == nil {
            target.gazeX = isClosed ? 0 : Self.direction(gazeX)
            target.gazeY = isClosed ? 0 : Self.direction(gazeY)
        }
        if isClosed {
            blinkStart = nil
            nextBlinkAt = clock + 3.5
        } else {
            // Do not replay a backlog of blinks after the display resumes.
            if delta > 1 {
                blinkStart = nil
                nextBlinkAt = clock + 3.5
            }
            if let start = blinkStart, clock >= start + NaraBlinkCurve.duration {
                blinkStart = nil
            }
            if clock >= nextBlinkAt {
                blinkStart = nextBlinkAt
                let interval = Self.cadence[blinkCount % Self.cadence.count]
                blinkCount += 1
                nextBlinkAt += NaraBlinkCurve.duration + interval
            }
        }
        let amount = Float(1 - exp(-delta / 0.085))
        func eased(_ current: Float, _ desired: Float) -> Float {
            let result = current + (desired - current) * amount
            return abs(result - desired) < 0.0005 ? desired : result
        }
        pose.blinkLeft = eased(pose.blinkLeft, target.blinkLeft)
        pose.blinkRight = eased(pose.blinkRight, target.blinkRight)
        pose.gazeX = eased(pose.gazeX, target.gazeX)
        pose.gazeY = eased(pose.gazeY, target.gazeY)
        pose.smile = eased(pose.smile, target.smile)
        let blink = blinkStart.map { NaraBlinkCurve.value(at: clock - $0) } ?? 0
        return pose.addingBlink(blink)
    }

    private static func direction(_ value: Float) -> Float {
        value.isFinite ? min(1, max(-1, value)) : 0
    }

    /// Facial accents share the authored body's timeline. The two play hops
    /// peak at .75 and 1.95 seconds; the face brightens and eyes gently squint
    /// with those same beats. The smile continues into the short settling pose.
    static func reactionPose(clip: String, time: TimeInterval, duration: TimeInterval,
                             fallback: NaraFacePose) -> NaraFacePose {
        guard time.isFinite, duration > 0 else { return fallback }
        let t = max(0, time) * 3 / duration
        func pulse(_ center: Double, _ width: Double) -> Float {
            let x = max(0, 1 - abs(t - center) / width)
            return Float(x * x * (3 - 2 * x))
        }
        let onset = NaraFacePose.unit(Float(t / 0.22))
        switch clip {
        case "play", "celebrate":
            let peaks = clip == "play" ? (0.75, 1.95) : (0.70, 2.15)
            let joy = max(pulse(peaks.0, 0.48), pulse(peaks.1, 0.48))
            return .init(blinkLeft: joy * 0.28, blinkRight: joy * 0.28,
                         smile: onset * (0.65 + 0.35 * joy))
        case "eat":
            let nibble = max(pulse(0.85, 0.35), pulse(1.75, 0.35))
            return .init(blinkLeft: nibble * 0.2, blinkRight: nibble * 0.2,
                         smile: onset * (0.6 + 0.4 * nibble))
        default: return fallback
        }
    }
}
