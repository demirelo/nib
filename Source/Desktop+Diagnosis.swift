// Diagnosis and records: why the app in front is or is not checked, the apply log,
// and the counts of the day. None of them holds draft text.

import AppKit
import ApplicationServices
import Carbon.HIToolbox

extension Desktop {
    /// Explains why the app in front gets, or does not get, live checks. It never includes the draft text.
    func diagnosis() -> (summary: String, lines: [String]) {
        var lines: [String] = []
        func add(_ name: String, _ value: Any) { lines.append(name + ": " + String(describing: value)) }
        add("Nib", Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?")
        let trusted = AXIsProcessTrusted()
        add("Accessibility permission", trusted ? "yes" : "NO")
        add("Sentence model", ProofEngine.modelAvailable ? ProofEngine.modelName : "unavailable")
        if pauseOnBattery, onBattery { return ("Paused on battery", lines) }
        add("Live checks", enabled ? "on" : "OFF")
        add("Secure input", IsSecureEventInputEnabled() ? "ACTIVE" : "off")
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier,
              id != Bundle.main.bundleIdentifier else { return ("No other app is in front", lines) }
        let name = app.localizedName ?? id
        add("Front app", name + " (" + id + ")")
        let reason = usesExtension(id) ? "uses the browser extension" : blocked(id) ? "never checked" :
            pausedApps.contains(id) ? "paused by you" : allowed(id) ? "" : "other apps are off"
        add("App checked", reason.isEmpty ? "yes" : "NO, " + reason)
        guard trusted else { return ("Accessibility permission is missing", lines) }
        guard enabled else { return ("Live checks are off", lines) }
        guard reason.isEmpty else { return (name + ": " + reason, lines) }
        if IsSecureEventInputEnabled() { return ("Paused: a password field has the keyboard", lines) }
        guard let element = focusedElement(of: app.processIdentifier) else {
            add("Focused element", "NONE")
            return (name + ": no text field has the focus", lines)
        }
        let role = readAttribute(element, kAXRoleAttribute as CFString) as? String ?? "none"
        add("Focused role", role)
        add("Subrole", readAttribute(element, kAXSubroleAttribute as CFString) as? String ?? "none")
        let roleFits = ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField"].contains(role)
        // A private field ends the report here. Its value, length and selection are never read.
        if isPrivate(element) {
            add("Private field", "YES")
            return (name + ": private field, skipped", lines)
        }
        add("Private field", "no")
        let canSelect = settable(element, axRange)
        add("Selection settable", canSelect ? "yes" : "NO")
        let selection = selectedRange(element)
        add("Selection", selection.map { "location \($0.location), length \($0.length)" } ?? "NOT READABLE")
        let text = readAttribute(element, axValue) as? String
        add("Text length", text.map { String($0.utf16.count) } ?? "NOT READABLE")
        add("Sentences", text.map { String(ProofEngine.sentences(in: $0).count) } ?? "-")
        add("Text can be replaced directly", settable(element, axSelectedText) ? "yes" : "no, uses paste")
        add("Caret position known", selection.flatMap { bounds(element, for: NSRange(location: $0.location, length: 0)) } != nil ? "yes" : "no")
        add("Editor frame known", frameOf(element) != nil ? "yes" : "NO")
        add("Suggestion on screen", shown != nil && offeredFix != nil ? "yes" : "no")
        if !roleFits { return (name + ": the focus is not in a text field (" + role + ")", lines) }
        if !canSelect { return (name + ": this text field is read-only for other apps", lines) }
        guard let selection else { return (name + ": the caret is not readable", lines) }
        guard let text else { return (name + ": the text is not readable", lines) }
        if text.isEmpty { return (name + ": the field is empty", lines) }
        if text.utf16.count > 30_000 { return (name + ": the text is too long", lines) }
        if selection.length > 0 { return (name + ": text is selected, press ⌃⌥P", lines) }
        if shown != nil, offeredFix != nil { return (name + ": suggestion shown", lines) }
        return (name + ": checked, no correction found", lines)
    }

    /// Writes the diagnosis to ~/Library/Logs/Nib-diagnosis.txt. The report holds no draft text.
    @discardableResult
    func saveDiagnosis() -> (summary: String, lines: [String], report: String) {
        let result = diagnosis()
        let report = ([result.summary, ""] + result.lines).joined(separator: "\n")
        let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Nib-diagnosis.txt")
        try? (ISO8601DateFormatter().string(from: Date()) + "\n" + report + "\n").write(to: log, atomically: true, encoding: .utf8)
        return (result.summary, result.lines, report)
    }

    @objc func showDiagnosis() {
        let result = saveDiagnosis()
        let report = result.report
        let alert = NSAlert()
        alert.messageText = result.summary
        alert.informativeText = result.lines.joined(separator: "\n") + "\n\nSaved to ~/Library/Logs/Nib-diagnosis.txt. The report holds no draft text."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Copy")
        if alert.runModal() == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report, forType: .string)
        }
    }

    // MARK: Statistics

    private func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    func todayStats() -> [String: Int] {
        (preferences.dictionary(forKey: "stats") as? [String: [String: Int]])?[todayKey()] ?? [:]
    }

    /// Counts stay on this Mac. They hold numbers only.
    func count(_ event: String) {
        var all = preferences.dictionary(forKey: "stats") as? [String: [String: Int]] ?? [:]
        var today = all[todayKey()] ?? [:]
        today[event, default: 0] += 1
        all[todayKey()] = today
        for old in all.keys.sorted().dropLast(60) { all[old] = nil }
        preferences.set(all, forKey: "stats")
    }

    /// Records what happened to an Apply click. The log holds reasons only, never draft text.
    func note(_ message: String, app pid: pid_t) {
        let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "unknown app"
        let line = ISO8601DateFormatter().string(from: Date()) + "  " + id + "  " + message + "\n"
        let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Nib-apply.log")
        if let handle = try? FileHandle(forWritingTo: log) {
            defer { try? handle.close() }
            if (try? handle.seekToEnd()) ?? 0 > 200_000 { try? handle.truncate(atOffset: 0) }
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: log)
        }
    }

    func report(_ reason: String, at spot: CGRect, app pid: pid_t) {
        note("FAILED: " + reason, app: pid)
        NSSound.beep()
        flash("Could not apply here. Select the text and press ⌃⌥P", at: spot)
    }
}
