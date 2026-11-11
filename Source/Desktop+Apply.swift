// Applying a suggestion: Apply, Apply All and Dismiss, the replacement of text in the other app,
// and the caret that goes back to its place.

import AppKit
import ApplicationServices

extension Desktop {
    @objc func applyAll() {
        // Apply All takes corrections only. A style suggestion is a choice for each sentence.
        let corrections = issues.filter { !$0.suggestion }
        guard !applying, manualDraft == nil, let first = corrections.first else { return }
        // From the end of the text to the start, so earlier positions stay valid.
        let list = corrections.sorted { $0.draft.range.location > $1.draft.range.location }
        let spot = panelAnchor()
        // Where the user's caret was. Each fix before it in the text moves it by the change in length.
        let start = lastField.flatMap { CFEqual($0.element, first.draft.element) ? $0.caret : nil }
        applying = true
        clear()
        Task { [weak self] in
            guard let self else { return }
            var done = 0
            var failure: String?
            var caret = start
            var textChanged = false
            for issue in list {
                guard let text = self.readAttribute(issue.draft.element, axValue) as? String,
                      NSMaxRange(issue.draft.range) <= text.utf16.count,
                      (text as NSString).substring(with: issue.draft.range) == issue.draft.text else {
                    failure = "the text changed"
                    textChanged = true
                    break
                }
                // `atCaret` stops a caret move after each fix. The caret goes back once, after the last fix.
                let draft = Draft(pid: issue.draft.pid, element: issue.draft.element, range: issue.draft.range,
                                  text: issue.draft.text, atCaret: true)
                let field = Field(pid: draft.pid, element: draft.element, text: text, caret: caret ?? NSMaxRange(draft.range))
                if let reason = await self.apply(issue.fix, to: draft, in: field) {
                    failure = reason
                    break
                }
                done += 1
                self.count("applied")
                if let position = caret {
                    let length = issue.fix.utf16.count
                    if position >= NSMaxRange(draft.range) {
                        caret = position + length - draft.range.length
                    } else if position > draft.range.location {
                        // The caret was inside this sentence: it stays, but not past the new end.
                        caret = min(position, draft.range.location + length)
                    }
                }
            }
            // Not after "the text changed": then the user is typing and the caret is theirs.
            if let caret, !textChanged {
                self.restoreCaret(NSRange(location: caret, length: 0), in: first.draft.element)
            }
            self.applying = false
            self.note((failure.map { "FAILED apply all after \(done): " + $0 } ?? "applied all \(done)"), app: first.draft.pid)
            if failure != nil { NSSound.beep() }
            self.flash(failure == nil ? "✓  \(done) corrections applied" : "Applied \(done) of \(list.count). The rest did not apply", at: spot)
        }
    }

    @objc func dismissFix() {
        if let completion {
            declinedCompletions.set(true, for: completion.prefix)
            clear()
            return
        }
        if shown != nil || manualDraft != nil { count("dismissed") }
        clearManual()
        if let shown { dismissed.set(true, for: shown.text) }
        clear()
    }

    @objc func accept() {
        if let manual = manualDraft, let replacement = offeredFix {
            acceptManual(manual, replacement: replacement)
            return
        }
        if completion != nil {
            acceptCompletion()
            return
        }
        guard !applying, let draft = shown, let replacement = offeredFix else { return }
        let spot = panelAnchor()
        guard let field = readField(), field.pid == draft.pid, CFEqual(field.element, draft.element),
              NSMaxRange(draft.range) <= field.text.utf16.count,
              (field.text as NSString).substring(with: draft.range) == draft.text else {
            clear()
            report("the text changed before the click", at: spot, app: draft.pid)
            return
        }
        applying = true
        clear()
        Task { [weak self] in
            guard let self else { return }
            let failure = await self.apply(replacement, to: draft, in: field)
            self.applying = false
            if let failure { self.report(failure, at: spot, app: draft.pid) } else { self.note("applied", app: draft.pid); self.count("applied") }
        }
    }

    /// Replaces the sentence with its correction. Returns nil on success, or the reason it failed.
    /// It tries the changed words first, then the whole sentence; for each, direct replacement, then paste.
    private func apply(_ replacement: String, to draft: Draft, in field: Field) async -> String? {
        let edit = ProofEngine.edit(from: draft.text, to: replacement)
        let small = NSRange(location: draft.range.location + edit.range.location, length: edit.range.length)
        let attempts = [(range: small, old: edit.original, new: edit.replacement),
                        (range: draft.range, old: draft.text, new: replacement)]
        var reasons: [String] = []
        for (index, attempt) in attempts.enumerated() {
            // A fix away from the caret must not move the caret.
            let shift = attempt.new.utf16.count - attempt.range.length
            let restore: NSRange? = draft.atCaret ? nil :
                NSRange(location: field.caret >= NSMaxRange(attempt.range) ? field.caret + shift : field.caret, length: 0)
            guard let reason = await replace(attempt.range, old: attempt.old, new: attempt.new, in: draft.element,
                                             pid: draft.pid, text: field.text, restore: restore,
                                             onFailure: NSRange(location: field.caret, length: 0)) else { return nil }
            reasons.append((index == 0 ? "words: " : "sentence: ") + reason)
        }
        return reasons.joined(separator: "; ")
    }

    /// Replaces one range of the editor's text: directly when the editor allows it, else by paste.
    /// Returns nil on success, or the reason it failed.
    /// `text` is the editor's text before the change. `onFailure` is the user's caret: a failure puts it back,
    /// because a sentence that stays selected is deleted by the user's next key.
    func replace(_ range: NSRange, old: String, new: String, in element: AXUIElement, pid: pid_t,
                 text: String, restore: NSRange?, onFailure: NSRange) async -> String? {
        // Success means that the editor holds exactly this text. "The text changed" is not enough:
        // a late paste of the old clipboard also changes it.
        let expected = (text as NSString).replacingCharacters(in: range, with: new)
        func fail(_ reason: String) -> String {
            restoreCaret(onFailure, in: element)
            return reason
        }
        guard await select(range, expecting: old, in: element) else { return fail("selection refused") }
        if settable(element, axSelectedText),
           AXUIElementSetAttributeValue(element, axSelectedText, new as CFString) == .success,
           await holds(expected, in: element) {
            restoreCaret(restore, in: element)
            return nil
        }
        // Paste only into the text as it was. If the direct replacement changed it in some other way,
        // a paste on top would add the fix a second time.
        guard matches(text, in: element) else {
            if matches(expected, in: element) {   // a slow direct replacement that landed after all
                restoreCaret(restore, in: element)
                return nil
            }
            return fail("unexpected text after direct replacement")
        }
        // Paste only while the old text is still selected.
        var stillSelected = ((readAttribute(element, axSelectedText) as? String) ?? "") == old
        if !stillSelected { stillSelected = await select(range, expecting: old, in: element) }
        guard stillSelected else { return fail("selection lost before paste") }
        guard await paste(new, into: pid, until: { self.matches(expected, in: element) }) else {
            return fail("paste not possible")
        }
        if matches(expected, in: element) {
            restoreCaret(restore, in: element)
            return nil
        }
        return fail(matches(text, in: element) ? "no change after paste" : "unexpected text after paste")
    }

    /// Some editors show a no-break space where the text has a plain one.
    private func plain(_ string: String) -> String { string.replacingOccurrences(of: "\u{00A0}", with: " ") }

    private func matches(_ expected: String, in element: AXUIElement) -> Bool {
        (readAttribute(element, axValue) as? String).map { plain($0) == plain(expected) } ?? false
    }

    /// Selects a range and confirms that the editor selected exactly the expected text.
    private func select(_ range: NSRange, expecting text: String, in element: AXUIElement) async -> Bool {
        guard let value = rangeValue(range),
              AXUIElementSetAttributeValue(element, axRange, value) == .success else { return false }
        for _ in 0..<8 {
            if let selected = selectedRange(element), selected.location == range.location, selected.length == range.length {
                if range.length == 0 { return true }   // an insertion point selects no text
                guard let selectedText = readAttribute(element, axSelectedText) as? String else { return false }
                return plain(selectedText) == plain(text)
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return false
    }

    /// Editors apply changes a moment after the request. Waits briefly for the expected text.
    private func holds(_ expected: String, in element: AXUIElement) async -> Bool {
        for _ in 0..<12 {
            if matches(expected, in: element) { return true }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return false
    }

    private func restoreCaret(_ range: NSRange?, in element: AXUIElement) {
        guard let range, let value = rangeValue(range) else { return }
        AXUIElementSetAttributeValue(element, axRange, value)
    }
}
