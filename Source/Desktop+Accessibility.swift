// Reading other apps through the Accessibility API: the focused text field, its text, selection and
// position on screen. Also the gate that decides which apps and fields Nib must never read.

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import IOKit.ps

extension Desktop {
    func blocked(_ id: String) -> Bool {
        neverChecked.contains(id) || neverCheckedPrefixes.contains(where: id.hasPrefix)
    }

    func usesExtension(_ id: String) -> Bool {
        extensionBrowsers.contains(id) || extensionBrowserPrefixes.contains(where: id.hasPrefix)
    }

    /// The one gate for everything that reads text on request: Proofread, Rewrite, Open Editor, Read Aloud
    /// and the ⌘C fallback itself. True means: do not read. Then nothing is read and no key is sent.
    /// An app that the user only paused is not in this gate. A pause stops live checks,
    /// and an explicit shortcut still works there.
    func mustNotRead(_ pid: pid_t) -> Bool {
        // An app without an identifier cannot be compared with the list, so it counts as listed.
        guard let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return true }
        if blocked(id) || IsSecureEventInputEnabled() { return true }
        if let element = focusedElement(of: pid), isPrivate(element) { return true }
        return false
    }

    /// Runs the gate for a manual action and tells the user when it says no.
    func refuse(_ pid: pid_t) -> Bool {
        guard mustNotRead(pid) else { return false }
        clearManual()
        clear()
        let listed = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier.map(blocked) ?? true
        flash(listed ? "Nib does not read this app" : "Nib does not read password fields", at: mouseAnchor(), seconds: 2.5)
        return true
    }

    func allowed(_ id: String) -> Bool {
        guard id != Bundle.main.bundleIdentifier, !usesExtension(id), !blocked(id),
              !pausedApps.contains(id) else { return false }
        return builtInApps.contains(id) || allApps || (preferences.stringArray(forKey: "extraApps") ?? []).contains(id)
    }

    var onBattery: Bool {
        if Date().timeIntervalSince(batteryCheck.at) < 15 { return batteryCheck.onBattery }
        var result = false
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() {
            result = (type as String) == "Battery Power"
        }
        batteryCheck = (Date(), result)
        return result
    }

    // MARK: Accessibility reads

    func readAttribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name, &value) == .success ? value : nil
    }

    func settable(_ element: AXUIElement, _ name: CFString) -> Bool {
        var result: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name, &result) == .success && result.boolValue
    }

    func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let value = readAttribute(element, axRange), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
    }

    func rangeValue(_ range: NSRange) -> AXValue? {
        var value = CFRange(location: range.location, length: range.length)
        return AXValueCreate(.cfRange, &value)
    }

    /// Electron and Chromium apps hide their text from Accessibility until a client asks for it.
    /// The switch can cost such an app performance, because it then builds its whole accessibility tree.
    /// So it is set only for an app that Nib checks live or that the user pointed a shortcut at:
    /// every caller comes after `allowed` or `mustNotRead`, and a never-checked app is refused here again.
    private func expose(_ app: AXUIElement, pid: pid_t) {
        guard exposed[pid] == nil else { return }
        guard let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier, !blocked(id) else { return }
        if exposed.count > 200 { exposed.removeAll(); enhanced.removeAll() }
        exposed[pid] = Date()
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// Some Electron apps (Signal) ignore the first switch. Such an app gets the second switch once.
    /// The same gate as `expose` applies: the caller already passed `allowed` or `mustNotRead`.
    private func exposeHarder(_ app: AXUIElement, pid: pid_t) {
        let running = NSRunningApplication(processIdentifier: pid)
        guard let id = running?.bundleIdentifier, !blocked(id),
              ElectronAccess.needsSecondSwitch(electron: ElectronAccess.isElectron(running?.bundleURL), focusFound: false,
                                               firstSwitchAge: exposed[pid].map { Date().timeIntervalSince($0) },
                                               secondSent: enhanced.contains(pid)) else { return }
        enhanced.insert(pid)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    func focusedElement(of pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        expose(app, pid: pid)
        guard let value = readAttribute(app, kAXFocusedUIElementAttribute as CFString),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            exposeHarder(app, pid: pid)
            return nil
        }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.15)
        return element
    }

    func isPrivate(_ element: AXUIElement) -> Bool {
        // The subrole is read every time: a "show password" switch can change it on the same element.
        if (readAttribute(element, kAXSubroleAttribute as CFString) as? String) == "AXSecureTextField" { return true }
        // The labels of an element stay the same, so the poll does not read all six on every tick.
        if let labelCheck, CFEqual(labelCheck.element, element) { return labelCheck.secret }
        let labels = [kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute, kAXHelpAttribute,
                      kAXPlaceholderValueAttribute, kAXRoleDescriptionAttribute]
            .compactMap { readAttribute(element, $0 as CFString) as? String }.joined(separator: " ")
        let secret = labels.range(of: #"password|passcode|passphrase|verification.?code|card.?number|security.?code|api.?key|secret.?key|seed.?phrase|recovery.?phrase|private.?key|one.?time.?code|\b(?:otp|pin|cvv|cvc|ssn|iban)\b"#,
                                  options: .caseInsensitive.union(.regularExpression)) != nil
        labelCheck = (element, secret)
        return secret
    }

    func readField() -> Field? {
        // Secure input is on while a password prompt has focus anywhere on the Mac.
        guard enabled, AXIsProcessTrusted(), !IsSecureEventInputEnabled(), !(pauseOnBattery && onBattery),
              let application = NSWorkspace.shared.frontmostApplication,
              let id = application.bundleIdentifier, allowed(id),
              let element = focusedElement(of: application.processIdentifier) else { return nil }
        let role = readAttribute(element, kAXRoleAttribute as CFString) as? String
        guard ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField"].contains(role ?? ""),
              settable(element, axRange), !isPrivate(element),
              let selection = selectedRange(element), selection.length == 0,
              let text = readAttribute(element, axValue) as? String, !text.isEmpty, text.utf16.count <= 30_000,
              selection.location >= 0, selection.location <= text.utf16.count else { return nil }
        return Field(pid: application.processIdentifier, element: element, text: text, caret: selection.location)
    }

    func bounds(_ element: AXUIElement, for range: NSRange) -> CGRect? {
        guard let parameter = rangeValue(range) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                        parameter, &result) == .success,
              let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(result as! AXValue, .cgRect, &rect) && rect != .zero ? rect : nil
    }

    func frameOf(_ element: AXUIElement) -> CGRect? {
        guard let position = readAttribute(element, kAXPositionAttribute as CFString),
              let size = readAttribute(element, kAXSizeAttribute as CFString),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions), dimensions.height > 0 else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    func anchor(for draft: Draft, caret: Int) -> CGRect? {
        let frame = frameOf(draft.element)
        let precise = (draft.atCaret ? bounds(draft.element, for: NSRange(location: caret, length: 0)) : nil)
            ?? bounds(draft.element, for: draft.range)
        // A sentence scrolled out of view reports bounds outside its editor.
        if let precise, frame == nil || frame!.insetBy(dx: -40, dy: -40).intersects(precise) { return precise }
        return frame
    }
}
