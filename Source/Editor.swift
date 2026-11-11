import AppKit
import AVFoundation
import NaturalLanguage

/// A small window to check, rewrite and translate text from apps that Nib cannot read directly,
/// such as Google Docs. "Paste Back" puts the result over the selection in the app it came from.
@MainActor
final class FloatingEditor: NSObject, NSWindowDelegate, NSTextViewDelegate {
    private var window: NSPanel?
    private var textView: NSTextView!
    private var status: NSTextField!
    private var pasteButton: NSButton!
    private var buttons: [NSControl] = []
    private var source: pid_t?
    private var busy = false { didSet { buttons.forEach { $0.isEnabled = !busy } } }
    private let speaker = AVSpeechSynthesizer()

    /// Pastes text into the app with this process id. Set by the app delegate.
    var pasteBack: ((String, pid_t) async -> Bool)?
    /// The user's instructions for the app the text came from.
    var instructions: ((pid_t?) -> String?)?

    func open(text: String?, from pid: pid_t?) {
        if window == nil { build() }
        source = pid
        if let text, !text.isEmpty { replace(NSRange(location: 0, length: (textView.string as NSString).length), with: text) }
        let name = pid.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
        pasteButton.title = name.map { "Paste Back to " + $0 } ?? "Paste Back"
        pasteButton.isHidden = pid == nil
        note(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(textView)
    }

    /// Shows the editor without new text. An editor that is already open only comes to the front:
    /// `open` would cut its link to the app that Paste Back goes to.
    func show() {
        guard let window, window.isVisible else {
            open(text: nil, from: nil)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// A picture of the editor with sample text, for `Nib --render`.
    func render(sample: String) -> Data? {
        if window == nil { build() }
        // The same path as text that comes from another app, so the picture shows what the user sees.
        replace(NSRange(location: 0, length: (textView.string as NSString).length), with: sample)
        pasteButton.title = "Paste Back to Notes"
        note("2 corrections applied. ⌘Z brings the old text back.")
        return window?.contentView?.png()
    }

    private func build() {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "Nib Editor"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = CGSize(width: 460, height: 240)
        panel.delegate = self
        panel.center()
        panel.setFrameAutosaveName("NibEditor")

        let scroll = NSTextView.scrollableTextView()
        scroll.borderType = .noBorder
        textView = scroll.documentView as? NSTextView
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = .textColor
        textView.typingAttributes = FloatingEditor.look
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = CGSize(width: 8, height: 10)
        textView.delegate = self

        let check = NSButton(title: "Check", target: self, action: #selector(check))
        check.keyEquivalent = "\r"
        check.keyEquivalentModifierMask = [.command]
        check.toolTip = "Correct spelling and grammar (⌘↩)"
        let rewrite = NSPopUpButton(frame: .zero, pullsDown: true)
        rewrite.addItem(withTitle: "Rewrite")
        for style in ProofEngine.Rewrite.allCases {
            rewrite.addItem(withTitle: style.title)
            rewrite.lastItem?.representedObject = ["style": style.rawValue]
        }
        rewrite.menu?.addItem(.separator())
        var languages = ["English"]
        let english = Locale(identifier: "en")
        for identifier in Locale.preferredLanguages {
            guard let code = Locale(identifier: identifier).language.languageCode?.identifier,
                  let name = english.localizedString(forLanguageCode: code), !languages.contains(name) else { continue }
            languages.append(name)
            if languages.count == 6 { break }
        }
        for language in languages {
            rewrite.addItem(withTitle: "Translate to " + language)
            rewrite.lastItem?.representedObject = ["language": language]
        }
        rewrite.target = self
        rewrite.action = #selector(rewriteChosen(_:))
        rewrite.toolTip = "Rewrites the selection, or all text when nothing is selected"
        let speak = NSButton(title: "Speak", target: self, action: #selector(speak))
        let copy = NSButton(title: "Copy", target: self, action: #selector(copyAll))
        pasteButton = NSButton(title: "Paste Back", target: self, action: #selector(paste))
        pasteButton.keyEquivalent = "\r"
        pasteButton.keyEquivalentModifierMask = [.command, .shift]
        pasteButton.toolTip = "Replace the selection in the other app with this text (⇧⌘↩)"
        buttons = [check, rewrite, speak, copy, pasteButton]

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let bar = NSStackView(views: [check, rewrite, speak, spacer, copy, pasteButton])
        bar.orientation = .horizontal
        bar.spacing = 8
        status = NSTextField(labelWithString: "")
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail

        let column = NSStackView(views: [scroll, bar, status])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 8
        column.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 10, right: 0)
        column.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            column.topAnchor.constraint(equalTo: content.topAnchor),
            column.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: column.widthAnchor),
            bar.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -12),
            status.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 14),
            status.trailingAnchor.constraint(lessThanOrEqualTo: column.trailingAnchor, constant: -14)
        ])
        panel.contentView = content
        window = panel
    }

    /// The font and colour of all text in the editor. The colour follows light and dark mode.
    private static let look: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.textColor]

    /// Replaces text through the text view's own edit path, so ⌘Z brings the old text back.
    private func replace(_ range: NSRange, with text: String) {
        guard textView.shouldChangeText(in: range, replacementString: text) else { return }
        // Plain text put into the storage gets the storage's default look: black and small.
        // In dark mode that is black on a dark window. So the text carries the editor's font and colour.
        textView.textStorage?.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: FloatingEditor.look))
        textView.typingAttributes = FloatingEditor.look
        textView.didChangeText()
    }

    private func note(_ message: String?) {
        let text = textView.string
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        let counts = "\(words) \(words == 1 ? "word" : "words") · \(text.count) characters"
        status.stringValue = message.map { $0 + "   ·   " + counts } ?? counts
    }

    func textDidChange(_ notification: Notification) {
        if !busy { note(nil) }
    }

    @objc private func check() {
        guard !busy, !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        busy = true
        note("Checking…")
        let original = textView.string
        let extra = instructions?(source)
        Task { [weak self] in
            // Long drafts go paragraph by paragraph, so each part fits the model.
            var parts: [String] = []
            var fixes = 0
            for paragraph in original.components(separatedBy: "\n") {
                if paragraph.utf16.count <= Proofreader.maxSelectionLength,
                   let result = await Proofreader.proofread(paragraph, extra: extra) {
                    parts.append(result.text)
                    fixes += result.fixes
                } else {
                    parts.append(paragraph)
                }
            }
            guard let self else { return }
            self.busy = false
            guard self.textView.string == original else {
                self.note("The text changed during the check. Check again.")
                return
            }
            if fixes > 0 {
                self.replace(NSRange(location: 0, length: (original as NSString).length), with: parts.joined(separator: "\n"))
                self.note("\(fixes) \(fixes == 1 ? "correction" : "corrections") applied. ⌘Z brings the old text back.")
            } else {
                self.note("No corrections found.")
            }
        }
    }

    @objc private func rewriteChosen(_ sender: NSPopUpButton) {
        guard !busy, let choice = sender.selectedItem?.representedObject as? [String: String] else { return }
        let whole = NSRange(location: 0, length: (textView.string as NSString).length)
        let range = textView.selectedRange().length > 0 ? textView.selectedRange() : whole
        let original = (textView.string as NSString).substring(with: range)
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard original.utf16.count <= ProofEngine.maxRewriteLength else {
            note("Select a shorter part to rewrite, up to \(ProofEngine.maxRewriteLength) characters.")
            return
        }
        busy = true
        note(choice["language"] == nil ? "Rewriting…" : "Translating…")
        let before = textView.string
        Task { [weak self] in
            let result = await ProofEngine.rewrite(original, style: choice["style"].flatMap(ProofEngine.Rewrite.init) ?? .clearer,
                                                   translateTo: choice["language"])
            guard let self else { return }
            self.busy = false
            guard self.textView.string == before else {
                self.note("The text changed in the meantime. Try again.")
                return
            }
            guard let result else {
                self.note("No rewrite is available for this text.")
                return
            }
            self.replace(range, with: result)
            self.note("Done. ⌘Z brings the old text back.")
        }
    }

    @objc private func speak() {
        if speaker.isSpeaking {
            speaker.stopSpeaking(at: .immediate)
            return
        }
        let selected = textView.selectedRange()
        let text = selected.length > 0 ? (textView.string as NSString).substring(with: selected) : textView.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        if let language = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue {
            utterance.voice = AVSpeechSynthesisVoice(language: language)
        }
        speaker.speak(utterance)
    }

    @objc private func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textView.string, forType: .string)
        note("Copied.")
    }

    @objc private func paste() {
        guard !busy, let source, let app = NSRunningApplication(processIdentifier: source), !app.isTerminated else {
            note("The other app is closed. Use Copy.")
            return
        }
        let text = textView.string
        busy = true
        window?.orderOut(nil)
        app.activate()
        Task { [weak self] in
            // The other app needs a moment to come to the front and take the keyboard.
            for _ in 0..<20 where NSWorkspace.shared.frontmostApplication?.processIdentifier != source {
                try? await Task.sleep(for: .milliseconds(50))
            }
            try? await Task.sleep(for: .milliseconds(150))
            let done = await self?.pasteBack?(text, source) ?? false
            guard let self else { return }
            self.busy = false
            if !done {
                self.open(text: nil, from: source)
                self.note("Could not paste into the other app. Use Copy.")
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        speaker.stopSpeaking(at: .immediate)
    }
}
