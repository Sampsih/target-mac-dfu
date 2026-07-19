#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="$(/bin/cat "$ROOT/VERSION")"
APP="$ROOT/dist/Target Mac DFU.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
MODULE_CACHE="$ROOT/.build/module-cache"
SDK_ARGS=()

if [[ -n "${TARGET_MAC_DFU_SDK:-}" ]]; then
  SDK_ARGS=(-sdk "$TARGET_MAC_DFU_SDK")
fi

/bin/rm -rf "$APP"
/bin/mkdir -p "$MACOS" "$RESOURCES/Sources" "$MODULE_CACHE"

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
/bin/cp "$ROOT"/Sources/*.swift "$RESOURCES/Sources/"
/bin/chmod 755 "$RESOURCES/backend.zsh" "$MACOS/TargetMacDFU"

/usr/bin/sed "s/__VERSION__/$VERSION/g; s/__BUILD__/100/g" "$ROOT/Resources/Info.plist.in" > "$CONTENTS/Info.plist"
/usr/bin/xattr -cr "$APP"
/usr/bin/xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
/usr/bin/xattr -d 'com.apple.fileprovider.fpfs#P' "$APP" 2>/dev/null || true
/usr/bin/codesign --force --deep --sign - "$APP"

print "Built: $APP"
