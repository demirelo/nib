<img src="Browser/icons/nib-128.png" width="96" alt="Nib icon: the tip of a fountain pen">

<!-- screenshot: docs/screenshot.png -->

# Nib

Private grammar and spelling suggestions for your Mac. Nib checks what you type in most desktop apps and in Chromium browsers. It runs fully on your device, so nothing you write leaves your Mac.

Type, pause for a second, and Nib shows a small button with the fix, for example `two → to`. Click it, or press **⌃⌥↩**, and the text is corrected in place.

## Features

- **Reads the sentence, not only the word.** Apple's on-device model fixes errors that a spell checker cannot see, such as `Their going to be late` and `thi sis a chapter in may life`.
- **Corrects, never rewrites.** A guard drops answers that change your wording. `gonna`, `lol` and your own words stay as you wrote them.
- **Suggests improvements** for sentences without errors: fewer filler words, a more natural word order. A star marks a suggestion, and it uses only your own words. A larger model gives better suggestions.
- **Underlines every issue** in the text field, with **Apply All** for the whole field.
- **Explains, rewrites and translates** selected text, and reads it aloud.
- **Has an editor for apps it cannot read**, such as Google Docs. Check the text there and paste it back.
- **Snippets, a personal dictionary and custom instructions**, in general and per app.
- **Optional larger model** from Ollama or LM Studio on the same Mac.

## Install

You need an Apple silicon Mac with macOS 26 or later. Turn on Apple Intelligence for the sentence model. Without it, Nib still checks spelling and fixed grammar rules.

There are two ways to install Nib. Use the installer if you only want the app. Build from source if you want to change the code.

### Option 1: Installer

1. Get `Nib-<version>.dmg` from the [Releases](https://github.com/demirelo/nib/releases) page and open it.
2. Drag **Nib** to the **Applications** folder.
3. Open Nib from Applications.

The image is not notarized by Apple, so macOS blocks the first launch with the message *"Nib" Not Opened*. Click **Done**. Then open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**. Open Nib again. The installer window shows these steps too, with a link that opens that page of System Settings.

### Option 2: Build from source

You also need the Xcode command line tools (`xcode-select --install`).

```bash
git clone https://github.com/demirelo/nib.git
cd nib
bash Source/install.sh
```

The script builds the app, runs the tests and opens `Nib.app` in the repository folder. It stops at the first failure.

### First launch

A setup guide opens. It has four steps.

1. **Permission.** Nib needs the Accessibility permission to read the text field in front and to apply a fix. Click **Allow Access…** and turn on **Nib** in the list that opens.
2. **Model.** Choose Apple's on-device model, or a larger model from Ollama or LM Studio on this Mac. You can change it later in **Settings… → Model**.
3. **Browser.** Optional, see below.
4. **Try it.**

You can open the guide again with **More → Setup Guide…**.

### Browser extension

A browser does not let an app add an extension, so one step is yours.

1. In the setup guide, click **Add to Browser**. Nib connects its helper, opens the Extensions page of your browser, and shows the folder **Nib Browser Extension** in Finder.
2. On the Extensions page, turn on **Developer mode**.
3. Drag the folder from Finder onto the page. Or click **Load unpacked** and choose it: it is in `~/Library/Application Support/Nib`.

Nib updates this folder with each new version of the app. After an update, reload the extension on the Extensions page.

The extension works in Chrome, Brave, Edge, Arc and Vivaldi. Safari and Firefox are checked by the Mac app.

- **What it can read.** The extension has access to the text fields on all sites and in all frames. It checks spelling and fixed rules inside the page.
- **Google Docs.** When you click **Check document**, the extension asks Google Docs for the plain text of that document, with your own sign-in. The text goes to the checker on your Mac and nowhere else, and Nib does not save it.
- **Sentence model.** If **Use Mac sentence model** is on, the extension sends sentences to the helper process `com.nib.bridge` on the same Mac. If it is off, no text leaves the browser.
- **Controls.** **Ignore** hides an issue in this tab. **Add to dictionary** keeps a word. **⌥⇧L** opens or closes the suggestion list. **Check this site** in the popup pauses Nib on one site.
- **For site authors.** Put `data-nib="off"` on a field, and Nib does not check it.
- **Remove the helper link.** Delete `com.nib.bridge.json` from the `NativeMessagingHosts` folder of the browser, under `~/Library/Application Support/`.

## Use

| Action | How |
|---|---|
| Apply the suggestion | Click it, or press **⌃⌥↩** |
| Dismiss the suggestion | Click **×**, or press **⌃⌥⌫** |
| Explain the suggestion | Press **⌃⌥E** |
| Proofread selected text | Press **⌃⌥P** |
| Rewrite or translate selected text | Press **⌃⌥R**, or use the menu |
| Open the selection in the editor | Press **⌃⌥F** |
| Insert a snippet | Type `\name` and a space |

The **⋯** button on a suggestion has **Apply All** and **Never Change**. The menu names the app in front and says what Nib sees there. Turn off **Check Text in This App** to pause Nib in that app. Less common commands are under **More**.

Terminals, code editors, password managers and remote desktop tools are never checked. Proofread, rewrite, read aloud and the editor shortcut also do nothing in these apps and in password fields.

## Use a larger model

Apple's model is small. A larger model finds more errors and writes better rewrites.

1. Install [Ollama](https://ollama.com) and get a model, for example `ollama pull qwen3`.
2. In Nib, open **Settings… → Model**.
3. Choose the local server, enter the model name and click **Save and Test**.

Nib accepts a server on this Mac only, so your text still stays on your device. If the server is not running, Nib uses Apple's model.

## Privacy

The full policy is in [PRIVACY.md](PRIVACY.md).

- Nib sends nothing to other machines. There is no account, no telemetry and no cloud service. The optional model server must be on this Mac.
- Nib does not save your drafts. The Mac app saves your settings, dictionary, snippets, instructions, per-app pauses and daily counts of suggestions.
- The extension has access to the text fields on all sites. It saves only your switches, paused sites and dictionary words, in the browser on this device.
- The logs in `~/Library/Logs` never hold your text. `Nib-apply.log` holds the time, the app id and the result of each apply. `Nib-diagnosis.txt` holds the report of **Diagnose Front App**.
- The browser troubleshooting log is off by default. A switch in the popup turns it on. `Nib-browser.log` then gets host names, field types and counts, but never from private windows.
- Nib skips password fields and every field while macOS secure input is active. The extension also skips fields for codes, keys, tokens and card numbers.
- When an app needs paste to apply a fix, Nib uses the clipboard for a moment and then puts the old contents back.

## Accuracy

`bash Source/test.sh --eval` scores Nib on the labelled sentences in `Source/eval-cases.tsv`. Results on one Mac, for 16 sentences with errors and 12 clean sentences that were not used to tune the rules:

| Mode | Exact fixes | False alarms |
|---|---|---|
| Without a model | 2 of 16 | 0 of 12 |
| Apple's model | 13 of 16 | 0 of 12 |
| `qwen3` through Ollama | 15 of 16 | 0 of 12 |

The sets are small, and model answers vary a little between runs. The fixed rules and word lists were tuned with some of the sentences in the file in view. A correct sentence can still get a wrong suggestion. If you see one, please [report the sentence](https://github.com/demirelo/nib/issues).

**Tested with** (tried by the author, not a guarantee):

- Mac app: Telegram, the Claude desktop app, Notes.
- Extension in Brave: Gmail, LinkedIn, X, Claude.ai.

## Troubleshooting

- **No suggestion shows.** Open the menu. The line under the app name says why. **More → Diagnose Front App…** shows the details.
- **The permission is on, but Nib says it is missing.** Remove **Nib** from the Accessibility list, add `Nib.app` again with the plus button, and restart Nib.
- **A click on a suggestion changes nothing.** Select the text and press **⌃⌥P**. The reason is in `~/Library/Logs/Nib-apply.log`.
- **No sentence suggestions in the browser.** Choose **More → Connect Browsers…** again and reload the extension.

## Limits

- Google Docs draws its text as a picture, so Nib cannot check there while you type, and it shows no underlines. Click **Check document** at the lower right of a document: Nib reads the text of the document and lists the fixes in a panel. You make the changes in the document yourself.
- Google Sheets and Slides get a note only. Select your text and press **⌃⌥F** to check it in the Nib editor.
- Each app decides what it exposes. Some apps get the suggestion button but no underlines.
- Explain, rewrite, translate, snippets and autocomplete are in the Mac app only.
- The fixed grammar rules and the browser word list are English only. Text in another language gets its fixes from the sentence model and the macOS spell checker, in that language. In the browser this needs **Connect Browsers**.
- Autocomplete is a beta and is off by default.
- The app is not notarized. macOS may ask you to confirm the first launch.

## Development

The Mac app is in `Source/` and the extension is in `Browser/`. Each sentence goes through fixed rules, the macOS spell checker and the sentence model. A guard then compares the answer with your sentence and drops it if it rewrites.

| Command | What it does |
|---|---|
| `bash Source/install.sh [folder]` | Builds, tests and installs `Nib.app` into the folder |
| `bash Source/test.sh` | Runs the logic tests. Add `--eval` for the scores, or `--browser` for the Node tests only |
| `NIB_PLAYWRIGHT=… bash Source/test.sh` | Also loads the real extension in Chromium and tests it |
| `bash Source/make-dmg.sh` | Makes the installer disk image |
| `bash Source/make-icons.sh` | Draws all icons again from `Source/Icon.swift` |
| `open -g nib://diagnose` | Saves the diagnosis to `~/Library/Logs/Nib-diagnosis.txt` |

`install.sh` signs with the first *Apple Development* certificate in your keychain, so the permission stays across builds. Set `NIB_SIGN` to choose another one.

When a suggestion is wrong, add the sentence to `Source/eval-cases.tsv` under `reported` before you fix it. [CONTRIBUTING.md](CONTRIBUTING.md) has the rules and a file map. [SECURITY.md](SECURITY.md) says how to report a vulnerability.

## Credits

The browser spelling list is derived from Webster's Second International via the Berkeley `web2` distribution, with additional modern vocabulary. See [NOTICE.md](NOTICE.md).

## License

Nib is released under the [MIT License](LICENSE).
