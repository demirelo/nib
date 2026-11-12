# Contributing to Nib

Thank you for your help. Nib is small on purpose. Read this page before you change the code.

## Requirements

- An Apple silicon Mac with macOS 26 or later.
- The Xcode command line tools (`xcode-select --install`).
- Node 20 or later, for the browser tests.
- Optional: Playwright with its Chromium, for the extension test.

The browser tests need only Node. They also run on Linux.

## Build, test, install

| Command | What it does |
|---|---|
| `bash Source/build.sh [folder]` | Builds `Nib.app` with the helper `NibBridge` inside. The default folder is `Source/Build`. It prints the path of the app. |
| `bash Source/test.sh` | Builds and runs the Swift logic tests, then the Node browser tests. |
| `bash Source/test.sh --browser` | Runs only the Node browser tests. It compiles no Swift. |
| `bash Source/test.sh --eval` | Also scores the checkers on the sentences in `Source/eval-cases.tsv`. This needs Apple's on-device model or a local model server. |
| `NIB_PLAYWRIGHT=/path/to/node_modules/playwright/index.mjs node Source/extension-test.mjs` | Loads the real extension in Chromium and tests it. `test.sh` also runs it if `NIB_PLAYWRIGHT` is set. |
| `bash Source/install.sh [folder]` | Builds, tests, installs `Nib.app` into the folder and opens it. The default folder is the repository folder. It stops at the first failure. It quits a running Nib first. |
| `bash Source/make-icons.sh` | Draws all icons again from `Source/Icon.swift`. It writes `Browser/icons/nib-*.png` and `Source/AppIcon.icns`. Commit both. |
| `bash Source/make-dmg.sh` | Builds, tests and makes `Source/Build/Nib-<version>.dmg`. |
| `open -g nib://diagnose` | Tells the running app to save the diagnosis to `~/Library/Logs/Nib-diagnosis.txt`. The file holds no text. |
| `Source/Build/Nib.app/Contents/MacOS/Nib --render <folder>` | Writes pictures of the windows and the suggestion button into the folder, then quits. Use it to check the layout. |

Signing: `build.sh` signs ad hoc by default. `install.sh` uses the first *Apple Development* certificate in your keychain, so the Accessibility permission stays across builds. Set `NIB_SIGN` to choose another identity.

To score a local model server, set `NIB_SERVER` and `NIB_MODEL` before `bash Source/test.sh --eval`.

CI runs the logic tests and the browser tests. CI does not run `--eval`, because the model is not available there.

## Rules

1. **Record the sentence first.** When a suggestion is wrong, add the sentence to `Source/eval-cases.tsv` under `reported` before you fix it. The first lines of the file explain the format.
2. **A fix needs a test that fails without it.** Add the test, see it fail, then fix the code. Swift tests are in `Source/Tests.swift`. Browser tests are in `Source/browser-test.js`.
3. **Correct, never rewrite.** Do not weaken the guard that drops model answers that change the wording.
4. **Text stays on the device.** Do not add network calls. Do not write draft text to a log or to the settings.
5. **Update the docs.** If the behaviour changes, change `README.md` and `PRIVACY.md` in the same pull request.

## File map

Files can move. Check the folders if this list does not match.

### `Source/` (the Mac app)

| File | Contents |
|---|---|
| `Desktop.swift` | The menu bar app: its state, the launch, the menu and the `nib://` scheme. The files below extend the same class. |
| `Desktop+Accessibility.swift` | Reads the text field in front. Holds the never-checked lists and the gate for apps and fields that Nib must not read. |
| `Desktop+LiveChecks.swift` | The check loop: sentences, issues, underlines, snippets and completions. |
| `Desktop+Apply.swift` | Puts a fix into the other app and confirms that it arrived. |
| `Desktop+Clipboard.swift` | Copy and paste as the last way to read and write, with the clipboard put back. |
| `Desktop+Panel.swift` | The suggestion button, its menu, Explain and the dictionary. |
| `Desktop+Manual.swift` | Proofread, rewrite, read aloud and the editor for a selection. |
| `Desktop+HotKeys.swift` | The global shortcuts. |
| `Desktop+Browser.swift` | The link between the browsers and the helper. |
| `Desktop+Diagnosis.swift` | Diagnose Front App, the apply log and the daily counts. |
| `ProofEngine.swift` | The sentence logic that the app and the helper share: sentence finding, edits, fixed rules, the guard, Apple's model and the local model server. |
| `Proofreader.swift` | Spelling with the macOS spell checker, and the pipeline that joins rules, spelling and the model. |
| `Overlay.swift` | The underlines over the text field, and the picture helper for `--render`. |
| `Editor.swift` | The editor window for apps that Nib cannot read. |
| `Settings.swift` | The settings window. |
| `Welcome.swift` | The setup guide: permission, model choice, browser extension, first try. |
| `BrowserExtension.swift` | Keeps the user's copy of the extension in a normal folder, the same as the copy in the app. |
| `ElectronAccess.swift` | Decides when an Electron app, such as Signal, needs the second Accessibility switch. |
| `Icon.swift` | The drawing of the Nib mark, for the app, the menu bar and the extension. |
| `Bridge.swift` | The native messaging host `com.nib.bridge` for the extension. It builds to `NibBridge`. |
| `Tests.swift` | The logic tests and the scoring run. |
| `eval-cases.tsv` | Labelled sentences for the scoring run. |
| `browser-test.js` | Logic tests for the browser checker. They run in Node. |
| `extension-test.mjs` | The test that loads the real extension in Chromium. It needs Playwright. |
| `Info.plist` | The app's property list: version, bundle id, URL scheme. |
| `AppIcon.icns` | The app icon. `make-icons.sh` makes it. |
| `build.sh`, `test.sh`, `install.sh`, `make-icons.sh`, `make-dmg.sh` | The scripts in the table above. |
| `Build/` | Build output. Git ignores it. |

### `Browser/` (the extension)

| File | Contents |
|---|---|
| `manifest.json` | The extension manifest: permissions and the list of scripts. |
| `content.js` | The script in the page: finds the text field, draws the underlines and the suggestion list, applies a fix. |
| `engine.js` | The checker: known typos, fixed rules and the dictionary lookup. |
| `sentences.js` | Splits a draft into sentences. |
| `words.js` | The English word list. See `NOTICE.md`. |
| `background.js` | The service worker: the connection to the helper on the Mac, and the start of Nib in open tabs. |
| `popup.html`, `popup.js` | The popup with the switches and the status of the page. |
| `icons/` | The icons. `make-icons.sh` makes them. |

## Code style

- Comments say why, not what. Name the trap that the code avoids. Use plain English and short sentences.
- No new dependencies. The app uses only Apple frameworks. The extension uses only browser APIs.
- The app must work offline.
- Keep changes small. Do not refactor code that your change does not need.
- Text in the interface and in the docs: short sentences, active voice, no idioms.

## Out of scope

- Cloud models, or a model server on another machine.
- Telemetry, analytics and crash reporting that send data.
- Accounts and sync.

## Pull requests

Keep one topic per pull request. Fill in the checklist in the template. For a vulnerability, do not open a pull request. Read [SECURITY.md](SECURITY.md).
