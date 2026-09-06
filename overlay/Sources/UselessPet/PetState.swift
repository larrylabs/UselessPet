import AppKit
import SwiftUI

/// Minimal public protocol. Animation values are constant presentation defaults.
struct PetState: Codable, Equatable {
    var speciesId: String
    var speciesName: String
    var renderedHunger: Int { 70 }
    var renderedMood: Int { 0 }
    enum CodingKeys: String, CodingKey {
        case speciesId = "species_id"
        case speciesName = "species_name"
    }
    static let placeholder = PetState(speciesId: "nara", speciesName: "Nara")
}

// MARK: - Mood / hunger derived state

enum HungerBand {
    case hungry, peckish, content, stuffed
    init(_ hunger: Int) {
        switch hunger {
        case ..<30:  self = .hungry
        case 30..<60: self = .peckish
        case 60..<85: self = .content
        default:     self = .stuffed
        }
    }
    var label: String {
        switch self {
        case .hungry:  return "hungry"
        case .peckish: return "peckish"
        case .content: return "content"
        case .stuffed: return "stuffed"
        }
    }
}

enum MoodBand {
    case sad, neutral, happy
    init(_ mood: Int) {
        switch mood {
        case ..<(-20): self = .sad
        case 20...:    self = .happy
        default:       self = .neutral
        }
    }
    var emoji: String {
        switch self {
        case .sad:     return "😟"
        case .neutral: return "🙂"
        case .happy:   return "😄"
        }
    }
}

// MARK: - Character appearance catalog

struct SpeciesInfo {
    let id: String
    let name: String
    let family: String            // debugging | wisdom | creativity | speed | chaos | curiosity
    let kind: String              // animal noun for the console subtitle ("hedgehog")
    let sfSymbol: String          // fallback when no PNG asset bundled
    let tintHex: String           // accent color as #RRGGBB (source of truth)
    let imageName: String?        // basename of bundled PNG in Resources/, nil = SF Symbol only
    let model3DName: String?        // basename of bundled .usdz in Resources/, nil = procedural 3D

    /// Accent color for SwiftUI (SF Symbol fallback + UI accents).
    var tint: Color { Color(hex: tintHex) }
    /// Accent color for RealityKit materials.
    var nsTint: NSColor { NSColor(hex: tintHex) }
    /// "hedgehog · creativity" — the console header subtitle.
    var subtitle: String { "\(kind) · \(family)" }
}

enum SpeciesCatalog {
    static let baseSpecies: [String: SpeciesInfo] = [
        // Rodin-generated characters; expressions are baked whole-texture
        // variants (PetReality's baked-face path), not a petFace decal.
        "mochi": SpeciesInfo(id: "mochi", name: "Mochi", family: "wisdom",     kind: "shiba",    sfSymbol: "dog.fill",  tintHex: "#E8964F", imageName: "mochi_portrait", model3DName: "mochi"),
        "nara": SpeciesInfo(id: "nara", name: "Nara", family: "curiosity", kind: "deer", sfSymbol: "leaf.fill", tintHex: "#FF6B6B", imageName: "nara_portrait", model3DName: "nara"),
        "lumi": SpeciesInfo(id: "lumi", name: "Lumi", family: "creativity", kind: "bunny", sfSymbol: "hare.fill", tintHex: "#8FC9E8", imageName: "lumi_portrait", model3DName: "lumi"),
        "pando": SpeciesInfo(id: "pando", name: "Pando", family: "wisdom", kind: "panda", sfSymbol: "teddybear.fill", tintHex: "#83B84E", imageName: "pando_portrait", model3DName: "pando"),
    ]

    static func info(for id: String) -> SpeciesInfo {
        baseSpecies[id] ?? baseSpecies["nara"]!
    }

    /// Every character is a directly pickable skin.
    static let pickableIds: [String] = [
        "nara",
        "mochi",
        "pando",
        "lumi",
    ]

    static var pickableSpecies: [SpeciesInfo] {
        pickableIds.map { info(for: $0) }
    }
}

/// Loads a PNG bundled under Sources/UselessPet/Resources/ via SwiftPM
/// app or SwiftPM resource bundle. Returns nil if the asset is missing.
func loadBundledImage(named base: String) -> NSImage? {
    guard let url = Bundle.uselesspetResources.url(forResource: base, withExtension: "png") else {
        return nil
    }
    return NSImage(contentsOf: url)
}

// MARK: - Color helper for #RRGGBB strings

extension Color {
    init(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}

extension NSColor {
    /// Parse a `#RRGGBB` string into an sRGB NSColor (for RealityKit materials).
    convenience init(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = CGFloat((v >> 16) & 0xFF) / 255.0
        let g = CGFloat((v >> 8) & 0xFF) / 255.0
        let b = CGFloat(v & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    /// Blend toward another color by `t` (0 = self, 1 = other), in sRGB.
    func blended(to other: NSColor, fraction t: CGFloat) -> NSColor {
        let a = usingColorSpace(.sRGB) ?? self
        let b = other.usingColorSpace(.sRGB) ?? other
        let f = max(0, min(1, t))
        return NSColor(
            srgbRed: a.redComponent + (b.redComponent - a.redComponent) * f,
            green: a.greenComponent + (b.greenComponent - a.greenComponent) * f,
            blue: a.blueComponent + (b.blueComponent - a.blueComponent) * f,
            alpha: 1.0
        )
    }
}
