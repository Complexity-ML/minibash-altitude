#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export BDB_PATH="$TMP/db"
export BDB_BIN="$TMP/bdbc"
export APPREG_DIRS="$TMP/apps"
export ALTITUDE_PKG_STATE="$TMP/packages"

cp "$ROOT/rootfs/usr/src/minibash/bdbc.c" "$TMP/bdbc.c"
cc -std=c11 -Wall -Wextra -O2 "$TMP/bdbc.c" -o "$TMP/bdbc"

mkdir -p "$TMP/apps" "$TMP/packages/altitude-demo"
"$BDB_BIN" init >/dev/null

cat > "$TMP/apps/org.altitude.Demo.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Altitude Demo
Comment=Demo native application
Exec=/bin/demo %U
Categories=Utility;System;
EOF

cat > "$TMP/apps/org.altitude.Hidden.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Hidden Demo
Exec=/bin/hidden
NoDisplay=true
Categories=Utility;
EOF

cat > "$TMP/apps/altitude-tool.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Altitude Tool
Exec=/bin/altitude-tool
Categories=System;
EOF

cat > "$TMP/packages/altitude-demo/paths" <<EOF
payload$TMP/apps/org.altitude.Demo.desktop
EOF

"$ROOT/rootfs/bin/appreg" refresh | grep -q 'indexed 3 applications'
"$ROOT/rootfs/bin/appreg" status | grep -q 'visible[[:space:]]*2'
"$ROOT/rootfs/bin/appreg" status | grep -q 'hidden[[:space:]]*1'
"$ROOT/rootfs/bin/appreg" status | grep -q 'packaged[[:space:]]*2'
"$ROOT/rootfs/bin/appreg" search demo | grep -q 'Altitude Demo'
"$ROOT/rootfs/bin/appreg" list | grep -q 'altitude-demo'
"$ROOT/rootfs/bin/appreg" list | grep -q 'altitude-core'
"$ROOT/rootfs/bin/appreg" info org.altitude.Demo | grep -q '/bin/demo'

echo "Altitude app registry: ok"
