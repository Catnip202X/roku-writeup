#!/bin/bash
# Sideload the RSPROBE sandbox probe onto the Roku.
#
#   ./sideload-probe.sh            install RSPROBE, replacing 云听小电视 in the dev slot
#   ./sideload-probe.sh --restore  put 云听小电视 back (uses build/yunting-tv.zip)
#
# Your developer password is read silently and never written to disk or echoed.
# Result lands in roku-debloat/status.txt for the other agent to pick up.

set -u
TV="${ROKU_IP:-TARGET_IP}"
HERE="$(cd "$(dirname "$0")" && pwd)"
WS="$(dirname "$HERE")"
STATUS="$HERE/status.txt"

say() { printf '%s\n' "$*" | tee -a "$STATUS"; }

: > "$STATUS"
say "=== $(date '+%Y-%m-%d %H:%M:%S') target=$TV mode=${1:-install} ==="

KC_SERVICE="${ROKU_KEYCHAIN_SERVICE:-roku-dev-$TV}"

if [ "${1:-}" = "--forget" ]; then
  if security delete-generic-password -s "$KC_SERVICE" -a rokudev >/dev/null 2>&1; then
    say "forgot stored password for $KC_SERVICE"
  else
    say "no stored password for $KC_SERVICE"
  fi
  exit 0
fi

MODE="${1:-install}"
APP_DIR="$HERE/probe"
ZIP=""

if [ "$MODE" = "--restore" ]; then
  ZIP="$WS/yunting-tv/build/yunting-tv.zip"
  [ -f "$ZIP" ] || { say "MISSING $ZIP — nothing to restore from"; exit 1; }
fi

if [ "$MODE" = "--app" ]; then
  # Accept an absolute path as-is; only prefix $HERE for relative ones.
  case "${2:?usage: --app <dir>}" in
    /*) APP_DIR="$2" ;;
    *)  APP_DIR="$HERE/$2" ;;
  esac
fi

if [ -z "$ZIP" ]; then
  [ -f "$APP_DIR/manifest" ] || { say "NO_MANIFEST in $APP_DIR"; exit 1; }
  ZIP="$HERE/build/$(basename "$APP_DIR").zip"
  mkdir -p "$HERE/build"
  rm -f "$ZIP"
  (cd "$APP_DIR" && zip -qr "$ZIP" . -x '*.DS_Store') || { say "PACKAGE_FAILED"; exit 1; }
  say "packaged $(basename "$APP_DIR") $(du -h "$ZIP" | cut -f1 | tr -d ' ') -> $ZIP"
fi

PW=""
PW_SOURCE="prompt"

# Prefer the login keychain: it is encrypted at rest, unlocks with your login
# password, and means the developer password is typed exactly once.
if command -v security >/dev/null 2>&1 && [ -z "${ROKU_NO_KEYCHAIN:-}" ]; then
  PW=$(security find-generic-password -s "$KC_SERVICE" -a rokudev -w 2>/dev/null) || PW=""
  if [ -n "$PW" ]; then
    PW_SOURCE="keychain"
    say "using stored password from keychain: $KC_SERVICE"
  fi
fi

if [ -z "$PW" ]; then
  if [ ! -t 0 ]; then
    say "NO_TTY: run this directly in a Terminal window so the password prompt works."
    exit 1
  fi
  read -r -s -p "Roku developer password: " PW
  echo
fi

RESP=$(curl -s -m 90 --digest --user "rokudev:$PW" -w '\nHTTP_CODE %{http_code}' \
  -F "mysubmit=Install" -F "archive=@$ZIP" "http://$TV/plugin_install" 2>&1)
CURL_RC=$?

if [ $CURL_RC -ne 0 ]; then
  say "UNREACHABLE curl_rc=$CURL_RC (is the TV on? tcp/80 open?)"
  exit 1
fi

CODE=$(printf '%s' "$RESP" | tail -1 | awk '{print $2}')
say "http_code=$CODE"
if [ "$CODE" = "401" ]; then say "BAD_PASSWORD"; unset PW; exit 1; fi

# Store only after the TV has accepted it, so a typo never gets saved.
if [ "$PW_SOURCE" = "prompt" ] && [ -n "$PW" ] && command -v security >/dev/null 2>&1 \
   && [ -z "${ROKU_NO_KEYCHAIN:-}" ]; then
  if security add-generic-password -U -a rokudev -s "$KC_SERVICE" -w "$PW" >/dev/null 2>&1; then
    say "saved password to keychain: $KC_SERVICE (next run won't ask)"
  else
    say "could not write to keychain; password not saved"
  fi
fi
unset PW
if [ "$CODE" != "200" ]; then
  say "UNEXPECTED_HTTP"
  # Dump the full body — Roku puts the actual rejection reason in here.
  printf '%s\n' "$RESP" > "$HERE/build/install-error.html"
  say "full response saved to build/install-error.html ($(wc -c < "$HERE/build/install-error.html" | tr -d ' ') bytes)"
  exit 1
fi

VERDICT=$(printf '%s' "$RESP" | grep -oiE 'Install Success|Identical to previous version|Install Failure[^"<]*|Compil[^"<]*[Ee]rror[^"<]*' | head -1)
say "verdict=${VERDICT:-unknown}"
if printf '%s' "$VERDICT" | grep -qi 'success'; then
  say "RESULT=INSTALL_OK"
elif printf '%s' "$VERDICT" | grep -qi 'identical'; then
  say "RESULT=ALREADY_INSTALLED"
else
  say "RESULT=INSTALL_PROBLEM"
  printf '%s\n' "$RESP" | sed -n '1,20p'
fi
say "=== done ==="
