// Actions the user asks for on selected text: Proofread, Rewrite, Translate, Read Aloud
// and Open Editor.

import AppKit
import ApplicationServices
import AVFoundation
import NaturalLanguage

extension Desktop {
    @objc func openEditor() {
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            editor.show()
            return
        }
        let pid = app.processIdentifier
        // The editor still opens over an app that Nib does not read, but empty and with no link to that app.
        guard !refuse(pid) else {
            editor.show()
            return
        }
        clearManual()
        clear()
        Task { [weak self] in
            guard let self else { return }
            let selection = AXIsProcessTrusted() ? await self.copySelection(from: pid) : nil
            self.editor.open(text: selection, from: pid)
        }
    }

    func rewriteMenu() -> NSMenu {
        let menu = NSMenu()
        for style in ProofEngine.Rewrite.allCases {
            let item = menu.addItem(withTitle: style.title, action: #selector(rewriteChosen(_:)), keyEquivalent: style == .clearer ? "r" : "")
            item.keyEquivalentModifierMask = [.control, .option]
            item.representedObject = ["style": style.rawValue]
        }
        menu.addItem(.separator())
        // English first, then the languages this Mac prefers.
        var languages = ["English"]
        let english = Locale(identifier: "en")
        for identifier in Locale.preferredLanguages {
            guard let code = Locale(identifier: identifier).language.languageCode?.identifier,
                  let name = english.localizedString(forLanguageCode: code), !languages.contains(name) else { continue }
            languages.append(name)
            if languages.count == 6 { break }
        }
        for language in languages {
            menu.addItem(withTitle: "Translate to " + language, action: #selector(rewriteChosen(_:)), keyEquivalent: "")
                .representedObject = ["language": language]
        }
        return menu
    }

    @objc private func rewriteChosen(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? [String: String] else { return }
        if let style = choice["style"] { preferences.set(style, forKey: "lastRewrite") }
        rewriteSelection(style: choice["style"].flatMap(ProofEngine.Rewrite.init) ?? .clearer, language: choice["language"])
    }

    func rewriteSelection(style: ProofEngine.Rewrite, language: String?) {
        // A request that waits for the model is replaced by the new one. Only a ⌘C in flight blocks.
        guard !applying, !copying, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else {
            NSSound.beep()
            return
        }
        let pid = app.processIdentifier
        guard !refuse(pid) else { return }
        clearManual()
        clear()
        let anchor = selectionAnchor(pid)
        manualRun += 1
        let run = manualRun
        manualPid = pid
        manualRequest = Task { [weak self] in
            guard let self else { return }
            // A cancelled request can end late. It must not touch the state of a newer one.
            let current = { !Task.isCancelled && self.manualRun == run }
            defer { if self.manualRun == run { self.manualRequest = nil } }
            guard let draft = await self.copySelection(from: pid), current(),
                  !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                if current() { NSSound.beep() }
                return
            }
            guard draft.utf16.count <= ProofEngine.maxRewriteLength else {
                self.flash("The selection is too long to rewrite", at: anchor)
                return
            }
            self.flash(language == nil ? "Rewriting…" : "Translating…", at: anchor, seconds: 60)
            let result = await ProofEngine.rewrite(draft, style: style, translateTo: language)
            // Cancelled: whoever cancelled it already took the notice away.
            guard current() else { return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                self.hidePanel()
                return
            }
            guard let result else {
                self.flash("No rewrite is available", at: anchor)
                return
            }
            self.manualDraft = (pid, draft)
            self.offeredFix = result
            self.pair = nil
            self.showPanel(title: language == nil ? "✓  Use rewrite: " + style.title : "✓  Use translation",
                           detail: result, at: anchor, note: result.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    @objc func readAloud() {
        if speaker.isSpeaking {
            speaker.stopSpeaking(at: .immediate)
            return
        }
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { NSSound.beep(); return }
        let pid = app.processIdentifier
        guard !refuse(pid) else { return }
        Task { [weak self] in
            guard let self, let text = await self.copySelection(from: pid),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { NSSound.beep(); return }
            let utterance = AVSpeechUtterance(string: String(text.prefix(20_000)))
            if let language = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue {
                utterance.voice = AVSpeechSynthesisVoice(language: language)
            }
            self.speaker.speak(utterance)
        }
    }

    // MARK: Proofread selected text

    @objc func proofreadSelection() {
        // A request that waits for the model is replaced by the new one. Only a ⌘C in flight blocks.
        guard !applying, !copying, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else {
            NSSound.beep()
            return
        }
        let pid = app.processIdentifier
        guard !refuse(pid) else { return }
        clearManual()
        clear()
        let anchor = selectionAnchor(pid)
        manualRun += 1
        let run = manualRun
        manualPid = pid
        manualRequest = Task { [weak self] in
            guard let self else { return }
            // A cancelled request can end late. It must not touch the state of a newer one.
            let current = { !Task.isCancelled && self.manualRun == run }
            defer { if self.manualRun == run { self.manualRequest = nil } }
            guard let draft = await copySelection(from: pid), current() else {
                if current() { NSSound.beep() }
                return
            }
            guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { NSSound.beep(); return }
            guard draft.utf16.count <= Proofreader.maxSelectionLength else {
                flash("Select less text: up to \(Proofreader.maxSelectionLength) characters", at: anchor, seconds: 3)
                return
            }
            let result = await Proofreader.proofread(draft, extra: self.appInstructions(for: pid))
            // Three different endings. Cancelled, or the user changed the app: say nothing.
            // Only a finished check of the app in front may say "No corrections".
            guard current(), NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            guard let result else {
                flash("✓  No corrections", at: anchor)
                return
            }
            manualDraft = (pid, draft)
            offeredFix = result.text
            pair = result.single
            count("shown")
            let title = result.single.map { self.label(from: $0.old, to: $0.new) } ?? "✓  Apply \(result.fixes) corrections"
            showPanel(title: title, detail: result.text, at: anchor)
        }
    }

    private func selectionAnchor(_ pid: pid_t) -> CGRect {
        if let element = focusedElement(of: pid), let range = selectedRange(element), range.length > 0,
           let rect = bounds(element, for: NSRange(location: range.location, length: range.length)) {
            return rect
        }
        return mouseAnchor()
    }

    /// A place for a notice that needs no read of the other app.
    func mouseAnchor() -> CGRect {
        let mouse = NSEvent.mouseLocation
        let top = (NSScreen.screens.first?.frame.maxY ?? 0) - mouse.y
        return CGRect(x: mouse.x - 130, y: top + 3, width: 0, height: 1)
    }

    func clearManual() {
        // A running request shows a notice such as "Rewriting…". It goes away with the request.
        if manualDraft != nil || manualRequest != nil { hidePanel() }
        manualRequest?.cancel()
        // Nil at once, not when the cancelled task ends: the model can take a minute to notice.
        manualRequest = nil
        manualPid = nil
        manualRun += 1
        manualDraft = nil
    }

    func acceptManual(_ manual: (pid: pid_t, text: String), replacement: String) {
        guard !applying else { return }
        applying = true
        let spot = panelAnchor()
        clearManual()
        clear()
        Task { [weak self] in
            guard let self else { return }
            let selection = await self.copySelection(from: manual.pid)
            let done = selection == manual.text ? await self.pasteOverSelection(replacement, into: manual.pid) : false
            self.applying = false
            if done { self.note("applied to selection", app: manual.pid); self.count("applied") }
            else { self.report(selection == manual.text ? "selection: paste not possible" : "the selection changed", at: spot, app: manual.pid) }
        }
    }
}
