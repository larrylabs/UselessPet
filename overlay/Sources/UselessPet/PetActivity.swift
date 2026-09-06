/// Internal animation vocabulary; the companion rests between interactions.
enum ActivityState: String { case idle, happy, error, sleeping }

enum PetActivityMap {
    static func clip(for activity: ActivityState) -> String {
        switch activity {
        case .idle: return "idle"
        case .happy: return "celebrate"
        case .error: return "sad"
        case .sleeping: return "sleep"
        }
    }
    static func expression(for activity: ActivityState) -> PetExpression {
        switch activity {
        case .idle: return .neutral
        case .happy: return .happy
        case .error: return .sad
        case .sleeping: return .sleepy
        }
    }
}
