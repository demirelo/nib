// The suggestion panel: the small floating button with a correction, its place on screen,
// short notices, the menu with more actions, and Explain.

import AppKit
import Carbon.HIToolbox

extension Desktop {
    // MARK: Panel

    func makePanel() {
        panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 350, height: 38),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let visual = NSVisualEffectView()
        visual.material = .popover
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 9
        acceptButton = NSButton(title: "", target: self, action: #selector(accept))
        acceptButton.bezelStyle = .regularSquare
        acceptButton.isBordered = false
        acceptButton.font = .systemFont(ofSize: 13, weight: .semibold)
        acceptButton.lineBreakMode = .byTruncatingTail
        acceptButton.setAccessibilityLabel("Apply Nib correction")
        let dismiss = NSButton(title: "×", target: self, action: #selector(dismissFix))
        dismiss.isBordered = false
        dismiss.font = .systemFont(ofSize: 17)
        dismiss.toolTip = "Dismiss (⌃⌥⌫)"
        dismiss.setAccessibilityLabel("Dismiss Nib correction")
        let more = NSButton(title: "⋯", target: self, action: #selector(showActions(_:)))
        more.isBordered = false
        more.font = .systemFont(ofSize: 15, weight: .semibold)
        more.toolTip = "Explain (⌃⌥E), dictionary and more"
        more.setAccessibilityLabel("More actions for this correction")
        let row = NSStackView(views: [acceptButton, more, dismiss])
        row.orientation = .horizontal
        row.spacing = 5
        detailLabel = NSTextField(wrappingLabelWithString: "")
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.isSelectable = false
        detailLabel.maximumNumberOfLines = 9
        detailLabel.isHidden = true
        let column = NSStackView(views: [row, detailLabel])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 2
        column.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: visual.leadingAnchor, constant: 10),
            column.trailingAnchor.constraint(equalTo: visual.trailingAnchor, constant: -8),
            column.topAnchor.constraint(equalTo: visual.topAnchor, constant: 4),
            row.heightAnchor.constraint(equalToConstant: 30),
            row.widthAnchor.constraint(equalTo: column.widthAnchor),
            dismiss.widthAnchor.constraint(equalToConstant: 21),
            more.widthAnchor.constraint(equalToConstant: 22)
        ])
        panel.contentView = visual
    }

    /// Shows "old → new" for a small change and the full sentence for a large one.
    func label(from original: String, to replacement: String) -> String {
        let change = ProofEngine.wordEdit(from: original, to: replacement)
        if !change.original.isEmpty, change.original.count <= 36, change.replacement.count <= 48 {
            return "✓  " + change.original + " → " + change.replacement
        }
        return "✓  " + replacement
    }

    /// `plain` allows Tab and Esc. They are global keys while they are registered, so the app in front
    /// does not get them. Only a suggestion right at the caret, or one the user asked for, may take them.
    func showPanel(title: String, detail: String, at anchor: CGRect, note: String? = nil, plain: Bool = true) {
        acceptButton.title = title
        acceptButton.toolTip = detail + "\n\nApply: ⌃⌥↩   Dismiss: ⌃⌥⌫   Explain: ⌃⌥E"
        acceptButton.setAccessibilityLabel("Apply correction: " + detail)
        explainTask?.cancel()
        setDetail(note)
        place(anchor)
        panel.orderFrontRegardless()
        register(.apply, key: kVK_Return)
        register(.dismiss, key: kVK_Delete)
        register(.explain, key: kVK_ANSI_E)
        if plainKeys, plain {
            register(.applyPlain, key: kVK_Tab, modifiers: 0)
            register(.dismissPlain, key: kVK_Escape, modifiers: 0)
        } else {
            releasePlainKeys()
        }
    }

    func releasePlainKeys() {
        unregister(.applyPlain)
        unregister(.dismissPlain)
    }

    /// The text under the button: an explanation or a rewrite preview. Nil hides it.
    private func setDetail(_ text: String?) {
        detailLabel.stringValue = text.map { $0.count > 700 ? String($0.prefix(700)) + "…" : $0 } ?? ""
        detailLabel.isHidden = text == nil
        if panel.isVisible { place(lastAnchor) }
    }

    func hidePanel() {
        panel?.orderOut(nil)
        explainTask?.cancel()
        detailLabel?.isHidden = true
        for key in [HotKey.apply, .dismiss, .explain, .applyPlain, .dismissPlain] { unregister(key) }
    }

    func place(_ anchor: CGRect) {
        guard let primary = NSScreen.screens.first else { return }
        lastAnchor = anchor
        let point = CGPoint(x: anchor.minX, y: primary.frame.maxY - anchor.maxY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? primary
        let visible = screen.visibleFrame
        var width = min(440, max(180, acceptButton.intrinsicContentSize.width + 66))
        var height: CGFloat = 38
        if !detailLabel.isHidden {
            width = 440
            detailLabel.preferredMaxLayoutWidth = width - 18
            let box = detailLabel.attributedStringValue.boundingRect(
                with: CGSize(width: width - 22, height: 400), options: [.usesLineFragmentOrigin, .usesFontLeading])
            height += min(150, ceil(box.height)) + 8
        }
        let x = min(visible.maxX - width - 4, max(visible.minX + 4, point.x))
        let above = primary.frame.maxY - anchor.minY + 4
        let y = point.y - height - 5 >= visible.minY ? point.y - height - 5 : min(visible.maxY - height, above)
        panel.setFrame(CGRect(x: x, y: y, width: width, height: height), display: true)
    }

    // MARK: Explain and dictionary

    @objc private func showActions(_ sender: NSButton) {
        let menu = NSMenu()
        if let pair {
            menu.addItem(withTitle: "Explain", action: #selector(explainFix), keyEquivalent: "").target = self
            let fragment = ProofEngine.wordEdit(from: pair.old, to: pair.new).original
            if !fragment.isEmpty, fragment.count <= 40 {
                let item = menu.addItem(withTitle: "Never Change “" + fragment + "”", action: #selector(neverChange(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = fragment
            }
        }
        if issues.count > 1, manualDraft == nil {
            menu.addItem(withTitle: "Apply All \(issues.count) Corrections", action: #selector(applyAll), keyEquivalent: "").target = self
        }
        menu.addItem(withTitle: "Copy Correction", action: #selector(copyFix), keyEquivalent: "").target = self
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc func explainFix() {
        guard let pair, panel.isVisible else { return }
        let offered = offeredFix
        setDetail("Thinking…")
        explainTask?.cancel()
        explainTask = Task { [weak self] in
            let text = await ProofEngine.explain(pair.old, pair.new)
            guard let self, !Task.isCancelled, self.panel.isVisible, self.offeredFix == offered else { return }
            self.setDetail(text ?? "No explanation is available for this correction.")
        }
    }

    @objc private func neverChange(_ sender: NSMenuItem) {
        guard let fragment = sender.representedObject as? String else { return }
        saveDictionary((preferences.stringArray(forKey: "dictionary") ?? []) + [fragment])
        dismissFix()
    }

    /// The entries keep their spelling. A word from running text, such as iPhone, must not lose its capital:
    /// the checker compares an entry with a capital letter exactly as written.
    private func saveDictionary(_ entries: [String]) {
        preferences.set(SettingsWindow.dictionaryEntries(entries), forKey: "dictionary")
        settingsChanged()
    }

    @objc private func copyFix() {
        guard let text = pair?.new ?? offeredFix else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func panelAnchor() -> CGRect {
        let top = (NSScreen.screens.first?.frame.maxY ?? 0) - panel.frame.maxY
        return CGRect(x: panel.frame.minX, y: top - 6, width: 0, height: 1)
    }

    /// A short notice that needs no action.
    func flash(_ message: String, at anchor: CGRect, seconds: Double = 1.6) {
        acceptButton.title = message
        acceptButton.toolTip = nil
        pair = nil
        detailLabel.isHidden = true
        place(anchor)
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.manualDraft == nil, self.shown == nil, self.acceptButton.title == message else { return }
            self.hidePanel()
        }
    }
}
