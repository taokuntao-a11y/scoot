#!/usr/bin/env bash
# scoot — build-from-source installer for macOS (Command Line Tools only, no Xcode).
#
# Clones (or reuses/updates) the scoot repo, builds it locally with `swift build`,
# and installs:
#   - the `scoot` CLI onto PATH        → ${PREFIX:-$HOME/.local/bin}/scoot
#   - the menu-bar app                 → /Applications/Scoot.app (or $HOME/Applications)
#
# Building locally (rather than shipping a signed binary) means no Gatekeeper /
# notarization step, and the CLI works for you and for any agent (Claude Code,
# OpenClaw, …) that shells out to it — sharing the same state files as the GUI.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/taokuntao-a11y/scoot/main/scripts/install.sh | bash
#   # or, from a clone:
#   ./scripts/install.sh
#
# Re-running upgrades an existing install.
set -euo pipefail

REPO_URL="https://github.com/taokuntao-a11y/scoot.git"
SRC_DIR="${SCOOT_SRC:-$HOME/.cache/scoot-src}"
PREFIX="${PREFIX:-$HOME/.local/bin}"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m warning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m error:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "scoot only runs on macOS."

command -v swift >/dev/null 2>&1 || die "swift not found. Install Command Line Tools with: xcode-select --install"
command -v git >/dev/null 2>&1 || die "git not found. Install Command Line Tools with: xcode-select --install"

say "Using $(swift --version 2>&1 | head -1)"

# --- Locate the source: reuse a clone if this script is being run from inside
#     one, otherwise clone (or pull) into SRC_DIR. ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT_GUESS="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$REPO_ROOT_GUESS/Package.swift" ] && [ -d "$REPO_ROOT_GUESS/Sources/ScootCLI" ]; then
    say "Running from an existing clone: $REPO_ROOT_GUESS"
    REPO_ROOT="$REPO_ROOT_GUESS"
elif [ -d "$SRC_DIR/.git" ]; then
    say "Updating existing source checkout at $SRC_DIR ..."
    git -C "$SRC_DIR" pull --ff-only
    REPO_ROOT="$SRC_DIR"
else
    say "Cloning $REPO_URL to $SRC_DIR ..."
    mkdir -p "$(dirname "$SRC_DIR")"
    git clone "$REPO_URL" "$SRC_DIR"
    REPO_ROOT="$SRC_DIR"
fi

cd "$REPO_ROOT"

# --- Optionally install slim so `scoot slim` works at runtime. Best-effort:
#     every other command (dest/src/list/move/rename/log) doesn't need it, and
#     scripts/build-app.sh no longer hard-requires a bundled copy. ---
if command -v slim >/dev/null 2>&1; then
    say "slim already on PATH: $(command -v slim)"
elif command -v pipx >/dev/null 2>&1; then
    say "Installing slim (for 'scoot slim') via pipx ..."
    pipx install "git+https://github.com/taokuntao-a11y/slim.git" \
        || warn "slim install failed — 'scoot slim' won't work until you install it manually (see github.com/taokuntao-a11y/slim)."
else
    warn "pipx not found — skipping slim install. 'scoot slim' will fail until 'slim' is on PATH."
    warn "See https://github.com/taokuntao-a11y/slim for install instructions."
fi

# --- Build. slim embedding in build-app.sh is optional, so this succeeds on a
#     fresh Mac even without a frozen slim binary lying around. ---
say "Building Scoot (release) — this can take a few minutes the first time ..."
make app

# --- Install the CLI. ---
say "Installing scoot CLI to $PREFIX ..."
mkdir -p "$PREFIX"
cp ".build/release/ScootCLI" "$PREFIX/scoot"
chmod +x "$PREFIX/scoot"

case ":$PATH:" in
    *":$PREFIX:"*) ;;
    *)
        warn "$PREFIX is not on your PATH in this shell."
        warn "Add this to your shell profile (~/.zshrc or ~/.bash_profile):"
        warn "  export PATH=\"$PREFIX:\$PATH\""
        ;;
esac

# --- Install the app. ---
APP_SRC="$REPO_ROOT/dist/Scoot.app"
APP_DEST="/Applications/Scoot.app"
if [ ! -w "/Applications" ]; then
    mkdir -p "$HOME/Applications"
    APP_DEST="$HOME/Applications/Scoot.app"
fi

say "Installing Scoot.app to $APP_DEST ..."
rm -rf "$APP_DEST"
cp -R "$APP_SRC" "$APP_DEST"

say "Done: $("$PREFIX/scoot" --version 2>/dev/null || echo "(re-open your shell to pick up scoot on PATH)")"

cat <<EOF

Try it:
  scoot --capabilities         # JSON manifest (for agents/tooling)
  scoot dest list              # list configured destination folders
  open "$APP_DEST"             # launch the menu-bar app

Re-run this script anytime to update to the latest version.
EOF
