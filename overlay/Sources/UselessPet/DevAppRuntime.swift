import AppKit
import Darwin

/// Local Dev bundles own a private service. Pet state remains in the Python daemon.
final class DevAppRuntime {
    static var isDev: Bool { Bundle.main.object(forInfoDictionaryKey: "UselessPetDev") as? Bool == true }
    static var buildLabel: String? { Bundle.main.object(forInfoDictionaryKey: "UselessPetDevBuild") as? String }
    private var service: Process?
    private var log: FileHandle?
    private var stopping = false

    func start() throws {
        guard Self.isDev else { return }
        guard let resources = Bundle.main.resourceURL,
              let python = Bundle.main.object(forInfoDictionaryKey: "UselessPetPython") as? String else {
            throw NSError(domain: "UselessPetDev", code: 1, userInfo: [NSLocalizedDescriptionKey: "The Dev app is incomplete. Run make install-dev again."])
        }
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/UselessPet Dev", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        // Set before constructing BridgeClient, so the view and service agree.
        setenv("USELESSPET_STATE_DIR", support.path, 1)
        setenv("USELESSPET_PORT", "17576", 1)
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/UselessPet Dev", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let logURL = logs.appendingPathComponent("service.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil,
                                           attributes: [.posixPermissions: 0o600])
        }
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        log = handle
        let process = Process()
        process.executableURL = resources.appendingPathComponent(python)
        process.arguments = ["-I", "-S", "-B", resources.appendingPathComponent("Backend/dev_bootstrap.py").path,
                             "--parent", String(ProcessInfo.processInfo.processIdentifier)]
        process.environment = ProcessInfo.processInfo.environment
        process.standardOutput = handle
        process.standardError = handle
        process.terminationHandler = { [weak self] child in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.stopping else { return }
                let alert = NSAlert()
                alert.messageText = "UselessPet Dev"
                alert.informativeText = "The local companion service stopped (\(child.terminationStatus)). Details are in ~/Library/Logs/UselessPet Dev/service.log. Please reopen the app."
                alert.runModal()
                NSApp.terminate(nil)
            }
        }
        try process.run()
        service = process
    }

    func stop() {
        stopping = true
        guard let process = service else { return }
        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(5)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        service = nil
        try? log?.close()
        log = nil
    }
}
