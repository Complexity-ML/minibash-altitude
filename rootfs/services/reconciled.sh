#!/usr/bin/env bash
# reconciled -- the LIVE control loop of the bdb "tour de controle".
#
# Watches each domain table's data file and runs its reconciler the moment a row
# changes -> `bdb update mounts ... desired=unmounted` applies ITSELF, no manual
# restart. This is what turns "scripts that read a DB" into a declarative
# control plane (k8s-style: you declare desired state, the loop converges the
# real Linux to it).
#
# Long-running supervised service. Polls a content signature (no inotify dep).
# After running a reconciler we re-read the signature and store THAT:
# reconcilers write status back, and without this the loop would retrigger.
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export BDB_PATH="${BDB_PATH:-/var/bdb}"
exec >>/var/log/reconciled.log 2>&1
log() { echo "reconciled: $* ($(date 2>/dev/null))"; }

# table -> reconciler
reconciler_for() {
  case "$1" in
    modules) echo /services/kmod.sh ;;
    mounts)  echo /services/mountd.sh ;;
    sysctl)  echo /services/sysctld.sh ;;
    *)       echo "" ;;
  esac
}
TABLES="modules mounts sysctl"

sig() {
  file="$BDB_PATH/tables/$1/data.bdb"
  [ -f "$file" ] || { echo missing; return; }
  cksum "$file" 2>/dev/null | awk '{print $1 ":" $2}'
}

reconcile_table() {
  table="$1"
  rec="$(reconciler_for "$table")"
  [ -n "$rec" ] && [ -x "$rec" ] || {
    log "no reconciler for table '$table'"
    return
  }
  log "reconcile '$table' -> $rec"
  "$rec" >/dev/null 2>&1 || log "reconciler '$rec' failed"
}

state=/run/reconciled
mkdir -p "$state"

# Converge once at startup, then remember the post-reconcile signatures.
for t in $TABLES; do
  reconcile_table "$t"
  sig "$t" > "$state/$t"
done
log "control loop up (watch: $TABLES)"

while true; do
  for t in $TABLES; do
    cur=$(sig "$t"); prev=$(cat "$state/$t" 2>/dev/null || echo 0)
    if [ "$cur" != "$prev" ]; then
      log "table '$t' changed ($prev -> $cur)"
      reconcile_table "$t"
      sig "$t" > "$state/$t"
    fi
  done
  sleep 2
done
