#!/bin/bash
# pCloud hang watchdog
# ---------------------------------------------------------------------------
# pCloud mounts your drive through an in-kernel FUSE kext (com.pcloud.pcloudfs).
# When its userspace daemon stalls, any stat()/lookup on the mount blocks
# UNINTERRUPTIBLY in the kernel, and every macOS app that touches the mount
# (Finder, Spotlight, your shell, your editor) freezes with it. That is how a
# single stuck daemon turns into a whole-system beachball.
#
# This watchdog runs every 30s from a per-user LaunchAgent and does three things:
#   1. Probes the mount with a forced daemon round-trip under a hard timeout.
#   2. If the mount is hung, it first grabs a stack SAMPLE of the stuck daemon
#      (so you can see WHY it stalled: network read, disk, or a lock), then
#   3. kill -9's pCloud, which releases the kext locks and unfreezes the system,
#      and relaunches it.
#
# The important design choice: the probe and the sample run in the BACKGROUND
# and are watched with a polling deadline. The watchdog never waits on them
# directly. A stuck probe sits in uninterruptible kernel wait and only dies once
# pCloud is killed, so waiting on it would hang the watchdog too.
# ---------------------------------------------------------------------------

set -u

# ---- config ---------------------------------------------------------------
# Default pCloud mount location. Change this if you mounted pCloud elsewhere.
MOUNT="$HOME/pCloud Drive"
APP="/Applications/pCloud Drive.app"
DAEMON_MATCH="/Applications/pCloud Drive.app/Contents/MacOS/pCloud Drive"
PROBE_TIMEOUT=12          # seconds the mount may take to answer before we call it hung
SAMPLE_SECONDS=2          # duration of the diagnostic stack sample
SAMPLE_DEADLINE=20        # max seconds to wait for the sample before forcing the kill
RELAUNCH=1                # 1 = relaunch pCloud after killing; 0 = kill only
LOGDIR="$HOME/Library/Logs/pcloud-watchdog"
LOG="$LOGDIR/watchdog.log"
LOCK="/tmp/pcloud-watchdog.lock"
# ---------------------------------------------------------------------------

mkdir -p "$LOGDIR"
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

# Single-instance lock (mkdir is atomic). If a prior run is still recovering, skip.
if ! mkdir "$LOCK" 2>/dev/null; then exit 0; fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

# Only watch if pCloud is actually running. If you quit it on purpose, do nothing.
DAEMON_PID=$(pgrep -f "$DAEMON_MATCH" | head -1)
[ -z "$DAEMON_PID" ] && exit 0

# Probe: a lookup of a path that does not exist forces the daemon to answer
# ENOENT (it is never served from a positive cache), so it blocks if the daemon
# is wedged.
( /usr/bin/stat "$MOUNT/.pcloud_watchdog_probe" >/dev/null 2>&1 ) &
PROBE_PID=$!

waited=0
while [ "$waited" -lt "$PROBE_TIMEOUT" ]; do
  kill -0 "$PROBE_PID" 2>/dev/null || break   # probe returned -> mount healthy
  sleep 1
  waited=$((waited+1))
done

# Probe finished in time, so the mount is healthy. Nothing to do.
if ! kill -0 "$PROBE_PID" 2>/dev/null; then
  exit 0
fi

# --- Mount is hung from here on -------------------------------------------
TS=$(date '+%Y%m%d-%H%M%S')
log "HANG DETECTED: mount '$MOUNT' did not respond within ${PROBE_TIMEOUT}s (daemon pid $DAEMON_PID)."

# (2) Capture WHERE the daemon is stuck, before killing it.
SAMPLE_FILE="$LOGDIR/hang-$TS.sample.txt"
( /usr/bin/sample -file "$SAMPLE_FILE" "$DAEMON_PID" "$SAMPLE_SECONDS" >/dev/null 2>&1 ) &
SAMPLE_PID=$!
swaited=0
while [ "$swaited" -lt "$SAMPLE_DEADLINE" ]; do
  kill -0 "$SAMPLE_PID" 2>/dev/null || break
  sleep 1
  swaited=$((swaited+1))
done
if kill -0 "$SAMPLE_PID" 2>/dev/null; then
  log "sample did not finish within ${SAMPLE_DEADLINE}s; proceeding to kill (sample may be partial)."
  kill -9 "$SAMPLE_PID" 2>/dev/null
else
  log "captured daemon stack sample -> $SAMPLE_FILE"
fi

# (3) Recover: kill pCloud, which releases the kext locks and unfreezes the system.
log "killing pCloud (daemon + finder extensions)."
pkill -9 -f "$DAEMON_MATCH" 2>/dev/null
pkill -9 -f "pCloudFinderExt" 2>/dev/null

sleep 2

if [ "$RELAUNCH" -eq 1 ]; then
  if /usr/bin/open -a "$APP" 2>/dev/null; then
    log "relaunched pCloud."
  else
    log "relaunch FAILED (open -a '$APP')."
  fi
else
  log "kill-only mode; not relaunching."
fi

exit 0
