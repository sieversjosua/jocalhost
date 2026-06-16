#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-}"

REMOTE_APP_DIR="${JOCALHOST_REMOTE_APP_DIR:-Applications}"
REMOTE_BIN_DIR="${JOCALHOST_REMOTE_BIN_DIR:-.local/bin}"
REMOTE_TMP_DIR=".jocalhost-install-$$"
OPEN_AFTER_INSTALL="${JOCALHOST_OPEN_AFTER_INSTALL:-1}"

usage() {
  cat <<USAGE
Usage:
  scripts/deploy-remote-mac.sh <ssh-target>

Example:
  scripts/deploy-remote-mac.sh user@Target-Mac.local

Environment:
  JOCALHOST_REMOTE_APP_DIR       Remote app directory relative to home. Default: Applications
  JOCALHOST_REMOTE_BIN_DIR       Remote bin directory relative to home. Default: .local/bin
  JOCALHOST_OPEN_AFTER_INSTALL   Open app after install. Default: 1
USAGE
}

if [[ -z "$TARGET" || "$TARGET" == "-h" || "$TARGET" == "--help" ]]; then
  usage
  exit 2
fi

cd "$ROOT_DIR"

./scripts/build-app.sh

ssh "$TARGET" "
  set -euo pipefail
  mkdir -p \"\$HOME/$REMOTE_APP_DIR\" \"\$HOME/$REMOTE_BIN_DIR\" \"\$HOME/$REMOTE_TMP_DIR\"
  rm -rf \"\$HOME/$REMOTE_TMP_DIR/jocalhost.app\"
"

rsync -a --delete "$ROOT_DIR/dist.noindex/jocalhost.app" "$TARGET:~/$REMOTE_TMP_DIR/"
rsync -a "$ROOT_DIR/dist/jocalhostctl" "$ROOT_DIR/dist/jocalhost-mcp" "$TARGET:~/$REMOTE_TMP_DIR/"

ssh "$TARGET" "
  set -euo pipefail
  pkill -x jocalhost >/dev/null 2>&1 || true
  rm -rf \"\$HOME/$REMOTE_APP_DIR/jocalhost.app\"
  mv \"\$HOME/$REMOTE_TMP_DIR/jocalhost.app\" \"\$HOME/$REMOTE_APP_DIR/jocalhost.app\"
  install -m 755 \"\$HOME/$REMOTE_TMP_DIR/jocalhostctl\" \"\$HOME/$REMOTE_BIN_DIR/jocalhostctl\"
  install -m 755 \"\$HOME/$REMOTE_TMP_DIR/jocalhost-mcp\" \"\$HOME/$REMOTE_BIN_DIR/jocalhost-mcp\"
  rm -rf \"\$HOME/$REMOTE_TMP_DIR\"
  xattr -dr com.apple.quarantine \"\$HOME/$REMOTE_APP_DIR/jocalhost.app\" \"\$HOME/$REMOTE_BIN_DIR/jocalhostctl\" \"\$HOME/$REMOTE_BIN_DIR/jocalhost-mcp\" >/dev/null 2>&1 || true
  if [[ \"$OPEN_AFTER_INSTALL\" == \"1\" ]]; then
    open \"\$HOME/$REMOTE_APP_DIR/jocalhost.app\"
  fi
"

echo "Installed jocalhost on $TARGET"
echo "App: ~/$REMOTE_APP_DIR/jocalhost.app"
echo "CLI: ~/$REMOTE_BIN_DIR/jocalhostctl"
