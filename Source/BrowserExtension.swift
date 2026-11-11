import Foundation

/// The browser extension as a normal folder that the user can load in the browser.
///
/// The extension travels inside the app. A browser cannot load it from there in a comfortable way:
/// Finder does not show a folder inside an app, and the file dialog of the browser does not enter an app.
/// So Nib keeps a copy in the user's Library, and keeps that copy the same as the one in the app.
enum BrowserExtension {
    /// The copy inside the app. Nil for a build without it.
    static var bundled: URL? {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("Browser"),
              FileManager.default.fileExists(atPath: folder.appendingPathComponent("manifest.json").path) else { return nil }
        return folder
    }

    /// Where the user's copy lives: ~/Library/Application Support/Nib/Nib Browser Extension.
    /// The path must stay the same across updates, because the browser remembers it.
    static var installed: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Nib/Nib Browser Extension")
    }

    /// The "version" in a folder's manifest.json. Nil when the folder or the file is missing or broken.
    static func version(of folder: URL) -> String? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return manifest["version"] as? String
    }

    /// Every file below `folder`, by its path inside the folder. Nil when the folder cannot be read.
    static func contents(of folder: URL) -> [String: Data]? {
        let root = folder.resolvingSymlinksInPath()
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return nil }
        var found: [String: Data] = [:]
        for case let file as URL in walker {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  let data = try? Data(contentsOf: file) else { continue }
            found[String(file.resolvingSymlinksInPath().path.dropFirst(root.path.count + 1))] = data
        }
        return found
    }

    /// Makes `target` a copy of `source`. Does nothing when both hold the same files.
    /// Returns true when it copied. The new files are in place before the old ones go,
    /// so a failure in the middle leaves the old copy as it was.
    ///
    /// The files decide, not the version number: two builds can carry the same number and still differ.
    /// The extension is about 2.5 MB, so the comparison costs little.
    @discardableResult
    static func sync(from source: URL, to target: URL) throws -> Bool {
        guard version(of: source) != nil, let wanted = contents(of: source) else { throw CocoaError(.fileReadCorruptFile) }
        if FileManager.default.fileExists(atPath: target.path), contents(of: target) == wanted { return false }
        let files = FileManager.default
        try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fresh = target.deletingLastPathComponent().appendingPathComponent(".nib-extension-" + UUID().uuidString)
        try files.copyItem(at: source, to: fresh)
        if files.fileExists(atPath: target.path) {
            _ = try files.replaceItemAt(target, withItemAt: fresh)
        } else {
            try files.moveItem(at: fresh, to: target)
        }
        return true
    }

    /// The folder to show to the user, copied or refreshed first. Nil when the app holds no extension.
    static func prepare() throws -> URL? {
        guard let bundled else { return nil }
        try sync(from: bundled, to: installed)
        return installed
    }

    /// At each launch of the app: brings an existing copy up to date. It creates no copy for a user
    /// who never asked for the extension.
    static func refreshIfInstalled() {
        guard let bundled, FileManager.default.fileExists(atPath: installed.path) else { return }
        _ = try? sync(from: bundled, to: installed)
    }
}
