#!/bin/bash
#
#  build-cli-release.sh
#  CLIKit
#
#  Created by David Sherlock on 2026.
#
#  Builds the release artefact for the Homebrew tap: a stripped, ad-hoc signed
#  arm64 binary with its resource bundles, licence and shell completions, plus
#  the sha256 the formula needs. One copy for the whole fleet — every CLI's
#  `Scripts/build-release.sh` hands over to this file in its resolved CLIKit
#  checkout, so a fix here reaches a tool at its next CLIKit bump, and the
#  script a release ran with is pinned in that tool's Package.resolved.
#
#  Run from the tool's root:
#
#      build-cli-release.sh <version>
#
#  The binary's name is the package's one executable product, as SwiftPM
#  reports it. What differs between tools lives in two optional files beside
#  the caller, SOURCED (not run) so they share this script's variables and its
#  `set -euo pipefail`:
#
#    Scripts/stage.sh   after the bundles are staged, before stripping — for
#                       anything else the archive must carry.
#    Scripts/smoke.sh   after the standard checks — the tool's own promises,
#                       asserted against the staged binary ($STAGE/$TOOL).
#                       `status` and `expect` (below) are there to use.
#
#  WHY there is no notarization here, unlike Sidewatch. Gatekeeper only assesses
#  files carrying com.apple.quarantine, and that attribute is set by browsers and
#  by Homebrew *casks* — not by formulae or curl. A formula-installed binary is
#  never assessed, so ad-hoc signing is sufficient. (Verifiable: `jq` from
#  homebrew-core is ad-hoc signed with no team identifier, `spctl` calls it
#  "rejected", and it runs fine.) Ship this as a .dmg or a cask and that stops
#  being true — then Sidewatch's notarize.sh is the model.
#

set -euo pipefail

VERSION="${1:-}"

if [ -z "$VERSION" ]; then
    echo "usage: Scripts/build-release.sh <version>   e.g. 0.1.0" >&2
    exit 2
fi

ROOT="$(pwd)"
[ -f "$ROOT/Package.swift" ] || { echo "✗ run from the tool's root (no Package.swift in $ROOT)" >&2; exit 2; }

# The one executable product. Two would leave the archive's name a guess, so
# that refuses rather than picking the first.
TOOL="$(swift package describe --type json 2>/dev/null | /usr/bin/python3 -c '
import json, sys
names = [p["name"] for p in json.load(sys.stdin)["products"] if "executable" in p["type"]]
print(names[0] if len(names) == 1 else "")
')"
[ -n "$TOOL" ] || { echo "✗ expected exactly one executable product in $ROOT/Package.swift" >&2; exit 1; }

REPO="$(basename -s .git "$(git config --get remote.origin.url 2>/dev/null || echo "$ROOT")")"
DIST="$ROOT/dist"
STAGE="$DIST/$TOOL-$VERSION"
ARCHIVE="$TOOL-$VERSION-macos-arm64.tar.gz"

cd "$ROOT"
rm -rf "$DIST"
mkdir -p "$STAGE/completions"

echo "==> Building $TOOL $VERSION (arm64, release)"
swift build -c release --arch arm64

# Redirected: if SwiftPM ever writes a warning to stdout, an unguarded capture
# silently turns BIN into a path plus prose.
BUILD_DIR="$(swift build -c release --arch arm64 --show-bin-path 2>/dev/null)"
BIN="$BUILD_DIR/$TOOL"
[ -x "$BIN" ] || { echo "✗ no binary at $BIN" >&2; exit 1; }
cp "$BIN" "$STAGE/$TOOL"

# SwiftPM emits a .bundle beside the binary for any dependency declaring
# `resources:`. Bundle.module resolves it relative to the executable, so a
# tarball containing only the binary traps the moment the resource is needed —
# and neither --version nor --help touches one, which is how that ships.
for bundle in "$BUILD_DIR"/*.bundle; do
    [ -e "$bundle" ] || continue
    echo "==> Bundling $(basename "$bundle")"
    cp -R "$bundle" "$STAGE/"
done

if [ -f "$ROOT/Scripts/stage.sh" ]; then
    echo "==> Staging extras (Scripts/stage.sh)"
    # shellcheck source=/dev/null
    source "$ROOT/Scripts/stage.sh"
fi

# Strip debug symbols and the local symbol table. Roughly halves the binary, and
# nothing here has debugging value to a user. ArgumentParser's Mirror-based
# parsing survives it — verified by running a real subcommand below.
echo "==> Stripping"
strip -rSTx "$STAGE/$TOOL"

# Re-sign after stripping: mutating a Mach-O invalidates its ad-hoc signature,
# and arm64 refuses to exec a binary whose signature does not match. Skipping
# this produces "killed: 9" with no further explanation.
echo "==> Re-signing (ad-hoc)"
codesign --force --sign - "$STAGE/$TOOL"
codesign --verify --strict "$STAGE/$TOOL"

# ── Assertions ───────────────────────────────────────────────────────────────
# Each of these has a matching way to ship something wrong silently.

echo "==> Verifying"

# A fat or x86_64 slice would install and run, just not as advertised.
ARCHS="$(lipo -archs "$STAGE/$TOOL")"
[ "$ARCHS" = "arm64" ] || { echo "✗ expected arm64 only, got: $ARCHS" >&2; exit 1; }

# Catches strip/sign damage, which is otherwise invisible until a user runs it.
REPORTED="$("$STAGE/$TOOL" --version)"

# Tagging v0.2.0 while CommandConfiguration still says 0.1.0 is an easy mistake
# and produces a release whose binary disagrees with its own filename.
[ "$REPORTED" = "$VERSION" ] || {
    echo "✗ version mismatch: tag says $VERSION, binary reports $REPORTED" >&2
    echo "  update CommandConfiguration(version:) to match." >&2
    exit 1
}

# Exercises real argument parsing, not just --version.
"$STAGE/$TOOL" --help >/dev/null

# Exercises the resource bundle, which --version and --help never reach. This
# is the check that catches a tarball missing its resources.
"$STAGE/$TOOL" describe --json >/dev/null

# Exit status, captured rather than tested with $? — under `set -e` a command
# that fails outside a conditional ends the script before its own test runs.
# Stdin is closed so a verb that reads a pipe cannot wait on the terminal.
status() {
    set +e
    "$@" >/dev/null 2>&1 </dev/null
    local code=$?
    set -e
    echo "$code"
}

# `expect 2 send` — the staged binary, run with those arguments, exits 2.
expect() {
    local want="$1"; shift
    local got
    got="$(status "$STAGE/$TOOL" "$@")"
    [ "$got" = "$want" ] || { echo "✗ $TOOL $* exited $got, expected $want" >&2; exit 1; }
}

if [ -f "$ROOT/Scripts/smoke.sh" ]; then
    echo "==> Smoke (Scripts/smoke.sh)"
    # shellcheck source=/dev/null
    source "$ROOT/Scripts/smoke.sh"
fi

# ── Extras ───────────────────────────────────────────────────────────────────

echo "==> Generating shell completions"
for shell in bash zsh fish; do
    case "$shell" in
        bash) name="$TOOL.bash" ;;
        zsh)  name="_$TOOL" ;;
        fish) name="$TOOL.fish" ;;
    esac
    "$STAGE/$TOOL" --generate-completion-script "$shell" > "$STAGE/completions/$name"
done

# MIT requires the notice accompany substantial portions of the software, and a
# bare binary in a tarball carries none.
cp "$ROOT/LICENSE" "$STAGE/LICENSE"

echo "==> Packaging"
tar -czf "$DIST/$ARCHIVE" -C "$DIST" "$TOOL-$VERSION"

SHA="$(shasum -a 256 "$DIST/$ARCHIVE" | cut -d' ' -f1)"
SIZE="$(du -h "$DIST/$ARCHIVE" | cut -f1 | tr -d ' ')"

cat <<EOF

Built $DIST/$ARCHIVE ($SIZE)

  arch:    $ARCHS
  version: $REPORTED
  sha256:  $SHA

Formula fields:
  url    "https://github.com/arraypress/$REPO/releases/download/v$VERSION/$ARCHIVE"
  sha256 "$SHA"
EOF
