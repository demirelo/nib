import Foundation

// Native messaging host for the Nib browser extension.
// It stays alive on one connection, so the model answers later sentences without a new process.
@main
struct Bridge {
    /// The largest message the extension sends. A sentence is at most 600 characters.
    static let maxMessage = 8192
    /// A larger message is skipped and answered with "invalid". Above this size the stream is not trusted.
    static let maxSkipped = 1_048_576
    /// The engine has its own, shorter deadlines. This one is the last line: no request blocks the next forever.
    static let requestTimeout: Duration = .seconds(60)

    static func main() async {
        let input = FileHandle.standardInput
        let output = FileHandle.standardOutput
        while true {
            do {
                let header = try read(4, from: input)
                guard header.count == 4 else { return }
                let length = header.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
                var response = ProofResponse(status: "invalid")
                if length > maxMessage {
                    // Ending here would leave the page waiting for an answer that never comes.
                    // Skip the bytes of this message, so the next header is read at the right place.
                    guard length <= maxSkipped, try skip(length, from: input) else { return }
                } else if length > 0 {
                    let data = try read(length, from: input)
                    guard data.count == length else { return }
                    response = await answer(data)
                }
                let body = try JSONEncoder().encode(response)
                var size = UInt32(body.count).littleEndian
                try output.write(contentsOf: Data(bytes: &size, count: 4))
                try output.write(contentsOf: body)
            } catch {
                // The browser owns this process and its stdout is reserved for the protocol.
                return
            }
        }
    }

    /// The reply to one message. It always carries the id of the request, so the page can match it.
    static func answer(_ data: Data) async -> ProofResponse {
        // The id is read on its own: a message with a broken field still gets its "invalid" back by id.
        let id = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["id"] as? Int
        // A message with text is a sentence to check, also when it holds a "log" field.
        if let request = try? JSONDecoder().decode(ProofRequest.self, from: data) {
            var response = await ProofEngine.limited(requestTimeout) { () -> ProofResponse? in
                if request.improve == true {
                    let better = await ProofEngine.improve(request.text)
                    return ProofResponse(status: better == nil ? "no-change" : "improve", replacement: better)
                }
                return await ProofEngine.contextual(request.text, before: request.before)
            } ?? ProofResponse(status: "timeout")
            response.id = id
            return response
        }
        if let entry = try? JSONDecoder().decode(LogEntry.self, from: data) {
            BrowserLog.append(entry.log)
            return ProofResponse(id: id, status: "logged")
        }
        return ProofResponse(id: id, status: "invalid")
    }

    /// A line for the browser log. The extension sends page structure only, never text.
    private struct LogEntry: Decodable {
        let log: String
    }

    private static func read(_ count: Int, from input: FileHandle) throws -> Data {
        var result = Data()
        while result.count < count {
            guard let chunk = try input.read(upToCount: count - result.count), !chunk.isEmpty else { break }
            result.append(chunk)
        }
        return result
    }

    /// Reads and drops `count` bytes. False when the stream ends first.
    private static func skip(_ count: Int, from input: FileHandle) throws -> Bool {
        var left = count
        while left > 0 {
            guard let chunk = try input.read(upToCount: min(left, 65_536)), !chunk.isEmpty else { return false }
            left -= chunk.count
        }
        return true
    }
}

/// ~/Library/Logs/Nib-browser.log: what the extension sees on a page, for troubleshooting.
/// The lines hold the host names of pages the user writes on, so the file is private to this Mac.
/// The extension sends lines only while its troubleshooting switch is on. With the switch off,
/// nothing arrives here and nothing is written.
enum BrowserLog {
    static func append(_ line: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Nib-browser.log")
        // A page can put anything in a line. Control characters could fake log lines or drive a terminal.
        let clean = ProofEngine.printable(line, limit: 300)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let data = Data((stamp + "  " + clean + "\n").utf8)
        // Keep the file small: start again when it passes 200 KB.
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if size > 200_000 || !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url)
        } else if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        }
    }
}
