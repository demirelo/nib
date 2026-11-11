// The global keyboard shortcuts. They are registered with Carbon, which needs no extra permission.

import AppKit
import Carbon.HIToolbox

extension Desktop {
    // MARK: Keyboard shortcuts

    func installHotKeys() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let value = id.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated { Desktop.shared?.pressed(value) }
            }
            return noErr
        }, 1, &spec, nil, nil)
        register(.proofread, key: kVK_ANSI_P)
        register(.rewrite, key: kVK_ANSI_R)
        register(.editor, key: kVK_ANSI_F)
    }

    func register(_ hotKey: HotKey, key: Int, modifiers: Int = controlKey | optionKey) {
        guard hotKeys[hotKey.rawValue] == nil else { return }
        var reference: EventHotKeyRef?
        // The signature spells "NIBK" (Nib keys). It only has to be the same for every key of this app.
        let id = EventHotKeyID(signature: OSType(0x4E49_424B), id: hotKey.rawValue)
        if RegisterEventHotKey(UInt32(key), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &reference) == noErr,
           let reference {
            hotKeys[hotKey.rawValue] = reference
        }
    }

    func unregister(_ hotKey: HotKey) {
        guard let reference = hotKeys.removeValue(forKey: hotKey.rawValue) else { return }
        UnregisterEventHotKey(reference)
    }

    private func pressed(_ id: UInt32) {
        switch HotKey(rawValue: id) {
        case .proofread: proofreadSelection()
        case .apply, .applyPlain: accept()
        case .dismiss, .dismissPlain: dismissFix()
        case .explain: explainFix()
        case .editor: openEditor()
        case .rewrite:
            rewriteSelection(style: preferences.string(forKey: "lastRewrite").flatMap(ProofEngine.Rewrite.init) ?? .clearer, language: nil)
        case nil: break
        }
    }
}
