import Foundation
import SharedModels

public final class RimeBridgeEngine: ChineseInputEngine {
    private let session: RimeBridgeSession
    private var recentText = ""
    private var lastKnownState = CompositionState()

    public init(configuration: RimeBridgeConfiguration) throws {
        let runtime = try RimeBridgeRuntime.shared(configuration: configuration)
        self.session = try runtime.makeSession(defaultSchemaID: configuration.defaultSchemaID)
    }

    deinit {
        session.destroy()
    }

    public func process(_ event: InputKeyEvent) -> InputSessionUpdate {
        guard let translatedKey = RimeKeyTranslator.translate(event) else {
            return InputSessionUpdate(handled: false, state: lastKnownState)
        }

        let handled = session.process(keyCode: translatedKey.keycode, mask: translatedKey.mask)
        let commitText = session.readCommitText()
        if let commitText, !commitText.isEmpty {
            recentText = commitText
        }

        lastKnownState = session.currentState(recentText: recentText)
        return InputSessionUpdate(handled: handled, state: lastKnownState, commitText: commitText)
    }

    public func selectCandidate(at index: Int) -> InputSessionUpdate {
        guard index >= 0 else {
            return InputSessionUpdate(handled: false, state: lastKnownState)
        }

        let handled = session.selectCandidateOnCurrentPage(index: index)
        let commitText = session.readCommitText()
        if let commitText, !commitText.isEmpty {
            recentText = commitText
        }

        lastKnownState = session.currentState(recentText: recentText)
        return InputSessionUpdate(handled: handled, state: lastKnownState, commitText: commitText)
    }

    public func highlightCandidate(at index: Int) -> InputSessionUpdate {
        guard index >= 0 else {
            return InputSessionUpdate(handled: false, state: lastKnownState)
        }

        let handled = session.highlightCandidateOnCurrentPage(index: index)
        lastKnownState = session.currentState(recentText: recentText)
        return InputSessionUpdate(handled: handled, state: lastKnownState)
    }

    public func reset() {
        session.reset()
        lastKnownState = CompositionState()
    }
}

private enum RimeKeyTranslator {
    private static let shiftMask: Int32 = 1 << 0
    private static let controlMask: Int32 = 1 << 2
    private static let altMask: Int32 = 1 << 3
    private static let superMask: Int32 = 1 << 26

    private static let backspace: Int32 = 0xff08
    private static let tab: Int32 = 0xff09
    private static let clear: Int32 = 0xff0b
    private static let returnKey: Int32 = 0xff0d
    private static let escape: Int32 = 0xff1b
    private static let delete: Int32 = 0xffff
    private static let home: Int32 = 0xff50
    private static let left: Int32 = 0xff51
    private static let up: Int32 = 0xff52
    private static let right: Int32 = 0xff53
    private static let down: Int32 = 0xff54
    private static let pageUp: Int32 = 0xff55
    private static let pageDown: Int32 = 0xff56
    private static let end: Int32 = 0xff57

    struct TranslatedKey {
        let keycode: Int32
        let mask: Int32
    }

    static func translate(_ event: InputKeyEvent) -> TranslatedKey? {
        let mask = modifierMask(from: event.modifierFlags)
        if let special = specialKeycode(for: event.keyCode) {
            return TranslatedKey(keycode: special, mask: mask)
        }

        let source = event.charactersIgnoringModifiers.isEmpty
            ? event.characters
            : event.charactersIgnoringModifiers

        guard let scalar = source.unicodeScalars.first else {
            return nil
        }

        return TranslatedKey(keycode: Int32(scalar.value), mask: mask)
    }

    private static func modifierMask(from flags: UInt) -> Int32 {
        var mask: Int32 = 0

        let shiftFlag = 1 << 17
        let controlFlag = 1 << 18
        let optionFlag = 1 << 19
        let commandFlag = 1 << 20

        if flags & UInt(shiftFlag) != 0 {
            mask |= shiftMask
        }
        if flags & UInt(controlFlag) != 0 {
            mask |= controlMask
        }
        if flags & UInt(optionFlag) != 0 {
            mask |= altMask
        }
        if flags & UInt(commandFlag) != 0 {
            mask |= superMask
        }

        return mask
    }

    private static func specialKeycode(for keyCode: UInt16) -> Int32? {
        switch keyCode {
        // Space: IMK sometimes delivers keyDown with empty `characters`; map by keyCode so Rime still receives XK_space.
        case 49:
            return 0x20
        case 36, 76:
            return returnKey
        case 48:
            return tab
        case 51:
            return backspace
        case 53:
            return escape
        case 71:
            return clear
        case 115:
            return home
        case 116:
            return pageUp
        case 117:
            return delete
        case 119:
            return end
        case 121:
            return pageDown
        case 123:
            return left
        case 124:
            return right
        case 125:
            return down
        case 126:
            return up
        default:
            return nil
        }
    }
}
