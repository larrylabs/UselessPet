import Foundation

extension Bundle {
    static let uselesspetResources: Bundle = {
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let url = Bundle.main.resourceURL?.appendingPathComponent("UselessPet_UselessPet.bundle"),
                  let resources = Bundle(url: url) else {
                fatalError("The UselessPet app is missing its bundled character resources. Reinstall the app.")
            }
            return resources
        }
        return .module
    }()
}
