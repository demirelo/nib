"use strict";
// Logic tests for the browser checker. Run with: node Source/browser-test.js
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const dir = path.join(__dirname, "..", "Browser");
for (const file of ["words.js", "engine.js", "sentences.js"]) {
  vm.runInThisContext(fs.readFileSync(path.join(dir, file), "utf8"), { filename: file });
}

let passed = 0;
let failed = 0;
function expect(condition, name) {
  if (condition) passed++;
  else {
    failed++;
    console.log("FAIL  " + name);
  }
}
function fixes(text) {
  return nibCheck(text, true, new Set(), new Set()).map(issue => issue.fragment + ">" + (issue.replacements[0] ?? ""));
}

expect(fixes("I recieved the report.").join() === "recieved>received", "typo");
expect(fixes("I should of gone.").join() === "should of>should have", "modal have");
expect(fixes("I could of course go.").length === 0, "of course is fine");
expect(fixes("It is a error.").join() === "a>an", "article");
expect(fixes("This is fine.").length === 0, "clean text");
expect(fixes("See https://exmaple.com/recieve now.").length === 0, "links are protected");
expect(fixes("Mail recieve@exmaple.com now.").length === 0, "emails are protected");
expect(fixes("Run `recieve` now.").length === 0, "inline code is protected");
expect(fixes("The the cat sat.").join() === "The the>The", "repeated word");
expect(nibCheck("I recieved it.", true, new Set(["spell:recieved"]), new Set()).length === 0, "ignored key");
expect(nibCheck("I use zkfoo daily.", true, new Set(), new Set(["zkfoo"])).length === 0, "personal dictionary");

expect(fixes("thi sis a chapter in may life.").join() === "thi sis>this is", "misplaced space");
expect(fixes("I wil lgo there.").join() !== "", "misplaced space, other direction");
expect(fixes("The zkfoo bar is open.").every(f => !f.includes(" ")), "unknown word keeps its neighbour");

// Text in another language gets no English checks. From a user report: German words were underlined.
expect(fixes("Sorry für die späte Antwort! Wir sind nur 4 Personen momentan und sind kurz vor dem Release.").length === 0, "German text is not checked as English");
expect(fixes("Lass uns vielleicht.").length === 0, "short German sentence");
expect(fixes("Merci beaucoup pour votre réponse rapide, je vous appelle demain.").length === 0, "French text");
expect(fixes("Gracias por tu ayuda con el proyecto, nos vemos el lunes.").length === 0, "Spanish text");
expect(fixes("Lass uns vielleicht morgen telefonieren. I recieved the report.").join() === "recieved>received", "mixed languages: English sentence still checked");
expect(fixes("I recieved teh report form him and it was vrey good.").length >= 3, "English with several typos stays English");
expect(nibLanguage("Wir sind kurz vor dem Release.") === "other" && nibLanguage("We are close to the release.") === "en", "language of a sentence");

// The word list lacks some short and irregular forms. From a user report: "A human has to read" was underlined.
expect(fixes("A human has to read the spec.").length === 0, "has is a word");
for (const word of "has began blew forgave forgiven heard held paid woken withdrew".split(" ")) {
  expect(fixes("Then it " + word + " there.").length === 0, "irregular form: " + word);
}

// From a user report: a check of a real document marked "using" as "suing". The word list lacked many
// common words. These are correct and must get no spelling mark.
for (const word of `using earlier newest cheaper larger fewer box byte cookie database download coordinate desktop
    checklist clipboard shortcut dialog behaviour baseline timeout keyword startup workspace rewritten newer
    stronger deeper broader slower lowest smallest filename homepage prioritize uninstall widget pixel
    easier happiest taller wisest nicer making hoping used tied`.split(/\s+/)) {
  expect(fixes("We " + word + " here.").every(fix => !fix.startsWith(word + ">")), "common word: " + word);
}
// Real typos must still get a mark, also ones that look like a word with an ending.
for (const typo of "recieve teh wierd definately seperate adress goverment enviroment tommorow usign earlyer boxx thier".split(" ")) {
  expect(fixes("We " + typo + " here.").some(fix => fix.startsWith(typo + ">")), "typo still marked: " + typo);
}

// Every labelled sentence must get the right language, or English text would lose its checks.
const labelled = fs.readFileSync(path.join(__dirname, "eval-cases.tsv"), "utf8").split("\n")
  .filter(line => line && !line.startsWith("#")).map(line => line.split("\t"));
// The older sets hold a few German sentences too.
const german = /[äöüß]|\b(?:Wir|Lass|Ich|Das|Der)\b/;
for (const [set, text] of labelled) {
  const expected = set === "other" || german.test(text) ? "other" : "en";
  expect(nibLanguage(text) === expected, "language " + expected + ": " + text);
}

// From a review: English text with typos, names or accents lost every check, because it counted as another language.
// Each row: the text, and a typo that must be flagged ("" where the checker has no rule for the typo).
for (const [text, typo] of [
  ["Recieved teh documnets yesterday, thnaks!", "teh"],
  ["Teh quik brwon fox jumsp.", "Teh"],
  ["Meeting moved, pls confrim attendence asap.", "confrim"],
  ["Plz fix asap thx", ""],
  ["Deployed Kubernetes Grafana dashbords yesterday.", "dashbords"],
  ["I recieved Zoë Müller's résumé.", "recieved"],
  ["Plese send the résumé to Zoë Müller.", ""],
  ["Naïve Bayes beats teh baseline.", "teh"],
  ["Might've hapened.", "hapened"],
  ["Should've, might've recieved more.", "recieved"],
  ["Flying form Las Vegas to Los Angelas tomorow.", "tomorow"],
  ["MIT et al. recieved funding.", "recieved"],
  ["Come quickly!", ""],
  ["Sim card missing.", ""]
]) {
  expect(nibLanguage(text) === "en", "English with typos or names is English: " + text);
  if (typo) expect(fixes(text).some(fix => fix.startsWith(typo + ">")), "typo " + typo + " is flagged in: " + text);
}
// Names with accents are not misspellings of the English words inside them.
expect(fixes("I recieved Zoë Müller's résumé.").join() === "recieved>received", "accented names get no suggestion");
// Short text in languages that the first word lists did not cover was checked as English.
for (const text of ["Ciao, come stai?", "Nos vemos pronto amigo.", "Was machst du?", "Jag har en bil och en hund.",
  "Saya mau makan nasi goreng.", "Dobrze, dziekuje bardzo.", "Dobrze, dziękuję bardzo.", "Kiitos paljon avusta.",
  "Danke!", "Schöne Grüße"]) {
  expect(nibLanguage(text) === "other", "not English: " + text);
  expect(fixes(text).length === 0, "no English checks for: " + text);
}

// U+FFFC stands for a part the user cannot edit, such as a mention. It is one opaque word in its sentence.
const mention = "Hi ￼ can you send teh report? wor￼d the￼ the ￼, fine.";
expect(nibSentences("Hi ￼ can you send it.").length === 1, "a mention does not split a sentence");
expect(fixes(mention).join() === "teh>the", "words that touch a mention get no suggestion: " + fixes(mention).join());
expect(nibCheck(mention, true, new Set(), new Set()).every(issue => !issue.fragment.includes("￼")), "no fix covers a mention");

const draft = "I went two the store. It was closed.\nSecond line";
expect(nibSentence(draft, 3).text === "I went two the store.", "sentence at caret");
expect(nibSentence(draft, draft.length).text === "Second line", "sentence at end");
expect(nibSentence(draft, 999) === null, "caret out of range");
const all = nibSentences(draft);
expect(all.map(s => s.text).join("|") === "I went two the store.|It was closed.|Second line", "all sentences");
expect(all.every(s => draft.slice(s.start, s.end) === s.text), "sentence offsets match text");

// Google Docs: the address of the text of a document comes from the path of its page.
expect(nibDocsExport("/document/d/ID/edit") === "/document/d/ID/export?format=txt", "export address of a document");
expect(nibDocsExport("/document/u/1/d/ID/edit") === "/document/u/1/d/ID/export?format=txt", "export address for a second account");
expect(nibDocsExport("/document/d/ID/") === "/document/d/ID/export?format=txt", "export address without a page name");
expect(nibDocsExport("/document/d/a-B_9") === "/document/d/a-B_9/export?format=txt", "export address with only the id");
expect(nibDocsExport("/spreadsheets/d/ID/edit") === null && nibDocsExport("/presentation/d/ID/edit") === null, "no export address for sheets and slides");
expect(nibDocsExport("/document/u/0/") === null && nibDocsExport("/document/d//edit") === null &&
  nibDocsExport("/x/document/d/ID/edit") === null, "no export address without an id");
// The text starts with a byte order mark and has Windows line ends. A long text is cut at a line end.
expect(JSON.stringify(nibDocsText("﻿One.\r\nTwo.\r\n", 100)) === '{"text":"One.\\nTwo.\\n","cut":false}', "document text is cleaned");
const long = nibDocsText("Line one.\r\nLine two.\r\nLine three.", 25);
expect(long.cut && long.text === "Line one.\nLine two.", "a long document is cut at a line end: " + JSON.stringify(long.text));
expect(nibDocsText("x".repeat(30), 20).text.length === 20, "one long line is cut at the limit");
expect(nibDocsText("x".repeat(19) + "😀", 20).text.length === 19, "the cut does not split a character");

console.log(passed + " passed, " + failed + " failed (browser)");
process.exit(failed ? 1 : 0);
