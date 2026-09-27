import Cocoa

if CommandLine.arguments.dropFirst().first == "--install" {
    exit(InputSourceInstaller.install())
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
