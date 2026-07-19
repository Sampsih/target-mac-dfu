#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="$(/bin/cat "$ROOT/VERSION")"
APP="$ROOT/dist/Target Mac DFU.app"
ARCHIVE="$ROOT/dist/Target-Mac-DFU-$VERSION.zip"

[[ -d "$APP" ]] || "$ROOT/scripts/build.sh"
/bin/rm -f "$ARCHIVE"
COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --norsrc --keepParent "$APP" "$ARCHIVE"

print "Packaged: $ARCHIVE"
