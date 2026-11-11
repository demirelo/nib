import AppKit

// Run with: bash Source/test.sh          (logic tests)
//           bash Source/test.sh --eval   (also scores the checkers on labelled sentences)

@main
@MainActor
struct Tests {
    static var failures = 0
    static var passed = 0

    static func expect(_ condition: Bool, _ name: String) {
        if condition { passed += 1 } else {
            failures += 1
            print("FAIL  " + name)
        }
    }

    static func main() async {
        // Tests never read the user's saved settings. This line comes first: without it the engine reads the
        // Mac app's settings, and a model server chosen there would answer the tests and the scoring.
        ProofEngine.config = ProofConfig()
        expect(ProofEngine.config.server.isEmpty && ProofEngine.config.localServer == nil
               && ProofEngine.config.dictionary.isEmpty && ProofEngine.config.instructions.isEmpty,
               "tests start with no model server, dictionary or instructions")
        expect(ProofConfig.appDomain == "com.nib.desktop", "settings come from the Mac app's domain")
        logic()
        guards()
        // NIB_SERVER and NIB_MODEL score a local model server instead of Apple's model.
        let environment = ProcessInfo.processInfo.environment
        if let server = environment["NIB_SERVER"], let model = environment["NIB_MODEL"] {
            ProofEngine.config = ProofConfig(server: server, model: model)
            print("Scoring with \(ProofEngine.modelName)")
        }
        var harmful = 0
        if CommandLine.arguments.contains("--eval") { harmful = await evaluate() }
        // `--improve <file>` prints the improvement suggestion for each line of a file.
        if let index = CommandLine.arguments.firstIndex(of: "--improve"), index + 1 < CommandLine.arguments.count,
           let file = try? String(contentsOfFile: CommandLine.arguments[index + 1], encoding: .utf8) {
            for line in file.split(separator: "\n").map(String.init) {
                let fields = line.split(separator: "\t").map(String.init)
                let suggestion = await ProofEngine.improve(fields[0])
                print((suggestion == nil ? "KEEP  " : "EDIT  ") + fields[0] + (suggestion.map { "  =>  " + $0 } ?? ""))
            }
        }
        print("\(passed) passed, \(failures) failed")
        if harmful > 0 { print("Scoring failed: \(harmful) false alarms or harmful changes") }
        exit(failures == 0 && harmful == 0 ? 0 : 1)
    }

    /// The copy of the browser extension that the user loads. Files only, in a temporary folder.
    static func extensionCopy() {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("nib-test-" + UUID().uuidString)
        defer { try? files.removeItem(at: root) }
        let source = root.appendingPathComponent("app/Browser"), target = root.appendingPathComponent("Library/Nib Browser Extension")
        func write(_ text: String, _ name: String, in folder: URL) {
            let file = folder.appendingPathComponent(name)
            try? files.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: file, atomically: true, encoding: .utf8)
        }
        func read(_ name: String) -> String? { try? String(contentsOf: target.appendingPathComponent(name), encoding: .utf8) }
        write("{\"version\": \"1.0\"}", "manifest.json", in: source)
        write("one", "content.js", in: source)
        expect((try? BrowserExtension.sync(from: source, to: target)) == true, "extension copy: first copy is made")
        expect(read("content.js") == "one" && BrowserExtension.version(of: target) == "1.0", "extension copy: files arrive")
        // Nothing changed: no copy, so the browser sees no change.
        expect((try? BrowserExtension.sync(from: source, to: target)) == false, "extension copy: an equal copy is not copied again")
        // From a user report: two builds with the same version number held different files, and the
        // user's browser kept the old ones. The files decide, not the version number.
        write("one, fixed", "content.js", in: source)
        expect((try? BrowserExtension.sync(from: source, to: target)) == true, "extension copy: a changed file with the same version is copied")
        expect(read("content.js") == "one, fixed", "extension copy: the changed file arrives")
        write("same size!", "content.js", in: source)   // same length as "one, fixed"
        expect((try? BrowserExtension.sync(from: source, to: target)) == true && read("content.js") == "same size!",
               "extension copy: a change of the same size is copied")
        write("x", "icons/new.png", in: source)
        expect((try? BrowserExtension.sync(from: source, to: target)) == true && read("icons/new.png") == "x",
               "extension copy: a new file in a subfolder is copied")
        // A new version in the app replaces the copy, and a file that left the app leaves the copy too.
        write("old only", "gone.js", in: target)
        write("{\"version\": \"1.1\"}", "manifest.json", in: source)
        write("two", "content.js", in: source)
        expect((try? BrowserExtension.sync(from: source, to: target)) == true, "extension copy: a new version is copied")
        expect(read("content.js") == "two" && read("gone.js") == nil && BrowserExtension.version(of: target) == "1.1",
               "extension copy: the new version replaces all files")
        expect(target.lastPathComponent == "Nib Browser Extension", "extension copy: the path stays the same")
        // A source without a manifest is an error, and the copy stays.
        let empty = root.appendingPathComponent("empty")
        try? files.createDirectory(at: empty, withIntermediateDirectories: true)
        expect((try? BrowserExtension.sync(from: empty, to: target)) == nil && read("content.js") == "two",
               "extension copy: a broken source changes nothing")
        let left = (try? files.contentsOfDirectory(atPath: target.deletingLastPathComponent().path)) ?? []
        expect(left == ["Nib Browser Extension"], "extension copy: no temporary folder is left")
    }

    static func logic() {
        extensionCopy()
        // Sentence finding
        let draft = "I went two the store. It was closed.\nSecond line here"
        let all = ProofEngine.sentences(in: draft)
        expect(all.map(\.text) == ["I went two the store.", "It was closed.", "Second line here"], "sentences split")
        expect(all.allSatisfy { (draft as NSString).substring(with: $0.range) == $0.text }, "sentence ranges match text")
        expect(ProofEngine.sentences(in: "").isEmpty, "empty draft has no sentences")
        expect(ProofEngine.sentences(in: "\n\n  \n").isEmpty, "blank lines have no sentences")
        expect(ProofEngine.sentences(in: "Emoji 👍🏽 first. Then more.").count == 2, "emoji keeps offsets valid")
        expect(ProofEngine.sentence(in: draft, at: 3)?.text == "I went two the store.", "sentence at caret")
        expect(ProofEngine.sentence(in: draft, at: (draft as NSString).length)?.text == "Second line here", "sentence at end")
        expect(ProofEngine.sentence(in: draft, at: 999) == nil, "caret out of range")

        // Edits
        let edit = ProofEngine.edit(from: "I went two the store.", to: "I went to the store.")
        let applied = ("I went two the store." as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        expect(applied == "I went to the store.", "minimal edit applies")
        let spaced = ProofEngine.edit(from: "what model doe sit", to: "what model does it")
        expect(spaced.original == "doe sit" && spaced.replacement == "does it", "edit covers whole words")
        expect(("what model doe sit" as NSString).replacingCharacters(in: spaced.range, with: spaced.replacement) == "what model does it", "whole-word edit applies")
        let typo = ProofEngine.edit(from: "I recieved the report.", to: "I received the report.")
        expect(typo.original == "recieved" && typo.replacement == "received", "edit of one word")
        let emoji = ProofEngine.edit(from: "👍🏽 I went two the store", to: "👍🏽 I went to the store")
        expect(("👍🏽 I went two the store" as NSString).replacingCharacters(in: emoji.range, with: emoji.replacement) == "👍🏽 I went to the store", "edit offsets after emoji")
        let insert = ProofEngine.edit(from: "However we left.", to: "However, we left.")
        expect(!insert.original.isEmpty, "insertion keeps a non-empty span")
        let word = ProofEngine.wordEdit(from: "I went two the store.", to: "I went to the store.")
        expect(word.original == "two" && word.replacement == "to", "word edit label")
        let comma = ProofEngine.wordEdit(from: "However we left.", to: "However, we left.")
        expect(comma.original == "However" && comma.replacement == "However,", "word edit for punctuation")
        let removal = ProofEngine.wordEdit(from: "It is is fine.", to: "It is fine.")
        expect(!removal.original.isEmpty && !removal.replacement.isEmpty, "word edit for removal has context")

        // Guard on model output
        expect(ProofEngine.acceptable("I went to the store.", for: "I went two the store."), "accepts a small fix")
        expect(!ProofEngine.acceptable("I went two the store.", for: "I went two the store."), "rejects no change")
        expect(!ProofEngine.acceptable("Sure! Here is a poem about cats and dogs for you.", for: "I went two the store."), "rejects a rewrite")
        expect(!ProofEngine.acceptable("Pay 200 dollars to me.", for: "Pay 100 dollars to me."), "rejects a changed number")
        expect(!ProofEngine.acceptable("See https://b.com now.", for: "See https://a.com now."), "rejects a changed link")
        expect(!ProofEngine.acceptable("\"I went to the store.\"", for: "I went two the store."), "rejects added quotes")
        expect(!ProofEngine.acceptable("Corrected: I went to the store.", for: "I went two the store."), "rejects a label")
        expect(!ProofEngine.acceptable("I went to\nthe store.", for: "I went two the store."), "rejects a new line")
        expect(!ProofEngine.acceptable("It is on-chain.", for: "It is onchain."), "keeps onchain")
        expect(!ProofEngine.acceptable("{\"text\":\"I went to the store.\"}", for: "I went two the store."), "rejects echoed JSON")

        expect(!ProofEngine.acceptable("What time does the meeting begin?", for: "What time does the meeting start?"), "rejects a synonym")
        expect(!ProofEngine.acceptable("The user does not exist.", for: "The user doesn't exist."), "rejects an expanded contraction")
        expect(!ProofEngine.acceptable("Let's sync on Slack, okay?", for: "Let's sync on Slack, k?"), "keeps slang")
        expect(!ProofEngine.acceptable("I am going to check it later.", for: "I am gonna check it later."), "keeps gonna")
        expect(ProofEngine.acceptable("They're going to be late.", for: "Their going to be late."), "accepts their to they're")
        expect(ProofEngine.acceptable("The results were better than we expected.", for: "The results was better then we expected."), "accepts verb agreement")
        expect(ProofEngine.acceptable("I didn't see your message.", for: "I didnt see youre message."), "accepts missing apostrophes")
        expect(ProofEngine.acceptable("However, we left early.", for: "However we left early."), "accepts a comma")
        expect(ProofEngine.acceptable("I am looking forward to meeting you.", for: "I am looking forward to meet you."), "accepts a word ending")
        expect(ProofEngine.acceptable("Ich habe gestern einen Fehler gemacht.", for: "Ich habe gestern ein Fehler gemacht."), "accepts a German ending")

        expect(ProofEngine.acceptable("Did you go to the meeting?", for: "Did you went to the meeting?"), "accepts a base verb form")

        expect(ProofEngine.acceptable("this is a chapter in my life.", for: "thi sis a chapter in may life."), "accepts three typos in a short sentence")
        expect(!ProofEngine.acceptable("We had a wonderful dinner by the sea.", for: "this is a chapter in my life."), "still rejects a new sentence")

        expect(!ProofEngine.acceptable("let us optimize the flow", for: "let us optimize the flow."), "rejects a dropped full stop")
        expect(ProofEngine.unwrap("{\"text\": \"I went to the store.\"}", source: "I went two the store.") == "I went to the store.", "unwraps echoed JSON")
        expect(ProofEngine.unwrap("\"I went to the store.\"", source: "I went two the store.") == "I went to the store.", "unwraps plain quotes")
        expect(ProofEngine.unwrap("\"Hi\" she said.", source: "\"Hi\" she sayed.") == "\"Hi\" she said.", "keeps real quotes")

        // Settings
        expect(ProofConfig(server: "http://127.0.0.1:11434", model: "m").localServer != nil, "accepts a server on this Mac")
        expect(ProofConfig(server: "http://localhost:1234", model: "m").localServer != nil, "accepts localhost")
        expect(ProofConfig(server: "https://api.example.com", model: "m").localServer == nil, "refuses a server on another machine")
        expect(ProofConfig(server: "http://192.168.1.5:11434", model: "m").localServer == nil, "refuses a server on the network")
        expect(ProofConfig(server: "http://127.0.0.1:11434", model: "").localServer == nil, "needs a model name")
        expect(LocalServer.clean("<think>hmm</think>\nI went to the store.") == "I went to the store.", "drops model reasoning")
        ProofEngine.config = ProofConfig(dictionary: ["btw", "doe sit"])
        expect(!ProofEngine.acceptable("By the way, I went to the store.", for: "Btw, I went two the store."), "dictionary word is kept")
        expect(ProofEngine.acceptable("Btw, I went to the store.", for: "Btw, I went two the store."), "other fixes still pass with a dictionary")
        expect(!ProofEngine.respectsDictionary("what model does it", for: "what model doe sit"), "dictionary phrase is kept")
        expect(ProofEngine.respectsDictionary("what model does it use", for: "what model do it use"), "dictionary ignores other text")
        ProofEngine.config = ProofConfig()
        let fenced = "Run this now.\n```\nlet x = teh value\n```\nThen wait."
        expect(ProofEngine.sentences(in: fenced).map(\.text) == ["Run this now.", "Then wait."], "code blocks are skipped")
        // The menus store a style by its raw value and read it back.
        expect(ProofEngine.Rewrite.allCases.allSatisfy { ProofEngine.Rewrite(rawValue: $0.rawValue) == $0 && !$0.title.isEmpty },
               "rewrite styles survive a round trip through their names")
        expect(Set(ProofEngine.Rewrite.allCases.map(\.goal)).count == ProofEngine.Rewrite.allCases.count, "each rewrite style has its own goal")

        // Snippets
        let snippets = ProofEngine.parseSnippets("sig = Best regards,\\nAlex\n\\addr = 123 Maple Street\nbad name = x\nempty =")
        expect(snippets == ["sig": "Best regards,\nAlex", "addr": "123 Maple Street"], "snippets are parsed")
        expect(ProofEngine.parseSnippets(ProofEngine.formatSnippets(snippets)) == snippets, "snippets survive a round trip")
        let typed = "Thanks. \\sig "
        let hit = ProofEngine.snippet(in: typed, caret: (typed as NSString).length, snippets: snippets)
        expect(hit?.expansion == "Best regards,\nAlex" && hit.map { (typed as NSString).substring(with: $0.range) } == "\\sig ", "snippet code expands")
        expect(ProofEngine.snippet(in: "Thanks. \\sig", caret: 12, snippets: snippets) == nil, "snippet waits for the space")
        expect(ProofEngine.snippet(in: "C:\\sig ", caret: 7, snippets: snippets) == nil, "a path is not a snippet")
        expect(ProofEngine.snippet(in: "\\nope ", caret: 6, snippets: snippets) == nil, "unknown snippet code")
        expect(ProofEngine.snippet(in: "\\SIG ", caret: 5, snippets: snippets) != nil, "snippet codes ignore case")

        // Autocomplete
        expect(ProofEngine.completionPrefix(in: "I will send the", caret: 15) == "I will send the", "completes an unfinished sentence")
        expect(ProofEngine.completionPrefix(in: "I will send the report.", caret: 23) == nil, "finished sentence needs no completion")
        expect(ProofEngine.completionPrefix(in: "I will", caret: 6) == nil, "too few words to complete")
        expect(ProofEngine.completionPrefix(in: "I will send the report today", caret: 10) == nil, "no completion in the middle of a line")
        expect(ProofEngine.completionPrefix(in: "Done.\nI will send the\nNext line", caret: 21) == "Done.\nI will send the", "completion at the end of a middle line")
        expect(ProofEngine.cleanCompletion("I will send the report tomorrow.", prefix: "I will send the") == " report tomorrow.", "echoed prefix is removed")
        expect(ProofEngine.cleanCompletion("report tomorrow", prefix: "I will send the ") == "report tomorrow", "no double space")
        expect(ProofEngine.cleanCompletion("", prefix: "I will send the") == nil, "empty completion")
        expect(ProofEngine.cleanCompletion(", and then call you", prefix: "I will send it") == ", and then call you", "no space before a comma")

        // Underlines
        let frame = CGRect(x: 100, y: 200, width: 400, height: 100)
        let lines = Overlay.layout([CGRect(x: 120, y: 210, width: 30, height: 16),      // inside the field
                                    CGRect(x: 120, y: 500, width: 30, height: 16),      // scrolled out of view
                                    CGRect(x: 120, y: 210, width: 300, height: 90),     // wraps over many lines
                                    CGRect(x: 120, y: 210, width: 0, height: 16)],      // no width
                                   within: frame, margin: 4)
        expect(lines == [CGRect(x: 20, y: 76, width: 30, height: 2)], "underline sits under the word, inside the field")

        // Fixed rules
        expect(ProofEngine.fallback("Their going to be late.") == "They're going to be late.", "rule: their going")
        expect(ProofEngine.fallback("Their house is big.") == nil, "rule: their house is fine")
        expect(ProofEngine.fallback("Its a great day.") == "It's a great day.", "rule: its a")
        expect(ProofEngine.fallback("The dog wagged its tail.") == nil, "rule: its tail is fine")
        expect(ProofEngine.fallback("It was better then we expected.") == "It was better than we expected.", "rule: better then")
        expect(ProofEngine.fallback("I am looking forward to meet you.") == "I am looking forward to meeting you.", "rule: forward to meet")
        expect(ProofEngine.fallback("Is your right hand free?") == nil, "rule: your right hand is fine")
        expect(ProofEngine.fallback("I recieved it.") == "I received it.", "rule: recieved")
        expect(ProofEngine.fallback("RECIEVED it.") == "RECEIVED it.", "rule keeps upper case")
        expect(ProofEngine.fallback("I should of gone.") == "I should have gone.", "rule: should of")
        expect(ProofEngine.fallback("I could of course go.") == nil, "rule: of course is fine")
        expect(ProofEngine.fallback("It is a error.") == "It is an error.", "rule: a error")
        expect(ProofEngine.fallback("Mail me at recieve@x.com") == nil, "rule skips emails")
        expect(ProofEngine.fallback("This is fine.") == nil, "rule: clean text")

        // Spelling
        expect(ProofEngine.distance("recieve", "receive") == 1, "swap counts once")
        expect(ProofEngine.distance("abc", "abc") == 0, "distance zero")
        // These need a dictionary on this Mac. A skip must be visible, so the count is printed.
        let spelling: [(() -> Bool, String)] = [
            ({ SpellEngine.fix("This is a sentance with a mistkae.") == "This is a sentence with a mistake." }, "spell: two typos"),
            ({ SpellEngine.fix("This is correct.") == nil }, "spell: clean text"),
            ({ SpellEngine.fix("Ask Jörg about Kubernetes and zkSNARKs.") == nil }, "spell: names and jargon"),
            ({ SpellEngine.fix("Run npm_install from src/utlis and see config.yaml.") == nil }, "spell: paths and files"),
            ({ SpellEngine.fix("Ping @johnn about #relase on https://exmaple.com/pth.") == nil }, "spell: handles and links"),
            ({ SpellEngine.fix("I am writi", caret: 10) == nil }, "spell: word under the caret"),
            ({ SpellEngine.fix("It settles onchain after the rollup posts calldata.") == nil }, "spell: crypto words"),
            ({ SpellEngine.fix("read this and let us optimize the flow.") == nil }, "spell: American spelling is fine"),
            ({ SpellEngine.fix("We organise the colours and realise the plan.") == nil }, "spell: British spelling is fine"),
            ({ SpellEngine.fix("The center of the neighbor's color program.") == nil }, "spell: more American spelling"),
            ({ Proofreader.local("read this and let us optimize the flow.") == nil }, "local: no fix for a correct sentence"),
            ({ SpellEngine.fix("thi sis a chapter in my life.") == "this is a chapter in my life." }, "spell: misplaced space"),
            ({ SpellEngine.fix("We wil lgo there soon.") == "We will go there soon." }, "spell: misplaced space, other direction"),
            ({ SpellEngine.fix("Sentance one is here.") == "Sentence one is here." }, "spell: capital at start"),
            ({ Proofreader.local("I recieved teh sentance.") == "I received the sentence." }, "local: rules plus spelling"),
        ]
        if NSSpellChecker.shared.availableLanguages.isEmpty {
            print("SKIPPED \(spelling.count) spelling tests: the macOS spell checker has no languages here")
        } else {
            for (test, name) in spelling { expect(test(), name) }
        }

        // Style suggestions: the writer's own words, fewer of them or in a better order. From user reports.
        let post = "This would eat up so much usage that it's actually a good sales trick."
        expect(ProofEngine.isImprovement("This would eat up so much usage that it's a good sales trick.", of: post), "improve: filler word removed")
        expect(!ProofEngine.isImprovement("This would consume so much usage—a good sales trick.", of: post), "improve: synonym rejected")
        expect(!ProofEngine.isImprovement(post, of: post), "improve: same sentence is no suggestion")
        expect(ProofEngine.isImprovement("Wir sind momentan nur 4 Personen und kurz vor dem Release.",
                                         of: "Wir sind nur 4 Personen momentan und sind kurz vor dem Release."), "improve: German word order")
        expect(!ProofEngine.isImprovement("Wir sind momentan nur 5 Personen und kurz vor dem Release.",
                                          of: "Wir sind nur 4 Personen momentan und sind kurz vor dem Release."), "improve: number must stay")
        expect(!ProofEngine.isImprovement("Thanks for the quick reply, I'll look at it today.",
                                          of: "Thanks for the quick reply, I will look at it today."), "improve: new contraction rejected")
        expect(!ProofEngine.isImprovement("I did have time to finish the report yesterday.",
                                          of: "I did not have time to finish the report yesterday."), "improve: negation must stay")
        expect(!ProofEngine.isImprovement("We ship on Friday.", of: "We are currently planning to ship the release on Friday."), "improve: too much removed")
        expect(!ProofEngine.isImprovement("This would eat up so much usage that it's a good sales trick", of: post), "improve: end mark must stay")
    }

    /// Tests from the review before the first public release. Each pair was wrong before its fix.
    static func guards() {
        // Fixed rules must stay silent on correct sentences. They fire at once, with no model to check them.
        let clean = [
            "Does she have the keys?", "You and I are friends.", "Are your notes ready?", "I read your welcome message.",
            "There is some confusion here.", "Things like this are common.", "One of those is broken.",
            "Someone like you has options.", "The cat has its very own bed.", "It got better then worse.",
            "Did he have time to look at it?", "Do they have what we need?", "Why does it have two buttons?",
            "Should she have called first?", "People like these are rare.", "Each of you has a login.",
            "Neither of those is right.", "The winner between me and you is Tom.", "My brother and I are in town.",
            "What it is is a mystery.", "The money I had went to rent.", "The time we had went by fast.",
            "All I had did not fit in the bag.", "The company lost its a-list clients.", "The dog wagged its tail.",
            "The team has its not-so-secret plan.", "We love their going away party idea.",
            "Their always helpful staff answered at once.", "Is your going there a problem?", "Your right answer surprised me.",
            "Thanks for your welcome.", "First we ate, then we left.", "Life was slower then for most people.",
            "I knew better then.", "We had more then, but less now.", "There is lots of time left.",
            "There is many a reason to wait.", "The might of the army was clear.", "I am not looking forward to work on Monday.",
            "Our Series A update is ready.", "Plan A option two looks fine.", "It is essential that she have access.",
            "Tom and she have a plan.", "The one I talked to is here.", "Back then it was a small company.",
            "Is it you or they who are late?", "I should of course call her.", "Give it a try if you have time.",
            "We met and then we talked for an hour.", "Their house is big.",
        ]
        for sentence in clean {
            expect(ProofEngine.fallback(sentence) == nil, "rule stays silent: \(sentence) => \(ProofEngine.fallback(sentence) ?? "")")
        }
        expect(clean.count >= 40, "at least 40 clean sentences")
        // The rules still catch what they are for.
        expect(ProofEngine.fallback("She don't like the new design.") == "She doesn't like the new design.", "rule: she don't")
        expect(ProofEngine.fallback("He have been working here for five years.") == "He has been working here for five years.", "rule: he have")
        expect(ProofEngine.fallback("There is many reasons to wait.") == "There are many reasons to wait.", "rule: there is many")
        expect(ProofEngine.fallback("We should of shipped this last week.") == "We should have shipped this last week.", "rule: should of, mid-sentence")
        expect(ProofEngine.fallback("The results was better then we expected.") == "The results was better than we expected.", "rule: better then we expected")
        expect(ProofEngine.fallback("It costs more then 5 dollars.") == "It costs more than 5 dollars.", "rule: more then a number")
        expect(ProofEngine.fallback("Your welcome!") == "You're welcome!", "rule: your welcome as a reply")
        expect(ProofEngine.fallback("I think your going to love it.") == "I think you're going to love it.", "rule: your going to love")
        expect(ProofEngine.fallback("I have went there before.") == "I have gone there before.", "rule: have went")
        expect(ProofEngine.fallback("I know they is late.") == "I know they are late.", "rule: they is after know")
        // English rules do not run on other languages.
        expect(ProofEngine.fallback("Skicka din adress till mig.") == nil, "rules skip Swedish")
        expect(ProofEngine.fallback("Hast du teh Datei gesehen?") == nil, "rules skip German")
        expect(ProofEngine.fallback("Send me the adress.") == "Send me the address.", "rules run on English")
        expect(ProofEngine.fallback("teh") == "the", "short text with no clear language counts as English")

        // The guard rejects every change of meaning.
        let changed: [(String, String)] = [
            ("I do not want to join the call.", "I do want to join the call."),
            ("The test is passing on main.", "The test isn't passing on main."),
            ("I did not approve the payment to Bob yesterday.", "I did approve the payment."),
            ("I approved the payment to Bob yesterday.", "I approved the payment."),
            ("This is legal in Germany.", "This is illegal in Germany."),
            ("It is possible to finish today.", "It is impossible to finish today."),
            ("We expect the costs to increase next year.", "We expect the costs to decrease next year."),
            ("They import steel from Asia.", "They export steel from Asia."),
            ("We will hire her next month.", "We will fire her next month."),
            ("Ship it with the usual tests.", "Ship it without the usual tests."),
            ("Ship it without the usual tests.", "Ship it with the usual tests."),
            ("I never said that to him.", "I ever said that to him."),
            ("Did you ever see it there?", "Did you never see it there?"),
            ("I am now ready for it.", "I am not ready for it."),
            ("I talked to Maria about the plan.", "I talked to Mario about the plan."),
            ("Please ask Tom for the keys.", "Please ask Tim for the keys."),
            ("She turned sixteen last week.", "She turned sixty last week."),
            ("We need three servers.", "We need two servers."),
            ("Meet me at 3:30 pm.", "Meet me at 3:30 am."),
            ("Are you there?", "I am here."),
            ("Is it done?", "No, it is not."),
            ("I went two the store.", "Here it is: I went to the store."),
            ("Thanks a lot.", "Thanks a lot!!! 🤬🖕"),
            ("Thanks a lot.", "Thanks a lot!!!"),
            ("I went to the store.", "**I went to the store.**"),
            ("I went to the store.", "`I went to the store.`"),
            ("It's done now.", "It is done now."), ("It is done now.", "It's done now."),
            ("I'd gone home.", "I had gone home."), ("I had gone home.", "I'd gone home."),
            ("Let us go now.", "Let's go now."), ("Let's go now.", "Let us go now."),
            ("Ich habe kein Geld.", "Ich habe ein Geld."),
            ("Das ist nicht mein Problem.", "Das ist mein Problem."),
            ("The careful driver stopped at the light.", "The careless driver stopped at the light."),
            // Numbers joined to letters, signs and units, hex strings and bare domains.
            ("It is 3x faster.", "It is 5x faster."), ("We ship in Q3.", "We ship in Q4."),
            ("It costs 100k per year.", "It costs 900k per year."), ("The balance is 500.", "The balance is -500."),
            ("Growth was 5", "Growth was 5%"),
            ("Send it to 0x52908400098527886E0F7030069857D2E4169EE7 now.", "Send it to 0x52908400098527886E0F7030069857D2E4169EE1 now."),
            ("Go to example.com/pay now.", "Go to examp1e.com/pay now."),
            ("Go to example.com now.", "Go to exemple.com now."),
        ]
        for (source, answer) in changed {
            expect(!ProofEngine.acceptable(answer, for: source), "guard rejects: \(source) => \(answer)")
        }
        // Good corrections still pass.
        let fixed: [(String, String)] = [
            ("I went two the store.", "I went to the store."),
            ("Their going to be late.", "They're going to be late."),
            ("She don't like it.", "She doesn't like it."),
            ("thi sis a chapter in may life.", "this is a chapter in my life."),
            ("Ich habe das Buch gestern gelsen.", "Ich habe das Buch gestern gelesen."),
            ("Ich freue mich auf dem Urlaub.", "Ich freue mich auf den Urlaub."),
            ("Das ist ein sehr gutes Idee.", "Das ist eine sehr gute Idee."),
            ("I dont know.", "I don't know."),
            ("I do nto want to join the call.", "I do not want to join the call."),
            ("I have know idea what happened.", "I have no idea what happened."),
            ("I have tree cats at home.", "I have three cats at home."),
            ("We need to talk on Wendesday about it.", "We need to talk on Wednesday about it."),
            ("I paid 5 dollar for it.", "I paid 5 dollars for it."),
            ("Meet me at 3:30 pm tomorow.", "Meet me at 3:30 pm tomorrow."),
            ("She is more taller than her brother.", "She is taller than her brother."),
            ("Vielen Dank für deine schnelle Antowrt.", "Vielen Dank für deine schnelle Antwort."),
            // A missing small word in German and French, slang letters that are plain words elsewhere, a moved space.
            ("Ich freue mich den Urlaub.", "Ich freue mich auf den Urlaub."),
            ("Je suis allé marché hier.", "Je suis allé au marché hier."),
            ("Ich fahre nah Hause.", "Ich fahre nach Hause."),
            ("I k now it works.", "I know it works."),
        ]
        for (source, answer) in fixed {
            expect(ProofEngine.acceptable(answer, for: source), "guard accepts: \(source) => \(answer)")
        }
        // A name changes only to a spelling that the sentence before shows.
        expect(!ProofEngine.acceptable("I met Katarzyna today.", for: "I met Katarzina today."), "name stays without context")
        expect(ProofEngine.acceptable("I met Katarzyna today.", for: "I met Katarzina today.", context: "Katarzyna called me."), "name follows the sentence before")
        expect(ProofEngine.unwrap("“I went to the store.”", source: "I went two the store.") == "I went to the store.", "unwraps curly quotes")
        expect(ProofEngine.protectedTokens("Pay $5.50 or 12% at 3:30 pm on 11/12 to a@b.co via x.io/pay, -40°.")
               == ["$5.50", "12%", "3:30 pm", "11/12", "a@b.co", "x.io/pay", "-40°"], "protected tokens")

        // Style suggestions never turn the claim.
        let turned: [(String, String)] = [
            ("Alice owes Bob money for the trip to Rome.", "Bob owes Alice money for the trip to Rome."),
            ("Send 5 units to site 10 before the end of the week.", "Send 10 units to site 5 before the end of the week."),
            ("We shipped it without the usual tests this week.", "We shipped it with the usual tests this week."),
            ("It is really possible to do this today.", "It is impossible to do this today."),
            ("This build is much more stable than before.", "This build is much less stable than before."),
            ("I do not think it is not ready.", "I do not think it is ready."),
        ]
        for (source, answer) in turned {
            expect(!ProofEngine.isImprovement(answer, of: source), "improve rejects: \(source) => \(answer)")
        }

        // Autocomplete
        expect(ProofEngine.cleanCompletion("the report tomorrow", prefix: "I will send the") == " report tomorrow", "short echo is removed")
        expect(ProofEngine.cleanCompletion("report to https://example.com", prefix: "I will send the") == nil, "no invented link")
        expect(ProofEngine.cleanCompletion("report to bob@example.com", prefix: "I will send the") == nil, "no invented address")
        expect(ProofEngine.cleanCompletion("report by 5 pm", prefix: "I will send the") == nil, "no invented number")
        expect(ProofEngine.cleanCompletion("5 reports today", prefix: "Of the 5 files I will send") == " 5 reports today", "the writer's own number may repeat")
        expect(ProofEngine.completionPrefix(in: "I will send the\n", caret: 16) == nil, "no completion on a new empty line")

        // Rewrite and cache
        expect(ProofConfig(dictionary: ["a"]).signature != ProofConfig(dictionary: ["b"]).signature, "dictionary is part of the cache key")

        // Code fences
        let inline = "```let x = 1``` is my code.\nI went two the store."
        expect(ProofEngine.sentences(in: inline).map(\.text) == ["I went two the store."], "a one-line fence does not hide the rest")
        let tilde = "Run this now.\n~~~\nlet x = teh value\n```\nstill code\n~~~\nThen wait."
        expect(ProofEngine.sentences(in: tilde).map(\.text) == ["Run this now.", "Then wait."], "tilde fences are skipped")

        // Dictionary entries with capitals or punctuation are kept as written.
        ProofEngine.config = ProofConfig(dictionary: ["iPhone", "e-mail", "c++"])
        expect(!ProofEngine.respectsDictionary("My Iphone is new.", for: "My iPhone are new."), "dictionary keeps iPhone")
        expect(!ProofEngine.respectsDictionary("Send an e mail today.", for: "Send a e-mail today."), "dictionary keeps e-mail")
        expect(!ProofEngine.respectsDictionary("I write c every day.", for: "I writes c++ every day."), "dictionary keeps c++")
        expect(ProofEngine.respectsDictionary("My iPhone is new.", for: "My iPhone are new."), "other fixes pass next to iPhone")
        expect(ProofEngine.respectsDictionary("I write c++ every day.", for: "I writes c++ every day."), "other fixes pass next to c++")
        // Settings stores entries in lower case today. The writer's inner capitals still count.
        ProofEngine.config = ProofConfig(dictionary: ["iphone"])
        expect(!ProofEngine.respectsDictionary("My Iphone is new.", for: "My iPhone are new."), "lower-case entry keeps iPhone")
        ProofEngine.config = ProofConfig()

        // Snippets and Windows paths
        expect(ProofEngine.parseSnippets("path = C:\\new\\notes") == ["path": "C:\\new\\notes"], "a Windows path keeps its backslash n")
        expect(ProofEngine.parseSnippets("share = \\\\nas\\new files") == ["share": "\\\\nas\\new files"], "a network path keeps its backslash n")
        expect(ProofEngine.parseSnippets("tex = use x\\\\not y") == ["tex": "use x\\not y"], "two backslashes escape a real backslash n")
        for value in ["C:\\new\\notes", "use x\\not y", "Best regards,\nAlex", "\\\\nas\\new files"] {
            expect(ProofEngine.parseSnippets(ProofEngine.formatSnippets(["k": value])) == ["k": value], "snippet round trip: \(value.debugDescription)")
        }

        // Scripts without spaces are checked too.
        expect(ProofEngine.checkable("我昨天去了商店。") && ProofEngine.checkable("今日は会議に行きます。"), "Chinese and Japanese sentences are checked")
        expect(!ProofEngine.checkable("好的") && !ProofEngine.checkable("Hello") && !ProofEngine.checkable("Hi\nthere you"), "too little text is skipped")
        expect(ProofEngine.checkable("I went two the store."), "an English sentence is checked")

        // Model input and local server
        expect((try? ProofEngine.modelInput(ProofRequest(text: "See https://a.com/b on 11/12."))) == "{\"text\":\"See https://a.com/b on 11/12.\"}", "model input keeps slashes")
        for bad in ["http://127.0.0.1@evil.com", "http://localhost.evil.com", "http://[::ffff:8.8.8.8]", "ftp://localhost",
                    "http://evil.com/localhost", "http://127.0.0.1.evil.com:11434", "localhost:11434"] {
            expect(ProofConfig(server: bad, model: "m").localServer == nil, "refuses \(bad)")
        }
        for good in ["http://[::1]:11434", "http://127.0.0.1:11434"] {
            expect(ProofConfig(server: good, model: "m").localServer != nil, "accepts \(good)")
        }
        for pasted in ["http://localhost:11434/v1", "http://localhost:11434/v1/", " http://localhost:11434/ ", "http://localhost:11434"] {
            expect(ProofConfig(server: pasted, model: "m").localServer?.appendingPathComponent("v1/models").absoluteString
                   == "http://localhost:11434/v1/models", "server address is normalised: \(pasted)")
        }

        // Browser log lines
        expect(ProofEngine.printable("a\r\nb\u{1B}[31mc\u{2028}d\u{202E}e\u{0}f\tg") == "a  b[31mc def g", "log line drops control characters")
        expect(ProofEngine.printable(String(repeating: "x", count: 500)).count == 300, "log line is capped")

        // A stuck model call ends at its deadline.
        let clock = ContinuousClock()
        let start = clock.now
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var late: Int? = 1
        nonisolated(unsafe) var quick: Int?
        Task.detached {
            late = await ProofEngine.limited(.milliseconds(100)) {
                try? await Task.sleep(for: .seconds(30))
                // Ignores cancellation on purpose, like a call that hangs.
                usleep(1_000_000)
                return 1
            }
            quick = await ProofEngine.limited(.seconds(5)) { 7 }
            done.signal()
        }
        done.wait()
        expect(late == nil && clock.now - start < .milliseconds(900), "a stuck call returns at the deadline")
        expect(quick == 7, "a quick call returns its answer")
    }

    /// Prints one line per set and mode. Returns the number of false alarms and harmful changes: any of them fails the run.
    static func evaluate() async -> Int {
        guard let index = CommandLine.arguments.firstIndex(of: "--eval"), index + 1 < CommandLine.arguments.count,
              let file = try? String(contentsOfFile: CommandLine.arguments[index + 1], encoding: .utf8) else {
            print("Pass the path of eval-cases.tsv after --eval")
            return 1
        }
        print("Model available: \(ProofEngine.modelAvailable)")
        var bad = 0
        let lines = file.split(separator: "\n").filter { !$0.hasPrefix("#") }.map { $0.split(separator: "\t").map(String.init) }
        for set in ["tuned", "holdout", "reported", "context", "other", "fresh"] {
            let cases = lines.filter { ($0.count == 3 || $0.count == 4) && $0[0] == set }
            guard !cases.isEmpty else { continue }
            let errors = cases.filter { $0[1] != $0[2] }.count
            var rows: [String: (caught: Int, exact: Int, wrong: Int, harmful: Int, alarms: Int)] = [:]
            for item in cases {
                let draft = item[1], expected = item[2]
                let outputs: [(String, String?)] = [
                    ("offline: rules + spelling", Proofreader.local(draft)),
                    ("with model: full pipeline", await Proofreader.check(draft, before: item.count == 4 ? item[3] : nil)),
                ]
                for (name, output) in outputs {
                    var row = rows[name] ?? (0, 0, 0, 0, 0)
                    if draft == expected {
                        if let output {
                            row.alarms += 1
                            print("ALARM [\(name)] \(draft)  =>  \(output)")
                        }
                    } else if let output {
                        row.caught += 1
                        if output == expected {
                            row.exact += 1
                        } else {
                            // A fix that is not the expected one. It is harmful when it changes a number, a link
                            // or a negation: the writer then sends something they did not say.
                            row.wrong += 1
                            let harmful = ProofEngine.protectedTokens(output) != ProofEngine.protectedTokens(expected)
                                || ProofEngine.negations(in: output) != ProofEngine.negations(in: expected)
                            if harmful { row.harmful += 1 }
                            print("\(harmful ? "HARM " : "DIFF ") [\(name)] \(draft)  =>  \(output)")
                        }
                    } else if name.hasPrefix("with model") {
                        print("MISS  \(draft)")
                    }
                    rows[name] = row
                }
            }
            print("\n[\(set)] mode | flagged of \(errors) errors | exact fix | wrong fix | harmful | false alarms of \(cases.count - errors) clean")
            for name in rows.keys.sorted() {
                let row = rows[name]!
                bad += row.alarms + row.harmful
                print("[\(set)] \(name) | \(row.caught) | \(row.exact) | \(row.wrong) | \(row.harmful) | \(row.alarms)")
            }
            print("")
        }
        return bad
    }
}
