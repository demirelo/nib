// Live checks while the user types: the poll of the focused field, the check of its sentences,
// the underlines, snippets and autocomplete.

import AppKit
import ApplicationServices

extension Desktop {
    // MARK: Live checks

    func poll() {
        guard !applying else { return }
        if let manualDraft {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == manualDraft.pid { return }
            clearManual()
        }
        if manualRequest != nil {
            // A request belongs to one app. When the user leaves that app, the request ends
            // and its "Rewriting…" notice goes away.
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == manualPid { return }
            clearManual()
        }
        guard let field = readField() else {
            if lastField != nil || shown != nil || !issues.isEmpty || completion != nil { clear() }
            return
        }
        if let lastField, lastField.same(field) {
            if panel.isVisible, shown != nil || completion != nil {
                let target = shown ?? Draft(pid: field.pid, element: field.element,
                                            range: NSRange(location: field.caret, length: 0), text: "", atCaret: true)
                if let anchor = anchor(for: target, caret: field.caret) { place(anchor) }
            }
            refreshOverlay(field, idle: true)   // follows the text when the user scrolls
            return
        }
        let textChanged = !(lastField?.sameText(field) ?? false)
        if textChanged, let hit = ProofEngine.snippet(in: field.text, caret: field.caret, snippets: snippets),
           justTyped(hit.range, in: field),
           !(triedSnippet.map { CFEqual($0.element, field.element) && $0.text == field.text } ?? false) {
            expand(hit, in: field)
            return
        }
        lastField = field
        pending?.cancel()
        // The caret left the sentence of the suggestion: Tab and Esc go back to the app at once.
        if let shown, gap(shown.range, to: field.caret) > 0 { releasePlainKeys() }
        if textChanged || completion != nil {
            // Stay out of the way while the user types.
            shown = nil
            offeredFix = nil
            completion = nil
            hidePanel()
        }
        // Known answers show at once, so underlines do not blink on every key press.
        issues = knownIssues(in: field)
        refreshOverlay(field)
        generation += 1
        let run = generation
        pending = Task { [weak self] in
            if textChanged { try? await Task.sleep(for: .milliseconds(700)) }
            guard !Task.isCancelled, let self else { return }
            await evaluate(field, run: run)
        }
    }

    /// True when the end of a snippet code, up to the whole code, was typed since the last poll.
    /// A code that was already in the field when the user clicked into it does not expand.
    private func justTyped(_ code: NSRange, in field: Field) -> Bool {
        guard let lastField, lastField.pid == field.pid, CFEqual(lastField.element, field.element),
              code.length > 0, NSMaxRange(code) == field.caret else { return false }
        let now = field.text as NSString
        return (1...code.length).contains { typed in
            now.replacingCharacters(in: NSRange(location: field.caret - typed, length: typed), with: "") == lastField.text
        }
    }

    private func gap(_ range: NSRange, to caret: Int) -> Int {
        if caret >= range.location && caret <= NSMaxRange(range) { return 0 }
        return min(abs(caret - range.location), abs(caret - NSMaxRange(range)))
    }

    private func memoKey(_ sentence: String, before: String?, extra: String?) -> String {
        sentence + "\u{1}" + (before ?? "") + "\u{1}" + (extra ?? "")
    }

    /// The sentences of a field with the sentence before each one, which gives the model its context.
    private func sentences(of field: Field) -> [(range: NSRange, text: String, before: String?)] {
        let ordered = ProofEngine.sentences(in: field.text)
        return ordered.enumerated().map { index, sentence in
            (sentence.range, sentence.text, index > 0 ? ordered[index - 1].text : nil)
        }
    }

    /// Issues that earlier checks already found. The sentence at the caret is left out: it is being typed.
    private func knownIssues(in field: Field) -> [Issue] {
        guard !memo.isEmpty else { return [] }
        let extra = appInstructions(for: field.pid)
        return sentences(of: field).compactMap { sentence in
            guard gap(sentence.range, to: field.caret) > 0, !dismissed.contains(sentence.text),
                  let known = memo[memoKey(sentence.text, before: sentence.before, extra: extra)] else { return nil }
            let draft = Draft(pid: field.pid, element: field.element, range: sentence.range, text: sentence.text, atCaret: false)
            if let fix = known { return Issue(draft: draft, fix: fix) }
            guard improvements, let better = improved[memoKey(sentence.text, before: nil, extra: extra)], let better else { return nil }
            return Issue(draft: draft, fix: better, suggestion: true)
        }
    }

    /// Checks the field. The sentence at the caret comes first, then the others, nearest first.
    private func evaluate(_ field: Field, run: Int) async {
        let caret = field.caret
        let extra = appInstructions(for: field.pid)
        let all = sentences(of: field).filter { !dismissed.contains($0.text) }
            .sorted { gap($0.range, to: caret) < gap($1.range, to: caret) }.prefix(80)
        var found: [Int: Issue] = [:]
        func issue(_ sentence: (range: NSRange, text: String, before: String?), _ fix: String) -> Issue {
            Issue(draft: Draft(pid: field.pid, element: field.element, range: sentence.range, text: sentence.text,
                               atCaret: gap(sentence.range, to: caret) == 0), fix: fix)
        }
        // Shows what is known so far: underlines for all issues, the panel for the nearest one.
        func publish() {
            guard run == generation else { return }
            issues = found.values.sorted { $0.draft.range.location < $1.draft.range.location }
            refreshOverlay(field)
            guard let nearest = issues.min(by: { gap($0.draft.range, to: caret) < gap($1.draft.range, to: caret) }) else {
                if shown != nil {
                    shown = nil
                    offeredFix = nil
                    hidePanel()
                }
                return
            }
            // `atCaret` decides whether Tab and Esc are taken, so a change of it shows the panel again.
            if shown?.text != nearest.draft.text || offeredFix != nearest.fix || !panel.isVisible
                || shown?.atCaret != nearest.draft.atCaret {
                present(nearest.fix, for: nearest.draft, in: field, suggestion: nearest.suggestion)
            }
        }
        // A sentence without an error can still get a style suggestion, once it is finished.
        var clean: [(range: NSRange, text: String, before: String?)] = []
        func finished(_ text: String) -> Bool { text.last.map { ".!?…".contains($0) } ?? false }
        var rest = Array(all)
        var caretHasIssue = false
        if let first = rest.first, gap(first.range, to: caret) == 0 {
            rest.removeFirst()
            let offset = caret - first.range.location
            if let quick = Proofreader.local(first.text, caret: offset) {
                found[first.range.location] = issue(first, quick)
                publish()
            }
            let full = await Proofreader.check(first.text, caret: offset, before: first.before, extra: extra)
            guard !Task.isCancelled, run == generation else { return }
            found[first.range.location] = full.map { issue(first, $0) }
            caretHasIssue = full != nil
            if full == nil, finished(first.text) { clean.append(first) }
            publish()
        }
        // Instant checks cover the whole field. The model reads only the nearest sentences.
        for sentence in rest {
            let key = memoKey(sentence.text, before: sentence.before, extra: extra)
            if let known = memo[key] {
                found[sentence.range.location] = known.map { issue(sentence, $0) }
                if known == nil, finished(sentence.text) { clean.append(sentence) }
            } else if let fix = Proofreader.local(sentence.text) {
                found[sentence.range.location] = issue(sentence, fix)
            }
        }
        publish()
        for sentence in rest.prefix(8) where gap(sentence.range, to: caret) <= 2_500 {
            let key = memoKey(sentence.text, before: sentence.before, extra: extra)
            guard memo[key] == nil else { continue }
            let fix = await Proofreader.check(sentence.text, before: sentence.before, extra: extra)
            guard !Task.isCancelled, run == generation else { return }
            memo.set(fix, for: key)
            found[sentence.range.location] = fix.map { issue(sentence, $0) }
            if fix == nil, finished(sentence.text) { clean.append(sentence) }
            publish()
        }
        if improvements {
            let nearest = clean.sorted { gap($0.range, to: caret) < gap($1.range, to: caret) }.prefix(6)
            for sentence in nearest where gap(sentence.range, to: caret) <= 2_500 {
                let key = memoKey(sentence.text, before: nil, extra: extra)
                if improved[key] == nil {
                    let better = await ProofEngine.improve(sentence.text, extra: extra)
                    guard !Task.isCancelled, run == generation else { return }
                    improved.set(better, for: key)
                }
                if let better = improved[key], let better {
                    var suggestion = issue(sentence, better)
                    suggestion.suggestion = true
                    found[sentence.range.location] = suggestion
                    publish()
                }
            }
        }
        guard autocomplete, !caretHasIssue, let prefix = ProofEngine.completionPrefix(in: field.text, caret: caret),
              !declinedCompletions.contains(prefix) else { return }
        let text = await ProofEngine.complete(prefix, extra: extra)
        guard !Task.isCancelled, run == generation, let text else { return }
        offer(text, after: prefix, in: field)
    }

    /// Draws an underline under the changed words of the twelve issues nearest to the caret.
    /// An idle poll passes `idle`: then one position is read first, and when neither the editor,
    /// the issues nor that position moved, the underlines stay as they are.
    private func refreshOverlay(_ field: Field, idle: Bool = false) {
        guard underlines, !issues.isEmpty, let frame = frameOf(field.element) else {
            overlay.hide()
            drawn = nil
            return
        }
        func mark(_ issue: Issue) -> CGRect? {
            let edit = ProofEngine.edit(from: issue.draft.text, to: issue.fix)
            return bounds(issue.draft.element, for: NSRange(location: issue.draft.range.location + edit.range.location,
                                                             length: max(1, edit.range.length)))
        }
        let nearest = issues.sorted { gap($0.draft.range, to: field.caret) < gap($1.draft.range, to: field.caret) }.prefix(12)
        // The first mark tells whether the text scrolled inside an editor that did not move.
        let probe = nearest.first.flatMap(mark)
        if idle, let drawn, drawn.version == issuesVersion, drawn.frame == frame, drawn.probe == probe { return }
        drawn = (issuesVersion, frame, probe)
        var boxes: [(bounds: CGRect, suggestion: Bool)] = []
        for (index, issue) in nearest.enumerated() {
            if let box = index == 0 ? probe : mark(issue) { boxes.append((box, issue.suggestion)) }
        }
        overlay.show(boxes, within: frame)
    }

    private func present(_ replacement: String, for draft: Draft, in field: Field, suggestion: Bool = false) {
        guard manualDraft == nil, let current = readField(), current.same(field),
              let anchor = anchor(for: draft, caret: current.caret) else { return }
        if shown?.text != draft.text || offeredFix != replacement { count("shown") }
        shown = draft
        offeredFix = replacement
        completion = nil
        pair = (draft.text, replacement)
        let others = issues.count - 1
        // A star marks a style suggestion, a check mark marks a correction.
        var title = label(from: draft.text, to: replacement)
        if suggestion { title = "✦  " + title.dropFirst(3) }
        showPanel(title: title + (others > 0 ? "    +\(others)" : ""),
                  detail: (suggestion ? "Suggestion, no error: " : "") + replacement, at: anchor,
                  plain: draft.atCaret && !suggestion)
    }

    // MARK: Autocomplete and snippets

    /// Shows a guess for the rest of the sentence. The same keys apply and dismiss it.
    private func offer(_ text: String, after prefix: String, in field: Field) {
        let caret = Draft(pid: field.pid, element: field.element, range: NSRange(location: field.caret, length: 0),
                          text: "", atCaret: true)
        guard manualDraft == nil, shown == nil, let current = readField(), current.same(field),
              let anchor = anchor(for: caret, caret: field.caret) else { return }
        completion = (prefix, text, field)
        offeredFix = nil
        pair = nil
        showPanel(title: "⇥ " + text.trimmingCharacters(in: .whitespaces), detail: "Insert: " + text, at: anchor)
    }

    func acceptCompletion() {
        guard !applying, let completion, let field = readField(), field.same(completion.field) else { clear(); return }
        let spot = panelAnchor()
        applying = true
        clear()
        Task { [weak self] in
            guard let self else { return }
            let failure = await self.replace(NSRange(location: field.caret, length: 0), old: "", new: completion.text,
                                             in: field.element, pid: field.pid, text: field.text, restore: nil,
                                             onFailure: NSRange(location: field.caret, length: 0))
            self.applying = false
            if let failure { self.report("completion: " + failure, at: spot, app: field.pid) }
            else { self.note("completion inserted", app: field.pid); self.count("completed") }
        }
    }

    /// Replaces a typed snippet code, such as \\sig and a space, with its saved text.
    private func expand(_ hit: (range: NSRange, expansion: String), in field: Field) {
        applying = true
        // `clear` forgets the field, so without this note the next poll would try the same code again.
        triedSnippet = (field.element, field.text)
        clear()
        let code = (field.text as NSString).substring(with: hit.range)
        Task { [weak self] in
            guard let self else { return }
            let failure = await self.replace(hit.range, old: code, new: hit.expansion, in: field.element,
                                             pid: field.pid, text: field.text, restore: nil,
                                             onFailure: NSRange(location: field.caret, length: 0))
            self.applying = false
            self.note(failure.map { "FAILED snippet: " + $0 } ?? "snippet inserted", app: field.pid)
            if failure != nil { NSSound.beep() }
        }
    }

    func clear() {
        pending?.cancel()
        pending = nil
        generation += 1
        lastField = nil
        shown = nil
        offeredFix = nil
        completion = nil
        issues = []
        overlay.hide()
        hidePanel()
    }
}
