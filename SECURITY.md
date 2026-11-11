# Security

## Report a vulnerability

Report it in private. Do not open a public issue.

1. Open <https://github.com/demirelo/nib/security/advisories/new>. You can also open the **Security** tab of the repository and click **Report a vulnerability**.
2. Describe the problem, the Nib version, the macOS version and the steps to reproduce it.
3. Do not include private text from your own drafts.

You get an answer in the advisory. Nib is a project of one person, so an answer can take some days.

## What counts

- Anything that makes Nib read text it must not read, for example a password field or a never-checked app.
- Anything that makes Nib save text, or send text to another machine.
- Anything that makes Nib insert or change text without a click or a shortcut from the user.
- The native messaging host `com.nib.bridge`: who can connect to it, and what a message can make it do.
- The URL scheme `nib://`: what a link or another app can make Nib do.
- The permissions of the browser extension, and how a web page can influence the extension.
- The optional local model server: a way to make Nib use an address that is not on this Mac.

A wrong grammar suggestion is not a vulnerability. Report it as a normal issue.

## Supported versions

Only the latest release gets security fixes.

## Threat model

- Nib has the Accessibility permission. It can read and change text in other apps. Thus a bug in Nib is serious.
- The extension has access to the text fields on all sites. A hostile page must not be able to use the extension to read another page, or to reach the helper.
- Text in a draft or on a web page can be hostile. It can contain instructions for a language model. Such text must never make Nib insert text without the user's click. Nib shows a suggestion, and the user applies it. A guard drops model answers that rewrite the sentence.
- Nib must not send text to another machine. The only network connection is to the optional model server on a loopback address. Nib refuses other addresses and refuses redirects.
- The logs and the stored settings must never hold draft text.
- The installer images are not notarized by Apple. Get them only from the Releases page of the repository, or build from source.
