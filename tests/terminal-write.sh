#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export BDB_PATH="$TMP/db"
export BDB_BIN="$TMP/bdbc"
export BDBREG_BIN="$ROOT/rootfs/bin/bdbreg"

cp "$ROOT/rootfs/usr/src/minibash/bdbc.c" "$TMP/bdbc.c"
cc -std=c11 -Wall -Wextra -O2 "$TMP/bdbc.c" -o "$TMP/bdbc"

"$BDB_BIN" init >/dev/null
"$BDB_BIN" create registry path:text:pk type:text value:text owner:text updated_at:int >/dev/null

"$ROOT/rootfs/bin/terminal-write" echo registry bridge ok | grep -q 'terminal-write: queued command'
"$ROOT/rootfs/bin/bdbreg" get /system/terminal/inbox/command | grep -q 'echo registry bridge ok'
"$ROOT/rootfs/bin/bdbreg" get /system/terminal/inbox/seq | grep -q 'terminal-write'

echo "Altitude terminal registry bridge: ok"
