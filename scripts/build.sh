#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="$(/bin/cat "$ROOT/VERSION")"
APP="$ROOT/dist/Target Mac DFU.app"
STAGING_ROOT=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/target-mac-dfu-build.XXXXXX")
STAGING_APP="$STAGING_ROOT/Target Mac DFU.app"
CONTENTS="$STAGING_APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
MODULE_CACHE="$ROOT/.build/module-cache"
BUILD_NUMBER="${TARGET_MAC_DFU_BUILD_NUMBER:-${VERSION//./}}"
SIGN_IDENTITY="${TARGET_MAC_DFU_SIGN_IDENTITY:--}"
SDK_ARGS=()
trap '/bin/rm -rf "$STAGING_ROOT"' EXIT

if [[ -n "${TARGET_MAC_DFU_SDK:-}" ]]; then
  SDK_ARGS=(-sdk "$TARGET_MAC_DFU_SDK")
fi

/bin/rm -rf "$APP"
/bin/mkdir -p "$MACOS" "$RESOURCES" "$MODULE_CACHE" "$ROOT/dist"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" SWIFT_MODULE_CACHE_PATH="$MODULE_CACHE" \
/usr/bin/xcrun swiftc "${SDK_ARGS[@]}" \
  -parse-as-library \
  -O \
  -framework SwiftUI \
  -framework AppKit \
  -framework UniformTypeIdentifiers \
  "$ROOT"/Sources/*.swift \
  -o "$MACOS/TargetMacDFU"

/bin/cp "$ROOT/Resources/backend.zsh" "$RESOURCES/backend.zsh"
/bin/cp "$ROOT/Resources/firmware-catalog.json" "$RESOURCES/firmware-catalog.json"
/bin/cp "$ROOT/Resources/TargetMacDFU.icns" "$RESOURCES/TargetMacDFU.icns"
/bin/chmod 755 "$RESOURCES/backend.zsh" "$MACOS/TargetMacDFU"

/usr/bin/sed "s/__VERSION__/$VERSION/g; s/__BUILD__/$BUILD_NUMBER/g" "$ROOT/Resources/Info.plist.in" > "$CONTENTS/Info.plist"
/usr/bin/xattr -cr "$STAGING_APP"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  /usr/bin/codesign --force --deep --sign - "$STAGING_APP"
else
  /usr/bin/codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$STAGING_APP"
fi
/usr/bin/ditto --norsrc "$STAGING_APP" "$APP"
/usr/bin/xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
/usr/bin/xattr -d 'com.apple.fileprovider.fpfs#P' "$APP" 2>/dev/null || true

print "Built: $APP"
