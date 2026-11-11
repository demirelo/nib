"use strict";

globalThis.nibCheck = (() => {
  let dictionary;
  const knownTypos = new Map(Object.entries({
    teh:"the", hte:"the", recieve:"receive", recieved:"received", recieving:"receiving",
    accomodate:"accommodate", accomodation:"accommodation", adress:"address",
    definately:"definitely", seperate:"separate", separatly:"separately", tommorow:"tomorrow",
    wierd:"weird", grammer:"grammar", speling:"spelling", misspeling:"misspelling", writting:"writing", freind:"friend", thier:"their",
    becuase:"because", beacuse:"because", acheive:"achieve", acheived:"achieved",
    ocurred:"occurred", occurrance:"occurrence", untill:"until", sucess:"success",
    succesful:"successful", comming:"coming", begining:"beginning", goverment:"government",
    enviroment:"environment", neccessary:"necessary", neccesary:"necessary", necesary:"necessary",
    recomend:"recommend", reccomend:"recommend", persue:"pursue",
    peice:"piece", beleive:"believe", concious:"conscious", dissapoint:"disappoint",
    independant:"independent", calender:"calendar", tomorow:"tomorrow", embarass:"embarrass",
    publically:"publicly", mroe:"more", pwoer:"power", foward:"forward", thiss:"this",
    responsiblity:"responsibility", maintainance:"maintenance", availible:"available",
    exmaple:"example", sentance:"sentence", langauge:"language", mistkae:"mistake",
    preffered:"preferred", preferrable:"preferable", orignal:"original", relevent:"relevant"
  }));
  const modernWords = `api apis app apps async auth autosave backend backends bitcoin blockchain blog blogs
  blogger blogging browser browsers calldata chatbot chatbots chromium cli codebase codebases
  config configs crypto cryptocurrency cryptocurrencies cybersecurity dataflow dataset datasets
  decentralized dedupe deduped deduplication defi dev devs devops dunno gonna gotta kinda sorta wanna yup yep nope ebook ebooks email emailed
  emailing emails fintech frontend frontends fullscreen github gitlab graphql html https hyperparameter
  hyperparameters iframe internet ios ipad iphone javascript jpeg json kanban localhost login logins
  macbook macos markdown metadata microservice microservices middleware minting multisig npm oauth offline
  ok okay online onchain offchain openai onboarding permalink podcast podcasts popover postmortem
  preprint preprints pressroom profiler repo repos rerun reruns roadmap sandbox sandboxed screenshot
  screenshots sdk selfie selfies semver serverless signup slack smartwatches smartwatch startups
  subagent subagents subreddit substack telemetry terraform timezone timezones timestamp timestamps
  tokenization tooltip touchpad typescript ui undoable unicode uniswap url urls usb username usernames
  viewport wasm webinar webinars webpage webpages website websites websocket websockets wifi
  workflow workflows workstream workstreams youtube zoom
  has does is was were been am are began begun blew blown forgave forgiven heard held paid woken withdrew
  withdrawn knelt leapt dreamt spelt spilt smelt strode strove trod trodden wove woven`.split(/\s+/);

  // Common words that the base list lacks, such as "using", "box" and "database". They come from a run
  // of this checker over 1.5 million words of correct English: each word here got a spelling mark there,
  // and the macOS dictionary accepts it as English. A word of three letters can hide a real typo, so
  // only the few in `shortKept` count.
  const shortKept = new Set(["box", "etc", "ids", "pdf", "png", "css", "xml"]);
  const commonAdded = `abs accessor accessors ack actionability addressable ads adversarial adversarially affordance agentic alloc allowlist allowlisted allowlisting
  allowlists anonymized anymore anytime arbitrage arg args aspirational associativity asynchronously attendees auditable autocomplete autofill
  autogenerate autoload automate automates automation automations avatar avatars avoidant awk babysit backlinks backoff backslash backslashes backtest
  backtick backticks backtrace backtraces ballpark bandwidth baseline baselines became behaviorally behaviour behavioural benchmark benchmarked
  benchmarking benchmarks bento bidirectionally blacklist blacklisting blacklists blocklist blocklists blogpost boardroom boilerplate bookend boolean
  booleans bouncy boutique box boxed boxes brainstorm brainstormed brainstorming brainstorms breadcrumbs breakpoints breathtaking broader browsable
  bubblewrap builtin builtins buzzwords byte bytes calc callback callbacks callee callees callout callouts canonicalize canonicalized canonicalizes
  captchas cardinalities cardinality catalog catalogs caveman centralised centre centred centreline cert certs cfg charset charsets cheaper cheapest
  cheatsheet checkbox checkboxes checklist checklists checkmark checkpoint checkpointing checkpoints checksum checksums chiclets chmod chokepoint
  classifies classify classifying cleanest clearest clickable clickjacking clipboard closeout cmd coarser codecs codepath codepaths codeveloping colour
  coloured colours combo combobox commonest comms comp completable composability composable computationally concat configurable contactable
  containerized cookie cooldown coolest coord coordinate coordinated coordinates coordinating coordination coordinator coordinators copyable copyleft
  coroutines cosign costlier counterexample counterexamples counterparties counterparty creds cron crud css customizable customization customizations
  customize customized customizing cwd cyclomatic darker database databases debounce debug debuggable debugged debugger debuggers debugging decoder
  decoders decouple decoupled decouples decoupling decrypt decrypted decryption deduplicate deduplicated deeper deepest def demo denylist deployable
  deployer deprioritize dept dereference dereferences desc descriptor descriptors deserialization deserialize desktop deterministically dialog dialogs
  dict dicts died diff diffed diffing diffs dir disambiguate disambiguation distractor docx dogfood dogfooding dogfoods download downloadable downloaded
  downloading downloads downscale drivetrain dropdown earlier echoes editable embeddings emoji emojis empirically encoder encoders encodings endian
  endpoint endpoints enqueue enqueues ent enum enums env ergonomics errno escalation escalations etc ethnicity eval evals evaluator exe exec execs
  executability exfiltrate exfiltrating expandable expertise exploitability extremal facto failover falsifiability fanout fastest favicon favour fewer
  fewest fibonacci fiddly filename filenames filesystem finalization finalizer finalizers firmware flowchart flowcharts foreach formatter formatters fps
  fractals freeform friendlier func fundraising fuzzer fuzzers gcc gdb gigabytes glob globs gmail google gotcha gotchas goto grandchildren grapheme
  greenfield grep gridlines groupthink guid gzip gzipped hackathon haiku handoff handoffs handwritten hang hangs hardcode hardcoded hardcodes hardcoding
  hardest hardwired headcount headwind healthcare heavier heroes hexadecimal hoc homepage honour honoured honours hostname hostnames hotspot hotspots
  href hrs http ids iff iii img impactful implementable implementer implementers inbox incrementally indexable info init initialization initializer
  inits inline inlined inlines inlining installable instantiation interactively interoperability intro iterator iterators jailbreaks judgement keychain
  keyframe keyframes keystrokes keyword keywords landmine lang laptop laptops larger leaderboard leaderboards letterforms lib libc libs licences
  lifecycle lifecycles lightest linux llm lockdown lockstep logout loopback lossy loudest lowercase lowercased lowercasing lowest mailto mainframe
  maintainability malware mappings marketplace marketplaces meantime mega megabytes metavariable metavariables microarchitecture micromanagement mindset
  mini minimalistic misaligned misc miscodes misconfigured misdetects mistyped mkdir mocktail mockup mockups modularity monospace monotonicity moonshot
  motivator motivators mph msg multicast multiline multipart multitasking mutator mutators mutex namespace namespaces narrowest nav nbsp nearer neg
  neighbouring newer newest newline newlines nicer nitpick nitpicks nofollow nondeterminism nondeterministic nonempty noninvasive nonnegative nontrivial
  normalised nullability num numeric obj offload ogg oldest onboard oops opcode opcodes operationalize operationalized operationalizes operationally ops
  org orgs outsource overkill overridable overridden overrode overwritten overwrote owed packager pairings panicking parameterization parameterize
  parameterized parseable partway passphrase passthrough pathname payback payload payloads paywalled pdf perf perl phishing pid pixel pixels plaintext
  plist plugin plugins png popup pos posix postconditions pptx pragma pragmas pre preemptively pref prefetch prefilled prefs preload preloaded prepend
  prepended prepending prepends preprocessing prev prewarming printf printout prioritization prioritize prioritized prioritizes prioritizing proactive
  proactively proud pseudocode pushback pushy pwd queryable quicker quickest rankings rarer rasterize rasterizes reachability readme readonly realpath
  realtime reboot reboots reconfiguration reconstructable recursively redoes reengineering reentrancy refactor refactored refactoring refactors reformat
  reformatting regenerable regex regexes reimplement reimplementation reimplementing reimplements reindex reinit reinitialize reinitialized rekey
  rekeyed rekeying relayer relayers relayout remediate reorg repeatably repro req reran res respawn restructure restructured restructures restructuring
  restructurings retarget retargeted retro retros reusability reusable rewordings rewritten rewrote richer riskier robotic rollout rollouts rollup
  roundtrip routable rsync ruleset rulesets runtime runtimes safer sanitization sanitizer sanitizers scalability scheduler scorecard scratchpad
  screencast screencasts scrollbars scroller sed selftest serializable serializer sharpest shootout shortcut shortcuts shortest shortlist shortlisted
  shortlists sidebar sidestep sidesteps sizeof slower slowest smallest smarter smartest smartypants softer speedup spinout spreadsheet spreadsheets src
  ssh standalone standup startup stat stats stderr stdin stdio stdout sterner stockout storyboard str streamable stricter strictest stronger strongest
  struct structs stylesheet stylesheets subcommand subcommands subdirectories subdirectory subdomain subfolder subgraph subgraphs submodule submodules
  subnet subnets subprocess subprocesses substring subtopic subtree sudo summarised superset swappable symlink symlinks tagline taglines takeaway
  takeaways takeover tapback tarball terracotta testability textbox tiebreakers tighter timeframe timeline timelines timeout timeouts tldr tmp todo
  todos tokenized tokenizer tokenizers tokenizing tokenomics toolbar toolbars toolchain toolkit toolset touchpoint tradeoff tradeoffs tripwire tripwires
  troubleshoot troubleshooting tuple tuples typeface typefaces typeof typings uint umask unarchived uncached undoes unescape unicast unimplemented
  uninitialized uninstall uniq unix unlabelled unoptimized unrecommended unserialize unstructured updater upfront upgradable upgradeability upgradeable
  upgrader uploader uppercase ups uptime usdt using util utils uuid validator validators var vars ver versa vetoes vibe vibes vibing von waitlist
  walkthrough walkthroughs warmup weaker weakest wellbeing whitelist whitelisted whitelists whitespace wider widget widgets wiki wildcard wildcards
  wireframe wireframes wordlist wordlists workaround workarounds workforce worksheets workspace workspaces worldview worldviews worthwhile wtf xlsx xml
  xterm yaml yolo zap zsh`.split(/\s+/).filter(word => word.length > 3 || shortKept.has(word));

  // Short words that a moved space may produce. The full dictionary holds too many rare short words.
  const common = new Set(`a an am as at be by do go he if in is it me my no of on or so to up us we
  all and any are but can did for get had has her him his how its let may new not now one our out
  see she the too two use was way who why yes yet you`.split(/\s+/));

  function matchCase(source, replacement) {
    if (source === source.toUpperCase() && source.length > 1) return replacement.toUpperCase();
    if (/^[A-Z]/.test(source)) return replacement.charAt(0).toUpperCase() + replacement.slice(1);
    return replacement;
  }

  function inDictionary(word) {
    if (dictionary.has(word)) return true;
    if (word.length < 4) return false;
    if (word.endsWith("ies") && dictionary.has(word.slice(0, -3) + "y")) return true;
    if (word.endsWith("ves")) {
      const stem = word.slice(0, -3);
      if (dictionary.has(stem + "f") || dictionary.has(stem + "fe")) return true;
    }
    if (word.endsWith("s") && dictionary.has(word.slice(0, -1))) return true;
    if (/(?:[sxz]|ch|sh)es$/.test(word) && dictionary.has(word.slice(0, -2))) return true;
    if (word.endsWith("ied") && dictionary.has(word.slice(0, -3) + "y")) return true;
    for (const ending of ["ed", "ing"]) {
      if (!word.endsWith(ending)) continue;
      const stem = word.slice(0, -ending.length);
      // A stem of two letters counts only with its final e: "using" is "use", "tied" is "tie".
      if (stem.length === 2 && dictionary.has(stem + "e")) return true;
      if (stem.length < 3) continue;
      if (dictionary.has(stem) || dictionary.has(stem + "e")) return true;
      if (/([^aeiou])\1$/.test(stem) && dictionary.has(stem.slice(0, -1))) return true;
    }
    // Comparatives: "taller", "nicest", "bigger", "happier". The list holds only some of them.
    for (const ending of ["iest", "ier", "est", "er"]) {
      if (!word.endsWith(ending)) continue;
      const stem = word.slice(0, -ending.length);
      if (stem.length < 3) continue;
      if (ending[0] === "i") {
        if (dictionary.has(stem + "y")) return true;
        continue;
      }
      // "earlyer" is a typo of "earlier", so a stem that ends in y does not take a plain ending.
      if (stem.endsWith("y")) continue;
      if (dictionary.has(stem) || dictionary.has(stem + "e")) return true;
      if (/([^aeiou])\1$/.test(stem) && dictionary.has(stem.slice(0, -1))) return true;
    }
    return false;
  }

  const spellingCache = new Map();
  const alphabet = "abcdefghijklmnopqrstuvwxyz";
  const keyboardRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"];
  function adjacentKeys(a, b) {
    const row = keyboardRows.find(keys => keys.includes(a) && keys.includes(b));
    return row && Math.abs(row.indexOf(a) - row.indexOf(b)) === 1;
  }
  function spellingGuesses(word) {
    if (knownTypos.has(word)) return [knownTypos.get(word)];
    if (spellingCache.has(word)) return spellingCache.get(word);
    const candidates = new Map();
    const add = (candidate, cost) => {
      if (candidate.length < 2 || candidate === word || !dictionary.has(candidate)) return;
      candidates.set(candidate, Math.min(cost + (candidate[0] === word[0] ? 0 : 0.45), candidates.get(candidate) ?? Infinity));
    };
    for (let i = 0; i <= word.length; i++) {
      const left = word.slice(0, i);
      const right = word.slice(i);
      if (i < word.length) {
        add(left + right.slice(1), 1);
        if (right.length > 1) add(left + right[1] + right[0] + right.slice(2), 0.65);
      }
      for (const letter of alphabet) {
        add(left + letter + right, 1.15);
        if (i < word.length) add(left + letter + right.slice(1), adjacentKeys(right[0], letter) ? 0.85 : 1.35);
      }
    }
    const guesses = [...candidates].sort(([a, scoreA], [b, scoreB]) => scoreA - scoreB || a.localeCompare(b))
      .slice(0, 3).map(([candidate]) => candidate);
    if (spellingCache.size >= 2500) spellingCache.clear();
    spellingCache.set(word, guesses);
    return guesses;
  }

  const rules = [
    ["repeated", "Grammar", /\b([a-z]+)([ \t]+)\1\b/gi,
      "This word appears twice in a row.", m => [m[1]], m => !/^(had|that|very|really|so|bye|no|yes|never)$/i.test(m[1])],
    ["modal-have", "Grammar", /\b(could|should|would|might|must) of\b/gi,
      "Use “have” after a modal verb here.", m => [m[1] + " have"], (m, text) => !/^\s+(?:course|all)\b/i.test(text.slice(m.index + m[0].length))],
    ["then-than", "Grammar", /\b(more|less|fewer|rather|better|worse|greater|higher|lower|longer|shorter) then\b(?=[ \t]+(?:a|an|the|[0-9]+|you|me|us|them|we|they|he|she|it|expected|before)\b)/gi,
      "Use “than” to make a comparison.", m => [m[1] + " than"]],
    ["singular-be", "Grammar", /\b(he|she|it|this) are\b/gi,
      "Check whether the verb agrees with the singular subject.", m => [m[1] + " is"]],
    ["plural-be", "Grammar", /\b(we|they|you|these|those) (is|was)\b/gi,
      "Check whether the verb agrees with the subject.", m => [m[1] + (m[2].toLowerCase() === "is" ? " are" : " were")]],
    ["first-be", "Grammar", /\bI (is|are)\b/gi,
      "Use “am” with “I.”", () => ["I am"]],
    ["have-agreement", "Grammar", /\b(?:(I|we|you|they) has|(he|she|it) have)\b/gi,
      "Check whether “have” agrees with the subject.", m => [m[1] ? m[1] + " have" : m[2] + " has"],
      (m, text) => !/\b(?:does|did|do|could|would|should|must|may|might|will|shall)\s*$/i.test(text.slice(Math.max(0, m.index - 14), m.index))],
    ["do-agreement", "Grammar", /\b(?:(he|she|it) (don['’]t|do not)|(I|we|you|they) (doesn['’]t|does not))\b/gi,
      "Check whether “do” agrees with the subject.", m => [m[1] ?
        m[1] + (/not$/i.test(m[2]) ? " does not" : m[2].includes("’") ? " doesn’t" : " doesn't") :
        m[3] + (/not$/i.test(m[4]) ? " do not" : m[4].includes("’") ? " don’t" : " don't")]],
    ["im", "Grammar", /\bim\b/g, "Use “I'm” for “I am.”", () => ["I'm"]],
    ["confused-loose", "Grammar", /\b(loose)(?=\s+(?:your|my|his|her|their|our)\s+(?:way|mind|money|job|keys|phone|wallet|patience|balance)\b)/gi,
      "Use “lose” when something goes missing.", () => ["lose"]],
    ["for-all-intents", "Grammar", /\bfor all intensive purposes\b/gi,
      "The usual expression is “for all intents and purposes.”", () => ["for all intents and purposes"]],
    ["irregular-participle", "Grammar", /\b(have|has|had) (went|saw|wrote|took|ate|gave|did|drove|spoke|broke|chose|fell)\b/gi,
      "Use the past participle after “have.”", m => [m[1] + " " + ({
        went:"gone", saw:"seen", wrote:"written", took:"taken", ate:"eaten", gave:"given",
        did:"done", drove:"driven", spoke:"spoken", broke:"broken", chose:"chosen", fell:"fallen"
      })[m[2].toLowerCase()]]],
    ["spacing", "Punctuation", /([^\s\r\n])([ \t]{2,})(?=\S)/g,
      "One space is enough here.", () => [" "], m => !m[2].includes("\t"), m => [1, m[2].length]],
    ["before-punctuation", "Punctuation", /[ \t]+(?=[,.;!?](?:\s|$))/g,
      "Remove the space before this punctuation mark.", () => [""]],
    ["after-punctuation", "Punctuation", /([,;!?])(?=[A-Za-z])/g,
      "Add a space after this punctuation mark.", m => [m[1] + " "],
      (m, text) => /[a-z0-9'’")]/i.test(text[m.index - 1] || "")],
    ["duplicate-punctuation", "Punctuation", /([,;])\1+/g,
      "This punctuation mark is repeated.", m => [m[1]]],
    ["style-order", "Style", /\bin order to\b/gi, "You can usually say this more directly.", () => ["to"]],
    ["style-due", "Style", /\bdue to the fact that\b/gi, "Consider a shorter phrase.", () => ["because"]],
    ["style-time", "Style", /\bat this point in time\b/gi, "Consider a shorter phrase.", () => ["now"]],
    ["style-number", "Style", /\ba large number of\b/gi, "Consider a shorter phrase.", () => ["many"]],
    ["style-able", "Style", /\bis able to\b/gi, "Consider a shorter phrase.", () => ["can"]],
    ["style-first", "Style", /\bfirst and foremost\b/gi, "Consider a shorter phrase.", () => ["first"]],
    ["style-advance", "Style", /\badvance planning\b/gi, "Consider a shorter phrase.", () => ["planning"]],
    ["style-regard", "Style", /\bwith regard to\b/gi, "Consider a shorter phrase.", () => ["about"]]
  ];

  // The rules and the word list are English. A sentence in another language must not get English checks.
  // Common words of other languages that are not also common English words.
  const foreignWords = new Set(`
    und der das ist nicht ich du wir ihr sie mit für auf dem den des ein eine einen einem einer auch sind wird
    werden haben habe hast kann kannst können noch nur aber oder wenn dass weil sehr schon uns euch mir dir mich
    dich vor nach bei von zu zum zur aus über unter kurz vielleicht bitte danke heute morgen gestern jetzt hier
    wie wo wer warum nein ja kein keine mehr immer wieder dann doch diese dieser dieses momentan lass
    le les est et je nous vous ils elles ne pas que qui avec dans sur une mais où très bien merci beaucoup votre
    notre cette ces aux du suis sont était avoir être fait comme aussi demain hier oui
    el los las yo tú nosotros para por pero muy gracias qué cómo está están tengo tiene mañana hoy ayer sí del
    este esta más también porque cuando
    il gli che sono ho hai abbiamo molto grazie questo questa anche perché oggi domani ieri della dei nel
    het een niet voor ook naar geen heb heeft wij jullie bedankt zijn ik
    não você nós uma mas muito obrigado obrigada isso também quando hoje amanhã ontem sim são tenho tem dos das
    ve bir için ile biz siz değil yok çok evet hayır teşekkürler nasıl zaman yarın bugün dün musun gibi daha ama
    guten gute hallo alles klar vielen dank viel viele wurde wurden hatte bist seid mein meine dein deine unser
    wann welche nichts etwas gleich leider gerne natürlich genau zeit geht gehe gehen komme kommt kommen mache
    macht machen gibt sich als durch ohne zwischen seit beim vom ins zusammen zwei drei vier fünf sechs sieben
    acht neun zehn bis
    bonjour salut tout ça
    ciao stai sei siamo buongiorno tutti mille
    nos hola amigo amiga amigos estoy somos eres hay adiós buenos buenas días todos hasta luego un una uno
    jag har och ett det är inte ikke og jeg
    dziekuje dziękuję bardzo dobrze jest nie tak się
    kiitos paljon ei että saya mau makan dan yang tidak ini itu terima kasih banyak
  `.trim().split(/\s+/));
  // Short forms from chat. They are English, although the dictionary does not hold them.
  const chatWords = new Set("pls plz thx asap btw fyi imo imho tbh idk lol omg afaik".split(" "));
  // English writes a few loan words with these marks: résumé, naïve, café. German and Turkish marks are not here.
  const loanMarks = /^[a-záàâéèêëíïóôúçñ]+$/;
  const englishWords = new Set(`the a an and of to in is are was were be been i you he she it we they this that
    these those for with on at by from not have has had do does did will would can could should my your his her
    our their me him us them what which who when where why how but or if so as there here very just about into
    than then`.split(/\s+/));

  // True for a word that looks like an English word with one typing slip. The dictionary is large, so a short
  // word of any language is one letter away from some entry: short words count only with two letters swapped.
  const closeCache = new Map();
  function closeToEnglish(word) {
    if (knownTypos.has(word)) return true;
    if (word.length < 4 || word.length > 20) return false;
    if (closeCache.has(word)) return closeCache.get(word);
    let close = false;
    for (let i = 0; i < word.length - 1 && !close; i++) {
      close = word[i] !== word[i + 1] && inDictionary(word.slice(0, i) + word[i + 1] + word[i] + word.slice(i + 2));
    }
    if (!close && word.length >= 6) {
      for (let i = 0; i <= word.length && !close; i++) {
        const left = word.slice(0, i);
        const right = word.slice(i);
        close = i < word.length && inDictionary(left + right.slice(1));
        for (let l = 0; l < 26 && !close; l++) {
          close = inDictionary(left + alphabet[l] + right) || (i < word.length && alphabet[l] !== right[0] &&
            inDictionary(left + alphabet[l] + right.slice(1)));
        }
      }
    }
    if (closeCache.size >= 2500) closeCache.clear();
    closeCache.set(word, close);
    return close;
  }

  // "en" or "other" for one sentence. Short or unclear text counts as English, so English checks stay on.
  function language(sentence) {
    // "might've" and "Anna's" are one word each: the Turkish list holds "ve". "l'homme" stays two words.
    const tokens = (sentence.match(/\p{L}+(?:['’]\p{L}+)*/gu) ?? []).flatMap(word =>
      /n['’]t$/i.test(word) ? [word] : word.replace(/['’](?:ve|s|ll|re|d|m)$/i, "").split(/['’]/));
    if (!tokens.length) return "en";
    // Scripts that English never uses.
    const letters = sentence.match(/\p{L}/gu) ?? [];
    const latin = letters.filter(letter => /\p{Script=Latin}/u.test(letter)).length;
    if (latin < letters.length / 2) return "other";
    if (!dictionary) dictionary = new Set([...nibWords.split(/\s+/), ...modernWords, ...commonAdded]);
    // foreign: words of another language. typos: unknown words one slip away from an English word.
    // strange: unknown words that are not close to English either. named: the same, written with a capital.
    // titled: listed foreign words written with a capital inside the sentence.
    let foreign = 0, english = 0, typos = 0, strange = 0, named = 0, titled = 0, searches = 0;
    tokens.forEach((raw, index) => {
      const token = raw.toLowerCase();
      // A capital inside the sentence, or all capitals, marks a name: Las Vegas, Zoë, MIT. It says nothing
      // about the language. The first word has a capital in every language, so it gets no such pass.
      const shout = raw.length > 1 && raw === raw.toUpperCase() && raw !== token;
      // A first word before another capital is part of a name too: Los Angeles, El Paso.
      const capital = word => Boolean(word) && word[0] !== word[0].toLowerCase();
      const name = shout || (capital(raw) && (index > 0 || (capital(tokens[1]) && /^[a-z]+$/.test(token))));
      if (englishWords.has(token) || chatWords.has(token) || /n['’]t$/.test(token)) {
        english++;
        return;
      }
      const known = /^[a-z]+$/.test(token) && inDictionary(token);
      // "du machst": the verb form of German "you". "Was" and "du" alone do not outweigh each other.
      const neighbour = (tokens[index - 1] ?? "").toLowerCase() === "du" || (tokens[index + 1] ?? "").toLowerCase() === "du";
      const listed = foreignWords.has(token) && !(token === "et" && /^al$/i.test(tokens[index + 1] ?? "")) ||
        (neighbour && !known && /^[a-zäöüß]{2,}st$/.test(token));
      if (listed) {
        if (!name) foreign++;
        else if (!shout) titled++;
        return;
      }
      if (known) return;
      if (/[^a-z]/.test(token)) {
        // A mark on a letter shows another language, unless English uses the word without the mark.
        const plain = token.normalize("NFD").replace(/\p{M}/gu, "");
        if (!name && !(token.length >= 4 && loanMarks.test(token) && inDictionary(plain))) foreign++;
        else if (!shout && !inDictionary(plain)) name ? named++ : strange++;
        return;
      }
      if (shout) return;
      // The search for a close English word costs up to a thousand lookups: only for some words of a sentence.
      if (name) named++;
      else if (searches++ < 12 && closeToEnglish(token)) typos++;
      else strange++;
    });
    // German writes every noun with a capital: "Guten Morgen". Such a word counts only next to other foreign
    // words, so "Las Vegas" and "Los Angeles" in an English sentence count for nothing.
    if (foreign >= 1 || titled === tokens.length) foreign += titled;
    if (foreign >= 2 && foreign > english) return "other";
    // One foreign word is enough only when the rest gives no sign of English: no English function word, and
    // unknown words that are not typos. "Come quickly!" and "Sim card missing." hold one word that another
    // language also has.
    if (foreign >= 1 && english === 0 && tokens.length <= 8 &&
        (foreign === tokens.length || strange + named >= (tokens.length <= 4 ? 1 : 2))) return "other";
    // A language that the lists above do not cover: most words are unknown and almost none are English.
    // English with many typos looks the same, except that its unknown words are close to English words.
    if (tokens.length >= 4 && english <= 1 && (typos + strange) / tokens.length >= 0.6 && strange > typos) return "other";
    return "en";
  }
  globalThis.nibLanguage = language;

  const priority = { Grammar: 4, Punctuation: 3, Spelling: 2, Style: 1 };
  function checkDraft(text, includeStyle, ignored, personal) {
    if (!text.trim()) return [];
    if (!dictionary) dictionary = new Set([...nibWords.split(/\s+/), ...modernWords, ...commonAdded]);
    const issues = [];
    const protectedSpans = [...text.matchAll(/```[\s\S]*?(?:```|$)|`[^`\n]+`|(?:https?:\/\/|www\.)[^\s<>()]+|\b[\w.+-]+@[\w.-]+\.[a-z]{2,}\b|\b(?:[a-z0-9-]+\.)+(?:com|net|org|io|dev|ai|ch|edu|gov)\b/gi)]
      .map(m => [m.index, m.index + m[0].length]);
    const unprotected = text.split("");
    for (const [start, end] of protectedSpans) {
      for (let i = start; i < end; i++) if (unprotected[i] !== "\n") unprotected[i] = "\u0000";
    }
    const searchable = unprotected.join("");
    function report(rule, kind, start, length, message, replacements) {
      if (searchable.slice(start, start + length).includes("\u0000")) return;
      const fragment = text.slice(start, start + length);
      // U+FFFC stands for a part of the page that the user cannot edit, such as a mention. No fix may cover it.
      if (fragment.includes("￼")) return;
      const key = rule + ":" + fragment.toLowerCase().replaceAll("’", "'");
      if (ignored.has(key)) return;
      issues.push({ id: rule + "-" + start, key, kind, start, end: start + length, fragment, message, replacements });
    }

    for (const [rule, kind, pattern, message, replace, guard, subrange] of rules) {
      if (kind === "Style" && !includeStyle) continue;
      for (const match of searchable.matchAll(pattern)) {
        if (guard && !guard(match, searchable)) continue;
        const [offset, length] = subrange ? subrange(match) : [0, match[0].length];
        const replacements = replace(match).map(value => matchCase(match[0], value));
        report(rule, kind, match.index + offset, length, message, replacements);
      }
    }

    for (const m of searchable.matchAll(/\b(a|an)(?=[ \t]+([A-Za-z]+)\b)/gi)) {
      const next = m[2];
      if (!/^[a-z]+$/.test(next) || !inDictionary(next)) continue;
      if (/^(?:herb|historic|historical|hotel|homage|haus|ouija)/.test(next)) continue;
      const vowelSound = /^(?:honest|hour|honor|honour|heir)/.test(next) ||
        (/^[aeiou]/.test(next) && !/^(?:use|usual|util|unit|univ|uni[cdflkoqst]|eu|ewe|one\b|once|ufo)/.test(next));
      const expected = vowelSound ? "an" : "a";
      if (expected !== m[1].toLowerCase()) {
        report("article", "Grammar", m.index, m[1].length,
          "Match the article to the sound at the start of the next word.", [matchCase(m[1], expected)]);
      }
    }

    // A word that touches U+FFFC is part of a longer word that Nib cannot see whole.
    for (const m of searchable.matchAll(/(?<![\p{L}\p{N}_￼])[A-Za-z]+(?:['’][A-Za-z]+)?(?![\p{L}\p{N}_￼])/gu)) {
      const word = m[0];
      const lower = word.toLowerCase().replaceAll("’", "'");
      if (personal.has(lower) || lower.length < 2 || lower.length > 32) continue;
      if (knownTypos.has(lower) && !/^[A-Z]{2,}$/.test(word)) {
        report("spell", "Spelling", m.index, word.length, "Possible misspelling.", [matchCase(word, knownTypos.get(lower))]);
        continue;
      }
      if (word !== lower || lower.includes("'") || inDictionary(lower)) continue;
      // A space typed one key early or late: "thi sis" is "this is".
      const next = /^ ([a-z]+)(?![\p{L}\p{N}_'’])/u.exec(searchable.slice(m.index + word.length));
      const usable = part => part.length > 1 ? common.has(part) || (part.length > 3 && inDictionary(part)) : part === "a";
      const shifted = next && [[lower + next[1][0], next[1].slice(1)], [lower.slice(0, -1), lower.slice(-1) + next[1]]]
        .find(([first, second]) => first && second && usable(first) && usable(second));
      if (shifted) {
        report("space", "Spelling", m.index, word.length + 1 + next[1].length, "The space looks misplaced.", [shifted.join(" ")]);
        continue;
      }
      report("spell", "Spelling", m.index, word.length, "This word isn’t in the spelling dictionary.", spellingGuesses(lower));
    }

    const occupied = new Uint8Array(text.length);
    const accepted = [];
    issues.sort((a, b) => priority[b.kind] - priority[a.kind] || a.start - b.start || b.end - a.end);
    for (const issue of issues) {
      if (occupied.subarray(issue.start, issue.end).includes(1)) continue;
      occupied.fill(1, issue.start, issue.end);
      accepted.push(issue);
    }
    const sentences = globalThis.nibSentences ? nibSentences(text) : [{ start: 0, end: text.length, text }];
    const foreign = sentences.filter(sentence => language(sentence.text) === "other");
    return accepted
      .filter(issue => !foreign.some(sentence => issue.start < sentence.end && issue.end > sentence.start))
      .sort((a, b) => a.start - b.start);
  }
  return checkDraft;
})();
