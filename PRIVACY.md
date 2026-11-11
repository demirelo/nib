# Privacy policy

This policy covers the Nib app for macOS and the Nib browser extension. Nib checks grammar and spelling on your device.

## Summary

- Nib sends nothing to other machines.
- Nib has no account, no telemetry, no advertising and no cloud service.
- Nib does not save the text that you write.

## What Nib reads

**The Mac app** uses the macOS Accessibility permission. It reads the text field that has the focus in the app in front. It does not read these:

- Password fields, and every field while macOS secure input is active.
- Terminals, code editors, password managers and remote desktop tools. The commands for proofread, rewrite, read aloud and the editor also do nothing there.
- Apps in which you turned off **Check Text in This App**.

**The browser extension** has access to the text fields on all sites and in all frames. It loads its word list only when you click into a text field. It does not read these:

- Password fields, also after a "show password" button changes the field.
- Fields that are labelled as codes, keys, tokens or card numbers.
- Fields on sites that you paused in the popup.
- Fields that the site marks with `data-nib="off"`.

## Where the text goes

The Mac app checks the text in its own process, with the macOS spell checker, fixed rules and Apple's on-device model.

The extension checks spelling and fixed rules inside the page. If **Use Mac sentence model** is on, it sends sentences to the helper process `com.nib.bridge` on the same Mac. It does this only after you type in a field. The helper answers and keeps nothing. If the switch is off, no text leaves the browser.

On a Google Docs document, the extension reads the document only when you click **Check document**. It then asks Google Docs for the plain text of that document, with your own sign-in. This request goes to Google, which already holds the document. The text is checked as described above, is kept in memory while the panel is open, and is not saved.

Nib keeps drafts and suggestions in memory only for the time it needs them.

When an app needs paste to apply a fix, Nib uses the clipboard for a moment. Then it puts the old contents back.

## The optional local model server

You can tell Nib to use a model server such as Ollama or LM Studio. The server must be on this Mac. Nib accepts only a loopback address (`127.0.0.1`, `localhost` or `::1`). Nib refuses other addresses and refuses redirects. The server gets the sentences that Nib checks. What the server does with them is the responsibility of that software.

This is the only network connection that Nib makes. Without a server, Nib makes none.

## What Nib stores, and where

| Where | What |
|---|---|
| Preferences of the Mac app (domain `com.nib.desktop`) | Settings, your dictionary, snippets, instructions, per-app pauses, and daily counts of shown, applied and dismissed suggestions. The counts are numbers only. |
| Storage of the extension (`chrome.storage.local`, on this device) | Your on/off switches, paused sites, and words that you add to its dictionary. Nothing else. |
| `~/Library/Logs/Nib-apply.log` | The time, the app id and the result of each apply. No text. |
| `~/Library/Logs/Nib-diagnosis.txt` | The report of **Diagnose Front App**. No text. |
| `~/Library/Logs/Nib-browser.log` | The browser troubleshooting log. See below. |

The browser troubleshooting log is off by default. A switch in the extension popup turns it on. While it is on, the extension sends lines to the helper on this Mac, and the helper writes them to the file. A line holds the host name of the page, the tag, class and role of the focused field, and counts. A line never holds text. The extension writes no lines from private or incognito windows.

## What leaves the device

Nothing. Nib does not collect, sell or share data. The author gets no data from your use of Nib.

If you report a problem, you decide what you put in the report.

## How to delete everything

1. Quit Nib.
2. Delete the preferences: `defaults delete com.nib.desktop`
3. Delete the logs: `Nib-apply.log`, `Nib-diagnosis.txt` and `Nib-browser.log` in `~/Library/Logs`.
4. Remove the extension from the browser. This deletes its storage. Then delete the folder `~/Library/Application Support/Nib`, which holds the copy of the extension that you loaded.
5. Delete `com.nib.bridge.json` from the `NativeMessagingHosts` folder of each browser, for example `~/Library/Application Support/Google/Chrome/NativeMessagingHosts`.
6. Move `Nib.app` to the Trash. Remove **Nib** from **System Settings → Privacy & Security → Accessibility**.

## Changes and questions

Changes to this policy are recorded in the repository history. For questions, open an issue at <https://github.com/demirelo/nib/issues>.
