import SwiftUI

/// Transparent desktop surface. Persistent companion state belongs to the daemon.
struct PetView: View {
    @ObservedObject var bridge: BridgeClient
    @AppStorage("uselesspet.petScale") private var petScale: Double = 1.0
    @AppStorage("uselesspet.petFollowsCursor") private var followsCursor: Bool = true
    @AppStorage(AppLanguage.preferenceKey) private var languageCode = AppLanguage.english.rawValue

    var body: some View {
        ZStack {
            PetRealityView(pet: bridge.pet, transient: bridge.transient,
                           userScale: Float(petScale), followsCursor: followsCursor,
                           activity: bridge.activity)
            Color.clear.contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contextMenu {
            Button(L10n.text(.petAction, language: .resolve(languageCode))) {
                bridge.send(command: "cmd.pet")
            }.disabled(bridge.status != .connected)
            Divider()
            Button(L10n.text(.quit, language: .resolve(languageCode))) {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
