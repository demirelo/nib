"use strict";

(() => {
  // After an update the new copy of Nib runs next to the old one. The old copy removes itself first.
  globalThis.nibStop?.();
  const life = new AbortController();
  // Every page listener ends with this copy of Nib.
  // Capture listeners see events that the page stops on the way up, as many editors do.
  const listen = (target, type, handler, capture = false) =>
    target?.addEventListener(type, handler, { capture, signal: life.signal });
  globalThis.nibStop = () => {
    life.abort();
    // Timers and observers of the old copy must not draw again after it stopped.
    clearTimeout(timer);
    clearTimeout(modelTimer);
    clearTimeout(scrollTimer);
    resizeObserver?.disconnect();
    editorObserver?.disconnect();
    hostObserver?.disconnect();
    secretObserver?.disconnect();
    // A check of a Google Docs document that still runs ends here: its next step sees the new number.
    docsSerial++;
    document.querySelectorAll("[data-nib-root], [data-nib-hint], [data-nib-docs]").forEach(node => node.remove());
  };
  const maxLength = 30000;
  // A few lines per page for the troubleshooting log on the Mac: page structure only, never text.
  // The log names the sites the user visits. It stays empty until the user turns it on, and in private windows.
  let reports = 0;
  let lastCount = -1;
  const report = line => {
    if (settings?.log !== true || chrome.extension?.inIncognitoContext || reports++ >= 25) return;
    try { chrome.runtime.sendMessage({ type: "nib:log", line }).catch(() => {}); } catch { /* old copy */ }
  };
  // A class name or a role can hold anything, also a user name or an address. Only plain names pass.
  const describe = node => {
    if (!(node instanceof Element)) return "node";
    const classes = [...node.classList].filter(name => /^[A-Za-z0-9_-]{1,32}$/.test(name)).slice(0, 2).join(".");
    const role = node.getAttribute("role") || "";
    const root = node.getRootNode();
    const shadow = root instanceof ShadowRoot ? " in-" + root.mode + "-shadow" : "";
    return node.tagName.toLowerCase().replace(/[^a-z0-9-]/g, "").slice(0, 32) + (classes ? "." + classes : "") +
      (/^[a-z]{1,20}$/.test(role) ? "[role=" + role + "]" : "") + (node.isContentEditable ? "[editable]" : "") + shadow;
  };
  const issueColors = { Spelling: "#db5264", Grammar: "#d4852b", Punctuation: "#7779d2", Style: "#3b9e7c" };
  const privateAutocomplete = /(?:^|\s)(?:username|(?:current|new)-password|one-time-code|cc-[\w-]+|transaction-[\w-]+|webauthn)(?:\s|$)/i;
  // Labels are compared as plain words: "mot de passe", "client secret". The word for password in a few languages.
  const privateLabel = /password|passcode|passphrase|passwort|kennwort|mot de passe|contraseña|senha|wachtwoord|şifre|parola|mnemonic|(?:^|\s)(?:pin|otp|cvv|cvv2|cvc|ssn|iban|seed|secret|token)(?:\s|$)|(?:credit|debit|card)\s+(?:card|number|expiry|expiration|security)|(?:verification|security|authenticator|two factor|recovery|backup|pin)\s+code|(?:api|private|secret|access)\s+(?:key|token)|(?:account|routing|social security)\s+number|(?:seed|recovery)\s+phrase|security\s+answer/i;
  // A name beside a password that marks a login field.
  const credentialName = /user|login|e-?mail|pass|pwd|secret|token|otp|code|pin/i;
  // Ace and xterm.js type into a hidden textarea: code and shell commands, not prose.
  const editorExclusion = '[data-nib="off"], [data-nib-root], pre, code, .monaco-editor, .CodeMirror, .cm-editor, .ace_editor, textarea.ace_text-input, .xterm, .xterm-helper-textarea';
  // Parts that sit inside a line of text. One that the user cannot edit, such as a mention, counts as one word.
  const inlineTags = new Set(["A", "ABBR", "B", "BDI", "CITE", "EM", "I", "IMG", "MARK", "S", "SMALL", "SPAN", "STRONG", "SUB", "SUP", "TIME", "U"]);
  const placeholder = "￼";
  const blockTags = new Set(["ADDRESS", "ARTICLE", "ASIDE", "BLOCKQUOTE", "DIV", "DL", "DT", "DD", "H1", "H2", "H3", "H4", "H5", "H6", "LI", "MAIN", "OL", "P", "SECTION", "TABLE", "TD", "TH", "TR", "UL"]);
  const ignored = new Set();
  let personal = new Set();
  let settings = null;
  let active = null;
  let snapshot = null;
  let issues = [];
  let timer = 0;
  let frame = 0;
  let composing = false;
  let open = false;
  let selectedId = null;
  let primary = null;
  let contextual = null;
  // "on" after the Mac model answered, "off" when it could not be reached.
  let modelState = "";
  let modelTimer = 0;
  let modelSerial = 0;
  let modelBlockUntil = 0;
  const modelCache = new Map();
  let notice = "";
  let resizeObserver = null;
  let editorObserver = null;
  let hostObserver = null;
  let secretObserver = null;
  let scrollTimer = 0;
  // How often Nib put its overlay back for this field, after the page removed or restyled it.
  let remounts = 0;
  // The word list and the checker come from the worker when the user enters a text field.
  let engine = false;
  let engineAsked = 0;
  // Every field that was a password field at any time. "Show password" makes it a text field: still secret.
  const secrets = new WeakSet();
  // Fields in which the user pressed a key, typed or pasted. Only these send sentences to the model.
  const touched = new WeakSet();
  let host, layer, badge, panel, mirror, chip, chipLabel, chipCheck;
  const hostCss = "all:initial!important;position:fixed!important;inset:0!important;width:auto!important;height:auto!important;margin:0!important;padding:0!important;border:0!important;background:transparent!important;overflow:visible!important;pointer-events:none!important;z-index:2147483647!important;";
  const topOrigin = location.ancestorOrigins?.[location.ancestorOrigins.length - 1] || location.origin;
  // Google Docs, Sheets and Slides take the key presses in a hidden frame with an editable element in it.
  // That is no text field: it holds scraps of what the user typed. Nib must not check it or send it to
  // the model, and its frame must not answer the popup in place of the top page.
  const keyTarget = (() => {
    if (window === window.top || topOrigin !== "https://docs.google.com") return false;
    // The frame element is readable only from the same site. Any other frame is not this one.
    try { return window.frameElement?.classList.contains("docs-texteventtarget-iframe") === true; } catch { return false; }
  })();
  // A check of a Google Docs document. The number changes when a run starts or stops.
  let docsSerial = 0;

  function canCheck() {
    return settings && settings.enabled !== false && settings["paused:" + location.origin] !== true &&
      settings["paused:" + topOrigin] !== true;
  }

  function loadEngine() {
    // One request at a time. After a failure, the next focus or change may ask again.
    if (engine || Date.now() < engineAsked + 5000) return;
    engineAsked = Date.now();
    try {
      chrome.runtime.sendMessage({ type: "nib:engine" }).then(answer => {
        if (life.signal.aborted) return;
        engine = answer?.ok === true && typeof globalThis.nibCheck === "function" &&
          typeof globalThis.nibSentences === "function" && typeof globalThis.nibSentence === "function";
        if (engine && active) update();
        else if (!engine) engineAsked = Date.now() - 4000;
      }).catch(() => {});
    } catch { /* old copy */ }
  }

  function notePasswords(root) {
    try {
      for (const field of root.querySelectorAll('input[type="password" i]')) secrets.add(field);
    } catch { /* not a tree */ }
  }

  function isPrivate(node) {
    if (secrets.has(node)) return true;
    const autocomplete = node.getAttribute("autocomplete") || "";
    if (privateAutocomplete.test(autocomplete)) return true;
    const identity = (node.id + " " + (node.getAttribute("name") || "")).toLowerCase();
    if (/\b(?:ccnumber|cardnumber|cc-number|ccv|cvv2?|ccnum|cardexpiry|ccmonth|ccyear|securitycode|otpcod[e]?|verificationcode)\b/.test(identity)) return true;
    if (node instanceof HTMLInputElement) {
      const words = identity.replace(/[^a-z0-9]+/g, " ");
      // A short field named "code" takes a one-time code. A long one may take a discount code or prose.
      if (/(?:^| )code(?: |$)|code *$/.test(words) && ((node.maxLength > 0 && node.maxLength <= 10) ||
          (node.getAttribute("inputmode") || "").toLowerCase() === "numeric")) return true;
      // Beside a password, a field with a login name is part of the login.
      const form = node.form;
      if (form) {
        notePasswords(form);
        if (credentialName.test(identity + " " + autocomplete) &&
            Array.from(form.elements).some(field => field !== node && secrets.has(field))) return true;
      }
    }
    const masked = getComputedStyle(node).getPropertyValue("-webkit-text-security");
    if (masked && masked !== "none") return true;
    const labelledBy = (node.getAttribute("aria-labelledby") || "").split(/\s+/).filter(Boolean)
      .map(id => node.getRootNode().getElementById?.(id)?.textContent.slice(0, 160));
    const labels = [
      node.id, node.getAttribute("name"), node.getAttribute("placeholder"),
      node.getAttribute("aria-label"), node.getAttribute("data-placeholder"), ...labelledBy,
      ...Array.from(node.labels || [], label => label.textContent.slice(0, 160))
    ];
    return labels.some(label => label && privateLabel.test(label.replace(/([a-z])([A-Z])/g, "$1 $2").replace(/[^\p{L}\p{N}]+/gu, " ")));
  }

  function editable(node) {
    if (keyTarget || !(node instanceof HTMLElement) || node.closest(editorExclusion)) return null;
    if (node.closest('[inert], [aria-disabled="true"], [aria-readonly="true"]')) return null;
    if (node instanceof HTMLInputElement || node instanceof HTMLTextAreaElement) {
      if (node instanceof HTMLInputElement && node.type === "password") secrets.add(node);
      if (node instanceof HTMLInputElement && !["text", "search"].includes(node.type)) return null;
      if (node.disabled || node.readOnly || isPrivate(node)) return null;
      return node;
    }
    if (!node.isContentEditable) return null;
    while (node.parentElement?.isContentEditable) node = node.parentElement;
    return node.closest(editorExclusion) || isPrivate(node) ? null : node;
  }

  function isControl(element) {
    return element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement;
  }

  // A closed shadow root hides its content from the page. An extension may still look inside.
  function inside(node) {
    if (!(node instanceof Element)) return null;
    try { return node.shadowRoot ?? chrome.dom?.openOrClosedShadowRoot?.(node) ?? null; } catch { return null; }
  }

  function focusedNode() {
    let element = document.activeElement;
    // Stop at Nib's own overlay: focus in its list is still focus in Nib, not a new field.
    while (element !== host && inside(element)?.activeElement) element = inside(element).activeElement;
    return element;
  }

  // The element an event started at. For a closed shadow root the event names only the outer element:
  // the real one is under the pointer for a pointer event, and holds the focus for every other event.
  function eventTarget(event) {
    let node = event.composedPath()[0];
    const pointer = event instanceof MouseEvent;
    for (let depth = 0; depth < 20 && node instanceof Element && node !== host && !isControl(node); depth++) {
      const root = inside(node);
      const inner = pointer ? root?.elementFromPoint(event.clientX, event.clientY) : root?.activeElement;
      if (!inner || inner === node || !root.contains(inner)) break;
      node = inner;
    }
    return node;
  }

  function readEditor(element) {
    if (isControl(element)) return { text: element.value, segments: null };
    let text = "";
    const segments = [];
    function boundary() {
      if (text && !text.endsWith("\n")) text += "\n";
    }
    function walk(node) {
      if (text.length > maxLength) return;
      if (node.nodeType === Node.TEXT_NODE) {
        if (!node.data) return;
        segments.push({ start: text.length, end: text.length + node.length, node });
        text += node.data;
        return;
      }
      if (!(node instanceof HTMLElement)) return;
      if (node !== element && (node.matches('[contenteditable="false"], [hidden], script, style, [aria-hidden="true"]'))) {
        // A mention or an inline image stands in the sentence like a word. A line break here would cut
        // "Hi @Anna can you send it" into two sentences. The placeholder has no segment: no fix can touch it.
        const display = node.matches("script, style") ? "block" : getComputedStyle(node).display;
        // A hidden part has no layout: its tag tells whether it belongs to the line.
        if (/^inline/.test(display) || ((display === "none" || display === "contents") && inlineTags.has(node.tagName))) text += placeholder;
        else boundary();
        return;
      }
      if (node.tagName === "BR") {
        text += "\n";
        return;
      }
      const block = node !== element && blockTags.has(node.tagName);
      if (block) boundary();
      for (const child of node.childNodes) walk(child);
      if (block) boundary();
    }
    walk(element);
    return { text, segments };
  }

  function makeElement(tag, className, text) {
    const element = document.createElement(tag);
    if (className) element.className = className;
    if (text) element.textContent = text;
    return element;
  }

  function makeButton(text, className, onClick) {
    const button = makeElement("button", className, text);
    button.type = "button";
    // A pointer click leaves the editor's selection intact. Buttons remain keyboard-focusable.
    button.addEventListener("mousedown", event => event.preventDefault());
    button.addEventListener("click", onClick);
    return button;
  }

  function mount() {
    if (life.signal.aborted) return;
    if (host?.isConnected) return;
    // The page removed the overlay. Put it back a few times for one field, then leave the page alone.
    if (host && remounts++ >= 3) return;
    host = document.createElement("div");
    host.setAttribute("data-nib-root", "");
    host.style.cssText = hostCss;
    const root = host.attachShadow({ mode: "closed" });
    const css = makeElement("style");
    css.textContent = `
      :host{color-scheme:light}*{box-sizing:border-box}[hidden]{display:none!important}
      .layer{position:fixed;inset:0;pointer-events:none}.line{position:fixed;height:2px;border-radius:2px}
      .badge,.chip,.panel{position:fixed;pointer-events:auto;font:13px/1.42 system-ui,-apple-system,sans-serif;color:#1a3026}
      .badge{min-width:24px;height:24px;padding:0 6px;background:#215945;color:#fff;border:1px solid #fff;border-radius:99px;font-size:11px;font-weight:750;box-shadow:0 1px 4px #142e254d;cursor:pointer}
      .badge:hover,.chip:hover{background:#163e30}
      .badge.clean{min-width:20px;height:20px;padding:0 4px;font-size:10px;opacity:.55;box-shadow:none}.badge.clean:hover{opacity:1}
      .chip{display:flex;align-items:center;gap:6px;max-width:min(380px,calc(100vw - 12px));min-height:30px;padding:4px 9px;border:1px solid #e5f0e9;background:#215945;color:#fff;border-radius:8px;font-size:12px;font-weight:700;box-shadow:0 2px 8px #142e2540;cursor:pointer}
      .chip-label{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
      .chip-check{font-size:14px;flex:none}
      .panel{width:min(320px,calc(100vw - 12px));max-height:min(425px,calc(100vh - 12px));overflow:auto;overscroll-behavior:contain;background:#fbfdfb;border:1px solid #ccdcd1;border-radius:12px;box-shadow:0 6px 28px #152e2840;padding:9px}
      .head{display:flex;align-items:center;justify-content:space-between;gap:6px;padding:1px 3px 5px}.head strong{font-size:15px}.notice{margin:2px 3px 6px;color:#4d6458;font-size:12px}
      .card{padding:8px;margin:5px 0;background:#fff;border:1px solid #deebe1;border-radius:8px;overflow-wrap:anywhere}
      .kind{font-size:11px;font-weight:750;color:#466558}.message{margin:4px 0;color:#263e32}.fragment{margin:2px 0 7px;color:#586b62}
      .buttons{display:flex;flex-wrap:wrap;gap:4px 7px}.fix,.minor{font:inherit;cursor:pointer}
      .fix{border:1px solid #d3e7d9;background:#e8f3ec;color:#215945;border-radius:6px;padding:3px 7px;max-width:100%;overflow-wrap:anywhere;font-weight:700}
      .minor{background:transparent;color:#406152;border:0;padding:4px 3px;font-size:11px;font-weight:650}.minor:hover{text-decoration:underline}
      .fix:hover{background:#d3eadc}.hint{padding:6px;color:#586b62}button:focus-visible{outline:2px solid #268763;outline-offset:2px}
      .mirror{position:fixed;visibility:hidden;pointer-events:none;overflow:hidden;border:0;margin:0}
    `;
    layer = makeElement("div", "layer");
    layer.setAttribute("aria-hidden", "true");
    mirror = makeElement("div", "mirror");
    mirror.setAttribute("aria-hidden", "true");
    badge = makeButton("", "badge", () => {
      open = !open;
      notice = "";
      renderPanel();
      position();
      if (open) panel.querySelector("button")?.focus({ preventScroll: true });
      else active?.focus({ preventScroll: true });
    });
    badge.setAttribute("aria-expanded", "false");
    chip = makeButton("", "chip", () => {
      if (primary) apply(primary, primary.replacements[0]);
    });
    chipLabel = makeElement("span", "chip-label");
    chipCheck = makeElement("span", "chip-check", "✓");
    chipCheck.setAttribute("aria-hidden", "true");
    chip.append(chipCheck, chipLabel);
    panel = makeElement("section", "panel");
    panel.setAttribute("aria-label", "Nib suggestions");
    panel.hidden = badge.hidden = chip.hidden = true;
    root.append(css, layer, mirror, chip, badge, panel);
    document.documentElement.append(host);
    raise();
  }

  // A page script may remove Nib's overlay or change its style, for example when it rebuilds the page.
  function guardHost() {
    hostObserver ??= new MutationObserver(records => {
      if (life.signal.aborted || !host || !active || !snapshot) return;
      if (!host.isConnected) {
        mount();
        if (!host.isConnected) return;
        renderPanel();
        position();
      } else if (records.some(record => record.type === "attributes")) {
        // Nib's own style changes never come here: the disconnect below drops them. This one is the page's.
        if (remounts++ >= 3) return;
        host.hidden = false;
        host.style.cssText = hostCss;
        raise();
      }
      guardHost();
    });
    // This also drops the records of changes that Nib made itself just now.
    hostObserver.disconnect();
    if (!host?.isConnected) return;
    // The overlay is a child of the page root, or of a modal dialog. Its removal shows on the parent.
    hostObserver.observe(host.parentNode, { childList: true });
    hostObserver.observe(host, { attributes: true, attributeFilter: ["style", "hidden"] });
  }

  // A modal dialog, such as the LinkedIn draft box, sits in the browser's top layer, above every z-index,
  // and makes the rest of the page inert. Nib's overlay is a popover, which joins the top layer above it.
  // Inside a modal dialog it must also be a child of that dialog, or it is inert and cannot be clicked.
  // As a popover it is not clipped by the dialog's hidden overflow, so the list of suggestions fits.
  function raise() {
    if (!host?.isConnected) return;
    try {
      // An old browser does not know ":modal" and throws here.
      const modal = active?.closest?.("dialog:modal") ?? null;
      const home = modal ?? document.documentElement;
      if (host.parentNode !== home) {
        if (host.matches(":popover-open")) host.hidePopover();
        home.append(host);
      }
      if (typeof host.showPopover === "function") {
        if (!host.hasAttribute("popover")) host.setAttribute("popover", "manual");
        if (host.matches(":popover-open")) host.hidePopover();
        host.showPopover();
      }
    } catch { /* an old browser: the z-index still works outside dialogs */ }
    // A dialog with a transform makes fixed children move with it. Shift the overlay back to the window.
    host.style.setProperty("translate", "0px 0px", "important");
    const box = host.getBoundingClientRect();
    if (Math.abs(box.left) > 0.5 || Math.abs(box.top) > 0.5) {
      host.style.setProperty("translate", -box.left + "px " + -box.top + "px", "important");
      host.style.setProperty("width", innerWidth + "px", "important");
      host.style.setProperty("height", innerHeight + "px", "important");
    }
    guardHost();
  }

  function fragmentLabel(issue) {
    return issue.fragment.trim() || (issue.fragment.length === 1 ? "space" : issue.fragment.length + " spaces");
  }

  function renderPanel() {
    if (!panel) return;
    // With no suggestion the badge stays as a small check mark, so the user sees that Nib read the text.
    badge.textContent = issues.length ? String(issues.length) : "✓";
    badge.classList.toggle("clean", !issues.length);
    badge.title = issues.length ? "" : "Nib checked this text";
    badge.setAttribute("aria-label", issues.length ? "Nib, " + issues.length + (issues.length === 1 ? " suggestion" : " suggestions") :
      "Nib checked this text. No suggestions.");
    badge.setAttribute("aria-expanded", String(open));
    panel.hidden = !open;
    if (primary) {
      const label = primary.preview || primary.replacements[0];
      chipLabel.textContent = label.trim() || (label ? "Use one space" : "Remove “" + fragmentLabel(primary) + "”");
      // A star marks a style suggestion, a check mark marks a correction.
      const style = primary.kind === "Style";
      chipCheck.textContent = style ? "✦" : "✓";
      chip.title = (style ? "Suggestion, no error. Apply: " : "Apply: ") + label;
      chip.setAttribute("aria-label", (style ? "Apply suggestion: " : "Apply correction: ") + chipLabel.textContent);
    }
    if (!open) return;
    const heading = makeElement("div", "head");
    heading.append(makeElement("strong", "", "Nib"), makeButton("Close", "minor", closePanel));
    const count = issues.length ? issues.length + (issues.length === 1 ? " suggestion" : " suggestions") : "No suggestions";
    const model = settings.context === false ? "" : modelState === "on" ? " · Mac model connected" :
      modelState === "off" ? " · Mac model not connected: in Nib, choose More → Connect Browsers…" : "";
    const feedback = makeElement("p", "notice", notice || count + " · checked locally" + model);
    feedback.setAttribute("role", "status");
    const nodes = [heading, feedback];
    const chosen = issues.find(issue => issue.id === selectedId);
    const listed = chosen ? [chosen, ...issues.filter(issue => issue !== chosen)] : issues;
    for (const issue of listed.slice(0, 30)) {
      const card = makeElement("article", "card");
      const buttons = makeElement("div", "buttons");
      if (replacementRange(snapshot, issue)) {
        for (const replacement of issue.replacements) {
          const label = replacement === "" ? "Remove" : !issue.fragment.trim() ? "Use one space" : replacement;
          const button = makeButton(label, "fix", () => apply(issue, replacement));
          button.setAttribute("aria-label", "Apply " + label.trim() + " to " + fragmentLabel(issue));
          buttons.append(button);
        }
      } else if (issue.replacements.length) {
        card.append(makeElement("p", "hint", "This suggestion crosses formatting. Edit it in the field."));
      }
      buttons.append(makeButton("Ignore", "minor", () => {
        ignored.add(issue.key);
        update("Ignored matching text in this tab");
        focusPanel();
      }));
      if (issue.kind === "Spelling") buttons.append(makeButton("Add to dictionary", "minor", async () => {
        const word = issue.fragment.toLowerCase();
        personal.add(word);
        let message = "Added to your dictionary";
        try {
          await chrome.storage.local.set({ ["word:" + word]: true });
        } catch {
          message = "Added for this tab";
        }
        update(message);
        focusPanel();
      }));
      card.prepend(makeElement("div", "kind", issue.kind), makeElement("p", "message", issue.message),
        makeElement("p", "fragment", "“" + fragmentLabel(issue) + "”"));
      card.append(buttons);
      nodes.push(card);
    }
    if (issues.length > 30) nodes.push(makeElement("p", "hint", "Showing the first 30 suggestions. The list updates as you review them."));
    panel.replaceChildren(...nodes);
  }

  function focusPanel() {
    if (open && !panel?.hidden) panel.querySelector("button")?.focus({ preventScroll: true });
  }

  function closePanel() {
    open = false;
    selectedId = null;
    active?.focus({ preventScroll: true });
    renderPanel();
    position();
  }

  function singleSegment(data, issue) {
    return data.segments.find(segment => segment.start <= issue.start && segment.end >= issue.end);
  }

  function replacementRange(data, issue) {
    return !data.segments || singleSegment(data, issue);
  }

  function caretFor(data) {
    if (isControl(active)) return active.selectionStart === active.selectionEnd ? active.selectionStart : null;
    const selection = active.getRootNode().getSelection?.() || window.getSelection();
    if (!selection?.isCollapsed) return null;
    const segment = data.segments.find(item => item.node === selection.anchorNode);
    if (segment) return segment.start + selection.anchorOffset;
    if (selection.anchorNode === active) {
      if (selection.anchorOffset === active.childNodes.length) return data.text.length;
      if (selection.anchorOffset === 0) return 0;
    }
    return null;
  }

  function selectPrimary(data, sentence) {
    const rank = { Grammar: 0, Spelling: 1, Punctuation: 2, Style: 3 };
    return issues.filter(issue => issue.replacements.length && replacementRange(data, issue) &&
      (issue === contextual || (!sentence || (issue.start >= sentence.start && issue.end <= sentence.end))) &&
      !issue.message.includes("isn’t in the spelling dictionary"))
      .sort((a, b) => a === contextual ? -1 : b === contextual ? 1 : rank[a.kind] - rank[b.kind])[0] || null;
  }

  function contextualIssue(data, sentence, replacement, style = false) {
    if (!replacement || replacement === sentence.text || replacement.length > 640 || /[\r\n]/.test(replacement)) return null;
    const outputWords = new Set(replacement.toLowerCase().match(/[a-z]+/g));
    if (sentence.text.toLowerCase().match(/[a-z]+/g)?.some(word => personal.has(word) && !outputWords.has(word))) return null;
    let prefix = 0;
    let suffix = 0;
    while (prefix < Math.min(sentence.text.length, replacement.length) && sentence.text[prefix] === replacement[prefix]) prefix++;
    while (suffix < Math.min(sentence.text.length, replacement.length) - prefix &&
      sentence.text[sentence.text.length - suffix - 1] === replacement[replacement.length - suffix - 1]) suffix++;
    // Mark whole words: "actually a" and not "ctually a".
    const letter = /[\p{L}\p{N}'’]/u;
    while (prefix > 0 && letter.test(sentence.text[prefix - 1]) &&
      (letter.test(sentence.text[prefix] || "") || letter.test(replacement[prefix] || ""))) prefix--;
    while (suffix > 0 && letter.test(sentence.text[sentence.text.length - suffix]) &&
      (letter.test(sentence.text[sentence.text.length - suffix - 1] || "") || letter.test(replacement[replacement.length - suffix - 1] || ""))) suffix--;
    // Keep a nonempty source span for insertions, and avoid splitting surrogate pairs.
    if (prefix === sentence.text.length - suffix) {
      if (prefix > 0) prefix--;
      else suffix--;
    }
    if (/^[\uDC00-\uDFFF]$/.test(sentence.text[prefix] || "")) prefix--;
    if (suffix > 0 && /^[\uDC00-\uDFFF]$/.test(sentence.text[sentence.text.length - suffix])) suffix--;
    const start = sentence.start + prefix;
    const end = sentence.end - suffix;
    const fragment = data.text.slice(start, end);
    const edit = replacement.slice(prefix, replacement.length - suffix);
    const key = (style ? "style:" : "model:") + sentence.text;
    if (ignored.has(key) || !fragment || edit === fragment) return null;
    const issue = { id: (style ? "style-" : "model-") + start, key, kind: style ? "Style" : "Grammar", start, end, fragment,
      message: style ? "Suggestion from the on-device model. This sentence has no error." :
        "Sentence correction from the on-device model.", replacements: [edit], preview: replacement };
    return replacementRange(data, issue) ? issue : null;
  }

  function modelEligible(sentence) {
    // A sentence with a mention would reach the model with a hole in it, and its answer could not be applied.
    return /[\p{L}]+.*\s+.*[\p{L}]+/u.test(sentence.text) && !/https?:\/\/|@|```/.test(sentence.text) &&
      !sentence.text.includes(placeholder);
  }

  function updatePrimary() {
    const offset = caretFor(snapshot);
    const sentence = offset === null ? null : nibSentence(snapshot.text, offset);
    const useModel = settings.context !== false;
    contextual = null;
    let next = null;
    let nextStyle = null;
    if (useModel) {
      // Sentences nearest the caret come first. Answers already known are shown at once.
      const anchor = offset ?? 0;
      const gap = item => anchor >= item.start && anchor <= item.end ? 0 :
        Math.min(Math.abs(anchor - item.start), Math.abs(anchor - item.end));
      const ordered = nibSentences(snapshot.text);
      // The sentence before each one gives the model its context.
      ordered.forEach((item, index) => {
        const previous = ordered[index - 1];
        item.before = previous && previous.end + 3 >= item.start ? previous.text : "";
        item.key = item.text + "\u0001" + item.before;
      });
      const nearby = ordered.slice().sort((a, b) => gap(a) - gap(b)).slice(0, 12);
      for (const item of nearby) {
        const response = modelCache.get(item.key);
        if (!response) {
          if (!next && offset !== null && modelEligible(item)) next = item;
          continue;
        }
        let issue = response.replacement ? contextualIssue(snapshot, item, response.replacement) : null;
        // A finished sentence without an error can get a style suggestion.
        if (!issue && !response.replacement && response.status === "no-change" && settings.style !== false &&
            /[.!?…]$/.test(item.text) && !issues.some(other => other.start < item.end && other.end > item.start)) {
          const better = modelCache.get(item.key + "\u0002");
          if (better?.replacement) issue = contextualIssue(snapshot, item, better.replacement, true);
          else if (!better && !nextStyle && offset !== null && modelEligible(item)) nextStyle = item;
        }
        if (!issue) continue;
        if (sentence && item.start === sentence.start) contextual = issue;
        issues = [...issues.filter(other => other.end <= issue.start || other.start >= issue.end), issue]
          .sort((a, b) => a.start - b.start);
      }
    }
    primary = offset === null || !sentence ? null : selectPrimary(snapshot, sentence);
    // Text leaves the page only after the user worked in the field. A page can set the focus by script,
    // and a reply box can hold a quoted mail that the user did not write.
    if (!touched.has(active)) return;
    if (next && Date.now() >= modelBlockUntil) {
      requestModel(next, sentence && next.start === sentence.start ? 650 : 200);
    } else if (nextStyle && Date.now() >= modelBlockUntil) {
      requestModel(nextStyle, 400, true);
    }
  }

  function requestModel(sentence, delay, improve = false) {
    const serial = ++modelSerial;
    const element = active;
    clearTimeout(modelTimer);
    modelTimer = setTimeout(async () => {
      if (serial !== modelSerial || !canCheck() || !element?.isConnected || editable(element) !== element ||
          !snapshot || snapshot.text.slice(sentence.start, sentence.end) !== sentence.text) return;
      try {
        const response = await chrome.runtime.sendMessage({ type: "nib:sentence", text: sentence.text, before: sentence.before,
          ...(improve ? { improve: true } : {}) });
        if (!response || response.status === "disconnected" || response.status === "unavailable") {
          modelBlockUntil = Date.now() + 15000;
          modelState = "off";
          return;
        }
        const answered = ["model", "no-change", "improve"].includes(response.status);
        if (!answered && response.status !== "invalid" && response.status !== "skipped") {
          // A timeout, or a status this version does not know: no answer yet. Ask again later.
          modelBlockUntil = Date.now() + 15000;
          return;
        }
        // Only a real answer shows that the model works.
        if (answered) modelState = "on";
        if (modelCache.size >= 300) modelCache.delete(modelCache.keys().next().value);
        // "invalid" and "skipped" are final for this sentence: kept without a replacement, so it is not asked again.
        modelCache.set(sentence.key + (improve ? "\u0002" : ""), answered ? response : { status: response.status });
        // The next update shows this answer and asks about the next sentence.
        if (serial === modelSerial && active === element && !open) update();
      } catch {
        modelBlockUntil = Date.now() + 15000;
      }
    }, delay);
  }

  function clearModelRequest() {
    clearTimeout(modelTimer);
    modelSerial++;
    primary = contextual = null;
  }

  function intersect(a, b) {
    return {
      left: Math.max(a.left, b.left), right: Math.min(a.right, b.right),
      top: Math.max(a.top, b.top), bottom: Math.min(a.bottom, b.bottom)
    };
  }

  function clipFor(element, rect) {
    let clip = intersect(rect, { left: 0, top: 0, right: innerWidth, bottom: innerHeight });
    for (let node = element; node;) {
      node = node.parentElement || node.getRootNode().host;
      if (!node || node === document.documentElement) break;
      const style = getComputedStyle(node);
      const clipX = /auto|scroll|hidden|clip/.test(style.overflowX);
      const clipY = /auto|scroll|hidden|clip/.test(style.overflowY);
      if (!clipX && !clipY) continue;
      const bound = node.getBoundingClientRect();
      clip = intersect(clip, {
        left: clipX ? bound.left + node.clientLeft : -Infinity,
        right: clipX ? bound.left + node.clientLeft + node.clientWidth : Infinity,
        top: clipY ? bound.top + node.clientTop : -Infinity,
        bottom: clipY ? bound.top + node.clientTop + node.clientHeight : Infinity
      });
    }
    return clip;
  }

  function prepareMirror(element, box, text) {
    const style = getComputedStyle(element);
    const single = element instanceof HTMLInputElement;
    for (const property of [
      "font-family", "font-size", "font-style", "font-weight", "font-stretch", "font-kerning",
      "font-variant", "font-feature-settings", "font-optical-sizing", "line-height", "text-align",
      "text-indent", "text-transform", "letter-spacing", "word-spacing", "padding",
      "direction", "tab-size", "word-break"
    ]) mirror.style.setProperty(property, style.getPropertyValue(property));
    Object.assign(mirror.style, {
      left: box.left + element.clientLeft + "px", top: box.top + element.clientTop + "px",
      width: element.clientWidth + "px", height: element.clientHeight + "px",
      whiteSpace: single || element.wrap === "off" ? "pre" : "pre-wrap",
      overflowWrap: single || element.wrap === "off" ? "normal" : "break-word"
    });
    const textNode = document.createTextNode(text + "\u200b");
    if (single) {
      const inner = makeElement("div");
      inner.style.position = "relative";
      inner.append(textNode);
      mirror.replaceChildren(inner);
      const usable = element.clientHeight - parseFloat(style.paddingTop) - parseFloat(style.paddingBottom);
      inner.style.top = Math.max(0, (usable - inner.getBoundingClientRect().height) / 2) + "px";
    } else {
      mirror.replaceChildren(textNode);
    }
    mirror.scrollLeft = element.scrollLeft;
    mirror.scrollTop = element.scrollTop;
    return textNode;
  }

  function rangeFor(data, issue, mirrorText) {
    const range = document.createRange();
    if (mirrorText) {
      range.setStart(mirrorText, issue.start);
      range.setEnd(mirrorText, issue.end);
      return range;
    }
    const start = data.segments.find(segment => segment.start <= issue.start && segment.end > issue.start);
    const end = data.segments.find(segment => segment.start < issue.end && segment.end >= issue.end);
    if (!start?.node.isConnected || !end?.node.isConnected ||
        issue.start - start.start > start.node.length || issue.end - end.start > end.node.length) return null;
    range.setStart(start.node, issue.start - start.start);
    range.setEnd(end.node, issue.end - end.start);
    return range;
  }

  function drawLines(box, clip) {
    if (!issues.length) {
      layer.replaceChildren();
      mirror.replaceChildren();
      return;
    }
    const mirrored = isControl(active) ? prepareMirror(active, box, snapshot.text) : null;
    const lines = document.createDocumentFragment();
    let count = 0;
    for (const issue of issues) {
      const range = rangeFor(snapshot, issue, mirrored);
      if (!range) continue;
      for (const rect of range.getClientRects()) {
        const visible = intersect(rect, clip);
        const y = Math.min(rect.bottom - 1, clip.bottom - 2);
        if (visible.right - visible.left < 2 || visible.bottom <= visible.top || y < clip.top) continue;
        const line = makeElement("div", "line");
        Object.assign(line.style, {
          left: visible.left + "px", top: y + "px", width: visible.right - visible.left + "px",
          backgroundColor: issueColors[issue.kind]
        });
        lines.append(line);
        count++;
      }
      if (count >= 300) break;
    }
    layer.replaceChildren(lines);
    // Keep mirrored drafts in memory only for the duration of a layout pass.
    mirror.replaceChildren();
  }

  function position() {
    if (!host || !active || !snapshot || (!issues.length && !open && !quietBadge())) {
      hide();
      return;
    }
    const box = active.getBoundingClientRect();
    const clip = clipFor(active, box);
    if (clip.right <= clip.left || clip.bottom <= clip.top || getComputedStyle(active).visibility !== "visible") {
      report("hidden: the field is outside the visible area (" + Math.round(box.width) + "x" + Math.round(box.height) + ")");
      hide();
      return;
    }
    badge.hidden = Boolean(primary && !open);
    chip.hidden = !primary || open;
    panel.hidden = !open;
    if (!chip.hidden) {
      const width = chip.offsetWidth;
      const height = chip.offsetHeight;
      const top = clip.bottom + height + 7 <= innerHeight ? clip.bottom + 4 :
        clip.top >= height + 7 ? clip.top - height - 4 : Math.max(4, clip.bottom - height - 3);
      chip.style.left = Math.min(innerWidth - width - 4, Math.max(4, clip.right - width)) + "px";
      chip.style.top = top + "px";
    }
    const outside = clip.right + 4;
    badge.style.left = (outside + badge.offsetWidth + 3 <= innerWidth ? outside :
      Math.max(3, clip.right - badge.offsetWidth - 3)) + "px";
    badge.style.top = Math.min(innerHeight - badge.offsetHeight - 3,
      Math.max(3, clip.bottom - badge.offsetHeight - 3)) + "px";
    if (open) {
      const height = panel.offsetHeight;
      const below = clip.bottom + 6;
      const above = clip.top - height - 6;
      panel.style.left = Math.min(innerWidth - panel.offsetWidth - 6,
        Math.max(6, box.right - panel.offsetWidth)) + "px";
      panel.style.top = Math.max(6, below + height <= innerHeight ? below :
        above >= 6 ? above : innerHeight - height - 6) + "px";
    }
    drawLines(box, clip);
  }

  function hide() {
    if (!host) return;
    badge.hidden = chip.hidden = true;
    panel.hidden = true;
    layer.replaceChildren();
    mirror.replaceChildren();
  }

  function schedulePosition() {
    if (frame || !active || !snapshot) return;
    frame = requestAnimationFrame(() => {
      frame = 0;
      position();
    });
  }

  // A layout pass copies the field text into the mirror and measures every mark. A scroll sends an event
  // per frame: the first one draws at once, the rest share one pass per 100 ms.
  function scheduleScroll() {
    if (scrollTimer || !active || !snapshot) return;
    schedulePosition();
    scrollTimer = setTimeout(() => {
      scrollTimer = 0;
      schedulePosition();
    }, 100);
  }

  function clearEditor() {
    clearTimeout(timer);
    clearModelRequest();
    timer = 0;
    resizeObserver?.disconnect();
    editorObserver?.disconnect();
    active = snapshot = selectedId = null;
    issues = [];
    open = composing = false;
    if (panel) panel.replaceChildren();
    hide();
  }

  function update(message = "") {
    if (life.signal.aborted) return;
    clearTimeout(timer);
    timer = 0;
    if (!canCheck() || !active?.isConnected || editable(active) !== active) {
      clearEditor();
      return;
    }
    if (composing) return;
    // The checker is not in the page yet. This runs again when it arrived.
    if (!engine) {
      loadEngine();
      return;
    }
    clearModelRequest();
    snapshot = readEditor(active);
    if (snapshot.text.length > maxLength || !snapshot.text.trim()) {
      snapshot = null;
      issues = [];
      open = false;
      if (panel) panel.replaceChildren();
      hide();
      return;
    }
    issues = nibCheck(snapshot.text, settings.style !== false, ignored, personal);
    if (issues.length !== lastCount) report("checked " + snapshot.text.length + " characters: " + issues.length + " suggestions");
    lastCount = issues.length;
    updatePrimary();
    notice = message;
    if (!issues.length && !open && !quietBadge()) {
      if (panel) panel.replaceChildren();
      hide();
      return;
    }
    mount();
    renderPanel();
    position();
  }

  // A draft of a few words in a multi-line editor gets the small check mark when Nib finds nothing.
  function quietBadge() {
    return Boolean(snapshot) && !(active instanceof HTMLInputElement) && snapshot.text.trim().split(/\s+/).length >= 3;
  }

  function scheduleCheck() {
    if (life.signal.aborted) return;
    clearTimeout(timer);
    clearModelRequest();
    snapshot = null;
    issues = [];
    hide();
    if (panel) panel.replaceChildren();
    selectedId = null;
    timer = setTimeout(update, 180);
  }

  function activate(node) {
    if (!canCheck()) return;
    const target = editable(node);
    if (!target) {
      clearEditor();
      return;
    }
    if (active === target) return;
    clearEditor();
    active = target;
    remounts = 0;
    report("focus " + describe(target));
    loadEngine();
    raise();
    resizeObserver ??= new ResizeObserver(schedulePosition);
    resizeObserver.observe(target);
    editorObserver ??= new MutationObserver(records => {
      if (!active || composing) return;
      // A check is already due and will read the newest text. A new delay for each change would
      // put the check off for ever in an editor that never rests.
      if (!snapshot && timer) return;
      // Many editors rebuild their nodes while the text stays the same. The marks must not flash then:
      // read the text first, and keep the marks when it did not change.
      if (snapshot && engine && !records.some(record => record.type === "attributes")) {
        const fresh = readEditor(active);
        if (fresh.text === snapshot.text) {
          // The text nodes may be new ones. The marks are measured on them.
          snapshot = fresh;
          schedulePosition();
          return;
        }
      }
      scheduleCheck();
    });
    editorObserver.observe(target, {
      attributes: true,
      attributeFilter: ["type", "autocomplete", "aria-label", "aria-labelledby", "placeholder", "name", "id",
        "disabled", "readonly", "aria-readonly", "aria-disabled", "contenteditable", "data-nib"],
      subtree: !isControl(target),
      childList: !isControl(target),
      characterData: !isControl(target)
    });
    scheduleCheck();
  }

  function apply(issue, replacement) {
    const element = active;
    if (!snapshot || !issues.includes(issue) || !element?.isConnected || editable(element) !== element || !canCheck()) return;
    const current = readEditor(element);
    if (current.text !== snapshot.text) {
      update("The draft changed. Review the updated suggestions.");
      focusPanel();
      return;
    }
    const wasOpen = open;
    if (isControl(element) && element.maxLength >= 0 &&
        current.text.length - issue.fragment.length + replacement.length > element.maxLength) {
      notice = "This fix would exceed the field’s character limit.";
      renderPanel();
      focusPanel();
      return;
    }
    const segment = current.segments && singleSegment(current, issue);
    if (current.segments && !segment) return;
    element.focus({ preventScroll: true });
    if (isControl(element)) {
      element.setSelectionRange(issue.start, issue.end);
    } else {
      const range = rangeFor(current, issue);
      const selection = element.getRootNode().getSelection?.() || window.getSelection();
      if (!range || !selection) return;
      selection.removeAllRanges();
      selection.addRange(range);
    }
    let succeeded = false;
    try {
      succeeded = replacement ? document.execCommand("insertText", false, replacement) : document.execCommand("delete");
    } catch {
      // Some editors do not support native replacement commands.
    }
    if (!succeeded && isControl(element) && element.value === current.text) {
      element.setRangeText(replacement, issue.start, issue.end, "end");
      element.dispatchEvent(new InputEvent("input", { bubbles: true, composed: true, inputType: "insertReplacementText", data: replacement }));
    }
    const expected = current.text.slice(0, issue.start) + replacement + current.text.slice(issue.end);
    const applied = readEditor(element).text === expected;
    editorObserver?.takeRecords();
    open = wasOpen;
    update(applied ? "Correction applied" : "This editor did not accept the fix. Edit the text directly.");
  }

  // Every handler below asks the same helper, so a field in a closed shadow root behaves like any other.
  function editorEvent(event) {
    return eventTarget(event);
  }
  // The popup asks whether Nib runs on this page, so the user can tell a quiet page from a broken one.
  // Every frame hears the question and the first answer wins. The frame with the text field answers at once.
  // The top page without a field waits a moment: an editor in a frame, as TinyMCE builds it, must come first.
  chrome.runtime.onMessage?.addListener((message, sender, reply) => {
    // The key press frame of Google Docs stays silent: the top page answers for the document.
    if (life.signal.aborted || message?.type !== "nib:status" || keyTarget) return;
    // For a Google Docs document: the button is in the page, and how far its check is. Counts only, no text.
    const answer = () => ({ running: true, enabled: canCheck(), editor: Boolean(active), issues: issues.length,
      model: modelState, engine, ...(unsupported ? { unsupported } : {}),
      ...(docsPath() ? { docsPanel: !docsHidden, docs: { ...docs, issues: docsResults.length } } : {}) });
    if (active) reply(answer());
    else if (window === window.top) {
      setTimeout(() => reply(answer()), 150);
      return true;
    }
  });

  listen(document, "focusin", event => {
    if (event.target === host) return;
    activate(editorEvent(event));
  }, true);
  listen(document, "focusout", () => {
    queueMicrotask(() => {
      const focused = focusedNode();
      if (focused !== host && editable(focused) !== active) clearEditor();
    });
  }, true);
  listen(document, "pointerdown", event => {
    if (event.target === host) return;
    if (editable(editorEvent(event)) !== active) clearEditor();
    else if (open) {
      open = false;
      renderPanel();
      position();
    }
  }, true);
  listen(document, "input", event => {
    if (event.target === host || !canCheck()) return;
    const target = editable(editorEvent(event));
    if (!target || target !== editable(focusedNode())) return;
    // Typing and pasting by the user. A script that fills the field does not count.
    if (event.isTrusted) touched.add(target);
    if (active !== target) activate(target);
    if (!event.isComposing && !composing) scheduleCheck();
  }, true);
  listen(document, "compositionstart", event => {
    if (editable(editorEvent(event)) !== active || !active) return;
    composing = true;
    clearTimeout(timer);
    clearModelRequest();
    timer = 0;
    hide();
  }, true);
  listen(document, "compositionend", event => {
    if (editable(editorEvent(event)) !== active || !active) return;
    composing = false;
    scheduleCheck();
  }, true);
  listen(document, "click", event => {
    // A page script must not open Nib's list.
    if (!event.isTrusted) return;
    if (event.target === host || !active || !snapshot || editable(editorEvent(event)) !== active) return;
    const offset = caretFor(snapshot);
    if (offset === null) return;
    const issue = issues.find(item => item.start <= offset && offset < item.end);
    if (!issue) {
      if (snapshot) update();
      return;
    }
    selectedId = issue.id;
    notice = "";
    open = true;
    renderPanel();
    position();
  }, true);
  listen(document, "keydown", event => {
    // A page script must not open Nib's list, and its keys are not the user's.
    if (!event.isTrusted) return;
    if (active && !touched.has(active) && event.target !== host && editable(editorEvent(event)) === active) touched.add(active);
    if (docsOpen && event.key === "Escape") {
      // The key stays with the page unless the focus is in Nib's panel: Google Docs closes its own menus with it.
      if (document.activeElement === docsHost) {
        event.preventDefault();
        event.stopPropagation();
      }
      closeDocs();
      return;
    }
    if (open && event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      closePanel();
    } else if (issues.length && event.altKey && event.shiftKey && event.code === "KeyL") {
      event.preventDefault();
      event.stopPropagation();
      if (open) closePanel();
      else {
        open = true;
        renderPanel();
        position();
        focusPanel();
      }
    }
  }, true);
  listen(document, "keyup", event => {
    if (active && snapshot && !open && !composing &&
        /^(?:Arrow(?:Left|Right|Up|Down)|Home|End|PageUp|PageDown)$/.test(event.key)) update();
  }, true);
  document.addEventListener("scroll", scheduleScroll, { capture: true, signal: life.signal });
  listen(window, "resize", schedulePosition);
  listen(window.visualViewport, "resize", schedulePosition);
  listen(window.visualViewport, "scroll", scheduleScroll);
  listen(document, "visibilitychange", () => {
    if (document.hidden) clearEditor();
    else activate(focusedNode());
  });

  // Editors that draw their text as a picture. Nib cannot read them, and silence there looks like a fault.
  // So the page gets one small note that says why, and what works in its place.
  const unsupported = window === window.top && location.hostname === "docs.google.com" &&
    /^\/(?:document|presentation|spreadsheets)\//.test(location.pathname) ? "Google Docs" : "";
  let hint = null;
  function showHint() {
    const key = "hint:" + unsupported;
    if (!unsupported || life.signal.aborted) return;
    // A document has the "Check document" button in place of the note.
    if (!canCheck() || settings[key] === false || docsPath()) {
      hint?.remove();
      hint = null;
      return;
    }
    if (hint?.isConnected) return;
    hint = document.createElement("div");
    hint.setAttribute("data-nib-hint", "");
    hint.style.cssText = "all:initial!important;position:fixed!important;right:16px!important;bottom:16px!important;z-index:2147483647!important;";
    const root = hint.attachShadow({ mode: "closed" });
    const css = document.createElement("style");
    css.textContent = `
      .box{position:relative;width:290px;padding:12px 34px 12px 14px;background:#fbfdfb;color:#1a3026;border:1px solid #ccdcd1;
        border-radius:12px;box-shadow:0 6px 28px #152e2840;font:13px/1.42 system-ui,-apple-system,sans-serif}
      strong{display:block;margin-bottom:3px;font-size:13px}p{margin:0;color:#4d6458;font-size:12px}
      button{position:absolute;top:6px;right:6px;width:22px;height:22px;border:0;border-radius:6px;background:transparent;
        color:#406152;font:16px/1 system-ui;cursor:pointer}button:hover{background:#e8f3ec}`;
    const box = document.createElement("div");
    box.className = "box";
    box.setAttribute("role", "status");
    const title = document.createElement("strong");
    title.textContent = "Nib cannot read " + unsupported;
    const text = document.createElement("p");
    text.textContent = unsupported + " draws its text as a picture, so Nib cannot check it in the page. " +
      "Select your text and press Control-Option-F. Nib opens it in its editor and can paste the result back.";
    const close = document.createElement("button");
    close.textContent = "×";
    close.title = "Do not show this again";
    close.setAttribute("aria-label", "Close. Do not show this again.");
    close.addEventListener("click", () => {
      hint?.remove();
      hint = null;
      chrome.storage.local.set({ [key]: false }).catch(() => {});
    });
    box.append(title, text, close);
    root.append(css, box);
    document.documentElement.append(hint);
  }

  // A Google Docs document gets more than the note: a button that reads the text of the document from
  // Google and lists what Nib finds. Nib cannot change the document, so each card offers the fix to copy.
  const docsLimit = 60000;
  // A line of this length is no prose, and the sentence finder skips it too.
  const docsLineLimit = 10000;
  const docsModelLimit = 150;
  const docsCardLimit = 200;
  // The same pattern as nibDocsExport in sentences.js, which is not in the page before the first check.
  const docsPattern = /^\/document\/(?:u\/\d+\/)?d\/[\w-]+(?=\/|$)/;
  // Read again on each use: Google Docs can move to another document without a reload.
  const docsPath = () => unsupported && docsPattern.exec(location.pathname)?.[0] || "";
  const docsIntro = "Google Docs draws its text as a picture, so Nib cannot check while you type. " +
    "Nib reads the text of this document and lists what it finds. You make the changes in the document.";
  const docsIdle = () => ({ state: "idle", sentences: 0, checked: 0, issues: 0, chars: 0, cut: false, capped: false, model: "" });
  let docs = docsIdle();
  // The sentences of the document stay in this list only, in memory, until the panel closes.
  let docsResults = [];
  let docsHost = null;
  let docsRoot, docsPanel, docsStatus, docsStopButton, docsNotes, docsList;
  let docsOpen = false;
  let docsHidden = false;
  let docsLogged = false;
  // The document that the open panel belongs to, and the message of a failed run.
  let docsFor = "";
  let docsMessage = "";
  const wait = time => new Promise(resolve => setTimeout(resolve, time));

  function showDocs() {
    if (life.signal.aborted) return;
    if (docsFor && docsFor !== docsPath()) closeDocs();
    // The closed note of older versions ("hint:Google Docs") does not hide the button:
    // a user who closed the note must still find the check.
    if (!docsPath() || !canCheck() || docsHidden) {
      closeDocs();
      docsHost?.remove();
      docsHost = null;
      return;
    }
    if (docsHost?.isConnected) return;
    docsHost = document.createElement("div");
    docsHost.setAttribute("data-nib-docs", "");
    docsHost.style.cssText = "all:initial!important;position:fixed!important;right:16px!important;bottom:16px!important;z-index:2147483647!important;";
    const root = docsHost.attachShadow({ mode: "closed" });
    const css = makeElement("style");
    css.textContent = `
      :host{color-scheme:light}*{box-sizing:border-box}[hidden]{display:none!important}
      .wrap{display:flex;flex-direction:column;align-items:flex-end;gap:8px;font:13px/1.42 system-ui,-apple-system,sans-serif;color:#1a3026}
      .bar{display:flex;align-items:center;gap:4px}
      .pill{min-height:30px;padding:5px 13px;background:#215945;color:#fff;border:1px solid #fff;border-radius:99px;font:inherit;font-size:12px;font-weight:700;box-shadow:0 2px 8px #142e2540;cursor:pointer}
      .pill:hover{background:#163e30}
      .hide{width:20px;height:20px;padding:0;border:1px solid #ccdcd1;border-radius:99px;background:#fbfdfb;color:#406152;font:14px/1 system-ui;cursor:pointer}
      .hide:hover{background:#e8f3ec}
      .panel{display:flex;flex-direction:column;width:min(360px,calc(100vw - 32px));max-height:min(70vh,calc(100vh - 70px));background:#fbfdfb;border:1px solid #ccdcd1;border-radius:12px;box-shadow:0 6px 28px #152e2840;padding:9px}
      .head{display:flex;align-items:center;gap:6px;padding:1px 3px 5px}.head strong{font-size:15px;margin-right:auto}
      .intro,.note{margin:2px 3px 6px;color:#4d6458;font-size:12px}
      .progress{display:flex;align-items:center;justify-content:space-between;gap:6px;margin:2px 3px 6px}.status{margin:0;font-weight:650;color:#263e32}
      .list{overflow:auto;overscroll-behavior:contain;min-height:0}
      .card{padding:8px;margin:5px 0;background:#fff;border:1px solid #deebe1;border-radius:8px;overflow-wrap:anywhere}
      .kind{font-size:11px;font-weight:750}.sentence{margin:4px 0 7px;color:#263e32}.sentence strong{font-weight:750}.message{margin:4px 0;color:#586b62;font-size:12px}
      .buttons{display:flex;flex-wrap:wrap;gap:4px 7px}.fix,.minor{font:inherit;cursor:pointer}
      .fix{border:1px solid #d3e7d9;background:#e8f3ec;color:#215945;border-radius:6px;padding:3px 7px;font-weight:700}.fix:hover{background:#d3eadc}
      .minor{background:transparent;color:#406152;border:0;padding:4px 3px;font-size:11px;font-weight:650}.minor:hover{text-decoration:underline}
      button:focus-visible{outline:2px solid #268763;outline-offset:2px}
    `;
    const label = (button, text) => { button.setAttribute("aria-label", text); return button; };
    docsPanel = makeElement("section", "panel");
    docsPanel.setAttribute("role", "dialog");
    docsPanel.setAttribute("aria-label", "Nib: check document");
    docsPanel.hidden = true;
    const head = makeElement("div", "head");
    head.append(makeElement("strong", "", "Nib"),
      label(makeButton("Check again", "minor", event => runDocs(event)), "Check the document again"),
      label(makeButton("Close", "minor", closeDocs), "Close the list of suggestions"));
    const progress = makeElement("div", "progress");
    docsStatus = makeElement("p", "status");
    docsStatus.setAttribute("role", "status");
    docsStopButton = label(makeButton("Stop", "minor", stopDocs), "Stop the check");
    progress.append(docsStatus, docsStopButton);
    docsNotes = makeElement("div", "notes");
    docsList = makeElement("div", "list");
    docsPanel.append(head, makeElement("p", "intro", docsIntro), progress, docsNotes, docsList);
    const bar = makeElement("div", "bar");
    bar.append(label(makeButton("Check document", "pill", event => runDocs(event)), "Nib: check document"),
      label(makeButton("×", "hide", () => {
        // Until the next page load. The button covers a corner of the page that the user may need.
        docsHidden = true;
        showDocs();
      }), "Hide the Nib button on this page"));
    bar.lastChild.title = "Hide until the page loads again";
    const wrap = makeElement("div", "wrap");
    wrap.append(docsPanel, bar);
    root.append(css, wrap);
    docsRoot = root;
    document.documentElement.append(docsHost);
    if (!docsLogged) report("docs: check button shown");
    docsLogged = true;
  }

  // Ends a run without a change to what the panel shows.
  function stopDocs() {
    docsSerial++;
    if (docs.state === "reading" || docs.state === "checking") {
      docs.state = "done";
      docs.stopped = true;
    }
    renderDocsStatus();
  }

  function closeDocs() {
    docsSerial++;
    const hadFocus = docsOpen && document.activeElement === docsHost;
    docsOpen = false;
    docsFor = docsMessage = "";
    docs = docsIdle();
    docsResults = [];
    if (!docsPanel) return;
    docsPanel.hidden = true;
    docsList.replaceChildren();
    // The focus must not stay on a hidden button.
    if (hadFocus) docsRoot.activeElement?.blur?.();
  }

  function renderDocsStatus() {
    if (!docsPanel) return;
    const plural = (count, word) => count + " " + word + (count === 1 ? "" : "s");
    const found = docsResults.length;
    docsStatus.textContent = docs.state === "reading" ? "Reading the document…" :
      docs.state === "checking" ? "Checked " + docs.checked + " of " + plural(docs.sentences, "sentence") + "…" :
      docs.state === "error" || !docs.sentences ? docsMessage :
      docs.stopped ? "Stopped. Checked " + docs.checked + " of " + plural(docs.sentences, "sentence") + "." :
      (found ? plural(found, "suggestion") + "." : "No suggestions.") + " Nib checked " + plural(docs.sentences, "sentence") + ".";
    docsStopButton.hidden = docs.state !== "reading" && docs.state !== "checking";
    const notes = [];
    if (docs.cut) notes.push("Nib checked the first part of this long document.");
    if (docs.capped) notes.push("The Mac model checks the first " + docsModelLimit + " sentences. The other sentences got the local checks only.");
    if (docs.model === "off") notes.push("Sentence fixes need the Nib app on this Mac: in Nib, choose More → Connect Browsers…");
    if (docs.model === "slow") notes.push("The Mac model did not answer in time. The list shows the local checks.");
    if (found > docsCardLimit) notes.push("Showing the first " + docsCardLimit);
    // Rebuild the notes only on a change: a screen reader would read them again each time.
    if (notes.join("\n") !== [...docsNotes.children].map(note => note.textContent).join("\n")) {
      docsNotes.replaceChildren(...notes.map(note => makeElement("p", "note", note)));
    }
  }

  // One card: the sentence with the old words struck through and the new words in bold.
  // Built from nodes and text only. The text of the document is not trusted, and the page forbids HTML strings.
  function docsCard(result) {
    const { issue } = result;
    const fix = issue.replacements[0];
    const card = makeElement("article", "card");
    const kind = makeElement("div", "kind", issue.kind);
    kind.style.color = issueColors[issue.kind];
    const sentence = makeElement("p", "sentence");
    const old = makeElement("s", "", issue.fragment.trim() ? issue.fragment : "␣".repeat(issue.fragment.length));
    old.style.color = issueColors[issue.kind];
    sentence.append(result.before, old);
    if (fix?.trim()) sentence.append(" ", makeElement("strong", "", fix));
    sentence.append(result.after);
    card.append(kind, sentence);
    // Where the marks alone do not show the change, the words of the checker do.
    if (!fix?.trim() || !issue.fragment.trim()) card.append(makeElement("p", "message", issue.message));
    const buttons = makeElement("div", "buttons");
    if (fix !== undefined) {
      const copy = makeButton("Copy fix", "fix", async () => {
        let done = true;
        try { await navigator.clipboard.writeText(result.before + fix + result.after); } catch { done = false; }
        copy.textContent = done ? "Copied" : "Could not copy";
        setTimeout(() => { copy.textContent = "Copy fix"; }, 1500);
      });
      copy.setAttribute("aria-label", "Copy the corrected sentence");
      buttons.append(copy);
    }
    const drop = keep => {
      docsResults = docsResults.filter(keep);
      renderDocsList();
      docsPanel.querySelector("button")?.focus({ preventScroll: true });
    };
    const ignore = makeButton("Ignore", "minor", () => {
      // As in the list of a text field: the same finding stays away in this tab.
      ignored.add(issue.key);
      drop(other => other.issue.key !== issue.key);
    });
    ignore.setAttribute("aria-label", "Ignore this suggestion");
    buttons.append(ignore);
    if (issue.kind === "Spelling") {
      const add = makeButton("Add to dictionary", "minor", () => {
        const word = issue.fragment.toLowerCase();
        personal.add(word);
        chrome.storage.local.set({ ["word:" + word]: true }).catch(() => {});
        drop(other => other.issue.kind !== "Spelling" || other.issue.fragment.toLowerCase() !== word);
      });
      add.setAttribute("aria-label", "Add " + issue.fragment + " to your dictionary");
      buttons.append(add);
    }
    card.append(buttons);
    return card;
  }

  function renderDocsList() {
    if (!docsPanel) return;
    docsList.replaceChildren(...docsResults.slice(0, docsCardLimit).map(docsCard));
    renderDocsStatus();
  }

  // The sentence around a finding. A finding between two sentences, such as two spaces, shows both.
  function addDocsResult(line, issue) {
    const near = line.sentences.filter(sentence => sentence.start <= issue.end && sentence.end >= issue.start);
    const start = near.length ? Math.min(issue.start, near[0].start) : Math.max(0, issue.start - 80);
    const end = near.length ? Math.max(issue.end, near.at(-1).end) : Math.min(line.text.length, issue.end + 80);
    const result = { issue, before: line.text.slice(start, issue.start), after: line.text.slice(issue.end, end) };
    docsResults.push(result);
    if (docsResults.length <= docsCardLimit) docsList.append(docsCard(result));
  }

  async function runDocs(event) {
    // Only a click by the user reads the document and may send its sentences to the Mac model.
    if (!event?.isTrusted || life.signal.aborted || !docsPanel) return;
    const path = docsPath();
    if (!path || !canCheck()) return showDocs();
    const serial = ++docsSerial;
    // False after Stop, Close, a newer run, a move to another document, or the end of this copy of Nib.
    const current = () => {
      if (serial !== docsSerial || life.signal.aborted) return false;
      if (docsPath() === path) return true;
      // The page moved and no event told Nib: close the panel of the old document now.
      showDocs();
      return false;
    };
    const fail = (message, code) => {
      docs.state = "error";
      docsMessage = message;
      renderDocsStatus();
      report("docs: could not read the document (" + code + ")");
    };
    const wasOpen = docsOpen;
    docsOpen = true;
    docsFor = path;
    docsMessage = "";
    docsResults = [];
    docs = { ...docsIdle(), state: "reading" };
    docsPanel.hidden = false;
    renderDocsList();
    // Escape closes the panel when the focus is in it. Google Docs keeps its own focus in a frame.
    if (!wasOpen) docsPanel.querySelector("button")?.focus({ preventScroll: true });
    // The checker comes from the worker, as for a text field. A slow start gets ten seconds.
    for (let tries = 0; !engine && tries < 40; tries++) {
      loadEngine();
      await wait(250);
      if (!current()) return;
    }
    if (!engine || typeof globalThis.nibDocsExport !== "function") return fail("Nib could not start its checker on this page. Try again.", "no checker");
    let answer = null;
    try {
      answer = await chrome.runtime.sendMessage({ type: "nib:docs", path: nibDocsExport(path) });
    } catch { /* old copy, or the worker is away */ }
    if (!current()) return;
    if (answer?.status === "denied") return fail("Nib could not read this document. Open it in a browser where you are signed in to Google.", String(answer.code).slice(0, 20));
    if (answer?.status !== "ok" || typeof answer.text !== "string") return fail("Nib could not read this document. Try again.", "network");
    const { text, cut } = nibDocsText(answer.text, docsLimit);
    docs.cut = cut || answer.more === true;
    docs.chars = text.length;
    // One line of the export is one paragraph. The place of each line in the text tells whether
    // the sentence before another one stands right before it.
    const lines = [];
    let offset = 0;
    for (const line of text.split("\n")) {
      if (line.trim() && line.length <= docsLineLimit) lines.push({ text: line, start: offset, sentences: nibSentences(line) });
      offset += line.length + 1;
    }
    docs.sentences = lines.reduce((sum, line) => sum + line.sentences.length, 0);
    const finish = () => {
      docs.state = "done";
      renderDocsStatus();
      report("docs: checked " + docs.sentences + " sentences: " + docsResults.length + " suggestions");
    };
    if (!docs.sentences) {
      docsMessage = "This document has no text.";
      return finish();
    }
    docs.state = "checking";
    renderDocsStatus();
    const style = settings.style !== false;
    let useModel = settings.context !== false;
    let asked = 0;
    let timeouts = 0;
    let previous = null;
    let since = performance.now();
    for (const line of lines) {
      const data = { text: line.text, segments: null };
      let local = nibCheck(line.text, style, ignored, personal);
      for (const sentence of line.sentences) {
        // The sentence before gives the model its context, by the same rule as in a text field.
        sentence.before = previous && previous.end + 3 >= line.start + sentence.start ? previous.text : "";
        sentence.key = sentence.text + "\u0001" + sentence.before;
        previous = { end: line.start + sentence.end, text: sentence.text };
        let fix = null;
        if (useModel && modelEligible(sentence)) {
          // The limit counts sentences, also those with a known answer: the same document gives the same list.
          const over = asked >= docsModelLimit;
          if (over) docs.capped = true;
          else asked++;
          let response = over ? null : modelCache.get(sentence.key);
          if (!over && !response) {
            // One request at a time, in the order of the document.
            try {
              response = await chrome.runtime.sendMessage({ type: "nib:sentence", text: sentence.text, before: sentence.before });
            } catch {
              response = null;
            }
            if (!current()) return;
            const answered = ["model", "no-change", "improve"].includes(response?.status);
            if (!response || response.status === "disconnected" || response.status === "unavailable") {
              // The Mac app is away. The local checks go on.
              useModel = false;
              modelState = docs.model = "off";
              response = null;
            } else if (!answered && response.status !== "invalid" && response.status !== "skipped") {
              // A timeout, or a status this version does not know. A second one in a row ends the
              // requests of this run: 150 sentences that each wait half a minute would take an hour.
              if (++timeouts >= 2) {
                useModel = false;
                docs.model = "slow";
              }
              response = null;
            } else {
              timeouts = 0;
              if (answered) modelState = "on";
              if (modelCache.size >= 300) modelCache.delete(modelCache.keys().next().value);
              // "invalid" and "skipped" are final for this sentence, as in a text field.
              response = answered ? response : { status: response.status };
              modelCache.set(sentence.key, response);
            }
          }
          if (response?.replacement) fix = contextualIssue(data, sentence, response.replacement);
        }
        // A fix of the model takes the place of the local findings that it covers.
        if (fix) local = local.filter(other => other.end <= fix.start || other.start >= fix.end);
        const ready = local.filter(other => other.start < sentence.end);
        local = local.filter(other => other.start >= sentence.end);
        for (const issue of [...ready, ...(fix ? [fix] : [])].sort((a, b) => a.start - b.start)) addDocsResult(line, issue);
        docs.checked++;
        // A long document must not freeze the page: after 40 ms of work the page gets its turn.
        if (performance.now() - since > 40) {
          renderDocsStatus();
          await wait(0);
          if (!current()) return;
          since = performance.now();
        }
      }
      for (const issue of local) addDocsResult(line, issue);
      renderDocsStatus();
    }
    finish();
  }

  // Google Docs can open another document without a reload. The panel belongs to the old one.
  listen(window.navigation, "currententrychange", showDocs);
  listen(window, "popstate", showDocs);
  // Leaving the page ends a run.
  listen(window, "pagehide", closeDocs);

  function updateSettings(next) {
    settings = next;
    showHint();
    showDocs();
    personal = new Set(Object.keys(next).filter(key => key.startsWith("word:") && next[key] === true)
      .map(key => key.slice(5)));
    if (!canCheck()) clearEditor();
    else if (active) update();
    else activate(focusedNode());
  }

  // Remember the password fields before a "show password" button turns one into a text field.
  // Only changes of the type attribute come here, so this costs nothing on a busy page.
  notePasswords(document);
  secretObserver = new MutationObserver(records => {
    for (const record of records) {
      if (record.target instanceof HTMLInputElement && (record.oldValue || "").toLowerCase() === "password") secrets.add(record.target);
    }
  });
  if (document.documentElement) {
    secretObserver.observe(document.documentElement, { attributes: true, attributeFilter: ["type"], attributeOldValue: true, subtree: true });
  }
  chrome.storage.local.get(null).then(updateSettings).catch(() => clearEditor());
  chrome.storage.onChanged.addListener((changes, area) => {
    if (life.signal.aborted) return;
    if (area !== "local" || !settings) return;
    const next = { ...settings };
    for (const [key, change] of Object.entries(changes)) {
      if (change.newValue === undefined) delete next[key];
      else next[key] = change.newValue;
    }
    updateSettings(next);
  });
})();
