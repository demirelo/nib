"use strict";

var nibSegmenter = new Intl.Segmenter(undefined, { granularity: "sentence" });

// Every sentence of the draft, in order, with offsets into the draft.
globalThis.nibSentences = text => {
  const found = [];
  let left = 0;
  while (left <= text.length) {
    const lineEnd = text.indexOf("\n", left);
    const right = lineEnd < 0 ? text.length : lineEnd;
    if (right - left <= 10000) {
      const paragraph = text.slice(left, right);
      for (const part of nibSegmenter.segment(paragraph)) {
        const clean = part.segment.trim();
        if (!clean || clean.length > 600) continue;
        const start = left + part.index + part.segment.indexOf(clean);
        found.push({ start, end: start + clean.length, text: clean });
      }
    }
    left = right + 1;
  }
  return found;
};

// Google Docs serves the plain text of a document beside its page. From the path of the page,
// "/document/d/<id>/edit" or "/document/u/<n>/d/<id>/edit" for a second account, this gives the path
// of the text. Null for every other page, also for sheets and slides.
globalThis.nibDocsExport = pathname => {
  const match = /^\/document\/(?:u\/\d+\/)?d\/[\w-]+(?=\/|$)/.exec(pathname);
  return match ? match[0] + "/export?format=txt" : null;
};

// The text of a document as Google Docs serves it: a byte order mark first, Windows line ends.
// A long text is cut at the last line end before the limit, so no half sentence gets checked.
globalThis.nibDocsText = (raw, limit) => {
  let text = raw.replace(/^﻿/, "").replace(/\r\n?/g, "\n");
  const cut = text.length > limit;
  if (cut) {
    text = text.slice(0, limit);
    const lineEnd = text.lastIndexOf("\n");
    if (lineEnd > 0) text = text.slice(0, lineEnd);
    // One long line: the cut must not leave half of a character.
    else if (/[\uD800-\uDBFF]$/.test(text)) text = text.slice(0, -1);
  }
  return { text, cut };
};

globalThis.nibSentence = (() => {
  const segmenter = nibSegmenter;
  return (text, offset) => {
    if (!Number.isInteger(offset) || offset < 0 || offset > text.length) return null;
    const left = offset === 0 ? 0 : text.lastIndexOf("\n", offset - 1) + 1;
    const lineEnd = text.indexOf("\n", offset);
    const right = lineEnd < 0 ? text.length : lineEnd;
    if (right - left > 10000) return null;
    const paragraph = text.slice(left, right);
    if (!paragraph.trim()) return null;
    const index = Math.min(offset - left, paragraph.length - 1);
    const part = segmenter.segment(paragraph).containing(index);
    if (!part) return null;
    const clean = part.segment.trim();
    if (!clean || clean.length > 600) return null;
    const start = left + part.index + part.segment.indexOf(clean);
    return { start, end: start + clean.length, text: clean };
  };
})();
