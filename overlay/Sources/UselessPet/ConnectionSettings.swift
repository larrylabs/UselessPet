import Foundation

enum ConnectionSettings {
    static var url: URL {
        let raw = ProcessInfo.processInfo.environment["USELESSPET_PORT"] ?? "17574"
        let port = Int(raw).flatMap { (1...65535).contains($0) ? $0 : nil } ?? 17574
        return URL(string: "ws://127.0.0.1:\(port)/")!
    }
    static var tokenFile: URL {
        let environment = ProcessInfo.processInfo.environment
        let directory: URL
        if let path = environment["USELESSPET_STATE_DIR"] {
            directory = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        } else {
            directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/UselessPet", isDirectory: true)
        }
        return directory.appendingPathComponent("bridge.token")
    }
}
