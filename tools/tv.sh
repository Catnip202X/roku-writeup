#!/usr/bin/env bash
# roku-debloat/tv.sh — driver for the Roku "ROKU_TV" debloat engagement
# Target: TARGET_IP  |  50R4CX (L816X)  |  Roku OS 15.3.4.2402  |  SN ROKU_SERIAL
set -uo pipefail
IP="${ROKU_IP:-TARGET_IP}"

con() { printf '%s\n' "$1" | nc -G "${2:-10}" "$IP" 8080 2>/dev/null | tr -d '\r' | sed '1d'; }
ecp() { curl -s -m 5 "$@"; }
press() { ecp -X POST "http://$IP:8060/keypress/$1" -o /dev/null -w "keypress/$1 -> %{http_code}\n"; }
lit() { ecp -X POST "http://$IP:8060/keypress/Lit_$1" -o /dev/null -w "Lit_$1 -> %{http_code}\n"; }

case "${1:-}" in
  plugins)  con 'plugins' 15 ;;
  free)     con 'free' ;;
  rm)       shift; for id in "$@"; do
              echo "--- remove_plugin $id"
              con "remove_plugin $id" 20
            done ;;
  home)     press Home; sleep 3; ecp "http://$IP:8060/query/active-app"; echo ;;
  health)   echo "== active-app =="; ecp "http://$IP:8060/query/active-app"; echo
            echo "== apps =="; ecp "http://$IP:8060/query/apps" | grep -c '<app '
            echo "== flash/plugin space =="; con 'plugins' 15 | tail -2
            echo "== mem =="; con 'free' | head -2 ;;
  *) echo "usage: $0 {plugins|free|rm <id...>|home|health}" ;;
esac
