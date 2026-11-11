import AppKit
import ApplicationServices
import AVFoundation
import Carbon.HIToolbox

// The Desktop class is one object in several files. This file holds its state, the launch and the menu.
// Each job has its own file: Desktop+Accessibility.swift, Desktop+LiveChecks.swift and so on.

// Accessibility attribute names that several of the files use.
let axValue = kAXValueAttribute as CFString
let axRange = kAXSelectedTextRangeAttribute as CFString
let axSelectedText = kAXSelectedTextAttribute as CFString

@main
@MainActor
final class Desktop: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// The focused editor at one moment.
    struct Field {
        let pid: pid_t
        let element: AXUIElement
        let text: String
        let caret: Int
        func sameText(_ other: Field) -> Bool {
            pid == other.pid && CFEqual(element, other.element) && text == other.text
        }
        func same(_ other: Field) -> Bool { sameText(other) && caret == other.caret }
    }

    /// One sentence of a field that has a suggested fix.
    struct Draft {
        let pid: pid_t
        let element: AXUIElement
        let range: NSRange
        let text: String
        let atCaret: Bool
    }

    /// A sentence with a correction that waits for the user.
    struct Issue {
        let draft: Draft
        let fix: String
        /// True for a style suggestion on a sentence that has no error.
        var suggestion = false
    }

    /// A small memory with a size limit. When it is full it forgets the oldest half, not everything:
    /// an empty memory would bring back every dismissed suggestion at once.
    struct Recent<Value> {
        let limit: Int
        private var values: [String: Value] = [:]
        private var order: [String] = []
        init(limit: Int) { self.limit = limit }
        var isEmpty: Bool { values.isEmpty }
        subscript(key: String) -> Value? { values[key] }
        func contains(_ key: String) -> Bool { values[key] != nil }
        mutating func set(_ value: Value, for key: String) {
            guard values.updateValue(value, forKey: key) == nil else { return }
            order.append(key)
            guard order.count > limit else { return }
            for old in order.prefix(limit / 2) { values.removeValue(forKey: old) }
            order.removeFirst(limit / 2)
        }
        mutating func removeAll() {
            values.removeAll()
            order.removeAll()
        }
    }

    struct BridgeError: LocalizedError {
        let errorDescription: String?
    }

    enum HotKey: UInt32 {
        case proofread = 1, apply, dismiss, explain, rewrite, applyPlain, dismissPlain, editor
    }

    static weak var shared: Desktop?

    let builtInApps: Set<String> = [
        "com.anthropic.claudefordesktop", "com.openai.codex", "com.openai.codex.with-1password",
        "com.tdesktop.Telegram", "ru.keepcoder.Telegram", "com.hnc.Discord",
        "com.hnc.DiscordCanary", "com.hnc.DiscordPTB"
    ]
    // Chromium browsers use the Nib extension instead.
    let extensionBrowsers: Set<String> = [
        "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac",
        "company.thebrowser.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "org.chromium.Chromium"
    ]
    // Beta and Canary builds, and web apps installed from these browsers. They are browsers, not code or passwords.
    let extensionBrowserPrefixes = ["com.google.Chrome.", "com.brave.Browser."]
    // Terminals, code editors and password managers hold text that is not prose.
    // Remote screens and virtual machines show another computer, where a password prompt is invisible to this Mac.
    // Nib never reads these apps, also not on an explicit shortcut.
    let neverChecked: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty", "io.alacritty", "org.alacritty", "com.github.wez.wezterm", "co.zeit.hyper",
        // com.todesktop.230313mzl4w4u92 is Cursor.
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92",
        "com.vscodium", "com.vscodium.VSCodiumInsiders", "com.exafunction.windsurf",
        "dev.zed.Zed", "com.apple.dt.Xcode", "com.sublimetext.4", "com.sublimetext.3", "com.panic.Nova",
        "com.barebones.bbedit", "com.macromates.TextMate", "com.macromates.textmate", "org.vim.MacVim", "org.gnu.Emacs",
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
        "com.apple.Passwords", "com.apple.keychainaccess", "com.lastpass.LastPass", "org.keepassxc.keepassxc",
        "com.dashlane.dashlanephonefinal", "me.proton.pass.electron", "com.callpod.keepermac.lite",
        "com.apple.ScreenSharing", "com.microsoft.rdc.macos", "com.vmware.fusion", "com.utmapp.UTM",
        "com.lemonmojo.RoyalTSX.App", "com.teamviewer.TeamViewer", "com.philandro.anydesk",
        "com.apple.loginwindow", "com.apple.SecurityAgent"
    ]
    // com.jetbrains. includes Fleet.
    let neverCheckedPrefixes = ["com.jetbrains.", "com.google.android.studio", "com.markmcguill.strongbox",
                                "in.sinew.Enpass-Desktop", "com.parallels.", "com.p5sys.jump.mac.viewer"]

    let preferences = UserDefaults.standard
    private var statusItem: NSStatusItem!
    private var permissionItem: NSMenuItem!
    private var modelItem: NSMenuItem!
    private var appItem: NSMenuItem!
    private var appHeader: NSMenuItem!
    private var statusLine: NSMenuItem!
    private var statsItem: NSMenuItem!
    private var appInstructionsItem: NSMenuItem!
    var detailLabel: NSTextField!
    var lastAnchor = CGRect.zero
    var explainTask: Task<Void, Never>?
    /// The sentence pair behind the suggestion on screen, for Explain and the dictionary.
    var pair: (old: String, new: String)?
    let speaker = AVSpeechSynthesizer()
    var batteryCheck = (at: Date.distantPast, onBattery: false)
    /// Every open issue in the focused field, in document order. The overlay underlines them.
    var issues: [Issue] = [] { didSet { issuesVersion += 1 } }
    /// Counts every change of `issues`, so an idle poll can tell that the underlines are still right.
    var issuesVersion = 0
    var drawn: (version: Int, frame: CGRect, probe: CGRect?)?
    /// Finished answers per sentence, so underlines come back at once while the user types elsewhere.
    var memo = Recent<String?>(limit: 3_000)
    /// Finished style suggestions per sentence. Nil inside means: the sentence is fine.
    var improved = Recent<String?>(limit: 3_000)
    var improvements: Bool { preferences.object(forKey: "improvements") as? Bool ?? true }
    var completion: (prefix: String, text: String, field: Field)?
    var declinedCompletions = Recent<Bool>(limit: 300)
    let overlay = Overlay()
    let editor = FloatingEditor()
    private let settings = SettingsWindow()
    private let welcome = WelcomeWindow()
    var underlines: Bool { preferences.object(forKey: "underlines") as? Bool ?? true }
    var autocomplete: Bool { preferences.bool(forKey: "autocomplete") }
    var snippets: [String: String] { preferences.dictionary(forKey: "snippets") as? [String: String] ?? [:] }
    var panel: NSPanel!
    var acceptButton: NSButton!
    var lastField: Field?
    var shown: Draft?
    var offeredFix: String?
    var pending: Task<Void, Never>?
    var generation = 0
    var dismissed = Recent<Bool>(limit: 500)
    private var timer: Timer?
    var applying = false
    var manualDraft: (pid: pid_t, text: String)?
    var manualRequest: Task<Void, Never>?
    /// The app a running manual request belongs to, and a number that tells an old request from the current one.
    var manualPid: pid_t?
    var manualRun = 0
    /// True while a ⌘C sent by Nib is on its way. A second copy in that time would read the wrong clipboard.
    var copying = false
    /// A clipboard that waits to come back because the app answered ⌘C too late.
    var lateCopy: (saved: [NSPasteboardItem], count: Int)?
    /// The last snippet code Nib tried to expand. A failed expansion is not tried again.
    var triedSnippet: (element: AXUIElement, text: String)?
    /// The label check of the focused element. It reads six attributes, so one answer per element is kept.
    var labelCheck: (element: AXUIElement, secret: Bool)?
    var exposed: Set<pid_t> = []
    var hotKeys: [UInt32: EventHotKeyRef] = [:]
    var enabled: Bool { preferences.object(forKey: "enabled") as? Bool ?? true }
    var allApps: Bool { preferences.object(forKey: "allApps") as? Bool ?? true }
    var pauseOnBattery: Bool { preferences.bool(forKey: "pauseOnBattery") }
    var plainKeys: Bool { preferences.bool(forKey: "plainKeys") }
    var pausedApps: Set<String> {
        get { Set(preferences.stringArray(forKey: "pausedApps") ?? []) }
        set { preferences.set(Array(newValue).sorted(), forKey: "pausedApps") }
    }

    static func main() {
        let app = NSApplication.shared
        let controller = Desktop()
        shared = controller
        app.setActivationPolicy(.accessory)
        app.delegate = controller
        app.run()
    }

    /// `Nib --render <folder>` writes pictures of the panel and the windows, then quits.
    /// It reads no text field and registers no shortcut.
    private func renderPictures(to folder: String) {
        var pictures: [(name: String, png: Data)] = settings.render()
        pictures += welcome.render()
        if let data = editor.render(sample: "Thanks for the quick reply. I will send you the file tomorrow.\n\nPlease let me know if you have any questions.") {
            pictures.append(("editor", data))
        }
        makePanel()
        for (name, title, note) in [("panel", "✓  two → to    +2", nil as String?),
                                    ("panel-explain", "✓  Their → They're", "“Their” shows possession. “They're” is the short form of “they are”, which this sentence needs.")] {
            acceptButton.title = title
            detailLabel.stringValue = note ?? ""
            detailLabel.isHidden = note == nil
            place(CGRect(x: 200, y: 200, width: 0, height: 16))
            if let data = panel.contentView?.png() { pictures.append((name, data)) }
        }
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        for picture in pictures {
            try? picture.png.write(to: URL(fileURLWithPath: folder).appendingPathComponent(picture.name + ".png"))
        }
        print("Wrote \(pictures.count) pictures to " + folder)
        exit(0)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = CommandLine.arguments.firstIndex(of: "--render"), index + 1 < CommandLine.arguments.count {
            renderPictures(to: CommandLine.arguments[index + 1])
        }
        if let index = CommandLine.arguments.firstIndex(of: "--icons"), index + 1 < CommandLine.arguments.count {
            do {
                try NibIcon.write(to: CommandLine.arguments[index + 1])
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Could not write the icons: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NibIcon.menuBar()
        statusItem.button?.toolTip = "Nib"
        let menu = NSMenu()
        menu.delegate = self
        // The top of the menu is about the app in front: its name, what Nib sees there, and the switch.
        appHeader = NSMenuItem.sectionHeader(title: "Front app")
        menu.addItem(appHeader)
        statusLine = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        permissionItem = menu.addItem(withTitle: "Enable Accessibility…", action: #selector(askAccessibility), keyEquivalent: "")
        appItem = menu.addItem(withTitle: "Check Text in This App", action: #selector(toggleApp(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        let proofread = menu.addItem(withTitle: "Proofread Selection", action: #selector(proofreadSelection), keyEquivalent: "p")
        proofread.keyEquivalentModifierMask = [.control, .option]
        let rewrite = menu.addItem(withTitle: "Rewrite Selection", action: nil, keyEquivalent: "")
        rewrite.submenu = rewriteMenu()
        let open = menu.addItem(withTitle: "Open Editor", action: #selector(openEditor), keyEquivalent: "f")
        open.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        // Everything that is used less often.
        let more = NSMenu()
        appInstructionsItem = more.addItem(withTitle: "Instructions for This App…", action: #selector(editAppInstructions(_:)), keyEquivalent: "")
        more.addItem(withTitle: "Read Selection Aloud", action: #selector(readAloud), keyEquivalent: "")
        more.addItem(.separator())
        more.addItem(withTitle: "Setup Guide…", action: #selector(openWelcome), keyEquivalent: "")
        more.addItem(withTitle: "Connect Browsers…", action: #selector(connectBrowsers), keyEquivalent: "")
        more.addItem(withTitle: "Diagnose Front App…", action: #selector(showDiagnosis), keyEquivalent: "")
        more.addItem(.separator())
        modelItem = more.addItem(withTitle: "", action: nil, keyEquivalent: "")
        statsItem = more.addItem(withTitle: "", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "More", action: nil, keyEquivalent: "").submenu = more
        menu.addItem(withTitle: "Quit Nib", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
        adopt(menu)
        statusItem.menu = menu
        installMainMenu()
        editor.pasteBack = { [weak self] text, pid in await self?.pasteOverSelection(text, into: pid) ?? false }
        editor.instructions = { [weak self] pid in pid.flatMap { self?.appInstructions(for: $0) } }
        settings.onChange = { [weak self] in self?.settingsChanged() }
        welcome.onChange = { [weak self] in self?.settingsChanged() }
        welcome.askAccessibility = { [weak self] in self?.askAccessibility() }
        welcome.openExtensionsPage = { [weak self] in self?.openExtensionsPage() }
        welcome.connectBrowsers = { [weak self] in
            do {
                try self?.installBrowserBridge()
                return nil
            } catch {
                return error.localizedDescription
            }
        }
        makePanel()
        refreshStatus()
        installHotKeys()
        let poll = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        poll.tolerance = 0.1   // lets the system group wake-ups
        RunLoop.main.add(poll, forMode: .common)
        timer = poll
        // The guide shows on the first launch, and again while the permission is missing.
        // A new version of the app brings a new extension. The user's copy follows it.
        BrowserExtension.refreshIfInstalled()
        if !preferences.bool(forKey: "welcomed") || !AXIsProcessTrusted() {
            preferences.set(true, forKey: "welcomed")
            welcome.open()
        }
    }

    /// `open nib://settings` and `open nib://editor` show the two windows, for scripts and shortcuts.
    /// `open -g nib://diagnose` writes the diagnosis file and shows no window.
    /// These links must never take text or parameters: any web page can open such a link,
    /// so only the host is read and each one does something harmless.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "nib" {
            switch url.host {
            case "settings": settings.open()
            case "editor": editor.show()
            case "diagnose": saveDiagnosis()
            case "welcome": welcome.open()
            default: break
            }
        }
    }

    // MARK: Menu

    /// An accessory app shows no menu bar, but its windows still need Edit commands for ⌘C, ⌘V and ⌘Z.
    private func installMainMenu() {
        let main = NSMenu()
        let app = NSMenu()
        app.addItem(withTitle: "Quit Nib", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "Nib", action: nil, keyEquivalent: "").submenu = app
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = window
        NSApp.mainMenu = main
    }

    @objc private func openSettings() { settings.open() }

    @objc private func openWelcome() { welcome.open() }

    /// Answers made with old settings are no longer valid.
    func settingsChanged() {
        memo.removeAll()
        improved.removeAll()
        declinedCompletions.removeAll()
        dismissed.removeAll()
        clearManual()
        clear()
    }

    func appInstructions(for pid: pid_t) -> String? {
        guard let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return nil }
        return (preferences.dictionary(forKey: "appInstructions") as? [String: String])?[id]
    }

    @objc private func editAppInstructions(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        var all = preferences.dictionary(forKey: "appInstructions") as? [String: String] ?? [:]
        let name = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }?.localizedName ?? id
        guard let text = ask("Instructions for " + name,
            info: "These apply only in " + name + ", in addition to your general instructions. Example: Keep it casual. Leave the text empty to remove them.",
            text: all[id] ?? "", lines: 4) else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        all[id] = clean.isEmpty ? nil : clean
        preferences.set(all, forKey: "appInstructions")
        settingsChanged()
    }

    /// Makes this object the target of every item, in submenus too.
    private func adopt(_ menu: NSMenu) {
        for item in menu.items {
            if item.target == nil, item.action != nil { item.target = self }
            if let submenu = item.submenu { adopt(submenu) }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        refreshStatus()
        let today = todayStats()
        statsItem.title = "Today: \(today["applied"] ?? 0) applied · \(today["dismissed"] ?? 0) dismissed · \(today["shown"] ?? 0) shown"
        let summary = diagnosis().summary
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier,
              id != Bundle.main.bundleIdentifier else {
            appHeader.title = "Front app"
            statusLine.title = summary
            appInstructionsItem.title = "Instructions for This App…"
            appInstructionsItem.representedObject = nil
            appInstructionsItem.isEnabled = false
            appItem.title = "Check Text in This App"
            appItem.representedObject = nil
            appItem.isEnabled = false
            appItem.state = .off
            return
        }
        let name = app.localizedName ?? id
        // The header names the app, so the line below it does not repeat the name.
        appHeader.title = "Front app: " + name
        let short = summary.hasPrefix(name + ": ") ? String(summary.dropFirst(name.count + 2)) : summary
        statusLine.title = short.prefix(1).uppercased() + short.dropFirst()
        appItem.representedObject = id
        appInstructionsItem.title = "Instructions for " + name + "…"
        appInstructionsItem.representedObject = id
        appInstructionsItem.isEnabled = true
        appInstructionsItem.state = appInstructions(for: app.processIdentifier) == nil ? .off : .on
        if usesExtension(id) {
            appItem.title = "Checked by the Browser Extension"
            appItem.isEnabled = false
            appItem.state = .off
        } else if blocked(id) {
            appItem.title = "Never Checked: Code, Passwords or Remote Screens"
            appItem.isEnabled = false
            appItem.state = .off
        } else {
            appItem.title = "Check Text in This App"
            appItem.isEnabled = true
            appItem.state = allowed(id) ? .on : .off
        }
    }

    private func refreshStatus() {
        let trusted = AXIsProcessTrusted()
        permissionItem.isHidden = trusted
        modelItem.title = ProofEngine.modelAvailable ? "Model: " + ProofEngine.modelName : "Apple Intelligence unavailable · spelling and basic checks"
    }

    /// A small dialog with one text box. Returns nil when the user cancels.
    private func ask(_ title: String, info: String, text: String, lines: Int) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 360, height: CGFloat(lines) * 18 + 10))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let view = NSTextView(frame: scroll.bounds)
        view.string = text
        view.font = .systemFont(ofSize: 13)
        view.isRichText = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.autoresizingMask = [.width]
        scroll.documentView = view
        alert.accessoryView = scroll
        alert.window.initialFirstResponder = view
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? view.string : nil
    }

    @objc private func askAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @objc private func toggleApp(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        var paused = pausedApps
        var extra = Set(preferences.stringArray(forKey: "extraApps") ?? [])
        if allowed(id) {
            paused.insert(id)
            extra.remove(id)
        } else {
            paused.remove(id)
            if !allApps && !builtInApps.contains(id) { extra.insert(id) }
        }
        pausedApps = paused
        preferences.set(Array(extra).sorted(), forKey: "extraApps")
        clearManual()
        clear()
    }
}
