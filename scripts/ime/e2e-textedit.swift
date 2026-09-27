import AppKit
import Carbon

// End-to-end smoke test for SmartIMEHost in a real client (TextEdit).
//
// Usage: swiftc -O -o /tmp/ime-e2e scripts/ime/e2e-textedit.swift && /tmp/ime-e2e
//
// - Needs Accessibility permission for the terminal (synthetic key and mouse events).
// - Opens a new TextEdit document, selects SmartIMEHost, types for ~20 seconds, then closes
//   the document without saving and restores the previous input source and app.
//   Do not touch the keyboard or mouse while it runs.
// - Candidate order comes from librime and its user dictionary, so the `huiyi + 6` and
//   `ceshi + 2` expectations can drift; read the printed text when a check fails.

let keyCodes: [Character: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
    "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
    "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40,
    "n": 45, "m": 46,
]
let space: CGKeyCode = 49, returnKey: CGKeyCode = 36, escape: CGKeyCode = 53

func run(_ script: String) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    let pipe = Pipe()
    process.standardOutput = pipe
    try! process.run()
    process.waitUntilExit()
    return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .newlines)
}

func sourceID(_ source: TISInputSource) -> String {
    Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(source, kTISPropertyInputSourceID)!).takeUnretainedValue() as String
}

func select(_ id: String) {
    let filter = [kTISPropertyInputSourceID: id as CFString] as CFDictionary
    if let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource], let source = list.first {
        TISSelectInputSource(source)
    }
}

let originalSource = sourceID(TISCopyCurrentKeyboardInputSource().takeRetainedValue())
let originalApp = NSWorkspace.shared.frontmostApplication

print("Starting in 3 seconds; do not use the keyboard or mouse for about 20 seconds.")
_ = run("display notification \"约 20 秒内请勿操作键盘和鼠标\" with title \"SmartIME 自动测试即将开始\"")
Thread.sleep(forTimeInterval: 3)

_ = run("tell application \"TextEdit\" to activate")
_ = run("tell application \"TextEdit\" to make new document")
Thread.sleep(forTimeInterval: 1.0)
let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first!.processIdentifier
select("lab.dcyber.inputmethod.smartime")
Thread.sleep(forTimeInterval: 1.0)

let eventSource = CGEventSource(stateID: .hidSystemState)
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
        let event = CGEvent(keyboardEventSource: eventSource, virtualKey: 56, keyDown: !flags.isEmpty)!
        event.type = .flagsChanged
        event.flags = flags
        event.postToPid(pid)
        Thread.sleep(forTimeInterval: 0.08)
    }
    Thread.sleep(forTimeInterval: 0.2)
}
func type(_ text: String) {
    for character in text { press(keyCodes[character]!) }
    Thread.sleep(forTimeInterval: 0.4)
}
func documentText() -> String {
    Thread.sleep(forTimeInterval: 0.5)
    return run("tell application \"TextEdit\" to get text of front document")
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

var passed = 0, failed = 0
func check(_ name: String, _ expected: String, _ actual: String) {
    let ok = actual == expected
    if ok { passed += 1 } else { failed += 1 }
    print("\(ok ? "PASS" : "FAIL")  \(name): expected \"\(expected)\", got \"\(actual)\"")
}

type("nihao")
let host = NSRunningApplication.runningApplications(withBundleIdentifier: "lab.dcyber.inputmethod.smartime").first
print("running IME: \(host?.bundleURL?.path ?? "none")")
let nihaoPanel = panelFrame()
print("panel for nihao: \(nihaoPanel.map { "\(Int($0.width))x\(Int($0.height))" } ?? "not visible")")
press(space)
check("nihao + Space", "你好", documentText())

type("huiyi")
let huiyiPanel = panelFrame()
print("panel for huiyi: \(huiyiPanel.map { "\(Int($0.width))x\(Int($0.height))" } ?? "not visible")")
press(keyCodes["6"]!)
check("huiyi + 6 (translation)", "你好meeting", documentText())

type("hello")
press(space)
check("hello + Space (English first)", "你好meetinghello", documentText())

type("women")
press(returnKey)
check("women + Return (raw input)", "你好meetinghellowomen", documentText())

type("zhongguo")
press(escape)
Thread.sleep(forTimeInterval: 0.3)
print("panel after Escape: \(panelFrame() == nil ? "hidden" : "STILL VISIBLE")")
check("zhongguo + Escape (cancel)", "你好meetinghellowomen", documentText())

type("ceshi")
press(keyCodes["2"]!)
let afterCeshi = documentText()
check("ceshi + 2 commits a Chinese candidate", "true", String(afterCeshi.count == "你好meetinghellowomen".count + 2 && afterCeshi.hasPrefix("你好meetinghellowomen")))

// Standalone Shift tap switches to English mode; Shift+letter would not.
tapShift()
type("he")
let englishPanel = panelFrame()
print("panel for English 'he': \(englishPanel.map { "\(Int($0.width))x\(Int($0.height))" } ?? "not visible")")
press(space)
check("English mode he + Space", afterCeshi + "he ", documentText())
tapShift()

type("shujuku")
if let frame = panelFrame() {
    print("panel for shujuku: \(Int(frame.width))x\(Int(frame.height))")
    // First row centre: 4pt outer padding + half of a ~26pt row, in global (top-left origin) coordinates.
    let point = CGPoint(x: frame.midX, y: frame.minY + 4 + 13)
    let originalMouse = CGEvent(source: nil)!.location
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.08)
    }
    CGWarpMouseCursorPosition(originalMouse)
    check("shujuku + click row 1", afterCeshi + "he 数据库", documentText())
} else {
    failed += 1
    print("FAIL  shujuku panel not visible for click test")
}

print("final text: \"\(documentText())\"")
print("RESULT: \(passed) passed, \(failed) failed")

_ = run("tell application \"TextEdit\" to close front document saving no")
select(originalSource)
originalApp?.activate()
exit(failed == 0 ? 0 : 1)
