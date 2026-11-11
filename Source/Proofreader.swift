import AppKit
import NaturalLanguage

/// Spelling from the macOS spell checker. It runs on this Mac and honours words the user has learned.
@MainActor
enum SpellEngine {
    private static let tag = NSSpellChecker.uniqueSpellDocumentTag()
    private static let skipped = try! NSRegularExpression(
        pattern: #"`[^`]*`|https?://\S+|www\.\S+|[\w.+-]+@[\w.-]+\.[a-zA-Z]{2,}|[@#]\w+|\S*[/\\_]\S*|\b\w+\.\w+\b"#)

    // Modern and technical words the system dictionary does not know. Same list as the browser checker.
    private static let vocabulary: Set<String> = Set("""
        api apis app apps async auth autosave backend backends bitcoin blockchain blog blogs blogger blogging
        browser browsers calldata chatbot chatbots chromium cli codebase codebases config configs crypto
        cryptocurrency cryptocurrencies cybersecurity dataflow dataset datasets decentralized dedupe deduped
        deduplication defi dev devs devops ebook ebooks email emailed emailing emails fintech frontend frontends
        fullscreen github gitlab graphql html https hyperparameter hyperparameters iframe internet ios ipad
        iphone javascript jpeg json kanban localhost login logins macbook macos markdown metadata microservice
        microservices middleware minting multisig npm oauth offline online onboarding permalink podcast podcasts
        popover postmortem preprint preprints profiler repo repos rerun reruns roadmap sandbox sandboxed
        screenshot screenshots sdk selfie selfies semver serverless signup slack startups subagent subagents
        subreddit substack telemetry terraform timezone timezones timestamp timestamps tokenization tooltip
        touchpad typescript ui undoable unicode uniswap url urls usb username usernames viewport wasm webinar
        webinars webpage webpages website websites websocket websockets wifi workflow workflows workstream
        workstreams youtube zoom rollup rollups mainnet testnet stablecoin stablecoins tokenomics staking
        validator validators prover provers zk snark snarks stark starks llm llms embeddings finetune finetuned
        """.split(whereSeparator: \.isWhitespace).map(String.init))

    private static func englishVariants(_ checker: NSSpellChecker) -> [String] {
        ["en", "en_GB"].filter(checker.availableLanguages.contains)
    }

    /// The language of the text when it is clearly not English and this Mac has a dictionary for it.
    static func foreignLanguage(of text: String, checker: NSSpellChecker = .shared) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              language != .english, confidence >= 0.7 else { return nil }
        let code = language.rawValue
        return checker.availableLanguages.first { $0 == code } ?? checker.availableLanguages.first { $0.hasPrefix(code + "_") }
    }

    /// Returns the text with confident spelling fixes, or nil when nothing changes.
    /// `caret` is a UTF-16 offset. The word under the caret is still being typed, so it is left alone.
    static func fix(_ text: String, caret: Int? = nil) -> String? {
        let checker = NSSpellChecker.shared
        checker.automaticallyIdentifiesLanguages = true
        let source = text as NSString
        guard source.length > 0, source.length <= 2_000 else { return nil }
        var orthography: NSOrthography?
        var wordCount = 0
        // The spell checker guesses the language of a short sentence badly, and then checks German as English.
        // A clear answer from the language recognizer tells it which dictionary to use.
        let known = foreignLanguage(of: text, checker: checker)
        let options = known.map { [NSSpellChecker.OptionKey.orthography: NSOrthography.defaultOrthography(forLanguage: $0)] }
        let results = checker.check(text, range: NSRange(location: 0, length: source.length),
                                    types: NSTextCheckingResult.CheckingType.spelling.rawValue, options: options,
                                    inSpellDocumentWithTag: tag, orthography: &orthography, wordCount: &wordCount)
        guard !results.isEmpty else { return nil }
        let language = known ?? orthography?.dominantLanguage ?? checker.language()
        let protected = skipped.matches(in: text, range: NSRange(location: 0, length: source.length)).map(\.range)
        var edits: [(range: NSRange, text: String)] = []
        func valid(_ word: String) -> Bool {
            if word.count == 1 { return ["a", "i"].contains(word.lowercased()) }
            return checker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false,
                                         inSpellDocumentWithTag: tag, wordCount: nil).location == NSNotFound
        }
        for result in results where result.resultType == .spelling {
            let range = result.range
            let word = source.substring(with: range)
            if edits.contains(where: { NSIntersectionRange($0.range, range).length > 0 }) { continue }
            if let caret, caret >= range.location, caret <= NSMaxRange(range) { continue }
            if protected.contains(where: { NSIntersectionRange($0, range).length > 0 }) { continue }
            guard word.count >= 2, word.allSatisfy(\.isLetter) else { continue }
            // Names, acronyms and camelCase identifiers are not typos.
            let lowered = word.lowercased()
            if ProofEngine.keptWords.contains(lowered) || vocabulary.contains(lowered) { continue }
            let capitalised = word.first!.isUppercase && word.dropFirst() == lowered.dropFirst()
            guard word == lowered || (capitalised && range.location == 0) else { continue }
            // British and American spellings are both correct. A typo is wrong in both.
            if language.hasPrefix("en"), englishVariants(checker).contains(where: {
                checker.checkSpelling(of: word, startingAt: 0, language: $0, wrap: false,
                                      inSpellDocumentWithTag: tag, wordCount: nil).location == NSNotFound
            }) { continue }
            // A space typed one key early or late: "thi sis" is "this is".
            if let shifted = shiftedSpace(source, range, caret: caret, valid: valid) {
                edits.append(shifted)
                continue
            }
            guard word.count >= 4 else { continue }
            // The autocorrect answer counts only when the dictionary also lists it as a guess.
            let guesses = checker.guesses(forWordRange: range, in: text, language: language,
                                          inSpellDocumentWithTag: tag) ?? []
            let confident = checker.correction(forWordRange: range, in: text, language: language,
                                               inSpellDocumentWithTag: tag)
            let choice = confident.flatMap { guesses.contains($0) ? $0 : nil } ?? guesses.first
            guard var guess = choice, guess.lowercased() != lowered,
                  ProofEngine.distance(lowered, guess.lowercased()) <= (word.count >= 8 ? 2 : 1) else { continue }
            if capitalised { guess = guess.prefix(1).uppercased() + guess.dropFirst() }
            edits.append((range, guess))
        }
        var output = source
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            output = output.replacingCharacters(in: edit.range, with: edit.text) as NSString
        }
        return output as String == text ? nil : output as String
    }

    /// Tries to repair an unknown word by moving the space between it and a neighbour by one letter.
    private static func shiftedSpace(_ source: NSString, _ range: NSRange, caret: Int?,
                                     valid: (String) -> Bool) -> (range: NSRange, text: String)? {
        let pattern = try! NSRegularExpression(pattern: #"^ (\p{L}+)(?!\p{L}|['’])"#)
        let word = source.substring(with: range)
        let tail = NSRange(location: NSMaxRange(range), length: source.length - NSMaxRange(range))
        if let match = pattern.firstMatch(in: source as String, range: tail) {
            let next = source.substring(with: match.range(at: 1))
            let whole = NSRange(location: range.location, length: NSMaxRange(match.range) - range.location)
            if let caret, caret >= whole.location, caret <= NSMaxRange(whole) { return nil }
            let options = [(word + next.prefix(1), String(next.dropFirst())),
                           (String(word.dropLast()), word.suffix(1) + next)]
            for (first, second) in options where !first.isEmpty && !second.isEmpty && valid(first) && valid(second) {
                return (whole, first + " " + second)
            }
        }
        return nil
    }

}

/// Combines the fixed rules, the macOS spell checker and the on-device model.
@MainActor
enum Proofreader {
    static let maxSelectionLength = 8_000

    /// Instant checks that need no model.
    static func local(_ sentence: String, caret: Int? = nil) -> String? {
        let ruled = ProofEngine.fallback(sentence)
        // A rule can shift offsets, so the caret guard applies only to untouched text.
        let spelled = SpellEngine.fix(ruled ?? sentence, caret: ruled == nil ? caret : nil)
        // A rule or spelling fix must respect the user's dictionary too. Fall back to the part that does.
        return [spelled, ruled].compactMap { $0 }.first { ProofEngine.respectsDictionary($0, for: sentence) }
    }

    /// The best available correction for one sentence, or nil when it looks correct.
    static func check(_ sentence: String, caret: Int? = nil, before: String? = nil, extra: String? = nil) async -> String? {
        guard var best = await ProofEngine.contextual(sentence, before: before, extra: extra).replacement else {
            return local(sentence, caret: caret)
        }
        // The model often fixes one error and leaves another. Look once more, then run the instant checks.
        if let again = await ProofEngine.contextual(best, before: before, extra: extra).replacement,
           ProofEngine.acceptable(again, for: sentence, context: before) { best = again }
        if let polished = local(best), ProofEngine.acceptable(polished, for: sentence, context: before) { best = polished }
        return best
    }

    /// Corrects every sentence of a selection and keeps all other characters as they are.
    static func proofread(_ text: String, extra: String? = nil) async -> (text: String, fixes: Int, single: (old: String, new: String)?)? {
        guard text.utf16.count <= maxSelectionLength else { return nil }
        var output = text as NSString
        var fixes = 0
        var single: (old: String, new: String)?
        let sentences = ProofEngine.sentences(in: text)
        for (index, sentence) in sentences.enumerated().reversed() {
            if Task.isCancelled { return nil }
            let before = index > 0 ? sentences[index - 1].text : nil
            guard let correction = await check(sentence.text, before: before, extra: extra) else { continue }
            output = output.replacingCharacters(in: sentence.range, with: correction) as NSString
            fixes += 1
            single = (old: sentence.text, new: correction)
        }
        guard fixes > 0 else { return nil }
        return (text: output as String, fixes: fixes, single: fixes == 1 ? single : nil)
    }
}
