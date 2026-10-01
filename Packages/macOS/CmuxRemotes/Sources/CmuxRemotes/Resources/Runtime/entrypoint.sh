#!/bin/sh
set -eu
umask 077
# An ordinary image directory must never be mistaken for persistent storage.
mountpoint -q /data || { echo 'Persistent /data mount is required' >&2; exit 1; }
mkdir -p /data/home/.local/bin /data/home/.local/state /data/home/.config /data/home/.cache /data/workspace /data/.cmux
chmod 700 /data/home /data/.cmux
ln -sfn /opt/cmux/bin/cmux-tui /data/home/.local/bin/cmux-tui
cp /opt/cmux/runtime.json /data/.cmux/runtime.json.new
mv /data/.cmux/runtime.json.new /data/.cmux/runtime.json
/opt/cmux/bin/cmux-tui remote-probe --json >/dev/null
touch /run/cmux-runtime-ready
cd /data/workspace
exec python3 /opt/cmux/health.py
