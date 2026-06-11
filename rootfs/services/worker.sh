#!/usr/bin/env bash
# One-shot legacy helper kept for BusyBox fallback experiments. Normal service
# lifecycle is owned by systemd units, not BDB rows.
set -u

echo "worker: background job online"
sleep 3
echo "worker: done"
