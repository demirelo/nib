#!/bin/bash
# Builds and runs the test runner. Pass --eval to also score the checkers on labelled sentences.
# Pass --browser to run only the Node tests. That mode compiles no Swift, so it also runs on Linux.
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" == "--browser" ]]; then
  # Here the browser tests are the whole job, so a missing Node is a failure and not a skip.
  command -v node >/dev/null 2>&1 || { echo "Node is not installed. The browser tests need it." >&2; exit 1; }
else
  build_dir="$source_dir/Build"
  mkdir -p "$build_dir"

  xcrun swiftc -O -target arm64-apple-macosx26.0 \
    "$source_dir/ProofEngine.swift" "$source_dir/Proofreader.swift" "$source_dir/Overlay.swift" \
    "$source_dir/BrowserExtension.swift" "$source_dir/ElectronAccess.swift" "$source_dir/Tests.swift" \
    -o "$build_dir/NibTests"
  if [[ "${1:-}" == "--eval" ]]; then
    "$build_dir/NibTests" --eval "$source_dir/eval-cases.tsv"
  else
    "$build_dir/NibTests"
  fi
fi

if command -v node >/dev/null 2>&1; then
  node "$source_dir/browser-test.js"
fi
# The extension test needs Playwright. Set NIB_PLAYWRIGHT to its index.mjs to run it.
if [[ -n "${NIB_PLAYWRIGHT:-}" ]]; then
  node "$source_dir/extension-test.mjs"
fi
