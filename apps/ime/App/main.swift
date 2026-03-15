import Cocoa

final class NSManualApplication: NSApplication {}

let delegate = AppDelegate()
NSManualApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
