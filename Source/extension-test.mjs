// Loads the real extension in Chromium and checks that Nib starts in an open tab, also when it starts again
// after an update, and that one working copy remains. Needs Playwright with its Chromium:
//   NIB_PLAYWRIGHT=/path/to/node_modules/playwright/index.mjs node Source/extension-test.mjs
import http from "node:http";
import os from "node:os";
import path from "node:path";
import fs from "node:fs";
import { fileURLToPath } from "node:url";

// The worker of the extension reads the text of a Google Docs document. With this switch the routes
// of the test also catch requests of the worker, so that request never reaches the network.
process.env.PW_EXPERIMENTAL_SERVICE_WORKER_NETWORK_EVENTS = "1";
const { chromium } = await import(process.env.NIB_PLAYWRIGHT);
const ext = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "Browser");
const profile = fs.mkdtempSync(path.join(os.tmpdir(), "nib-extension-"));
const server = http.createServer((request, response) => {
  response.setHeader("content-type", "text/html");
  // Like the LinkedIn draft box: a modal dialog with a transform and hidden overflow, filled by the editor.
  if (request.url === "/dialog-list") return response.end(`<!doctype html><meta charset=utf-8>
    <dialog id=d style="width:640px;height:360px;padding:0;overflow:hidden;transform:translateY(0)">
      <div contenteditable=true id=e style="height:320px;overflow:auto;padding:12px">I recieved the report. The rest is fine.</div></dialog>
    <script>document.getElementById("d").showModal();</script>`);
  // A modal dialog, as on LinkedIn: it sits in the top layer, above every z-index.
  if (request.url === "/dialog") return response.end(`<!doctype html><meta charset=utf-8><body style="height:900px">
    <dialog id=d style="width:600px;padding:20px;transform:translateY(10px)"><div contenteditable=true id=e style="min-height:120px">I recieved the report from Anna yesterday.</div></dialog>
    <script>document.getElementById("d").showModal();</script>`);
  // A text field inside a closed shadow root, as web components build them.
  if (request.url === "/closed") return response.end(`<!doctype html><meta charset=utf-8><div id=h></div>
    <script>const root = document.getElementById("h").attachShadow({ mode: "closed" });
      root.innerHTML = '<textarea id=t style="width:400px;height:120px"></textarea>';</script>`);
  // "Show password" turns a password field into a text field. Neutral names: no label gives the field away.
  if (request.url === "/password") return response.end(`<!doctype html><meta charset=utf-8>
    <form><input id=f1 type=password><button type=button id=b1>show</button><br>
    <input id=f2 type=password><button type=button id=b2>show</button><br><input id=f3 type=text style="margin-top:150px"></form>
    <script>for (const n of [1, 2]) document.getElementById("b" + n).onclick = () => { document.getElementById("f" + n).type = "text"; };</script>`);
  // Editors of code and terminals keep a hidden textarea. Nib must not check it.
  if (request.url === "/code") return response.end(`<!doctype html><meta charset=utf-8>
    <div class=ace_editor><textarea class=ace_text-input id=a></textarea></div>
    <div class=xterm><textarea class=xterm-helper-textarea id=x></textarea></div>`);
  // A mention is one part that the user cannot edit, in the middle of a sentence.
  if (request.url === "/mention") return response.end(`<!doctype html><meta charset=utf-8>
    <div contenteditable=true id=e style="width:500px;min-height:80px"><div>This first line is all fine here.</div><div>Hi <span contenteditable=false>@Anna</span> can you send teh report now</div></div>`);
  // An editor in a frame, as TinyMCE builds it.
  if (request.url === "/frame-inner") return response.end(`<!doctype html><meta charset=utf-8>
    <body contenteditable=true id=e>I recieved the report from Anna yesterday.</body>`);
  if (request.url === "/frame") return response.end(`<!doctype html><meta charset=utf-8><p>Top page</p>
    <iframe id=f src="/frame-inner" style="width:500px;height:200px"></iframe>`);
  // Many editors write their document into an empty frame: it has no address of its own.
  if (request.url === "/blank-frame") return response.end(`<!doctype html><meta charset=utf-8><p>Top page</p>
    <iframe id=f style="width:500px;height:200px"></iframe>
    <script>const d = document.getElementById("f").contentDocument; d.open();
      d.write("<body contenteditable=true>I recieved the report from Anna yesterday.</body>"); d.close();</script>`);
  // The page puts the focus into a field with text that the user did not type.
  if (request.url === "/autofocus") return response.end(`<!doctype html><meta charset=utf-8>
    <textarea id=t style="width:400px;height:120px">This are a quoted message from another person.</textarea>
    <script>const t = document.getElementById("t"); t.focus(); t.setSelectionRange(3, 3);</script>`);
  // An editor that changes its own nodes all the time, while the text stays the same.
  if (request.url === "/busy") return response.end(`<!doctype html><meta charset=utf-8>
    <div contenteditable=true id=e style="width:500px;min-height:80px">I recieved the report from Anna yesterday.</div>
    <script>const e = document.getElementById("e");
      setInterval(() => { const mark = document.createElement("span"); e.append(mark); mark.remove(); }, 50);</script>`);
  // A field for the troubleshooting log: class names and a role that must not reach the log as written.
  if (request.url === "/log") return response.end(`<!doctype html><meta charset=utf-8>
    <button id=b>A button</button>
    <textarea id=t class="fine-class two three secret:data" role="Private Role!" style="width:400px;height:120px"></textarea>`);
  if (request.url === "/plain") return response.end(`<!doctype html><meta charset=utf-8>
    <textarea id=t style="width:400px;height:120px">I recieved the report from Anna yesterday.</textarea>`);
  // Like many editors, the page stops focus, input and key events on the way up.
  response.end(`<!doctype html><meta charset=utf-8><div contenteditable=true id=e style="width:500px;min-height:80px">I recieved the report from Anna yesterday.</div>
    <script>for (const type of ["focusin", "focusout", "input", "keydown", "keyup", "pointerdown", "click"])
      document.getElementById("e").addEventListener(type, event => event.stopPropagation());</script>`);
}).listen(0);
const url = "http://127.0.0.1:" + server.address().port + "/";
let failed = 0;
const expect = (condition, name) => { if (!condition) { failed++; console.log("FAIL  " + name); } };

const context = await chromium.launchPersistentContext(profile, { channel: "chromium", headless: true,
  args: [`--disable-extensions-except=${ext}`, `--load-extension=${ext}`] });
try {
  const worker = context.serviceWorkers()[0] ?? await context.waitForEvent("serviceworker");
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", error => errors.push(error.message));
  // The test reads what the pages send to the worker: sentences for the model and lines for the log.
  await worker.evaluate(() => {
    globalThis.seen = [];
    chrome.runtime.onMessage.addListener(message => {
      if (message?.type === "nib:sentence" || message?.type === "nib:log") seen.push(message);
    });
  });
  await page.goto(url);
  await page.waitForTimeout(500);
  // The word list is large. A page gets it only when the user enters a text field.
  const idle = await worker.evaluate(async () => {
    for (const tab of await chrome.tabs.query({})) {
      try { return await chrome.tabs.sendMessage(tab.id, { type: "nib:status" }); } catch { /* browser pages */ }
    }
  });
  expect(idle?.running && idle.engine === false, "before the first focus the page has no word list");
  for (let round = 1; round <= 3; round++) {
    // The same call the extension makes after it is installed or updated.
    await worker.evaluate(() => startInOpenTabs());
    await page.waitForTimeout(800);
    await page.mouse.click(700, 400);
    await page.click("#e");
    await page.waitForTimeout(1500);
    const answers = await worker.evaluate(async () => {
      const out = [];
      for (const tab of await chrome.tabs.query({})) {
        try { out.push(await chrome.tabs.sendMessage(tab.id, { type: "nib:status" })); } catch { /* browser pages */ }
      }
      return out;
    });
    const status = answers.find(answer => answer?.editor);
    expect(status?.running && status.issues >= 1, "round " + round + ": Nib runs and finds the typo");
    expect(status?.engine === true, "round " + round + ": the word list is loaded after the focus");
    expect(await page.evaluate(() => document.querySelectorAll("[data-nib-root]").length) === 1, "round " + round + ": one Nib overlay");
  }
  // In a modal dialog, Nib's badge must be on top: the point beside the field must hit Nib's overlay.
  const dialog = await context.newPage();
  dialog.on("pageerror", error => errors.push(error.message));
  await dialog.goto(url + "dialog");
  await dialog.click("#e");
  await dialog.waitForTimeout(1500);
  const onTop = await dialog.evaluate(() => {
    const box = document.getElementById("e").getBoundingClientRect();
    // The badge sits at the lower right corner of the field, the suggestion button just below it.
    for (let x = box.left; x < box.right + 40; x += 6) for (let y = box.bottom - 30; y < box.bottom + 44; y += 4) {
      if (document.elementFromPoint(x, y)?.hasAttribute?.("data-nib-root")) return [x, y];
    }
    return null;
  });
  if (!onTop && process.env.NIB_SHOT) await dialog.screenshot({ path: process.env.NIB_SHOT });
  expect(onTop, "in a modal dialog, Nib's suggestion is on top and can be clicked");
  if (onTop) {
    await dialog.mouse.click(onTop[0], onTop[1]);
    await dialog.waitForTimeout(800);
    expect((await dialog.textContent("#e")).includes("received"), "in a modal dialog, a click applies the fix");
  }
    // A click on the count opens the list of suggestions, also when the dialog clips its content.
  const list = await context.newPage();
  list.on("pageerror", error => errors.push(error.message));
  await list.goto(url + "dialog-list");
  await list.click("#e");
  await list.keyboard.press("End");
  await list.keyboard.press("Control+End");
  await list.waitForTimeout(1500);
  const hits = () => list.evaluate(() => {
    let count = 0, at = null;
    for (let x = 0; x < innerWidth; x += 8) for (let y = 0; y < innerHeight; y += 8) {
      if (document.elementFromPoint(x, y)?.hasAttribute?.("data-nib-root")) { count++; at ??= [x, y]; }
    }
    return { count, at };
  });
  const before = await hits();
  expect(before.at, "in a clipped dialog, the count is visible");
  if (before.at) {
    await list.mouse.click(before.at[0] + 2, before.at[1] + 2);
    await list.waitForTimeout(800);
    const after = await hits();
    if (after.count - before.count <= 200 && process.env.NIB_SHOT) await list.screenshot({ path: process.env.NIB_SHOT });
    expect(after.count - before.count > 200, "a click on the count opens the list (" + before.count + " -> " + after.count + " points)");
  }

  // From here on a stand-in takes the place of the Mac app, so the test sees what would go to the Mac.
  await worker.evaluate(() => {
    globalThis.fake = { sent: [], onMessage: { addListener: listener => { fake.deliver = listener; } },
      onDisconnect: { addListener: () => {} }, postMessage: message => { fake.sent.push(message); }, disconnect() {} };
    chrome.runtime.connectNative = () => fake;
  });
  const open = async (name, base = url) => {
    const next = await context.newPage();
    next.on("pageerror", error => errors.push(error.message));
    await next.goto(base + name);
    return next;
  };
  const statusOf = target => worker.evaluate(async address => {
    const tab = (await chrome.tabs.query({})).find(item => item.url === address);
    try { return await chrome.tabs.sendMessage(tab.id, { type: "nib:status" }); } catch { return null; }
  }, target.url());
  const sentences = () => worker.evaluate(() => seen.filter(message => message.type === "nib:sentence").map(message => message.text));
  const logLines = () => worker.evaluate(() => seen.filter(message => message.type === "nib:log").map(message => message.line));
  const toMac = () => worker.evaluate(() => fake.sent.filter(message => message.log).map(message => message.log));

  // A field in a closed shadow root is checked again after each change, and a click inside keeps it.
  const closed = await open("closed");
  await closed.mouse.click(100, 60);
  await closed.keyboard.type("I recieved it. ");
  await closed.waitForTimeout(1200);
  let status = await statusOf(closed);
  expect(status?.editor && status.issues === 1, "closed shadow root: the typed text is checked");
  await closed.mouse.click(300, 100);
  await closed.waitForTimeout(300);
  expect((await statusOf(closed))?.editor, "closed shadow root: a click inside the field keeps it");
  await closed.keyboard.type("And teh rest. ");
  await closed.waitForTimeout(1200);
  status = await statusOf(closed);
  expect(status?.editor && status.issues === 2, "closed shadow root: the check runs again after more typing");
  await closed.close();

  // A password stays private when the page shows it as text.
  const secret = await open("password");
  await secret.click("#f1");
  await secret.keyboard.type("I recieved teh report");
  await secret.click("#b1");
  await secret.click("#f1");
  await secret.keyboard.type(" again");
  await secret.waitForTimeout(1200);
  expect(!(await statusOf(secret))?.editor, "a password shown as text is not checked");
  await secret.click("#b2");
  await secret.click("#f2");
  await secret.keyboard.type("I recieved teh report");
  await secret.waitForTimeout(1200);
  expect(!(await statusOf(secret))?.editor, "a password shown as text before its first focus is not checked");
  await secret.click("#f3");
  await secret.keyboard.type("I recieved it");
  await secret.waitForTimeout(1200);
  status = await statusOf(secret);
  expect(status?.editor && status.issues === 1, "a plain field next to a password is checked");
  await secret.close();

  const code = await open("code");
  for (const id of ["#a", "#x"]) {
    await code.focus(id);
    await code.keyboard.type("I recieved teh report");
    await code.waitForTimeout(900);
    expect(!(await statusOf(code))?.editor, "the hidden field of a code editor or terminal is not checked: " + id);
  }
  await code.close();

  // The sentence with the mention stays one sentence and never goes to the model. The other sentence does.
  let asked = (await sentences()).length;
  const mention = await open("mention");
  await mention.click("#e");
  await mention.evaluate(() => { getSelection().selectAllChildren(document.getElementById("e")); getSelection().collapseToEnd(); });
  await mention.keyboard.type(" ");
  await mention.waitForTimeout(1500);
  let texts = (await sentences()).slice(asked);
  expect(!texts.some(text => text.includes("can you send")), "a sentence with a mention is not sent in parts: " + texts.join(" | "));
  expect(texts.some(text => text.includes("first line")), "a sentence without a mention goes to the model");
  expect((await statusOf(mention))?.issues === 1, "the typo beside a mention is found");
  await mention.close();

  // The popup must hear from the frame that holds the editor, not only from the top page.
  const framed = await open("frame");
  await framed.frameLocator("#f").locator("body").click();
  await framed.waitForTimeout(1500);
  status = await statusOf(framed);
  expect(status?.editor && status.issues >= 1, "the status comes from the frame with the editor");
  await framed.close();
  const blank = await open("blank-frame");
  await blank.frameLocator("#f").locator("body").click();
  await blank.waitForTimeout(1500);
  status = await statusOf(blank);
  expect(status?.editor && status.engine && status.issues >= 1, "a frame without an address gets the word list too");
  await blank.close();

  // Focus set by the page starts the local check, but no request to the model.
  asked = (await sentences()).length;
  const auto = await open("autofocus");
  await auto.waitForTimeout(1500);
  status = await statusOf(auto);
  expect(status?.editor && status.issues >= 1, "focus set by the page: the local check runs");
  expect((await sentences()).length === asked, "focus set by the page: nothing goes to the model");
  await auto.keyboard.press("ArrowRight");
  await auto.waitForTimeout(1200);
  expect((await sentences()).length > asked, "after a key press the sentence goes to the model");
  // The page hides Nib's overlay with a style: Nib restores its own style.
  await auto.evaluate(() => { document.querySelector("[data-nib-root]").style.setProperty("display", "none", "important"); });
  await auto.waitForTimeout(300);
  expect(await auto.evaluate(() => getComputedStyle(document.querySelector("[data-nib-root]")).display !== "none"),
    "the overlay shows again after the page hid it");
  await auto.close();

  const busy = await open("busy");
  await busy.click("#e");
  await busy.waitForTimeout(1500);
  expect((await statusOf(busy))?.issues >= 1, "an editor that rebuilds its nodes keeps its suggestions");
  await busy.close();

  // An answer belongs to the request with the same id, and to nothing else.
  const model = await open("plain");
  await model.click("#t");
  await model.keyboard.press("ArrowRight");
  await model.waitForTimeout(1200);
  const pending = await worker.evaluate(() => {
    const request = fake.sent.filter(message => message.text?.startsWith("I recieved the report")).at(-1);
    const before = waiting.size;
    fake.deliver({ id: 987654321, status: "model", replacement: "WRONG" });
    fake.deliver({ status: "model", replacement: "WRONG" });
    return { id: request?.id, before, after: waiting.size };
  });
  expect(pending.id && pending.before === pending.after, "an answer with an unknown id settles no request");
  await worker.evaluate(id => fake.deliver({ id, status: "model", replacement: "I received the report from Anna yesterday." }), pending.id);
  await model.waitForTimeout(700);
  expect((await statusOf(model))?.model === "on", "a real answer shows the model as connected");
  // The page removes Nib's overlay: Nib puts it back, but not for ever.
  const overlays = () => model.evaluate(() => document.querySelectorAll("[data-nib-root]").length);
  for (let round = 1; round <= 3; round++) {
    await model.evaluate(() => document.querySelector("[data-nib-root]")?.remove());
    await model.waitForTimeout(300);
    expect(await overlays() === 1, "the overlay comes back after the page removed it, time " + round);
  }
  await model.evaluate(() => document.querySelector("[data-nib-root]")?.remove());
  await model.waitForTimeout(300);
  expect(await overlays() === 0, "after three times Nib leaves the overlay removed");
  await model.close();

  // The same sentence on another site is asked again: one site must not learn what another site wrote.
  const sameText = () => worker.evaluate(() => fake.sent.filter(message => message.text?.startsWith("I recieved the report from Anna")).length);
  const count = await sameText();
  const other = await open("plain", url.replace("127.0.0.1", "localhost"));
  await other.click("#t");
  await other.keyboard.press("ArrowRight");
  await other.waitForTimeout(1200);
  expect(await sameText() === count + 1, "an answer for one site is not reused for another site");
  // An answer that is no answer does not show the model as connected.
  await worker.evaluate(() => fake.deliver({ id: fake.sent.filter(message => message.text).at(-1).id, status: "invalid" }));
  await other.waitForTimeout(700);
  expect((await statusOf(other))?.model !== "on", "an invalid answer does not count as a connection");
  await other.keyboard.press("End");
  await other.keyboard.type(" This are bad.");
  await other.waitForTimeout(1200);
  await worker.evaluate(() => settle(fake.sent.filter(message => message.text).at(-1).id, { status: "timeout" }));
  await other.waitForTimeout(700);
  expect((await statusOf(other))?.model !== "on", "a timeout does not count as a connection");
  await other.close();

  // The troubleshooting log is off until the user turns it on. Then it holds page structure, never text.
  expect((await logLines()).length === 0, "nothing is logged while the setting is off: " + (await logLines()).slice(0, 3).join(" | "));
  expect((await toMac()).length === 0, "no log line goes to the Mac while the setting is off");
  await worker.evaluate(() => chrome.storage.local.set({ log: true }));
  const logged = await open("log");
  await logged.click("#b");
  await logged.click("#t");
  await logged.keyboard.type("I recieved it");
  await logged.waitForTimeout(1200);
  const lines = await logLines();
  expect(lines.some(line => line.startsWith("focus textarea.fine-class.two")), "with the setting on, a focused text field is logged: " + lines.join(" | "));
  expect(lines.some(line => /^checked \d+ characters: 1 suggestions$/.test(line)), "with the setting on, the check is logged");
  expect(lines.every(line => /^(?:focus [a-z0-9.\[\]=> _-]+|checked \d+ characters: \d+ suggestions|hidden: [a-z0-9 ()]+)$/i.test(line) &&
    !/started|button|three|secret|private|role/i.test(line)), "log lines hold only cleaned page structure: " + lines.join(" | "));
  expect((await toMac()).length === lines.length, "with the setting on, the lines go to the Mac");
  await worker.evaluate(() => chrome.storage.local.set({ log: false }));
  await logged.close();
  // Google Docs draws its text as a picture, so Nib cannot read it. From a user report: nothing showed there,
  // and the user could not know why. The page must show a hint. Another page must not.
  // The stand-in page has what the real one has: a canvas, the hidden frame that takes the key presses,
  // and a plain text field in the top page, as a comment box is. The text of the document comes from
  // the export address, which the worker asks for. No request here reaches the network.
  const exported = { count: 0, last: "", reply: { status: 200, contentType: "text/plain; charset=utf-8", body: "" } };
  await context.route("https://docs.google.com/**", route => {
    const address = route.request().url();
    if (address.includes("/export")) {
      exported.count++;
      exported.last = address;
      return exported.reply === "abort" ? route.abort() : route.fulfill(exported.reply);
    }
    return route.fulfill({ contentType: "text/html", body: `<!doctype html><meta charset=utf-8><title>Untitled document</title>
      <canvas width=600 height=300></canvas><br><textarea id=top style="width:400px;height:80px"></textarea><br>
      <iframe class="docs-texteventtarget-iframe" style="width:400px;height:60px"
        srcdoc="<div contenteditable=true id=t>I recieved teh text</div>"></iframe>` });
  });
  const docs = await context.newPage();
  docs.on("pageerror", error => errors.push(error.message));
  await docs.goto("https://docs.google.com/spreadsheets/d/test/edit");
  await docs.waitForTimeout(1200);
  expect(await docs.evaluate(() => document.querySelectorAll("[data-nib-hint]").length) === 1, "Google Sheets: the page shows one hint");
  expect(await docs.evaluate(() => document.querySelectorAll("[data-nib-docs]").length) === 0, "Google Sheets: no Check document button");
  const docsStatus = (await worker.evaluate(async () => {
    const out = [];
    for (const tab of await chrome.tabs.query({})) {
      try { out.push(await chrome.tabs.sendMessage(tab.id, { type: "nib:status" })); } catch { /* browser pages */ }
    }
    return out;
  })).find(answer => answer?.unsupported);
  expect(docsStatus?.unsupported === "Google Docs" && !docsStatus.docsPanel, "Google Sheets: the status for the popup names it, without the panel");
  // The hint closes for good: after the close button and a reload it stays away.
  const close = await docs.evaluate(() => {
    const box = document.querySelector("[data-nib-hint]").getBoundingClientRect();
    return [box.right - 16, box.top + 16];
  });
  await docs.mouse.click(close[0], close[1]);
  await docs.waitForTimeout(400);
  await docs.reload();
  await docs.waitForTimeout(1200);
  expect(await docs.evaluate(() => document.querySelectorAll("[data-nib-hint]").length) === 0, "Google Docs: a closed hint stays closed");
  await docs.close();
  const plain = await context.newPage();
  await plain.goto(url);
  await plain.waitForTimeout(800);
  expect(await plain.evaluate(() => document.querySelectorAll("[data-nib-hint], [data-nib-docs]").length) === 0, "a normal page shows no hint and no Check document button");
  await plain.close();

  // A Google Docs document gets a button that reads the text of the document and lists what Nib finds.
  // The closed note of the test above (hint:Google Docs = false) must not hide it.
  expect((await worker.evaluate(() => chrome.storage.local.get("hint:Google Docs")))["hint:Google Docs"] === false, "the note is closed for good in storage");
  // The stand-in for the Mac model answers at once: one sentence gets a fix, every other one is fine.
  await worker.evaluate(() => {
    globalThis.auto = { "She go to the office every day.": "She goes to the office every day." };
    fake.postMessage = message => {
      fake.sent.push(message);
      if (fake.broken) throw new Error("no Mac app");
      if (message.text) setTimeout(() => fake.deliver({ id: message.id, ...(auto[message.text] ?
        { status: "model", replacement: auto[message.text] } : { status: "no-change" }) }), 3);
    };
  });
  await context.grantPermissions(["clipboard-read", "clipboard-write"], { origin: "https://docs.google.com" });
  const doc = await context.newPage();
  doc.on("pageerror", error => errors.push(error.message));
  await doc.goto("https://docs.google.com/document/d/test/edit");
  await doc.waitForTimeout(1200);
  const marks = () => doc.evaluate(() => [document.querySelectorAll("[data-nib-docs]").length, document.querySelectorAll("[data-nib-hint]").length]);
  expect((await marks()).join() === "1,0", "Google Docs document: one Check document button and no note: " + await marks());
  // Nib's button and panel live in a closed shadow root. The page cannot look inside, an extension script can.
  const peek = (act = "") => worker.evaluate(async ([address, act]) => {
    const tab = (await chrome.tabs.query({})).find(item => item.url === address);
    const [out] = await chrome.scripting.executeScript({ target: { tabId: tab.id }, args: [act], func: act => {
      const host = document.querySelector("[data-nib-docs]");
      const root = host && chrome.dom.openOrClosedShadowRoot(host);
      if (!root) return null;
      const middle = node => { const box = node.getBoundingClientRect(); return [Math.round(box.left + box.width / 2), Math.round(box.top + box.height / 2)]; };
      // A click made by a script, on the real button.
      if (act === "untrusted") root.querySelector(".pill").click();
      const panel = root.querySelector(".panel");
      const buttons = scope => Object.fromEntries([...scope.querySelectorAll("button")].map(button => [button.textContent, middle(button)]));
      return { pill: middle(root.querySelector(".pill")), pillText: root.querySelector(".pill").textContent, hide: middle(root.querySelector(".hide")),
        box: host.getBoundingClientRect().toJSON(), open: !panel.hidden, role: panel.getAttribute("role"), label: panel.getAttribute("aria-label"),
        labelled: [...root.querySelectorAll("button")].every(button => button.getAttribute("aria-label")),
        intro: root.querySelector(".intro")?.textContent ?? "", status: root.querySelector(".status")?.textContent ?? "",
        notes: [...root.querySelectorAll(".note")].map(note => note.textContent), head: buttons(root.querySelector(".head") ?? root),
        html: [...root.querySelectorAll(".sentence")].map(node => node.innerHTML),
        cards: [...root.querySelectorAll(".card")].map(card => ({ kind: card.querySelector(".kind").textContent,
          text: card.querySelector(".sentence").textContent, old: card.querySelector("s")?.textContent ?? "",
          fresh: card.querySelector("strong")?.textContent ?? "", buttons: buttons(card) })) };
    } });
    return out.result;
  }, [doc.url(), act]);
  const until = async (state, limit = 15000) => {
    for (const end = Date.now() + limit; Date.now() < end;) {
      const answer = await statusOf(doc);
      if (answer?.docs?.state === state) return answer;
      await doc.waitForTimeout(150);
    }
    return await statusOf(doc);
  };
  status = await statusOf(doc);
  expect(status?.unsupported === "Google Docs" && status.docsPanel === true && status.docs?.state === "idle",
    "Google Docs document: the status names the panel: " + JSON.stringify(status));
  let seenPanel = await peek();
  expect(seenPanel?.pillText === "Check document" && !seenPanel.open, "the button says Check document and the panel is closed");
  const [wide, high] = await doc.evaluate(() => [innerWidth, innerHeight]);
  expect(seenPanel && Math.round(wide - seenPanel.box.right) === 16 && Math.round(high - seenPanel.box.bottom) === 16, "the button sits 16 px from the lower right corner");

  // Google Docs takes the key presses in a hidden frame. From a user report: Nib took that frame for a text
  // field, so the popup said "Nib is checking this text field" and junk text could go to the model.
  const keyFrame = doc.frames().find(frame => frame !== doc.mainFrame());
  const macTexts = () => worker.evaluate(() => fake.sent.filter(message => message.text).map(message => message.text));
  asked = (await macTexts()).length;
  await keyFrame.click("#t");
  await doc.keyboard.press("End");
  await doc.keyboard.type(" that I typed now.");
  await doc.waitForTimeout(1500);
  status = await statusOf(doc);
  expect(status?.unsupported === "Google Docs" && status.docsPanel === true && !status.editor,
    "the key press frame of Google Docs is no text field for the popup: " + JSON.stringify(status));
  expect(await keyFrame.evaluate(() => document.querySelectorAll("[data-nib-root]").length) === 0, "no Nib overlay in the key press frame");
  expect((await macTexts()).length === asked, "nothing from the key press frame goes to the model: " + (await macTexts()).slice(asked).join(" | "));
  await doc.click("#top");
  await doc.keyboard.type("I recieved it");
  await doc.waitForTimeout(1200);
  status = await statusOf(doc);
  expect(status?.editor && status.issues === 1, "a plain text field in the top page of Google Docs is still checked");
  await doc.mouse.click(900, 100);

  // Only a click by the user reads the document.
  await doc.evaluate(() => document.querySelector("[data-nib-docs]").click());
  await peek("untrusted");
  await doc.waitForTimeout(600);
  expect(exported.count === 0 && (await statusOf(doc))?.docs?.state === "idle", "a click made by a script does not read the document");

  exported.reply.body = "﻿I recieved the report from Anna.\r\nShe go to the office every day.\r\nThis sentence is fine.\r\n";
  await doc.bringToFront();
  asked = (await macTexts()).length;
  await doc.mouse.click(...seenPanel.pill);
  status = await until("done");
  expect(exported.count === 1 && exported.last === "https://docs.google.com/document/d/test/export?format=txt", "one request for the text: " + exported.last);
  expect(status?.docs?.sentences === 3 && status.docs.checked === 3 && status.docs.issues === 2 && !status.docs.cut,
    "three sentences are checked and two have a fix: " + JSON.stringify(status?.docs));
  seenPanel = await peek();
  expect(seenPanel.open && seenPanel.role === "dialog" && seenPanel.label === "Nib: check document" && seenPanel.labelled, "the panel is a labelled dialog with labelled buttons");
  expect(seenPanel.intro.startsWith("Google Docs draws its text as a picture") && seenPanel.intro.endsWith("You make the changes in the document."), "the panel explains itself: " + seenPanel.intro);
  expect(seenPanel.cards.length === 2 && seenPanel.cards[0].kind === "Spelling" && seenPanel.cards[0].old === "recieved" && seenPanel.cards[0].fresh === "received" &&
    seenPanel.cards[0].text === "I recieved received the report from Anna.", "a spelling card for recieved: " + JSON.stringify(seenPanel.cards[0]));
  expect(seenPanel.cards[1]?.kind === "Grammar" && seenPanel.cards[1].fresh.includes("goes") && seenPanel.cards[1].old.includes("go"), "a grammar card from the model with goes: " + JSON.stringify(seenPanel.cards[1]));
  expect(seenPanel.html[0].replace(/ style="color: rgb\(219, 82, 100\);"/, "") === "I <s>recieved</s> <strong>received</strong> the report from Anna.", "the old word is struck and the new one is bold: " + seenPanel.html[0]);
  expect(/^2 suggestions/.test(seenPanel.status), "the panel says what it found: " + seenPanel.status);
  expect((await macTexts()).slice(asked).join("|") === "I recieved the report from Anna.|She go to the office every day.|This sentence is fine.", "the sentences go to the model in order, one each");
  await doc.mouse.click(...seenPanel.cards[0].buttons["Copy fix"]);
  await doc.waitForTimeout(300);
  expect(await doc.evaluate(() => navigator.clipboard.readText()) === "I received the report from Anna.", "Copy fix puts the corrected sentence on the clipboard");
  expect((await peek()).cards[0].buttons.Copied, "the button says Copied");
  await doc.mouse.click(...seenPanel.cards[1].buttons["Copy fix"]);
  await doc.waitForTimeout(300);
  expect(await doc.evaluate(() => navigator.clipboard.readText()) === "She goes to the office every day.", "Copy fix of the model card copies the sentence of the model");
  await doc.mouse.click(...seenPanel.cards[1].buttons.Ignore);
  await doc.waitForTimeout(300);
  seenPanel = await peek();
  expect(seenPanel.cards.length === 1 && (await statusOf(doc)).docs.issues === 1, "Ignore removes the card");
  expect(seenPanel.cards[0].buttons["Add to dictionary"], "a spelling card offers the dictionary");
  await doc.keyboard.press("Escape");
  await doc.waitForTimeout(300);
  expect(!(await peek()).open && (await statusOf(doc)).docs.state === "idle", "Escape closes the panel");

  // After an update the page script starts again: one button remains, and the old panel is gone.
  await doc.mouse.click(...seenPanel.pill);
  await until("done");
  await worker.evaluate(() => startInOpenTabs());
  await doc.waitForTimeout(1000);
  expect((await marks()).join() === "1,0", "a second start of the page script leaves one button");
  expect(!(await peek()).open && (await statusOf(doc)).docs.state === "idle", "a second start of the page script closes the old panel");

  // No access, or the sign-in page in place of the text: the panel says so and shows no card.
  for (const [name, reply] of [["401", { status: 401, contentType: "text/html", body: "<html>no</html>" }],
    ["a sign-in page", { status: 200, contentType: "text/html; charset=utf-8", body: "<!doctype html><title>Sign in</title>" }]]) {
    exported.reply = reply;
    await doc.mouse.click(...seenPanel.pill);
    status = await until("error");
    seenPanel = await peek();
    expect(status?.docs?.state === "error" && seenPanel.cards.length === 0 &&
      seenPanel.status === "Nib could not read this document. Open it in a browser where you are signed in to Google.", name + ": an error and no card: " + seenPanel.status);
  }
  exported.reply = "abort";
  await doc.mouse.click(...seenPanel.pill);
  await until("error");
  expect((await peek()).status === "Nib could not read this document. Try again.", "a network error asks to try again: " + (await peek()).status);
  exported.reply = { status: 200, contentType: "text/plain; charset=utf-8", body: "﻿\r\n \r\n" };
  await doc.mouse.click(...(await peek()).head["Check again"]);
  await until("done");
  expect((await peek()).status === "This document has no text.", "an empty document: " + (await peek()).status);
  exported.reply.body = "This sentence is fine.\r\n";
  await doc.mouse.click(...seenPanel.pill);
  await until("done");
  expect((await peek()).status === "No suggestions. Nib checked 1 sentence.", "nothing found: " + (await peek()).status);

  // A long document: the first 60,000 characters are checked, and the model sees the first 150 sentences.
  exported.reply.body = "This sentence is fine.\r\n".repeat(3000) + "I recieved it.\r\n";
  asked = (await macTexts()).length;
  await doc.mouse.click(...seenPanel.pill);
  status = await until("done", 40000);
  seenPanel = await peek();
  expect(status?.docs?.cut === true && status.docs.chars <= 60000 && status.docs.chars > 59000 && status.docs.issues === 0,
    "a long document is cut at 60,000 characters: " + JSON.stringify(status?.docs));
  expect(seenPanel.notes.includes("Nib checked the first part of this long document."), "the panel says that the document was cut: " + seenPanel.notes.join(" | "));
  expect(status?.docs?.capped === true && seenPanel.notes.some(note => note.includes("150")), "the panel says that the model saw the first 150 sentences");
  expect((await macTexts()).length - asked <= 150, "at most 150 sentences go to the model: " + ((await macTexts()).length - asked));

  // The Mac app is away: the local results stay, and one line says what is missing.
  exported.reply.body = "I recieved a new report from Berlin.\r\n";
  await worker.evaluate(() => { fake.broken = true; });
  await doc.mouse.click(...seenPanel.pill);
  status = await until("done");
  seenPanel = await peek();
  expect(status?.docs?.issues === 1 && seenPanel.notes.includes("Sentence fixes need the Nib app on this Mac: in Nib, choose More → Connect Browsers…"),
    "without the Mac app the local results show with one line: " + seenPanel.notes.join(" | "));
  await worker.evaluate(() => { fake.broken = false; });

  // The page moves to another document without a reload: the panel closes, and the next check reads the new one.
  await doc.evaluate(() => history.pushState({}, "", "/document/u/1/d/other-2/edit"));
  await doc.waitForTimeout(400);
  expect(!(await peek()).open, "the panel closes when the page moves to another document");
  await doc.mouse.click(...seenPanel.pill);
  await until("done");
  expect(exported.last === "https://docs.google.com/document/u/1/d/other-2/export?format=txt", "the text comes from the new address: " + exported.last);

  // The × beside the button hides it for this page view.
  await doc.mouse.click(...seenPanel.hide);
  await doc.waitForTimeout(300);
  expect((await marks()).join() === "0,0", "the × hides the button");
  await doc.close();

  // The log gets one line for the button and one for each run, never text.
  await worker.evaluate(() => chrome.storage.local.set({ log: true }));
  const before2 = (await logLines()).length;
  exported.reply.body = "I recieved the report from Anna.\r\n";
  const logDoc = await context.newPage();
  await logDoc.goto("https://docs.google.com/document/d/test/edit");
  await logDoc.waitForTimeout(1200);
  await logDoc.mouse.click(...seenPanel.pill);
  await logDoc.waitForTimeout(1500);
  exported.reply = { status: 403, contentType: "text/html", body: "no" };
  await logDoc.mouse.click(...seenPanel.pill);
  await logDoc.waitForTimeout(1000);
  const docLines = (await logLines()).slice(before2);
  expect(docLines.join(" | ") === "docs: check button shown | docs: checked 1 sentences: 1 suggestions | docs: could not read the document (403)",
    "the log lines of a document: " + docLines.join(" | "));
  await worker.evaluate(() => chrome.storage.local.set({ log: false }));
  await logDoc.close();

  expect(errors.length === 0, "no page errors: " + errors.join("; "));
} finally {
  await context.close();
  server.close();
  fs.rmSync(profile, { recursive: true, force: true });
}
console.log(failed ? `extension test: ${failed} failed` : "extension test: passed");
process.exit(failed ? 1 : 0);
