import AppKit

let identifier = "io.github.LarryZYN.UselessPet.Dev"
let apps = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
for app in apps {
    guard app.bundleURL?.lastPathComponent == "UselessPet Dev.app", app.terminate() else {
        fputs("Could not quit the installed UselessPet Dev app.\n", stderr)
        exit(1)
    }
}
let deadline = Date().addingTimeInterval(12)
while apps.contains(where: { !$0.isTerminated }) && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}
guard apps.allSatisfy({ $0.isTerminated }) else {
    fputs("Dev app did not quit; keeping the installed app intact.\n", stderr)
    exit(1)
}
