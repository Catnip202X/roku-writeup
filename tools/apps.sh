#!/bin/bash
# apps.sh — see and switch which app occupies the single Roku dev slot.
#
#   ./apps.sh          list what's available and what the TV currently holds
#   ./apps.sh 2        install entry 2 (prompts for the developer password)
#
# Roku allows exactly one sideloaded channel (id "dev"); this makes swapping it
# a one-liner instead of a rebuild-and-remember exercise.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
WS="$(dirname "$HERE")"
TV="${ROKU_IP:-TARGET_IP}"

# bash 3.2 has no associative arrays — parallel indexed arrays.
NAMES=("RSPROBE (sandbox REPL)" "SGPROBE (SceneGraph/roHtmlWidget)" "云听小电视 yunting-tv" "云屏 Biliku")
DIRS=("$HERE/probe" "$HERE/probe-sg" "$WS/yunting-tv/app" "$WS/yunping/roku")

current=$(curl -s -m 4 "http://$TV:8060/query/apps" 2>/dev/null |
  sed -n 's/.*<app id="dev"[^>]*>\([^<]*\)<.*/\1/p')

echo "TV  $TV"
echo "dev slot now: ${current:-<empty or unreachable>}"
echo
i=0
while [ $i -lt ${#NAMES[@]} ]; do
  dir="${DIRS[$i]}"
  n=$((i + 1))
  if [ -f "$dir/manifest" ]; then
    title=$(sed -n 's/^title=//p' "$dir/manifest" | head -1)
    printf '  [%d] %-32s %s\n' "$n" "${NAMES[$i]}" "(manifest: $title)"
  else
    printf '  [%d] %-32s MISSING: %s\n' "$n" "${NAMES[$i]}" "$dir"
  fi
  i=$((i + 1))
done

sel="${1:-}"
if [ -z "$sel" ]; then
  echo
  echo "usage: ./apps.sh <1-${#NAMES[@]}>   to install one of the above"
  exit 0
fi

idx=$((sel - 1))
if [ "$idx" -lt 0 ] || [ "$idx" -ge ${#NAMES[@]} ]; then
  echo "no such entry: $sel" >&2
  exit 1
fi
target="${DIRS[$idx]}"
[ -f "$target/manifest" ] || { echo "missing: $target" >&2; exit 1; }

echo
echo ">>> installing ${NAMES[$idx]}"
exec "$HERE/sideload-probe.sh" --app "$target"
