import AppKit

/// Detects a standalone Shift tap: Shift pressed and released with no other key or modifier in between.
struct ShiftToggleDetector {
    private static let relevantFlags: NSEvent.ModifierFlags = [.shift, .control, .option, .command, .function]

    private var previousFlags: NSEvent.ModifierFlags = []
    private var isStandaloneShift = false

    /// Returns true when this modifier change completes a standalone Shift tap.
    mutating func flagsChanged(_ flags: NSEvent.ModifierFlags) -> Bool {
        let flags = flags.intersection(Self.relevantFlags)
        defer { previousFlags = flags }

        if previousFlags.isEmpty && flags == .shift {
            isStandaloneShift = true
            return false
        }
        if previousFlags == .shift && flags.isEmpty {
            defer { isStandaloneShift = false }
            return isStandaloneShift
        }
        isStandaloneShift = false
        return false
    }

    /// Any key pressed while Shift is held makes it a modifier, not a toggle.
    mutating func keyDown() {
        isStandaloneShift = false
    }
}
