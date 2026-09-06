import Foundation

struct ConsoleRosterEntry: Equatable, Identifiable {
    let id: String
    let portrait: String
    let accentHex: String
    let selected: Bool
}

struct ConsoleViewModel: Equatable {
    let petName: String
    let portrait: String
    let accentHex: String
    let connected: Bool
    let roster: [ConsoleRosterEntry]

    static func build(pet: PetState, connected: Bool) -> Self {
        let info = SpeciesCatalog.info(for: pet.speciesId)
        return Self(petName: info.name, portrait: info.imageName ?? "",
                    accentHex: info.tintHex, connected: connected,
                    roster: SpeciesCatalog.pickableSpecies.map {
                        ConsoleRosterEntry(id: $0.id, portrait: $0.imageName ?? "",
                                           accentHex: $0.tintHex, selected: $0.id == pet.speciesId)
                    })
    }
}

enum ConsoleEyeIntent: Equatable {
    case show     // hidden, on the active screen → reveal in place
    case hide     // visible, on the active screen → hide
    case summon   // parked on another display → bring it to the active screen
}

/// The eye button's icon + tooltip. The icon MIRRORS the pet's current visibility
/// (`eye` = on screen, `eye.slash` = hidden); the tooltip states what the click
/// does. Pure & testable.
enum ConsoleEyeButton {
    static func state(_ intent: ConsoleEyeIntent) -> (systemImage: String, help: String) {
        switch intent {
        case .hide:   return (systemImage: "eye", help: "Hide pet")                  // visible now
        case .show:   return (systemImage: "eye.slash", help: "Show pet")            // hidden now
        case .summon: return (systemImage: "eye", help: "Bring pet to this screen")  // visible elsewhere
        }
    }
}
