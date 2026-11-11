"use strict";

// One long-lived connection to the Mac companion. The companion keeps its model warm between sentences.
const host = "com.nib.bridge";
const waiting = new Map();
const cache = new Map();
let port = null;
let nextId = 1;
let idleTimer = 0;

function settle(id, result) {
  const entry = waiting.get(id);
  if (!entry) return;
  waiting.delete(id);
  clearTimeout(entry.timer);
  if (result.status === "model" || result.status === "no-change" || result.status === "improve") {
    if (cache.size >= 400) cache.delete(cache.keys().next().value);
    cache.set(entry.text, result);
  }
  entry.reply(result);
}

function connect() {
  if (port) return port;
  try {
    port = chrome.runtime.connectNative(host);
  } catch {
    return null;
  }
  port.onMessage.addListener(message => {
    if (message?.status === "logged") return;
    // An answer without a waiting id is late: its request timed out. It must not become the answer
    // to another request, which can belong to another site.
    if (waiting.has(message?.id)) settle(message.id, { status: String(message?.status), replacement: message?.replacement });
  });
  port.onDisconnect.addListener(() => {
    void chrome.runtime.lastError;
    port = null;
    for (const id of [...waiting.keys()]) settle(id, { status: "disconnected" });
  });
  return port;
}

// Release the companion process after two quiet minutes. Log lines count as use too.
function armIdleTimer() {
  clearTimeout(idleTimer);
  idleTimer = setTimeout(() => {
    if (!waiting.size && port) {
      port.disconnect();
      port = null;
    }
  }, 120000);
}

function originOf(sender) {
  try { return sender.origin || new URL(sender.url || sender.tab?.url || "").origin; } catch { return ""; }
}

chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (message?.type !== "nib:sentence" || !sender.tab || typeof message.text !== "string" ||
      message.text.length > 600 || !message.text.trim()) return;
  const before = typeof message.before === "string" && message.before.length <= 400 ? message.before : "";
  // An improvement request asks about style. It has its own cache entry.
  const improve = message.improve === true;
  // The site is part of the key: a page must not learn from a fast answer what another site wrote.
  const key = originOf(sender) + "\u0000" + message.text + "\u0001" + before + (improve ? "\u0002improve" : "");
  const known = cache.get(key);
  if (known) {
    reply(known);
    return;
  }
  const channel = connect();
  if (!channel) {
    reply({ status: "disconnected" });
    return;
  }
  const id = nextId++;
  waiting.set(id, { text: key, reply, timer: setTimeout(() => settle(id, { status: "timeout" }), 30000) });
  try {
    channel.postMessage({ id, text: message.text, ...(before ? { before } : {}), ...(improve ? { improve: true } : {}) });
  } catch {
    settle(id, { status: "disconnected" });
  }
  armIdleTimer();
  return true;
});

// A page loads only the small page script. The word list and the checker follow when the user enters
// a text field, and only in that frame: the list is large, and most frames never need it.
const engineScripts = ["words.js", "engine.js", "sentences.js"];
chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (message?.type !== "nib:engine" || !sender.tab) return;
  // The document id names this very page. A frame id alone could meet the next page after a navigation.
  const target = sender.documentId ? { tabId: sender.tab.id, documentIds: [sender.documentId] } :
    { tabId: sender.tab.id, frameIds: [sender.frameId ?? 0] };
  chrome.scripting.executeScript({ target, files: engineScripts })
    .then(() => reply({ ok: true }), () => reply({ ok: false }));
  return true;
});

// Google Docs draws a document as a picture. Its plain text comes from the export address of the document.
// The worker reads it, not the page: the answer is a redirect to another Google host, which a page script
// may not follow with the user's cookies, and which leads to the sign-in page when the user has no access.
// The page script sends this only after a real click on "Check document". The address can only be
// the export of a document on docs.google.com, asked by the top page of a tab on that site.
const docsExport = /^\/document\/(?:u\/\d+\/)?d\/[\w-]+\/export\?format=txt$/;
chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (message?.type !== "nib:docs" || !sender.tab || sender.frameId !== 0 || typeof message.path !== "string" ||
      originOf(sender) !== "https://docs.google.com" || !docsExport.test(message.path)) return;
  (async () => {
    try {
      const response = await fetch("https://docs.google.com" + message.path,
        { credentials: "include", cache: "no-store", signal: AbortSignal.timeout(30000) });
      // Without access the answer is 401 or 403, or the sign-in page: a web page, not plain text.
      const plain = /^text\/plain\b/i.test(response.headers.get("content-type") || "");
      if (!response.ok || !plain) return reply({ status: "denied", code: response.ok ? "sign-in page" : String(response.status) });
      const text = await response.text();
      // The page checks the first part of a long document. The rest need not cross to the page.
      reply({ status: "ok", text: text.slice(0, 200000), more: text.length > 200000 });
    } catch {
      reply({ status: "network" });
    }
  })();
  return true;
});

// Tabs that were open before Nib was installed or updated have no Nib in them. Start it there.
// The new page script stops the old copy in the page first.
const pageScripts = ["content.js"];
async function startInOpenTabs() {
  // Without the "tabs" permission a query by address finds nothing, so ask every tab. Browser pages refuse.
  const tabs = await chrome.tabs.query({});
  await Promise.all(tabs.map(tab => chrome.scripting.executeScript({ target: { tabId: tab.id, allFrames: true }, files: pageScripts })
    .catch(() => {})));
}
chrome.runtime.onInstalled.addListener(details => {
  // This event also comes when the browser itself updates. The pages still hold a working Nib then.
  if (details.reason === "install" || details.reason === "update") startInOpenTabs();
});

// Lines for ~/Library/Logs/Nib-browser.log on the Mac. Page structure only, never text.
// The log shows which sites the user visits, so it is off until the user turns it on in the popup.
async function log(line) {
  let wanted = false;
  try { wanted = (await chrome.storage.local.get("log")).log === true; } catch { /* no settings */ }
  if (!wanted) return;
  const channel = connect();
  try {
    channel?.postMessage({ id: nextId++, log: "extension " + chrome.runtime.getManifest().version + ": " + line });
  } catch { /* the Mac app is not connected */ }
  // Without this, a session that only logs would keep the companion process for ever.
  if (channel) armIdleTimer();
}
chrome.runtime.onInstalled.addListener(details => { log("installed or updated (" + details.reason + ")"); });
chrome.runtime.onStartup.addListener(() => { log("browser started"); });
chrome.runtime.onMessage.addListener((message, sender) => {
  // Private windows leave no trace in the log.
  if (message?.type !== "nib:log" || typeof message.line !== "string" || !sender.tab || sender.tab.incognito) return;
  let origin = "?";
  try { origin = new URL(sender.url || sender.tab.url || "").host || "?"; } catch { /* no address */ }
  log(origin + (sender.frameId ? " frame " + sender.frameId : "") + ": " + message.line.slice(0, 240));
});
