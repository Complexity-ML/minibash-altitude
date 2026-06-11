#!/usr/bin/env bash
# Manual helper service. The destructive installer is a command, not an
# autostart service.
set -u

echo "installer: available command: minibash-install --target /dev/DEVICE --yes"
echo "installer: manual helper only; systemd owns lifecycle"
