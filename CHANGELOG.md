# Changelog

## Unreleased

- Nib works in Signal Desktop. Signal, an Electron app, showed no text to Nib, because it ignores the switch that Nib sends to Electron apps. Nib now sends a second switch, the one that VoiceOver uses, once to an Electron app that still shows nothing after one second. Other apps get no change.
- The diagnosis says if the app in front is an Electron app, and if Nib sent it the second switch.

## 0.2.3

- **Check document** for Google Docs. Docs draws its text as a picture, so Nib cannot check there while you type. A button at the lower right of a document now reads the text of the document and lists the fixes in a panel. You copy a fix and make the change in the document yourself.
- Fixed: on a Google document the popup said "Nib is checking this text field: no suggestions". Nib took the hidden input box of Docs for a text field. It now leaves that box alone, and the popup points to **Check document**.
- Fixed: the browser checker marked many common words as spelling errors, for example "using" (it offered "suing"), "box", "earlier" and "database". About 880 common words are added, and endings such as "taller" and "nicest" count as correct. In 1.5 million words of correct English, the share of wrong marks fell from 2.5 % to 0.8 %. The rest is mostly project jargon.

## 0.2.2

- Fixed: in dark mode, text that came into the Nib editor from another app was black on a dark window, and smaller than typed text.

## 0.2.1

- Fixed: Nib did not refresh the browser extension folder when a new build had the same version number. The browser then kept old extension files. Nib now compares the files.

## 0.2.0

A review of the whole code before the project goes public. Three independent reviews found the points below. Each fix has a test where a test is possible.

**Privacy and safety**
- The shortcuts for proofread, rewrite, read aloud and the editor no longer work in never-checked apps and in password fields. Before, a shortcut in a password manager could copy a password.
- The never-checked list now also holds more password managers, more code editors and remote desktop tools.
- The browser troubleshooting log is off by default, has a switch in the popup, and never writes from private windows. Its lines hold only plain tag, class and role names.
- The extension skips a password field also after a "show password" button, and it knows the word for password in more languages.
- The extension asks the model only after you type in a field.
- An answer from the Mac helper that arrives late is dropped. Before, it could become the suggestion for another sentence.
- The local model server cannot send your text on to another machine through a redirect.
- The installer script no longer signs with a personal development certificate.
- The installer window now shows the steps for the first launch: what to do when macOS says that it cannot open Nib. A link in the window opens the right page of System Settings.
- The installer image no longer holds the folder path and user name of the Mac that built it. The script checks each image for them and stops if it finds one.

**Fewer wrong suggestions**
- Fixed rules that changed correct sentences are narrowed or removed. "Does she have the keys?" no longer becomes "has".
- The guard no longer accepts an answer that flips a negation, swaps a look-alike word such as "legal" and "illegal", changes a number word or a time, changes a name, or replaces a short sentence.
- Improvement suggestions keep the order of names and numbers.
- English rules no longer run on text in other languages in the Mac app.
- In the browser, English text with typos or accented names keeps its checks. Short sentences in more languages get no English marks.
- The cost: some correct fixes are refused now, such as two typos in a very short sentence.

**Reliability**
- A fix counts as applied only when the text field holds the expected text. The clipboard comes back only after the paste arrived. A failed fix puts the caret back.
- Copy and paste use the keys of your keyboard layout.
- Snippets no longer retry in a loop, and expand only right after you type them.
- A slow rewrite no longer stops the live checks after you change the app.
- Tab and Esc are taken only for a suggestion at the caret.
- Settings no longer overwrite a word that **Never Change** added while the window was open. Dictionary words keep their capital letters.
- The browser helper now uses the model, dictionary and instructions that you set in the app. Before, it always used Apple's model.
- The helper answers every request with its id, has a time limit for each request, and survives a message that is too large.

**New**
- In Google Docs, Sheets and Slides the extension shows a note that says why Nib is silent there and what to do. Before, nothing showed. The popup says the same.
- **Add to Browser** in the setup guide does every step that a browser permits: it connects the helper, opens the Extensions page and shows the extension folder beside it. The drag onto the page stays with the user.
- **Show Extension Folder** now opens a normal folder that you can drag into the browser. Before, it pointed into the app, where Finder showed nothing. Nib updates this folder with each new version of the app.
- The setup guide has a step to choose the model: Apple's on-device model, or a model from Ollama or LM Studio on this Mac.
- The extension loads its word list only when you click into a text field. Before, it loaded into every frame of every page.
- `bash Source/test.sh --browser` runs only the browser tests. The scoring run now fails on a false alarm or a harmful change.
- A new list of 30 labelled sentences that nobody tuned on.

**For contributors**
- `Desktop.swift` is split into ten files by job.
- New files: `CONTRIBUTING.md`, `SECURITY.md`, `PRIVACY.md`, `NOTICE.md`, issue and pull request templates, and a GitHub workflow for the tests.
- `install.sh` with a target folder installs only `Nib.app` there.

## 0.1.7

- Fixed: in 0.1.6 a click on the suggestion count in the browser closed Nib instead of opening the list.
- The list of suggestions is no longer cut off by dialogs that hide their overflow, such as the LinkedIn draft box.
- The extension test now clicks the count in such a dialog and expects the list.

## 0.1.6

- Nib works in modal dialogs, such as the LinkedIn draft box. Before, its marks and suggestions were drawn behind the dialog and could not be clicked.
- The extension popup says whether Nib runs on the page: running, paused, not running (reload the page), and if the Mac model is connected. It also shows the version.
- After you install or update the extension, Nib starts by itself in the tabs that are already open. Before, those tabs had no working Nib until you reloaded them. If Nib still does not run on a page, the popup starts it, or says that the browser blocks the site.
- Fixed: a change in this version stopped Nib from seeing focus and typing in editors that stop events, as many do. A test now covers such a page.
- Nib reaches text fields inside closed shadow roots.
- A troubleshooting log for the browser at `~/Library/Logs/Nib-browser.log`. It holds page structure and counts only, never your text.
- The browser checker no longer marks `has`, `heard`, `paid`, `began` and other short or irregular words as spelling errors.

## 0.1.5

- Improvement suggestions for sentences that have no error: Nib removes filler words or puts the words in a more natural order. A star and a green line mark a suggestion, so it is easy to tell from a correction. A guard accepts only the writer's own words. Turn it off in **Settings… → General**, or in the extension popup.
- The browser extension shows a small check mark in a text field when it found nothing, so you see that Nib read the text. A click shows the status of the Mac model.
- **Apply All** applies corrections only.

## 0.1.4

- The browser extension no longer underlines German, French, Spanish or other non-English text as wrong. It finds the language of each sentence and applies its English checks to English sentences only.
- Fixes for other languages come from the sentence model on the Mac, in the language of the text.
- The Mac spell checker now gets the detected language of a sentence, so it uses the right dictionary for short text.
- The MIT license.

## 0.1.3

- A shorter menu. It names the app in front, says what Nib sees there, and keeps less common commands under **More**.
- A setup guide on the first launch, for the permission and the browser extension.
- An installer disk image: `bash Source/make-dmg.sh`.
- The browser extension is now also inside the app.

## 0.1.2

- All file names and internal ids now use the name Nib. The app id is `com.nib.desktop`. macOS asks for the Accessibility permission one more time after this update.
- The icon is at the top of the README.
- `open -g nib://diagnose` saves the diagnosis and shows no window.

## 0.1.1

- A new icon, the tip of a fountain pen, for the app, the menu bar and the browser extension. One drawing in `Source/Icon.swift` makes all of them.

## 0.1.0

The first release.

**Checks**
- Live suggestions in most desktop apps, including Electron apps, Safari and Firefox, and in Chromium browsers through the extension.
- Sentence checks with Apple's on-device model, the macOS spell checker and fixed rules. The model reads the previous sentence as context.
- A guard that rejects rewrites: synonyms, expanded contractions, cleaned-up slang, changed numbers and links.
- An underline under every issue in the focused text field, and **Apply All**.
- An optional larger model from Ollama or LM Studio on the same Mac.

**Tools**
- Explain a fix in one sentence.
- Rewrite selected text (Clearer, Shorter, More Professional, Friendlier) and translate it, with a preview.
- A floating editor for apps that Nib cannot read: check, rewrite, translate, speak and paste back.
- Read the selection aloud.
- Snippets: type `\\name` and a space to insert saved text.
- Autocomplete (beta): a suggestion for the rest of the sentence.

**Settings**
- A dictionary of words that are never changed.
- Custom instructions for the model, in general and per app.
- Pause on battery, optional Tab and Esc keys, open at login, and daily counts.

**For troubleshooting and development**
- A status line, Diagnose Front App and an apply log.
- Logic tests, a scoring run on labelled sentences, a render mode for layout checks, and an install script that stops at the first failure.
