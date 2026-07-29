#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="$(/bin/cat "$ROOT/VERSION")"
APP="$ROOT/dist/Target Mac DFU.app"
ARCHIVE="$ROOT/dist/Target-Mac-DFU-$VERSION.zip"
PROFILE="${TARGET_MAC_DFU_NOTARY_PROFILE:-}"

[[ -n "$PROFILE" ]] || {
  print -u2 -- "Set TARGET_MAC_DFU_NOTARY_PROFILE to a notarytool keychain profile."
  exit 64
}
[[ -d "$APP" ]] || {
  print -u2 -- "Build the Developer ID signed application first."
  exit 66
}

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
"$ROOT/scripts/package.sh"
/usr/bin/xcrun notarytool submit "$ARCHIVE" --keychain-profile "$PROFILE" --wait
/usr/bin/xcrun stapler staple "$APP"
/usr/bin/xcrun stapler validate "$APP"
"$ROOT/scripts/package.sh"

print "Notarized and packaged: $ARCHIVE"
