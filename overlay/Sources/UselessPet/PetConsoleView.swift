import SwiftUI

enum CompanionPage: String { case home, picker, settings }

/// A small, voluntary interaction surface. All pet state comes from the daemon.
struct PetConsoleView: View {
    let model: ConsoleViewModel
    var onPet: () -> Void = {}
    var onSwitch: (String) -> Void = { _ in }
    var onToggle: () -> Void = {}
    var eyeIntent: ConsoleEyeIntent = .hide
    var pendingSpecies: String? = nil
    var feedback: L10nKey? = nil
    var snapshotLanguage: AppLanguage? = nil
    @State var page: CompanionPage = .home
    @AppStorage(AppLanguage.preferenceKey) private var languageCode = AppLanguage.english.rawValue
    @AppStorage("uselesspet.petScale") private var petScale = 1.0
    @AppStorage("uselesspet.petFollowsCursor") private var followsCursor = true

    private var language: AppLanguage { snapshotLanguage ?? AppLanguage.resolve(languageCode) }
    private func t(_ key: L10nKey) -> String { L10n.text(key, language: language) }

    private var accent: Color { Color(hex: model.accentHex) }
    private var visibilityLabel: String {
        switch eyeIntent {
        case .hide: return t(.hidePet)
        case .show: return t(.showPet)
        case .summon: return t(.summonPet)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            switch page {
            case .home: home
            case .picker: picker
            case .settings: settings
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale, Locale(identifier: language.rawValue))
    }

    private var header: some View {
        HStack {
            if page != .home {
                Button { page = .home } label: {
                    Image(systemName: "chevron.left").frame(width: 24, height: 24)
                }
                .buttonStyle(.plain).help(t(.back))
                .accessibilityLabel(t(.back)).accessibilityIdentifier("companion-back")
            }
            Text(page == .home ? L10n.appName : page == .picker ? t(.chooseTitle) : t(.settings))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Spacer()
            if page == .home {
                Button { page = .settings } label: {
                    Image(systemName: "gearshape").frame(width: 24, height: 24)
                }
                .buttonStyle(.plain).help(t(.settings))
                .accessibilityLabel(t(.settings)).accessibilityIdentifier("companion-settings")
            }
        }
        .foregroundStyle(.secondary)
    }

    private var home: some View {
        VStack(spacing: 14) {
            portrait(model.portrait, size: 136)
                .padding(.top, 2).accessibilityHidden(true)
            VStack(spacing: 5) {
                Text(model.petName).font(.system(size: 23, weight: .semibold, design: .rounded))
                    .accessibilityIdentifier("companion-name")
                Text(t(model.connected ? (feedback ?? .homeSubtitle) : .reconnecting))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("companion-feedback").frame(height: 18)
            }
            Button(action: onPet) {
                Label(t(.petAction), systemImage: "hand.draw")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 38)
                    .background(accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain).disabled(!model.connected)
            .accessibilityIdentifier("pet-companion")
            HStack(spacing: 10) {
                secondaryButton(t(.chooseAction), icon: "square.grid.2x2", id: "choose-companion") { page = .picker }
                secondaryButton(visibilityLabel, icon: eyeIntent == .show ? "eye" : "eye.slash", id: "toggle-companion", action: onToggle)
            }
        }
    }

    private var picker: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(model.roster) { entry in
                    let info = SpeciesCatalog.info(for: entry.id)
                    Button { onSwitch(entry.id) } label: {
                        VStack(spacing: 4) {
                            portrait(entry.portrait, size: 94)
                            HStack(spacing: 5) {
                                Text(info.name).font(.system(size: 13, weight: .medium))
                                if entry.selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(accent) }
                                if pendingSpecies == entry.id { ProgressView().controlSize(.mini) }
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(entry.selected ? accent.opacity(0.1) : Color.primary.opacity(0.035),
                                    in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(entry.selected ? accent.opacity(0.45) : .clear))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain).disabled(!model.connected || pendingSpecies != nil)
                    .accessibilityLabel(L10n.text(.switchTo, language: language, name: info.name))
                    .accessibilityValue(t(entry.selected ? .selected : .notSelected))
                    .accessibilityIdentifier("switch-pet-\(entry.id)")
                }
            }
            Text(t(!model.connected ? .pickerOffline : feedback ?? .pickerSubtitle))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Picker(t(.language), selection: Binding(get: { language.rawValue }, set: { languageCode = $0 })) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.nativeName).tag(language.rawValue)
                    }
                }.accessibilityIdentifier("companion-language")
                Text(t(.languageHint)).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(t(.sizeTitle)).font(.system(size: 12, weight: .medium))
                Picker(t(.sizeTitle), selection: $petScale) {
                    Text(t(.sizeSmall)).tag(0.5); Text(t(.sizeMedium)).tag(0.75); Text(t(.sizeLarge)).tag(1.0)
                }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("companion-size")
            }
            Toggle(t(.headTracking), isOn: $followsCursor).accessibilityIdentifier("companion-head-tracking")
            Divider()
            Button(t(.quit)) { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityIdentifier("companion-quit")
        }
        .font(.system(size: 13)).padding(.vertical, 8)
    }

    private func portrait(_ name: String, size: CGFloat) -> some View {
        Group {
            if let image = loadBundledImage(named: name) { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "pawprint.fill").resizable().scaledToFit().foregroundStyle(accent) }
        }.frame(width: size, height: size)
    }

    private func secondaryButton(_ label: String, icon: String, id: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon).font(.system(size: 11))
                .frame(maxWidth: .infinity).frame(height: 32)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }
}

struct PetConsolePanel: View {
    @ObservedObject var bridge: BridgeClient
    @ObservedObject var visibility: PetVisibility
    var onTogglePet: () -> Void = {}

    var body: some View {
        PetConsoleView(
            model: ConsoleViewModel.build(pet: bridge.pet, connected: bridge.status == .connected),
            onPet: { bridge.send(command: "cmd.pet") },
            onSwitch: { bridge.switchCompanion(to: $0) },
            onToggle: onTogglePet, eyeIntent: visibility.eyeIntent,
            pendingSpecies: bridge.pendingSpecies, feedback: bridge.companionFeedback
        )
    }
}

@MainActor
enum ConsoleSnapshot {
    static func dumpAll(to dir: String) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var failed = 0
        for language in AppLanguage.allCases {
          for scheme in [ColorScheme.light, .dark] {
            for page in [CompanionPage.home, .picker, .settings] {
                for connected in [true, false] where connected || page == .home {
                    let model = ConsoleViewModel.build(pet: .placeholder, connected: connected)
                    let content = PetConsoleView(model: model, snapshotLanguage: language, page: page).environment(\.colorScheme, scheme)
                    let name = "\(language.rawValue)-\(page.rawValue)-\(scheme == .dark ? "dark" : "light")-\(connected ? "online" : "offline")"
                    // ImageRenderer substitutes yellow placeholders for native
                    // AppKit pickers/toggles. Host the real controls instead.
                    let host = NSHostingView(rootView: content)
                    let size = host.fittingSize
                    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                          styleMask: .borderless, backing: .buffered, defer: false)
                    window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                    window.contentView = host
                    window.setFrameOrigin(NSPoint(x: -10000, y: 0))
                    window.orderFrontRegardless()
                    host.layoutSubtreeIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
                    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                        window.orderOut(nil); failed += 1; continue
                    }
                    host.cacheDisplay(in: host.bounds, to: rep)
                    window.orderOut(nil)
                    guard let png = rep.representation(using: .png, properties: [:]) else {
                        failed += 1; continue
                    }
                    try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
                    print("ConsoleSnapshot: rendered \(name)")
                }
            }
          }
        }
        print("ConsoleSnapshot: completed; failures=\(failed)")
        if failed > 0 { exit(1) }
    }
}
