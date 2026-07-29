#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
MODULE_CACHE="$ROOT/.build/screenshot-cache"
RENDERER="$ROOT/.build/RenderScreenshots"
SDK_ARGS=()

if [[ -n "${TARGET_MAC_DFU_SDK:-}" ]]; then
  SDK_ARGS=(-sdk "$TARGET_MAC_DFU_SDK")
fi

/bin/mkdir -p "$MODULE_CACHE" "$ROOT/.build" "$ROOT/docs/images"
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" SWIFT_MODULE_CACHE_PATH="$MODULE_CACHE" \
/usr/bin/xcrun swiftc "${SDK_ARGS[@]}" \
  -parse-as-library \
  -O \
  -framework SwiftUI \
  -framework AppKit \
  -framework UniformTypeIdentifiers \
  "$ROOT"/Sources/AppModel.swift \
  "$ROOT"/Sources/BackendClient.swift \
  "$ROOT"/Sources/DownloadManager.swift \
  "$ROOT"/Sources/IPSWValidator.swift \
  "$ROOT"/Sources/Models.swift \
  "$ROOT"/Sources/SettingsAndHistory.swift \
  "$ROOT"/Sources/UpdateChecker.swift \
  "$ROOT"/Sources/Views.swift \
  "$ROOT"/Tools/RenderScreenshots.swift \
  -o "$RENDERER"

TARGET_MAC_DFU_RESOURCES="$ROOT/Resources" "$RENDERER" "$ROOT/docs/images"
print "Screenshots rendered in $ROOT/docs/images"
