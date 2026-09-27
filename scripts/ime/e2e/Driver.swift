import AppKit
import Carbon

// End-to-end smoke test for SmartIMEHost, driven against the throwaway SmartIMETestClient app
// (never against the user's apps or documents). Run through scripts/ime/dev-cycle.sh.
//
// Usage: SmartIMEDriver <path to SmartIMETestClient.app>
//
// - Needs Accessibility permission for the terminal (synthetic key and mouse events are posted
//   from this process, which the terminal launches).
// - Waits until the keyboard and mouse have been idle for 5 seconds, then takes about 20 seconds.
//   It aborts as soon as it sees a real key press or the test window losing focus.
// - Candidate order comes from librime and its user dictionary, so the `huiyi + 6` and
//   `ceshi + 2` expectations can drift; read the printed text when a check fails.

let testClientBundleID = "lab.dcyber.smartime.testclient"
let imeSourceID = "lab.dcyber.inputmethod.smartime"
let keyCodes: [Character: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
    "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
    "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40,
    "n": 45, "m": 46,
]
let space: CGKeyCode = 49, returnKey: CGKeyCode = 36, escape: CGKeyCode = 53, shiftKey: CGKeyCode = 56

func sourceID(_ source: TISInputSource) -> String {
    Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(source, kTISPropertyInputSourceID)!).takeUnretainedValue() as String
}

func select(_ id: String) {
    let filter = [kTISPropertyInputSourceID: id as CFString] as CFDictionary
    if let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource], let source = list.first {
        TISSelectInputSource(source)
    }
}

func secondsSinceUserInput() -> Double {
    let types: [CGEventType] = [.keyDown, .flagsChanged, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]
    return types.map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }.min() ?? .infinity
}

guard CommandLine.arguments.count > 1 else {
    print("usage: SmartIMEDriver <path to SmartIMETestClient.app>")
    exit(2)
}
let clientApp = CommandLine.arguments[1]

// 1. Wait for the user to stop typing or moving the mouse.
print("Waiting for 5 seconds without keyboard or mouse input...")
let waitStart = Date()
while secondsSinceUserInput() < 5 {
    if Date().timeIntervalSince(waitStart) > 90 {
        print("ABORT: keyboard or mouse kept being used for 90 seconds; not starting.")
        exit(3)
    }
    Thread.sleep(forTimeInterval: 0.5)
}
_ = try? Process.run(URL(fileURLWithPath: "/usr/bin/osascript"),
                     arguments: ["-e", "display notification \"约 20 秒内请勿操作键盘和鼠标\" with title \"SmartIME 自动测试开始\""])

// 2. Launch the test client with a fresh state directory.
let originalSource = sourceID(TISCopyCurrentKeyboardInputSource().takeRetainedValue())
let originalApp = NSWorkspace.shared.frontmostApplication
let stateDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("smartime-e2e-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
let launch = try Process.run(URL(fileURLWithPath: "/usr/bin/open"), arguments: ["-n", clientApp, "--args", stateDirectory.path])
launch.waitUntilExit()

let readyFile = stateDirectory.appendingPathComponent("ready")
let launchStart = Date()
while !FileManager.default.fileExists(atPath: readyFile.path) {
    if Date().timeIntervalSince(launchStart) > 10 {
        print("ABORT: the test client window never became active.")
        exit(3)
    }
    Thread.sleep(forTimeInterval: 0.1)
}
guard let client = NSRunningApplication.runningApplications(withBundleIdentifier: testClientBundleID).last else {
    print("ABORT: test client process not found.")
    exit(3)
}
let pid = client.processIdentifier

var passed = 0, failed = 0
func finish(_ message: String? = nil) -> Never {
    if let message { print(message) }
    select(originalSource)
    client.terminate()
    originalApp?.activate()
    try? FileManager.default.removeItem(at: stateDirectory)
    print("RESULT: \(passed) passed, \(failed) failed\(message == nil ? "" : " (aborted)")")
    exit(message == nil && failed == 0 ? 0 : 1)
}

let testStart = Date()
/// Stops the run if the user pressed a key or the test window lost focus.
func guardNoInterference() {
    let sinceStart = Date().timeIntervalSince(testStart)
    if CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown) < sinceStart {
        finish("ABORT: a real key press was detected during the test.")
    }
    if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
        finish("ABORT: the test window is no longer frontmost.")
    }
}

select(imeSourceID)
Thread.sleep(forTimeInterval: 1.0)

// Private event source: synthetic events must not look like real HID input to guardNoInterference().
let eventSource = CGEventSource(stateID: .privateState)
func press(_ code: CGKeyCode, flags: CGEventFlags = []) {
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: down)!
        event.flags = flags
        event.postToPid(pid)
        Thread.sleep(forTimeInterval: 0.05)
    }
    Thread.sleep(forTimeInterval: 0.15)
}
func tapShift() {
    // A standalone Shift tap arrives as two flagsChanged events, not keyDown/keyUp.
    for flags: CGEventFlags in [.maskShift, []] {
        let event = CGEvent(keyboardEventSource: eventSource, virtualKey: shiftKey, keyDown: !flags.isEmpty)!
        event.type = .flagsChanged
        event.flags = flags
        event.postToPid(pid)
        Thread.sleep(forTimeInterval: 0.08)
    }
    Thread.sleep(forTimeInterval: 0.2)
}
func type(_ text: String) {
    guardNoInterference()
    for character in text { press(keyCodes[character]!) }
    Thread.sleep(forTimeInterval: 0.4)
}
func committedText() -> String {
    Thread.sleep(forTimeInterval: 0.4)
    return (try? String(contentsOf: stateDirectory.appendingPathComponent("text.txt"), encoding: .utf8)) ?? ""
}
func markedText() -> String {
    Thread.sleep(forTimeInterval: 0.3)
    return (try? String(contentsOf: stateDirectory.appendingPathComponent("marked.txt"), encoding: .utf8)) ?? ""
}
func panelFrame() -> CGRect? {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    for window in windows where (window[kCGWindowOwnerName as String] as? String) == "SmartIMEHost" {
        if let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] {
            return CGRect(x: bounds["X"]!, y: bounds["Y"]!, width: bounds["Width"]!, height: bounds["Height"]!)
        }
    }
    return nil
}
func describe(_ frame: CGRect?) -> String {
    frame.map { "\(Int($0.width))x\(Int($0.height))" } ?? "not visible"
}
func check(_ name: String, _ expected: String, _ actual: String) {
    let ok = actual == expected
    if ok { passed += 1 } else { failed += 1 }
    print("\(ok ? "PASS" : "FAIL")  \(name): expected \"\(expected)\", got \"\(actual)\"")
}

let host = NSRunningApplication.runningApplications(withBundleIdentifier: imeSourceID).first
type("nihao")
print("running IME: \(host?.bundleURL?.path ?? "none")")
print("panel for nihao: \(describe(panelFrame()))")
press(space)
check("nihao + Space", "你好", committedText())

type("huiyi")
print("panel for huiyi: \(describe(panelFrame()))")
press(keyCodes["6"]!)
check("huiyi + 6 (translation)", "你好meeting", committedText())

type("hello")
press(space)
check("hello + Space (English first)", "你好meetinghello", committedText())

type("women")
press(returnKey)
check("women + Return (raw input)", "你好meetinghellowomen", committedText())

type("zhongguo")
press(escape)
Thread.sleep(forTimeInterval: 0.3)
print("panel after Escape: \(panelFrame() == nil ? "hidden" : "STILL VISIBLE")")
check("zhongguo + Escape (cancel)", "你好meetinghellowomen", committedText())

type("good")
check("good shows raw input while composing", "good", markedText())
press(escape)

type("ceshi")
press(keyCodes["2"]!)
let afterCeshi = committedText()
check("ceshi + 2 commits a Chinese candidate", "true",
      String(afterCeshi.count == "你好meetinghellowomen".count + 2 && afterCeshi.hasPrefix("你好meetinghellowomen")))

guardNoInterference()
tapShift()
type("he")
print("panel for English 'he': \(describe(panelFrame()))")
press(space)
check("English mode he + Space", afterCeshi + "he ", committedText())
tapShift()

type("shujuku")
if let frame = panelFrame() {
    print("panel for shujuku: \(describe(frame))")
    if secondsSinceUserInput() < Date().timeIntervalSince(testStart) {
        finish("ABORT: keyboard or mouse input was detected before the click step.")
    }
    // First row centre in Chinese mode: 4pt outer padding + ~21pt preedit header + half of a ~26pt row,
    // in global (top-left origin) coordinates.
    let point = CGPoint(x: frame.midX, y: frame.minY + 4 + 21 + 13)
    let originalMouse = CGEvent(source: nil)!.location
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.08)
    }
    CGWarpMouseCursorPosition(originalMouse)
    check("shujuku + click row 1", afterCeshi + "he 数据库", committedText())
} else {
    failed += 1
    print("FAIL  shujuku panel not visible for click test")
}

let beforeGith = committedText()
type("gith")
press(keyCodes["2"]!)
check("gith + 2 (promoted completion, display casing)", beforeGith + "GitHub", committedText())

print("final text: \"\(committedText())\"")
finish()
