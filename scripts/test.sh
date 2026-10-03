#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
MODULE_CACHE="$ROOT/.build/module-cache"
TEST_BINARY="$ROOT/.build/TargetMacDFUCoreTests"
SDK_ARGS=()

if [[ -n "${TARGET_MAC_DFU_SDK:-}" ]]; then
  SDK_ARGS=(-sdk "$TARGET_MAC_DFU_SDK")
fi

/bin/mkdir -p "$MODULE_CACHE" "$ROOT/.build"
/bin/zsh -n "$ROOT/Resources/backend.zsh" "$ROOT/scripts/build.sh" "$ROOT/scripts/package.sh" "$ROOT/scripts/notarize.sh"
/usr/bin/osascript -l JavaScript "$ROOT/Tests/DeviceParserTests.js" "$ROOT/Resources/device-parser.js"

TARGET_MAC_DFU_FAKE=1 "$ROOT/Resources/backend.zsh" self-test >/dev/null
TARGET_MAC_DFU_FAKE=1 "$ROOT/Resources/backend.zsh" dfu | /usr/bin/grep -q 'STAGE|DFU подтверждён'
TARGET_MAC_DFU_FAKE=1 "$ROOT/Resources/backend.zsh" recover restore 0xDEMO "$ROOT/README.md" | /usr/bin/grep -q 'restore: 100%'
"$ROOT/Resources/backend.zsh" firmwares Mac14,7 localCatalog "$ROOT/examples/custom-catalog.json" 1 \
  | /usr/bin/grep -q '"build":"24F74"'

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" SWIFT_MODULE_CACHE_PATH="$MODULE_CACHE" \
/usr/bin/xcrun swiftc "${SDK_ARGS[@]}" \
  -parse-as-library \
  -framework Combine \
  -framework CryptoKit \
  "$ROOT/Sources/Models.swift" \
  "$ROOT/Sources/OperationCoordinator.swift" \
  "$ROOT/Sources/Localization.swift" \
  "$ROOT/Sources/IPSWValidator.swift" \
  "$ROOT/Sources/UpdateChecker.swift" \
  "$ROOT/Tests/CoreTests.swift" \
  -o "$TEST_BINARY"

TARGET_MAC_DFU_RESOURCES="$ROOT/Resources" "$TEST_BINARY"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" SWIFT_MODULE_CACHE_PATH="$MODULE_CACHE" \
/usr/bin/xcrun swiftc "${SDK_ARGS[@]}" \
  -parse-as-library \
  -framework AppKit \
  -framework UniformTypeIdentifiers \
  "$ROOT/Sources/AppModel.swift" \
  "$ROOT/Sources/BackendClient.swift" \
  "$ROOT/Sources/DownloadManager.swift" \
  "$ROOT/Sources/IPSWValidator.swift" \
  "$ROOT/Sources/Localization.swift" \
  "$ROOT/Sources/Models.swift" \
  "$ROOT/Sources/OperationCoordinator.swift" \
  "$ROOT/Sources/SettingsAndHistory.swift" \
  "$ROOT/Sources/UpdateChecker.swift" \
  "$ROOT/Tests/AppModelTests.swift" \
  -o "$ROOT/.build/TargetMacDFUAppModelTests"

TARGET_MAC_DFU_RESOURCES="$ROOT/Resources" "$ROOT/.build/TargetMacDFUAppModelTests"
print "All tests passed"
