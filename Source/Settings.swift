import AppKit
import FoundationModels
import ServiceManagement

/// Saves which sentence model Nib uses. The settings window and the setup guide both save through here,
/// so one set of rules decides what is valid. No "modelServer" and no "modelName" means Apple's model.
@MainActor
enum ModelChoice {
    enum Outcome: Equatable {
        case saved
        /// The address is not on this Mac, or the model name is empty.
        case badAddress
        case noServer
        /// The server answers, but it does not have this model. Holds the models it has.
        case notOffered([String])
        /// The caller cancelled the task while the server was asked. Nothing was saved.
        case cancelled
    }

    /// False when Apple Intelligence is off or this Mac does not have it.
    static var appleAvailable: Bool { SystemLanguageModel.default.isAvailable }

    /// `onChange` runs after the save, so the app drops answers made with the old model.
    static func useApple(then onChange: (() -> Void)?) {
        UserDefaults.standard.removeObject(forKey: "modelServer")
        UserDefaults.standard.removeObject(forKey: "modelName")
        onChange?()
    }

    /// Saves a model of a server on this Mac, but only after the server answered and offers that model.
    static func useServer(_ server: String, model: String, then onChange: (() -> Void)?) async -> Outcome {
        let chosen = ProofConfig(server: server.trimmingCharacters(in: .whitespaces),
                                 model: model.trimmingCharacters(in: .whitespaces))
        let offered = await LocalServer.models(at: chosen.server)
        // A newer choice of the user replaced this one while the server was asked. It must not come back.
        guard !Task.isCancelled else { return .cancelled }
        guard chosen.localServer != nil else { return .badAddress }
        guard let offered else { return .noServer }
        guard offered.contains(chosen.model) else { return .notOffered(offered) }
        UserDefaults.standard.set(chosen.server, forKey: "modelServer")
        UserDefaults.standard.set(chosen.model, forKey: "modelName")
        onChange?()
        return .saved
    }
}

/// The settings window. Every control writes straight to the saved settings.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate, NSTextViewDelegate {
    private var window: NSWindow?
    private let defaults = UserDefaults.standard
    private var toggles: [(button: NSButton, key: String, fallback: Bool)] = []
    private var loginBox: NSButton!
    private var useServer: NSButton!
    private var useApple: NSButton!
    private var serverField: NSTextField!
    private var modelField: NSTextField!
    private var modelStatus: NSTextField!
    private var instructions: NSTextView!
    private var dictionary: NSTextView!
    private var snippets: NSTextView!

    /// Called after any setting changes, so the app drops answers made with the old settings.
    var onChange: (() -> Void)?

    /// The dictionary as this window last read or wrote it, in lower case. A word that is in the saved list
    /// but not here came from outside, for example from "Never Change" in the suggestion panel, and must be kept.
    private var knownWords: Set<String> = []

    /// The dictionary as it is saved: trimmed, no empty lines, one entry per word. The spelling stays as
    /// typed, because the checker keeps an entry such as iPhone or c++ letter for letter. Two entries that
    /// differ only in case are one word, and the first spelling wins. Every writer of "dictionary" uses this.
    nonisolated static func dictionaryEntries(_ lines: [String]) -> [String] {
        var seen: Set<String> = []
        let entries = lines.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        // The second key gives one fixed order to entries that are equal without case.
        return entries.sorted { ($0.lowercased(), $0) < ($1.lowercased(), $1) }
    }
    private var pendingSave: DispatchWorkItem?

    func open() {
        if window == nil { build() }
        // A window that is already open keeps its text: a reload would discard what is not saved yet.
        if window?.isVisible == true { adoptOutsideWords() } else { load() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// One picture per tab, for `Nib --render`.
    func render() -> [(name: String, png: Data)] {
        if window == nil { build() }
        load()
        guard let content = window?.contentView, let tabs = content.subviews.first as? NSTabView else { return [] }
        return tabs.tabViewItems.compactMap { item in
            tabs.selectTabViewItem(item)
            return content.png().map { ("settings-" + item.label.lowercased(), $0) }
        }
    }

    // MARK: Layout

    private func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func hint(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 440
        return label
    }

    private func toggle(_ title: String, key: String, fallback: Bool = false) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: #selector(toggled(_:)))
        toggles.append((button, key, fallback))
        return button
    }

    private func editor(lines: Int) -> (scroll: NSScrollView, view: NSTextView) {
        let scroll = NSTextView.scrollableTextView()
        scroll.borderType = .bezelBorder
        let view = scroll.documentView as! NSTextView
        view.font = .systemFont(ofSize: 13)
        view.isRichText = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.delegate = self
        scroll.heightAnchor.constraint(equalToConstant: CGFloat(lines) * 18 + 12).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 440).isActive = true
        return (scroll, view)
    }

    private func page(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        return stack
    }

    private func build() {
        loginBox = NSButton(checkboxWithTitle: "Open Nib at login", target: self, action: #selector(toggleLogin))
        let general = page([
            heading("Checks"),
            toggle("Check as I type in desktop apps", key: "enabled", fallback: true),
            toggle("Include apps beyond Claude, Codex, Telegram and Discord", key: "allApps", fallback: true),
            toggle("Underline every issue in the text field", key: "underlines", fallback: true),
            toggle("Suggest improvements for sentences without errors", key: "improvements", fallback: true),
            toggle("Pause checks on battery power", key: "pauseOnBattery"),
            heading("Typing"),
            toggle("Autocomplete: suggest the rest of the sentence (beta)", key: "autocomplete"),
            toggle("Tab applies and Esc dismisses while a suggestion shows", key: "plainKeys"),
            hint("Snippets, the dictionary and your instructions are in the Writing tab."),
            heading("Start"),
            loginBox
        ])

        useApple = NSButton(radioButtonWithTitle: "Apple's on-device model", target: self, action: #selector(modelChanged))
        useServer = NSButton(radioButtonWithTitle: "A model from Ollama or LM Studio on this Mac", target: self, action: #selector(modelChanged))
        serverField = NSTextField(string: "")
        serverField.placeholderString = "http://127.0.0.1:11434"
        modelField = NSTextField(string: "")
        modelField.placeholderString = "Model name, for example qwen3:latest"
        for field in [serverField!, modelField!] {
            field.widthAnchor.constraint(equalToConstant: 320).isActive = true
            field.target = self
            field.action = #selector(modelChanged)
        }
        modelStatus = hint("")
        let test = NSButton(title: "Save and Test", target: self, action: #selector(modelChanged))
        let model = page([
            heading("Sentence model"),
            useApple,
            hint("Needs no setup. Small and fast."),
            useServer,
            hint("Finds more errors and writes better rewrites. Uses more memory and battery. Nib accepts a server on this Mac only, so your text stays on your device."),
            serverField, modelField, test, modelStatus
        ])

        let instructionBox = editor(lines: 4)
        instructions = instructionBox.view
        let dictionaryBox = editor(lines: 4)
        dictionary = dictionaryBox.view
        let snippetBox = editor(lines: 5)
        snippets = snippetBox.view
        let writing = page([
            heading("Custom instructions"),
            hint("Tell the model how you write. Example: Keep informal expressions. Use British spelling."),
            instructionBox.scroll,
            heading("Dictionary"),
            hint("Words and phrases that Nib never changes. One per line."),
            dictionaryBox.scroll,
            heading("Snippets"),
            hint("One per line: name = text. Type \\name and a space to insert the text. Write \\n for a line break, \\\\n for a real \\n."),
            snippetBox.scroll
        ])

        let tabs = NSTabView()
        for (title, view) in [("General", general), ("Model", model), ("Writing", writing)] {
            let item = NSTabViewItem(identifier: title)
            item.label = title
            item.view = view
            tabs.addTabViewItem(item)
        }
        let panel = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 610),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Nib Settings"
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        tabs.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(tabs)
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            tabs.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            tabs.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            tabs.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10)
        ])
        panel.contentView = content
        panel.center()
        window = panel
        // Quit with the window open does not close the window first, so the text is saved here.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveText() }
        }
    }

    // MARK: Values

    private func load() {
        for (button, key, fallback) in toggles {
            button.state = (defaults.object(forKey: key) as? Bool ?? fallback) ? .on : .off
        }
        loginBox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let saved = ProofConfig.saved()
        useServer.state = saved.localServer != nil ? .on : .off
        useApple.state = saved.localServer != nil ? .off : .on
        serverField.stringValue = saved.server.isEmpty ? "http://127.0.0.1:11434" : saved.server
        modelField.stringValue = saved.model
        modelStatus.stringValue = ""
        instructions.string = saved.instructions
        dictionary.string = saved.dictionary.joined(separator: "\n")
        knownWords = Set(saved.dictionary.map { $0.lowercased() })
        snippets.string = ProofEngine.formatSnippets(defaults.dictionary(forKey: "snippets") as? [String: String] ?? [:])
        if saved.model.isEmpty { suggestModel() }
    }

    private func suggestModel() {
        let server = serverField.stringValue
        Task { [weak self] in
            let found = await LocalServer.models(at: server)
            guard let self, self.modelField.stringValue.isEmpty else { return }
            if let first = found?.first { self.modelField.stringValue = first }
            self.modelStatus.stringValue = found.map { $0.isEmpty ? "The server answers, but it has no models." : "Models found: " + $0.prefix(8).joined(separator: ", ") }
                ?? "No model server answers at " + server + "."
        }
    }

    @objc private func toggled(_ sender: NSButton) {
        guard let entry = toggles.first(where: { $0.button === sender }) else { return }
        defaults.set(sender.state == .on, forKey: entry.key)
        onChange?()
    }

    @objc private func toggleLogin() {
        do {
            if loginBox.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            loginBox.state = SMAppService.mainApp.status == .enabled ? .on : .off
            let alert = NSAlert()
            alert.messageText = "Could not change Open at Login"
            alert.informativeText = "You can add Nib in System Settings → General → Login Items."
            alert.runModal()
        }
    }

    @objc private func modelChanged() {
        if useApple.state == .on {
            ModelChoice.useApple(then: onChange)
            modelStatus.stringValue = "Nib uses Apple's on-device model."
            return
        }
        let server = serverField.stringValue, model = modelField.stringValue.trimmingCharacters(in: .whitespaces)
        modelStatus.stringValue = "Testing…"
        Task { [weak self] in
            let outcome = await ModelChoice.useServer(server, model: model, then: { self?.onChange?() })
            guard let self else { return }
            switch outcome {
            case .saved:
                self.modelStatus.stringValue = "Saved. Nib now uses " + model + ". If the server stops, Apple's model takes over."
            case .badAddress:
                self.modelStatus.stringValue = "Not saved. Enter an address on this Mac, such as http://127.0.0.1:11434, and a model name."
            case .noServer:
                self.modelStatus.stringValue = "Not saved. No server answers at that address. Start Ollama or LM Studio first."
            case .notOffered(let offered):
                self.modelStatus.stringValue = "Not saved. The server offers: " + offered.prefix(8).joined(separator: ", ")
            case .cancelled:
                break   // This task is never cancelled.
            }
        }
    }

    /// Adds the words that were saved from outside this window to its dictionary box. Returns them.
    @discardableResult
    private func adoptOutsideWords() -> Set<String> {
        // Compared without case: "iPhone" in the box and "iphone" in the saved list are the same word.
        let outside = Set((defaults.stringArray(forKey: "dictionary") ?? []).filter { !knownWords.contains($0.lowercased()) })
        guard !outside.isEmpty else { return [] }
        knownWords.formUnion(outside.map { $0.lowercased() })
        let typed = Set(dictionary.string.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        let missing = SettingsWindow.dictionaryEntries(outside.filter { !typed.contains($0.lowercased()) })
        if !missing.isEmpty {
            // Appended at the end, so the caret of a user who types in the box stays where it is.
            let lead = dictionary.string.isEmpty || dictionary.string.hasSuffix("\n") ? "" : "\n"
            dictionary.textStorage?.append(NSAttributedString(string: lead + missing.joined(separator: "\n"),
                                                               attributes: dictionary.typingAttributes))
        }
        return outside
    }

    private func saveText() {
        pendingSave?.cancel()
        pendingSave = nil
        guard window != nil else { return }
        // First take in what was saved from outside. Without this, the list in the box would
        // overwrite it and delete a word that "Never Change" added a moment ago.
        adoptOutsideWords()
        let note = instructions.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = SettingsWindow.dictionaryEntries(dictionary.string.split(whereSeparator: \.isNewline).map(String.init))
        let codes = ProofEngine.parseSnippets(snippets.string)
        // Nothing new: no write, and the app keeps the answers it already has.
        // The saved list is compared as written, so a change of case alone ("iphone" to "iPhone") is saved.
        if note == defaults.string(forKey: "instructions") ?? "",
           words == defaults.stringArray(forKey: "dictionary") ?? [],
           codes == defaults.dictionary(forKey: "snippets") as? [String: String] ?? [:] { return }
        defaults.set(note, forKey: "instructions")
        defaults.set(words, forKey: "dictionary")
        knownWords = Set(words.map { $0.lowercased() })
        defaults.set(codes, forKey: "snippets")
        onChange?()
    }

    /// Saves half a second after the last key, so text is not lost when the app quits or the Mac restarts.
    func textDidChange(_ notification: Notification) {
        pendingSave?.cancel()
        let save = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveText() }
        }
        pendingSave = save
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: save)
    }

    func textDidEndEditing(_ notification: Notification) { saveText() }

    func windowDidBecomeKey(_ notification: Notification) { adoptOutsideWords() }

    func windowWillClose(_ notification: Notification) { saveText() }
}
