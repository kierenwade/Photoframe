#!/usr/bin/env bash
# Power the TV on and make the Pi the active HDMI source.
# Runs at boot. The TV ignores CEC for ~15-25s after a cold power cut, so we retry.
set -u

LOG=/data/logs/cec.log
mkdir -p "$(dirname "$LOG")"

cec() { echo "$1" | cec-client -s -d 1 2>>"$LOG"; }

echo "$(date -Is) cec-assert start" >>"$LOG"

for i in $(seq 1 20); do
  cec 'on 0' >/dev/null      # wake the TV (logical address 0 = TV)
  cec 'as'   >/dev/null       # 'active source' -> TV switches to our input

  if cec 'pow 0' | grep -qi 'power status: on'; then
    echo "$(date -Is) TV on after ${i} tries; asserting source once more" >>"$LOG"
    sleep 1
    cec 'as' >/dev/null
    exit 0
  fi
  sleep 2
done

echo "$(date -Is) gave up waiting for TV" >>"$LOG"
exit 0   # never fail the boot over this
