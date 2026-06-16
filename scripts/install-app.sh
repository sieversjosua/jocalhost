#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="jocalhost"
SOURCE_APP="$ROOT_DIR/dist.noindex/$APP_NAME.app"
INSTALL_APP="/Applications/$APP_NAME.app"
LEGACY_DIST_APP="$ROOT_DIR/dist/$APP_NAME.app"
LEGACY_CASE_APP="/Applications/Jocalhost.app"
LEGACY_LOCALHOST_APP="/Applications/Localhost.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

same_file() {
  [[ -e "$1" && -e "$2" ]] || return 1
  [[ "$(stat -f '%d:%i' "$1")" == "$(stat -f '%d:%i' "$2")" ]]
}

if [[ -e "$LEGACY_DIST_APP" ]]; then
  "$LSREGISTER" -u "$LEGACY_DIST_APP" >/dev/null 2>&1 || true
fi

"$ROOT_DIR/scripts/build-app.sh"

if [[ -e "$LEGACY_CASE_APP" ]] && ! same_file "$LEGACY_CASE_APP" "$INSTALL_APP"; then
  rm -rf "$LEGACY_CASE_APP"
fi

if [[ -e "$LEGACY_LOCALHOST_APP" ]] && ! same_file "$LEGACY_LOCALHOST_APP" "$INSTALL_APP"; then
  rm -rf "$LEGACY_LOCALHOST_APP"
fi

if [[ -e "$INSTALL_APP" ]]; then
  "$LSREGISTER" -u "$INSTALL_APP" >/dev/null 2>&1 || true
  rm -rf "$INSTALL_APP"
fi

ditto "$SOURCE_APP" "$INSTALL_APP"
touch "$INSTALL_APP"

codesign --verify --deep --strict --verbose=2 "$INSTALL_APP"

"$LSREGISTER" -f "$INSTALL_APP" >/dev/null 2>&1 || true
mdimport "$INSTALL_APP" >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

echo "$INSTALL_APP"
