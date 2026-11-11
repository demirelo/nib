// The link to the browser extension: registers the NibBridge helper as a native messaging host
// in every supported browser on this Mac.

import AppKit

private let hostName = "com.nib.bridge"

extension Desktop {
    @objc func connectBrowsers() {
        let alert = NSAlert()
        alert.messageText = "Connect Nib to your browsers?"
        alert.informativeText = "This registers the local sentence checker for the Nib extension in Chrome, Brave, Edge, Arc, Opera, Vivaldi and Chromium, for each one that is on this Mac. The extension can then send one sentence at a time to the model on this Mac."
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let outcome = NSAlert()
        do {
            let browsers = try installBrowserBridge()
            outcome.messageText = "Browser connection ready"
            outcome.informativeText = "Connected: " + browsers.joined(separator: ", ") + ". Reload the Nib extension and any tabs where you want sentence suggestions."
        } catch {
            outcome.messageText = "Could not connect the browsers"
            outcome.informativeText = error.localizedDescription
        }
        outcome.runModal()
    }

    /// Opens the Extensions page in a browser that the extension supports. Returns the name of that
    /// browser, or nil when this Mac has none. A browser accepts this address from another app.
    /// It accepts no extension from another app: the user must add the extension on that page.
    func openExtensionsPage() -> String? {
        let workspace = NSWorkspace.shared
        func supported(_ app: URL?) -> URL? {
            guard let app, let id = Bundle(url: app)?.bundleIdentifier, extensionBrowsers.contains(id) else { return nil }
            return app
        }
        // The user's usual browser first, then one that is open, then any that is installed.
        let usual = URL(string: "https://example.com").flatMap { workspace.urlForApplication(toOpen: $0) }
        let open = workspace.runningApplications.first { $0.bundleIdentifier.map(extensionBrowsers.contains) ?? false }?.bundleURL
        let installed = extensionBrowsers.sorted().lazy.compactMap { workspace.urlForApplication(withBundleIdentifier: $0) }.first
        guard let browser = supported(usual) ?? supported(open) ?? installed,
              let page = URL(string: "chrome://extensions") else { return nil }
        workspace.open([page], withApplicationAt: browser, configuration: NSWorkspace.OpenConfiguration())
        return FileManager.default.displayName(atPath: browser.path).replacingOccurrences(of: ".app", with: "")
    }

    /// Registers the sentence checker with every supported browser on this Mac. Returns their names.
    @discardableResult
    func installBrowserBridge() throws -> [String] {
        let file = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/NibBridge")
        // The browsers store the path of the checker. On a disk image, or in the random folder
        // that macOS uses for an app opened straight from a download, that path stops working later.
        let place = Bundle.main.bundlePath
        if place.hasPrefix("/Volumes/") || place.contains("/AppTranslocation/") {
            throw BridgeError(errorDescription: "Move Nib to the Applications folder first, open it from there, and connect again.")
        }
        guard FileManager.default.isExecutableFile(atPath: file.path) else { throw CocoaError(.fileNoSuchFile) }
        let info: [String: Any] = [
            "name": hostName, "description": "Nib on-device sentence checker",
            "path": file.path, "type": "stdio",
            "allowed_origins": ["chrome-extension://omijbpogjflnjbfpnnjgeaboppgllapg/"]
        ]
        let contents = try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        // A browser that never ran has no folder here, and Nib does not create one for it.
        let browsers = [("Chrome", "Google/Chrome"), ("Brave", "BraveSoftware/Brave-Browser"), ("Edge", "Microsoft Edge"),
                        ("Arc", "Arc/User Data"), ("Opera", "com.operasoftware.Opera"), ("Vivaldi", "Vivaldi"),
                        ("Chromium", "Chromium")]
        var connected: [String] = []
        for (name, folder) in browsers {
            let home = support.appendingPathComponent(folder)
            guard FileManager.default.fileExists(atPath: home.path) else { continue }
            let dir = home.appendingPathComponent("NativeMessagingHosts")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try contents.write(to: dir.appendingPathComponent(hostName + ".json"), options: .atomic)
            connected.append(name)
        }
        guard !connected.isEmpty else {
            throw BridgeError(errorDescription: "No supported browser was found on this Mac. Nib works with Chrome, Brave, Edge, Arc, Opera, Vivaldi and Chromium. Open the browser once, then connect again.")
        }
        return connected
    }
}
