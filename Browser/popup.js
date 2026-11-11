"use strict";

const enabled = document.querySelector("#enabled");
const site = document.querySelector("#site");
const style = document.querySelector("#style");
const host = document.querySelector("#host");
const error = document.querySelector("#error");

// A setting is on until the user turns it off. With optIn it is off until the user turns it on.
async function bind(input, key, inverse = false, optIn = false) {
  const settings = await chrome.storage.local.get(key);
  input.checked = optIn ? settings[key] === true : inverse ? settings[key] !== true : settings[key] !== false;
  input.disabled = false;
  input.addEventListener("change", async () => {
    error.textContent = "";
    const next = input.checked;
    input.disabled = true;
    try {
      await chrome.storage.local.set({ [key]: inverse ? !next : next });
    } catch {
      input.checked = !next;
      error.textContent = "Could not save the setting.";
    } finally {
      input.disabled = false;
    }
  });
}

async function init() {
  document.querySelector("#version").textContent = "v" + chrome.runtime.getManifest().version;
  await Promise.all([bind(enabled, "enabled"), bind(style, "style"), bind(document.querySelector("#context"), "context"),
    bind(document.querySelector("#log"), "log", false, true)]);
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  const url = tab?.url && new URL(tab.url);
  if (!url || !["http:", "https:"].includes(url.protocol)) {
    host.textContent = "Open a website to use this setting";
    return;
  }
  host.textContent = url.host;
  await bind(site, "paused:" + url.origin, true);
  await showStatus(tab);
}

// Tells the user whether Nib runs on this page. A page opened before the extension loaded has no Nib in it.
async function showStatus(tab) {
  const status = document.querySelector("#status");
  const say = (text, warn) => { status.textContent = text; status.classList.toggle("warn", warn); };
  let answer = null;
  try {
    // Every frame hears this. The frame that holds the text field answers first, the top page a moment later.
    answer = await chrome.tabs.sendMessage(tab.id, { type: "nib:status" });
  } catch {
    answer = null;
  }
  if (!answer?.running) {
    // Start Nib on the page now. A failure here means the browser does not let Nib read this site.
    try {
      // The page script alone: it asks for the word list when the user enters a text field.
      await chrome.scripting.executeScript({ target: { tabId: tab.id, allFrames: true }, files: ["content.js"] });
      return say("Nib started on this page. Click into the text field again.", false);
    } catch {
      return say("The browser does not let Nib read this site. Open the Extensions page, choose Details on Nib, and set Site access to On all sites.", true);
    }
  }
  if (!answer.enabled) return say("Nib is paused on this page.", true);
  // Google Docs and similar editors draw their text as a picture.
  if (answer.unsupported) {
    // A document has the "Check document" button in the page. Sheets and slides have no such button.
    if (answer.docsPanel) return say("Nib cannot check Google Docs as you type. Click Check document at the lower right of the page.", true);
    return say("Nib cannot read " + answer.unsupported + ". Select your text and press Control-Option-F to open it in the Nib editor.", true);
  }
  if (!answer.editor) return say("Nib runs on this page. Click into a text field.", false);
  const model = answer.model === "off" ? " The Mac model is not connected." : answer.model === "on" ? " The Mac model is connected." : "";
  say("Nib is checking this text field: " + (answer.issues ? answer.issues + (answer.issues === 1 ? " suggestion." : " suggestions.") : "no suggestions.") + model, answer.model === "off");
}
init().catch(() => { error.textContent = "Could not load the settings."; });
