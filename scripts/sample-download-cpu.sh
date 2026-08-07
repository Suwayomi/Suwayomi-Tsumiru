#!/usr/bin/env bash
# Sample Tsumiru's CPU while it downloads, so "is it still pegged?" gets an
# answer in numbers instead of an impression.
#
#   scripts/sample-download-cpu.sh [seconds]
#
# Start it BEFORE kicking off the download — the old fsync-per-page cost showed
# up the moment pages started landing, and a sampler attached late misses the
# ramp. Reports per-second total CPU across every Tsumiru thread, then a summary.

set -euo pipefail
DURATION="${1:-120}"

pid="$(pgrep -x tsumiru | head -1 || true)"
if [[ -z "$pid" ]]; then
  echo "Tsumiru isn't running. Launch it first:" >&2
  echo "  flatpak run io.github.aaronbamblett.tsumiru" >&2
  exit 1
fi

echo "Sampling pid $pid for ${DURATION}s — start the download now."
echo
printf '%-9s %8s %8s\n' 'time' 'cpu%' 'rss_mb'

samples=()
for ((i = 0; i < DURATION; i++)); do
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "process exited"
    break
  fi
  # top -b gives the same %CPU the user sees, summed over threads.
  read -r cpu rss < <(top -b -n 1 -p "$pid" | awk -v p="$pid" '$1 == p {print $9, $6; exit}')
  [[ -z "${cpu:-}" ]] && continue
  rss_mb=$(awk -v r="${rss//[^0-9]/}" 'BEGIN { printf "%.0f", r / 1024 }')
  printf '%-9s %8s %8s\n' "$(date +%H:%M:%S)" "$cpu" "$rss_mb"
  samples+=("$cpu")
  sleep 1
done

echo
printf '%s\n' "${samples[@]}" | awk '
  { sum += $1; n++; if ($1 > max) max = $1 }
  END {
    if (n == 0) { print "no samples"; exit }
    printf "samples %d   mean %.1f%%   peak %.1f%%\n", n, sum / n, max
    print ""
    # Idle sits near 1%. Never call a run clean without evidence it downloaded
    # anything — a sampler that missed the work looks identical to a fix.
    if (max < 3)       print "INCONCLUSIVE: never left idle. Did the download actually run?"
    else if (max < 15) print "VERDICT: stayed low through the download — the fsync storm is gone."
    else if (max < 40) print "VERDICT: moderate. Better than the 30-80% baseline, worth a second look."
    else               print "VERDICT: still pegged. The fix did not land, or something else is burning CPU."
  }'
