import AppKit
import InputMethodKit
import RimeBridge
import SharedModels

public final class IMEInputController: IMKInputController {
    private let sessionStore = IMEHostSessionStore()
    private let chineseEngine: ChineseInputEngine?

    public override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        do {
            chineseEngine = try RimeBridgeEngine(
                configuration: RimeBridgeConfiguration(
                    sharedDataDirectory: IMEHostConfiguration.rimeSharedDataDirectory(),
                    userDataDirectory: IMEHostConfiguration.rimeUserDataDirectory(),
                    prebuiltDataDirectory: IMEHostConfiguration.rimeBuildDirectory(),
                    stagingDirectory: IMEHostConfiguration.rimeBuildDirectory(),
                    appName: "rime.smartime",
                    distributionName: "SmartIME Host",
                    distributionCodeName: "smart-ime",
                    distributionVersion: "0.1.0",
                    defaultSchemaID: IMEHostConfiguration.defaultSchemaID
                )
            )
        } catch {
            chineseEngine = nil
        }

        super.init(server: server, delegate: delegate, client: inputClient)
    }

    public override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    public override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown else {
            return false
        }

        guard let chineseEngine else {
            return false
        }

        let update = chineseEngine.process(
            InputKeyEvent(
                keyCode: event.keyCode,
                characters: event.characters ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                modifierFlags: event.modifierFlags.rawValue
            )
        )

        guard update.handled || update.commitText != nil || !update.state.compositionText.isEmpty else {
            return false
        }

        sessionStore.apply(update)
        if let committedText = update.commitText {
            commit(committedText, using: sender)
        }
        updateComposition()
        return update.handled || update.commitText != nil
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
        commit(sessionStore.state.compositionText, using: sender)
        chineseEngine?.reset()
        sessionStore.reset()
        updateComposition()
    }

    private func commit(_ committedText: String, using sender: Any?) {
        guard !committedText.isEmpty else {
            return
        }

        if let client = (sender as AnyObject?) as? NSTextInputClient {
            client.insertText(committedText, replacementRange: NSRange(location: NSNotFound, length: 0))
        } else if let client = self.client() as? NSTextInputClient {
            client.insertText(committedText, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }
}
