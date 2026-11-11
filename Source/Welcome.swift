import AppKit

/// A rounded panel behind one step. It draws itself, so its colour follows light and dark mode.
private final class Card: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.quaternarySystemFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
    }
}

/// The round mark at the left of a step: its number, or a check mark when the step is done.
/// It draws the text itself. A label in a circle sits too high, because a label leaves room below the baseline.
private final class Badge: NSView {
    var text = "" { didSet { needsDisplay = true } }
    var color = NSColor.systemGreen { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { NSSize(width: 26, height: 26) }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: bounds).fill()
        let font = NSFont.systemFont(ofSize: 13, weight: .bold)
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
        // Centre the capital height of the font, so a digit sits in the middle of the circle.
        let width = string.size().width
        let baseline = bounds.midY - font.capHeight / 2
        string.draw(at: CGPoint(x: bounds.midX - width / 2, y: baseline + font.descender))
    }
}

/// One model that a server on this Mac offers.
private struct Offer {
    let server: String
    let name: String

    /// People write the same server as localhost or as 127.0.0.1, with or without "/v1".
    private var address: String {
        ProofConfig.normalised(server).lowercased().replacingOccurrences(of: "://localhost", with: "://127.0.0.1")
    }
    func sameServer(_ other: Offer) -> Bool { address == other.address }
    func same(_ other: Offer) -> Bool { name == other.name && sameServer(other) }
}

/// The setup guide. It shows on the first launch and walks through the four steps
/// that Nib cannot do for the user: the permission, the model, the browser extension and a first try.
@MainActor
final class WelcomeWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var accessStatus: NSTextField!
    private var accessButton: NSButton!
    private var browserStatus: NSTextField!
    private var accessBadge: Badge!
    private var browserBadge: Badge!
    private var timer: Timer?

    private var useApple: NSButton!
    private var useServer: NSButton!
    private var appleHint: NSTextField!
    private var modelPopup: NSPopUpButton!
    private var lookButton: NSButton!
    private var modelNote: NSTextField!
    private var modelStatus: NSTextField!
    private var modelBadge: Badge!

    // The state of the model step. `showModel` draws the controls from these values and from nothing else,
    // so `render` can set them and needs no network.
    /// The saved choice. Only the server and the model count. Both empty means Apple's model.
    private var chosen = ProofConfig()
    /// The radio button the user selected. It can run ahead of `chosen`: a local model is saved
    /// only after one is found and its server answered.
    private var wantsServer = false
    /// The model the user picked in the pop-up button, while its save still runs or after it failed.
    private var picked: Offer?
    private var appleReady = true
    private var looking = false
    /// True when a server answered the last search, also when it has no models.
    private var answered = false
    private var offers: [Offer] = []
    /// The rows of the pop-up button, in order.
    private var listed: [Offer] = []
    private var checking = false
    private var problem: String?
    /// Counts the searches, so a slow answer of an old search does not replace a newer one.
    private var search = 0
    private var saving: Task<Void, Never>?

    /// Where Nib looks for a model server: the standard ports of Ollama and LM Studio.
    private static let servers = [(name: "Ollama", address: "http://127.0.0.1:11434"),
                                  (name: "LM Studio", address: "http://127.0.0.1:1234")]

    /// Asks macOS for the Accessibility permission. Set by the app delegate.
    var askAccessibility: (() -> Void)?
    /// Registers the browser helper. Returns the error text, or nil when it worked.
    var connectBrowsers: (() -> String?)?
    /// Opens the Extensions page of a supported browser. Returns the browser's name, or nil when there is none.
    var openExtensionsPage: (() -> String?)?
    /// Called after the model changes, so the app drops answers made with the old model.
    var onChange: (() -> Void)?

    /// The extension travels inside the app, so a copy from the disk image has it too.
    private var extensionFolder: URL? { BrowserExtension.bundled }

    func open() {
        if window == nil { build() }
        refresh()
        adoptSavedModel()
        lookForModels()
        if timer == nil {
            // The permission changes in System Settings, so the window looks again every second.
            let tick = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            RunLoop.main.add(tick, forMode: .common)
            timer = tick
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Pictures of the guide, for `Nib --render`. The model step is set by hand:
    /// a picture must not ask the network and must not change what is saved.
    func render() -> [(name: String, png: Data)] {
        if window == nil { build() }
        refresh()
        var pictures: [(name: String, png: Data)] = []
        func picture(_ name: String) {
            showModel()
            resize()
            if let data = window?.contentView?.png() { pictures.append((name, data)) }
        }
        // The first state: nothing is saved, and the search for models still runs.
        (chosen, wantsServer, appleReady, looking, answered, offers) = (ProofConfig(), false, true, true, false, [])
        picture("welcome")
        // The longest messages, to catch a layout that overflows.
        show("Allowed. Nib can read and correct text.", color: .systemGreen, in: accessStatus)
        mark(accessBadge, number: 1, done: true)
        show(WelcomeWindow.addedText(browser: "Brave Browser"), color: .systemGreen, in: browserStatus)
        mark(browserBadge, number: 3, done: true)
        let long = Offer(server: WelcomeWindow.servers[0].address, name: "hf.co/bartowski/Qwen3-30B-A3B-Instruct-2507-GGUF:Q4_K_M")
        offers = [Offer(server: long.server, name: "qwen3:latest"), long]
        (chosen, wantsServer, looking, answered) = (ProofConfig(server: long.server, model: long.name), true, false, true)
        picture("welcome-done")
        // The tallest state: Apple's model is off and no server runs.
        (chosen, appleReady, answered, offers) = (ProofConfig(), false, false, [])
        picture("welcome-no-server")
        return pictures
    }

    private let green = NSColor(srgbRed: 0.16, green: 0.42, blue: 0.32, alpha: 1)
    /// The width of the text inside a step card.
    private let textWidth: CGFloat = 420

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor,
                       width: CGFloat? = nil) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.preferredMaxLayoutWidth = width ?? textWidth
        return field
    }

    /// One step: a numbered card with a title, a short text, buttons, and a status line below the buttons.
    /// The status has its own line, so a long message never pushes the card wider.
    /// `body` holds rows of a step that needs more than one line of buttons. They stand above the status.
    private func step(_ number: Int, _ title: String, _ text: String, _ controls: [NSView], body: [NSView] = [],
                      status: NSTextField? = nil) -> (card: NSView, badge: Badge) {
        let badge = Badge()
        badge.text = String(number)
        badge.color = green
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentHuggingPriority(.required, for: .vertical)

        var rows: [NSView] = [label(title, size: 14, weight: .semibold)]
        if !text.isEmpty { rows.append(label(text, size: 12, color: .secondaryLabelColor)) }
        let lead = rows.count - 1
        if !controls.isEmpty {
            let row = NSStackView(views: controls)
            row.orientation = .horizontal
            row.spacing = 8
            rows.append(row)
        }
        rows += body
        if let status { rows.append(status) }
        let column = NSStackView(views: rows)
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        if !controls.isEmpty || !body.isEmpty { column.setCustomSpacing(10, after: rows[lead]) }
        for row in body { column.setCustomSpacing(10, after: row) }
        column.widthAnchor.constraint(equalToConstant: textWidth).isActive = true
        // A stack view may clip its content when space is short. These must never clip.
        column.setClippingResistancePriority(.required, for: .vertical)
        let line = NSStackView(views: [badge, column])
        line.orientation = .horizontal
        line.alignment = .top
        line.spacing = 12
        line.setClippingResistancePriority(.required, for: .vertical)
        line.translatesAutoresizingMaskIntoConstraints = false

        let card = Card()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            line.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -14),
            line.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            line.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            column.bottomAnchor.constraint(equalTo: line.bottomAnchor)
        ])
        return (card, badge)
    }

    private func status() -> NSTextField {
        let field = label("", size: 12, weight: .medium)
        field.isHidden = true
        return field
    }

    private func show(_ text: String, color: NSColor, in field: NSTextField) {
        field.stringValue = text
        field.textColor = color
        field.isHidden = text.isEmpty
    }

    /// One choice of the model step: a radio button, and below it the lines that belong to it.
    /// The lines start under the title of the radio button, not under its circle.
    private func choice(_ button: NSButton, _ lines: [NSView]) -> NSView {
        let below = NSStackView(views: lines)
        below.orientation = .vertical
        below.alignment = .leading
        below.spacing = 6
        below.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)
        below.setClippingResistancePriority(.required, for: .vertical)
        let group = NSStackView(views: [button, below])
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 3
        group.setClippingResistancePriority(.required, for: .vertical)
        return group
    }

    private func build() {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true
        let titles = NSStackView(views: [
            label("Welcome to Nib", size: 22, weight: .bold),
            label("Grammar and spelling suggestions that stay on your Mac.", size: 13, color: .secondaryLabelColor)
        ])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 2
        let header = NSStackView(views: [icon, titles])
        header.orientation = .horizontal
        header.spacing = 12

        accessButton = NSButton(title: "Allow Access…", target: self, action: #selector(allow))
        accessStatus = status()
        let show = NSButton(title: "Show Extension Folder", target: self, action: #selector(showExtension))
        show.isHidden = extensionFolder == nil
        let connect = NSButton(title: "Add to Browser", target: self, action: #selector(connect))
        browserStatus = status()

        // Two radio buttons with one action and one parent view would form a group by themselves.
        // Here each one has its own parent, so `showModel` sets both states.
        useApple = NSButton(radioButtonWithTitle: "Apple's on-device model", target: self, action: #selector(chooseModel(_:)))
        useServer = NSButton(radioButtonWithTitle: "A larger model from Ollama or LM Studio on this Mac", target: self,
                             action: #selector(chooseModel(_:)))
        appleHint = label("", size: 12, color: .secondaryLabelColor, width: textWidth - 20)
        modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        modelPopup.target = self
        modelPopup.action = #selector(chooseModel(_:))
        // A model name can be very long. The button keeps its width and cuts the name.
        // The status line and the tooltip show the full name.
        modelPopup.widthAnchor.constraint(equalToConstant: 270).isActive = true
        modelPopup.setAccessibilityLabel("Model")
        lookButton = NSButton(title: "Look Again", target: self, action: #selector(lookAgain))
        let found = NSStackView(views: [modelPopup, lookButton])
        found.orientation = .horizontal
        found.spacing = 8
        modelNote = label("", size: 12, color: .systemOrange, width: textWidth - 20)
        modelNote.isHidden = true
        modelStatus = status()

        let done = NSButton(title: "Done", target: self, action: #selector(close))
        done.keyEquivalent = "\r"
        done.controlSize = .large
        let foot = label("You find Nib behind the nib icon in the menu bar.\nThis guide is under More → Setup Guide…", size: 11,
                         color: .tertiaryLabelColor, width: 340)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [foot, spacer, done])
        footer.orientation = .horizontal
        footer.alignment = .centerY

        let first = step(1, "Let Nib read and correct text",
                         "Click the button, then turn on Nib in the Accessibility list that opens.",
                         [accessButton], status: accessStatus)
        accessBadge = first.badge
        let second = step(2, "Choose the model",
                          "", [],
                          body: [choice(useApple, [appleHint]),
                                 choice(useServer, [
                                    label("Finds more errors and writes better suggestions. Needs about 5 GB of memory. Your text stays on this Mac.",
                                          size: 12, color: .secondaryLabelColor, width: textWidth - 20),
                                    found, modelNote])],
                          status: modelStatus)
        modelBadge = second.badge
        let third = step(3, "Add Nib to your browser (optional)",
                         "For Chrome, Brave, Edge, Arc and Vivaldi. Nib opens the Extensions page and shows the extension folder. There, turn on Developer mode and drag the folder onto the page.",
                         [connect, show], status: browserStatus)
        browserBadge = third.badge
        let fourth = step(4, "Try it",
                          "Type “I went two the store.” in any app and wait a second. Click the suggestion, or press ⌃⌥↩, to apply it.", [])

        let column = NSStackView(views: [header, first.card, second.card, third.card, fourth.card, footer])
        column.orientation = .vertical
        column.alignment = .leading
        // Four cards must fit on a 13-inch screen, so the gaps are small.
        column.spacing = 10
        column.setCustomSpacing(16, after: header)
        column.setCustomSpacing(12, after: fourth.card)
        column.edgeInsets = NSEdgeInsets(top: 30, left: 22, bottom: 16, right: 22)
        column.setClippingResistancePriority(.required, for: .vertical)
        column.translatesAutoresizingMaskIntoConstraints = false

        let panel = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 530, height: 500),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "Welcome to Nib"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let content = NSView()
        content.addSubview(column)
        var constraints = [
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            column.topAnchor.constraint(equalTo: content.topAnchor),
            column.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: 530)
        ]
        // Every card and the footer take the full width, whatever their text.
        for view in [first.card, second.card, third.card, fourth.card, footer] {
            constraints.append(view.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -44))
        }
        NSLayoutConstraint.activate(constraints)
        panel.contentView = content
        panel.setContentSize(content.fittingSize)
        window = panel
    }

    /// A finished step shows a check mark in place of its number.
    private func mark(_ badge: Badge, number: Int, done: Bool) {
        badge.text = done ? "✓" : String(number)
        badge.color = done ? .systemGreen : green
    }

    private func refresh() {
        let trusted = AXIsProcessTrusted()
        show(trusted ? "Allowed. Nib can read and correct text." : "Not allowed yet.",
             color: trusted ? .systemGreen : .systemOrange, in: accessStatus)
        accessButton.isEnabled = !trusted
        mark(accessBadge, number: 1, done: trusted)
    }

    @objc private func allow() {
        askAccessibility?()
        // The system prompt shows only once. The list itself always opens.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func addedText(browser: String?) -> String {
        browser.map { "Connected. In " + $0 + ": turn on Developer mode, then drag “Nib Browser Extension” from Finder onto the page." }
            ?? "Connected, but no supported browser is on this Mac. Nib works with Chrome, Brave, Edge, Arc and Vivaldi."
    }

    /// A browser lets no app add an extension. So this does every step that an app may do: it connects the
    /// helper, opens the Extensions page, and puts the extension folder beside it. The drag is the user's.
    @objc private func connect() {
        defer { resize() }
        if let problem = connectBrowsers?() {
            show("Could not connect: " + problem, color: .systemRed, in: browserStatus)
            mark(browserBadge, number: 3, done: false)
            return
        }
        mark(browserBadge, number: 3, done: true)
        let folder: URL?
        do {
            folder = try BrowserExtension.prepare()
        } catch {
            show("Connected, but the extension could not be copied: " + error.localizedDescription, color: .systemRed, in: browserStatus)
            return
        }
        let browser = openExtensionsPage?()
        show(WelcomeWindow.addedText(browser: browser), color: browser == nil ? .systemOrange : .systemGreen, in: browserStatus)
        // Finder comes after the browser, so its window with the folder lies on top, ready for the drag.
        if let folder, browser != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
        }
    }

    // MARK: The model step

    /// Takes over what is saved, for example after the user changed the model in Settings.
    private func adoptSavedModel() {
        let saved = ProofConfig.saved()
        appleReady = ModelChoice.appleAvailable
        // While a save runs, the saved value is the old one. The save sets `chosen` when it ends.
        guard !checking, saved.server != chosen.server || saved.model != chosen.model || window?.isVisible != true else {
            showModel()
            return
        }
        chosen = ProofConfig(server: saved.server, model: saved.model)
        wantsServer = chosen.localServer != nil
        picked = nil
        problem = nil
        showModel()
    }

    /// Asks the servers on this Mac for their models. The window stays usable in the meantime.
    private func lookForModels() {
        search += 1
        let run = search
        looking = true
        showModel()
        resize()
        var places = WelcomeWindow.servers.map(\.address)
        // A model that was saved in Settings can come from another address on this Mac.
        let saved = Offer(server: chosen.server, name: chosen.model)
        if chosen.localServer != nil, !places.contains(where: { Offer(server: $0, name: "").sameServer(saved) }) {
            places.append(chosen.server)
        }
        Task { [weak self] in
            // All servers are asked at the same time. A server that is not there costs up to 3 seconds.
            let lists = await withTaskGroup(of: (Int, [String]?).self, returning: [[String]?].self) { group in
                for (index, place) in places.enumerated() {
                    group.addTask { (index, await LocalServer.models(at: place)) }
                }
                var lists = [[String]?](repeating: nil, count: places.count)
                for await (index, list) in group { lists[index] = list }
                return lists
            }
            guard let self, self.search == run else { return }
            self.looking = false
            self.answered = lists.contains { $0 != nil }
            self.offers = zip(places, lists).flatMap { place, list in (list ?? []).map { Offer(server: place, name: $0) } }
            self.showModel()
            self.resize()
            // The user selected "a larger model" before one was found. The pop-up button now shows a model
            // as selected, so that model is saved.
            if self.wantsServer, self.chosen.localServer == nil, !self.offers.isEmpty, !self.checking { self.saveModel() }
        }
    }

    /// Draws the model step from its state.
    private func showModel() {
        useApple.state = wantsServer ? .off : .on
        useServer.state = wantsServer ? .on : .off
        appleHint.stringValue = appleReady ? "No setup. Small and fast."
            : "Apple Intelligence is off on this Mac. Turn it on in System Settings, or choose a local model."
        appleHint.textColor = appleReady ? .secondaryLabelColor : .systemOrange

        let saved = chosen.localServer == nil ? nil : Offer(server: chosen.server, name: chosen.model)
        listed = offers
        // The saved model stays in the list when its server does not answer.
        // Without it the button would show another model as if that one were chosen.
        if let saved, !listed.contains(where: saved.same) { listed.insert(saved, at: 0) }
        let several = offers.contains { !$0.sameServer(offers[0]) }
        // Built as a menu: `addItem(withTitle:)` of the button removes an item that has the same title.
        let menu = NSMenu()
        for offer in listed {
            let place = WelcomeWindow.servers.first { Offer(server: $0.address, name: "").sameServer(offer) }?.name
            menu.addItem(withTitle: offer.name + (several ? place.map { "  ·  " + $0 } ?? "" : ""), action: nil, keyEquivalent: "")
        }
        if listed.isEmpty { menu.addItem(withTitle: looking ? "Looking for models…" : "No models found", action: nil, keyEquivalent: "") }
        modelPopup.menu = menu
        let current = picked ?? saved
        modelPopup.selectItem(at: current.flatMap { listed.firstIndex(where: $0.same) } ?? 0)
        modelPopup.toolTip = modelPopup.titleOfSelectedItem
        modelPopup.isEnabled = !offers.isEmpty && !looking
        lookButton.isEnabled = !looking
        modelNote.stringValue = answered ? "The server has no models. Run `ollama pull qwen3`, then click Look Again."
            : "No model server runs. Install Ollama, run `ollama pull qwen3`, then click Look Again."
        modelNote.isHidden = looking || !offers.isEmpty

        // The status line says what is active. The check mark needs a choice that works.
        var done = false
        if checking {
            show("Checking…", color: .secondaryLabelColor, in: modelStatus)
        } else if let problem {
            show(problem, color: .systemRed, in: modelStatus)
        } else if let saved {
            if offers.contains(where: saved.same) {
                show("Nib uses " + saved.name + ". If the server stops, Apple's model takes over.", color: .systemGreen, in: modelStatus)
                done = true
            } else if looking {
                show("Nib is set to use " + saved.name + ".", color: .secondaryLabelColor, in: modelStatus)
            } else {
                show("The server of " + saved.name + " does not answer. Apple's model takes over until it runs.",
                     color: .systemOrange, in: modelStatus)
            }
        } else if wantsServer {
            // With no server and no Apple model, the two orange lines above already say all of it.
            show(appleReady ? "No local model is chosen yet. Nib uses Apple's on-device model."
                 : modelNote.isHidden ? "No local model is chosen yet." : "", color: .systemOrange, in: modelStatus)
        } else if appleReady {
            // Apple's model is the default, but the step is done only after the user chose it.
            let confirmed = UserDefaults.standard.bool(forKey: WelcomeWindow.modelChosenKey)
            show(confirmed ? "Nib uses Apple's on-device model." : "Nib uses Apple's on-device model for now. Choose one to confirm.",
                 color: confirmed ? .systemGreen : .secondaryLabelColor, in: modelStatus)
            done = confirmed
        } else {
            show("Apple's model is not available. Nib does spelling and basic checks only.", color: .systemOrange, in: modelStatus)
        }
        mark(modelBadge, number: 2, done: done)
    }

    /// True after the user picked a model in the guide. Until then the model step stays open.
    static let modelChosenKey = "modelChosen"

    @objc private func chooseModel(_ sender: NSControl) {
        UserDefaults.standard.set(true, forKey: WelcomeWindow.modelChosenKey)
        if sender === modelPopup {
            picked = listed.indices.contains(modelPopup.indexOfSelectedItem) ? listed[modelPopup.indexOfSelectedItem] : nil
            wantsServer = true
        } else {
            wantsServer = sender === useServer
        }
        saveModel()
    }

    @objc private func lookAgain() {
        appleReady = ModelChoice.appleAvailable
        problem = nil
        lookForModels()
    }

    /// Saves the choice at once, through the same check that Settings uses.
    private func saveModel() {
        saving?.cancel()
        saving = nil
        checking = false
        problem = nil
        defer {
            showModel()
            resize()
        }
        guard wantsServer else {
            ModelChoice.useApple(then: onChange)
            chosen = ProofConfig()
            picked = nil
            return
        }
        // No model to save yet. When the search finds one, it calls this again.
        guard !looking, listed.indices.contains(modelPopup.indexOfSelectedItem) else { return }
        let offer = listed[modelPopup.indexOfSelectedItem]
        picked = offer   // the button keeps this model while the check runs
        checking = true
        saving = Task { [weak self] in
            let outcome = await ModelChoice.useServer(offer.server, model: offer.name, then: { self?.onChange?() })
            // Cancelled: a newer choice of the user is in charge of the window now.
            guard let self, !Task.isCancelled, outcome != .cancelled else { return }
            self.checking = false
            switch outcome {
            case .saved:
                let saved = ProofConfig.saved()
                self.chosen = ProofConfig(server: saved.server, model: saved.model)
                self.picked = nil
            case .noServer:
                self.problem = "Not saved. The server does not answer now. Start it, then click Look Again."
            case .notOffered:
                self.problem = "Not saved. The server does not have this model now. Click Look Again."
            case .badAddress, .cancelled:
                self.problem = "Not saved. Choose the model in Settings."
            }
            self.showModel()
            self.resize()
        }
    }

    /// The window grows when a status line appears.
    private func resize() {
        guard let window, let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let top = window.frame.maxY
        window.setContentSize(content.fittingSize)
        window.setFrameTopLeftPoint(CGPoint(x: window.frame.minX, y: top))
    }

    @objc private func showExtension() {
        // Finder does not show a folder inside an app, so the user gets a copy in a normal folder.
        do {
            guard let folder = try BrowserExtension.prepare() else { return }
            NSWorkspace.shared.activateFileViewerSelecting([folder])
            show("The folder “Nib Browser Extension” is selected in Finder. Drag it onto the Extensions page.",
                 color: .secondaryLabelColor, in: browserStatus)
        } catch {
            show("Could not copy the extension: " + error.localizedDescription, color: .systemRed, in: browserStatus)
        }
        resize()
    }

    @objc private func close() { window?.close() }

    /// The user can come back from System Settings or from Nib Settings with another model or
    /// with Apple Intelligence turned on.
    func windowDidBecomeKey(_ notification: Notification) {
        adoptSavedModel()
        resize()
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }
}
