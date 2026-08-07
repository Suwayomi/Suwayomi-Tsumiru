#!/usr/bin/env bash
# Watch a download run: CPU, staging progress, and what the catalog thinks.
#
#   scripts/watch-download.sh [seconds]
#
# A CPU number alone can't tell "the write path is expensive" apart from "the
# work is being thrown away and redone" — they look identical from outside. So
# this samples all three together: how hot the app is, how many pages are
# actually landing in staging, and how many chapters the catalog calls
# downloaded / queued / deleted.

set -euo pipefail
DURATION="${1:-90}"
# Point at whichever install is actually running. A profile/native build uses
# XDG_DATA_HOME; the flatpak keeps its own tree. Watching the wrong one reports
# a perfectly steady zero for an app that is working hard.
APP_DATA="${TSUMIRU_DATA:-$HOME/.var/app/io.github.aaronbamblett.tsumiru/data/tsumiru/offline}"
DB="$APP_DATA/catalog.sqlite"

pid="$(pgrep -x tsumiru | head -1 || true)"
if [[ -z "$pid" ]]; then
  echo "Tsumiru isn't running." >&2
  exit 1
fi

# Read a copy: the app holds the live DB and sqlite would block on its lock.
snapshot_counts() {
  # Copy the WAL and index too: drift runs in WAL mode, so recent commits live
  # beside the main file and a lone .sqlite copy reads as frozen in the past.
  cp -f "$DB" /tmp/tsumiru-catalog-peek.sqlite 2>/dev/null || return
  cp -f "$DB-wal" /tmp/tsumiru-catalog-peek.sqlite-wal 2>/dev/null || true
  cp -f "$DB-shm" /tmp/tsumiru-catalog-peek.sqlite-shm 2>/dev/null || true
  python3 - <<'PY' 2>/dev/null || true
import sqlite3
c = sqlite3.connect('/tmp/tsumiru-catalog-peek.sqlite')
q = lambda s: c.execute(s).fetchone()[0]
print('%s %s %s %s' % (
    q("select count(*) from offline_chapters where device_state='downloaded'"),
    q("select count(*) from offline_chapters where device_state in ('queued','downloading')"),
    q("select count(*) from offline_pages"),
    q("select coalesce(sum(download_generation),0) from offline_chapters"),
))
PY
}

echo "Watching pid $pid for ${DURATION}s."
echo "  staged  = page files sitting in .part dirs right now"
echo "  dl/queue= chapters the catalog calls downloaded / queued+downloading"
echo "  rows    = committed page rows;  gen = total deletes ever"
echo
printf '%-9s %7s %8s %8s %9s %7s %6s\n' 'time' 'cpu%' 'staged' 'partdirs' 'dl/queue' 'rows' 'gen'

peak=0
for ((i = 0; i < DURATION; i++)); do
  kill -0 "$pid" 2>/dev/null || { echo "process exited"; break; }
  cpu="$(top -b -n 1 -p "$pid" | awk -v p="$pid" '$1 == p {print $9; exit}')"
  [[ -z "${cpu:-}" ]] && cpu=0
  staged=$(find "$APP_DATA" -path '*.part/*' -type f ! -name '.manifest' 2>/dev/null | wc -l)
  partdirs=$(find "$APP_DATA" -maxdepth 2 -type d -name '*.part' 2>/dev/null | wc -l)
  read -r dl queued rows gen <<<"$(snapshot_counts)"
  printf '%-9s %7s %8s %8s %9s %7s %6s\n' \
    "$(date +%H:%M:%S)" "$cpu" "$staged" "$partdirs" "${dl:-?}/${queued:-?}" "${rows:-?}" "${gen:-?}"
  awk -v a="$cpu" -v b="$peak" 'BEGIN { exit !(a > b) }' && peak="$cpu"
  sleep 1
done

echo
echo "peak cpu ${peak}%"
echo
echo "Reading it:"
echo "  staged climbing, rows jumping at the end  -> healthy; chapters are landing"
echo "  staged climbing then dropping to 0, rows flat -> work is being discarded"
echo "  gen climbing during the run               -> something is deleting mid-download"
