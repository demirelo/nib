// The clipboard path for apps that do not give or take text through Accessibility: ⌘C to read the
// selection, ⌘V to paste a result, and the user's own clipboard that always comes back.

import AppKit
import ApplicationServices
import Carbon.HIToolbox

extension Desktop {
    // MARK: Clipboard

    private func clipboardItems(_ board: NSPasteboard) -> [NSPasteboardItem]? {
        var saved: [NSPasteboardItem] = []
        var total = 0
        for item in board.pasteboardItems ?? [] {
            let copy = NSPasteboardItem()
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }
                total += data.count
                guard total <= 8 * 1024 * 1024, copy.setData(data, forType: type) else { return nil }
            }
            saved.append(copy)
        }
        return saved
    }

    private func shortcut(_ key: CGKeyCode, to pid: pid_t) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(pid)
        up.postToPid(pid)
        return true
    }

    /// The key that types this letter together with ⌘ in the keyboard layout in use.
    /// A key code names a position on the keyboard, not a letter: on Dvorak, position 8 is not "c".
    private func keyCode(for letter: String, fallback: CGKeyCode) -> CGKeyCode {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return fallback }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        return data.withUnsafeBytes { bytes -> CGKeyCode in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return fallback }
            // First with ⌘ held, because layouts such as "Dvorak – QWERTY ⌘" move the letters for shortcuts.
            for modifiers in [UInt32(cmdKey >> 8), 0] {
                for code in UInt16(0)...50 {
                    var dead: UInt32 = 0
                    var length = 0
                    var characters = [UniChar](repeating: 0, count: 4)
                    let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), modifiers, UInt32(LMGetKbdType()),
                                                OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &characters)
                    if status == noErr, length == 1,
                       String(utf16CodeUnits: characters, count: 1).lowercased() == letter { return CGKeyCode(code) }
                }
            }
            return fallback
        }
    }

    /// Puts the old clipboard back when an app answered a ⌘C from Nib only after Nib stopped waiting.
    private func settleLateCopy() {
        guard let late = lateCopy else { return }
        lateCopy = nil
        let board = NSPasteboard.general
        guard board.changeCount != late.count else { return }
        board.clearContents()
        if !late.saved.isEmpty { board.writeObjects(late.saved) }
    }

    func copySelection(from pid: pid_t) async -> String? {
        // The gate once more, at the last step: for an app that Nib must not read, nothing below runs.
        // No value is read and no ⌘C is sent, which in a password manager would copy a password.
        guard !copying, !mustNotRead(pid) else { return nil }
        if let element = focusedElement(of: pid),
           let selection = readAttribute(element, axSelectedText) as? String, !selection.isEmpty { return selection }
        settleLateCopy()
        let board = NSPasteboard.general
        let before = board.changeCount
        guard let saved = clipboardItems(board), board.changeCount == before else { return nil }
        copying = true
        defer { copying = false }
        guard shortcut(keyCode(for: "c", fallback: 8), to: pid) else { return nil }
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(25))
            if board.changeCount != before {
                let copied = board.changeCount
                let text = board.string(forType: .string)
                if board.changeCount == copied {
                    board.clearContents()
                    if !saved.isEmpty { board.writeObjects(saved) }
                }
                return NSWorkspace.shared.frontmostApplication?.processIdentifier == pid ? text : nil
            }
        }
        // The app did not copy in time. Its copy can still arrive, and then the user's clipboard
        // would be lost. So the saved clipboard waits two more seconds and comes back if that happens.
        lateCopy = (saved, before)
        Task { [weak self] in
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, let late = self.lateCopy, late.count == before else { return }
                if NSPasteboard.general.changeCount != before {
                    self.settleLateCopy()
                    return
                }
            }
            if let self, self.lateCopy?.count == before { self.lateCopy = nil }
        }
        return nil
    }

    /// Pastes over the selection of another app: a manual result, or Paste Back from the editor.
    /// When Nib can read the field, the old clipboard comes back as soon as the field changed,
    /// and a paste that changed nothing counts as failed.
    func pasteOverSelection(_ text: String, into pid: pid_t) async -> Bool {
        guard !mustNotRead(pid), let element = focusedElement(of: pid),
              let before = readAttribute(element, axValue) as? String, let range = selectedRange(element),
              range.location >= 0, range.length >= 0, range.location + range.length <= before.utf16.count else {
            return await paste(text, into: pid)
        }
        let selected = (before as NSString).substring(with: NSRange(location: range.location, length: range.length))
        func differs() -> Bool { (readAttribute(element, axValue) as? String).map { $0 != before } ?? true }
        guard await paste(text, into: pid, until: differs) else { return false }
        // A rich editor may format what it pastes, so the exact text is not compared here.
        return differs() || selected == text
    }

    /// Pastes text over the current selection. Only an explicit Apply uses the clipboard,
    /// and its previous contents come back afterwards.
    /// `landed` tells when the app took the text. Without it Nib cannot know and waits a fixed time.
    func paste(_ text: String, into pid: pid_t, until landed: (() -> Bool)? = nil) async -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
        settleLateCopy()
        let clipboard = NSPasteboard.general
        let originalCount = clipboard.changeCount
        guard let saved = clipboardItems(clipboard), clipboard.changeCount == originalCount else { return false }
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string) else { return false }
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        clipboard.clearContents()
        func restore(ifCount count: Int) {
            guard clipboard.changeCount == count else { return }
            clipboard.clearContents()
            if !saved.isEmpty { clipboard.writeObjects(saved) }
        }
        guard clipboard.writeObjects([item]) else {
            restore(ifCount: clipboard.changeCount)
            return false
        }
        let editCount = clipboard.changeCount
        let posted = shortcut(keyCode(for: "v", fallback: 9), to: pid)
        // The target app reads the clipboard a moment after the key press. If the old clipboard
        // came back before that, a slow app would paste the old clipboard over the selection.
        if posted {
            if let landed {
                var waited = 0
                while !landed(), waited < 1_500 {
                    try? await Task.sleep(for: .milliseconds(50))
                    waited += 50
                }
            } else {
                try? await Task.sleep(for: .milliseconds(450))
            }
        }
        restore(ifCount: editCount)
        return posted
    }
}
