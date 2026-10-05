import AppKit
import Carbon.HIToolbox

/// System-wide hotkeys (Carbon `RegisterEventHotKey`, no permission needed), dispatched by ID. One
/// application event handler serves all of them.
@MainActor
final class GlobalHotkeys {
    static let shared = GlobalHotkeys()

    enum ID: UInt32 {
        case aiRead = 1
        case screenshot = 2
        case screenshotOCR = 3
    }

    private static let signature = OSType(0x534D4149) // 'SMAI'

    private var refs: [ID: EventHotKeyRef] = [:]
    private var actions: [ID: @MainActor () -> Void] = [:]
    private var handlerInstalled = false

    private init() {}

    /// Replaces any hotkey registered under `id`. Returns the Carbon status (`noErr`, or e.g.
    /// `eventHotKeyExistsErr` when another app holds the same combination).
    @discardableResult
    func register(_ hotkey: TranslationHotkey, id: ID, action: @escaping @MainActor () -> Void) -> OSStatus {
        installHandlerIfNeeded()
        unregister(id)
        var modifiers: UInt32 = 0
        for (flag, carbon) in [(NSEvent.ModifierFlags.control, controlKey), (.option, optionKey), (.shift, shiftKey), (.command, cmdKey)]
        where hotkey.modifiers.contains(flag) {
            modifiers |= UInt32(carbon)
        }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(hotkey.keyCode), modifiers, EventHotKeyID(signature: Self.signature, id: id.rawValue),
            GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr, let ref {
            refs[id] = ref
            actions[id] = action
        }
        return status
    }

    func unregister(_ id: ID) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        actions[id] = nil
    }

    private func fire(_ rawID: UInt32) {
        guard let id = ID(rawValue: rawID) else {
            return
        }
        actions[id]?()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else {
            return
        }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr, hotKeyID.signature == GlobalHotkeys.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let id = hotKeyID.id
            Task { @MainActor in
                GlobalHotkeys.shared.fire(id)
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
