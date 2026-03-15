import AppKit
import InputMethodKit
import SharedModels

public final class IMEInputController: IMKInputController {
    private let sessionStore = IMEHostSessionStore()

    public override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    public override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown else {
            return false
        }

        switch event.keyCode {
        case 36, 76:
            commitCurrentComposition(using: sender)
            return true
        case 51:
            sessionStore.deleteBackward()
            updateComposition()
            return true
        default:
            break
        }

        guard let characters = event.characters, !characters.isEmpty else {
            return false
        }

        guard shouldHandle(characters: characters) else {
            return false
        }

        sessionStore.append(characters)
        updateComposition()
        return true
    }

    public override func composedString(_ sender: Any!) -> Any! {
        let composition = sessionStore.state.compositionText
        return composition.isEmpty ? nil : composition
    }

    public override func originalString(_ sender: Any!) -> NSAttributedString! {
        NSAttributedString(string: sessionStore.state.rawInput)
    }

    public override func candidates(_ sender: Any!) -> [Any]! {
        sessionStore.state.candidates.map(\.text)
    }

    public override func commitComposition(_ sender: Any!) {
        commitCurrentComposition(using: sender)
    }

    private func commitCurrentComposition(using sender: Any?) {
        guard let committedText = sessionStore.commitTextIfReady() else {
            return
        }

        if let client = (sender as AnyObject?) as? NSTextInputClient {
            client.insertText(committedText, replacementRange: NSRange(location: NSNotFound, length: 0))
        } else if let client = self.client() as? NSTextInputClient {
            client.insertText(committedText, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }

    private func shouldHandle(characters: String) -> Bool {
        characters.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar)
        }
    }
}
