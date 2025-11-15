#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

ENDPOINT="${ENDPOINT:-http://localhost:8080}"
APIKEY="${APIKEY:-demo}"
ORDERS="${ORDERS:-50}"
AMOUNT="${AMOUNT:-15}"
FAST="${FAST:-0}"
PART="${PART:-all}"

say() { printf "\n\033[1m%s\033[0m\n" "$*"; }
bar() { printf "\033[2m────────────────────────────────────────────────────────────\033[0m\n"; }
pause() { [[ "$FAST" == "1" ]] || read -r -p "⏸  Press Enter to continue..."; }

step_health() {
  say "Part 1 — Availability: Health + Circuit Breaker"
  bar
  tests/availability/health_smoke.sh
  pause

  say "Open breaker (simulate failures at provider: rate=1.0)"
  make cb-open
  echo
  say "Trigger several payments — expect fast 503 once breaker is OPEN"
  for i in $(seq 1 10); do
    code=$(curl -s -o /dev/null -w "%{http_code} " \
      -H "apikey: $APIKEY" -H "Content-Type: application/json" \
      -X POST "$ENDPOINT/orders/$((2000+i))/pay" --data '{"amount":5}')
    printf "%s " "$code"
  done
  echo
  pause

  say "Close breaker (rate=0.0) — half-open probes should succeed"
  make cb-close
  bar

  pause
  say "Verificando recuperación (esperamos volver a HTTP 200)"
  sleep 3
  for i in $(seq 1 3); do
    code=$(curl -s -o /dev/null -w "%{http_code} " \
      -H "apikey: $APIKEY" -H "Content-Type: application/json" \
      -X POST "$ENDPOINT/orders/$((3000+i))/pay" --data '{"amount":5}')
    printf "%s " "$code"
  done
  echo
  bar
}


step_performance() {
  say "Part 2 — Performance: Queue + Competing Consumers + CQRS + Cache"
  bar
  ENDPOINT="$ENDPOINT" APIKEY="$APIKEY" ORDERS="$ORDERS" AMOUNT="$AMOUNT"     tests/load/burst_payments.sh
  pause

  say "Query the same order twice — second call should be faster (cache)"
  { time curl -s -H "apikey: $APIKEY" "$ENDPOINT/orders/123" >/dev/null; } 2>&1 | tail -n1
  { time curl -s -H "apikey: $APIKEY" "$ENDPOINT/orders/123" >/dev/null; } 2>&1 | tail -n1
  echo "TIP: Open RabbitMQ UI http://localhost:15672 to see queue activity."
  bar
}

step_security() {
  say "Part 3 — Security: API Key + Rate Limiting at Gateway"
  bar
  ENDPOINT="$ENDPOINT" APIKEY="$APIKEY" tests/security/auth_and_rl.sh
  bar
}

step_config() {
  say "Part 4 — Mod/Deploy: External Configuration Store (hot change)"
  bar
  echo "Current:"
  curl -s http://localhost:8088/config | python3 -m json.tool || curl -s http://localhost:8088/config
  echo
  echo "Apply change: paymentMaxRetries=1, cacheTtlSec=3"
  curl -s -X POST http://localhost:8088/config -H "Content-Type: application/json"     --data '{"paymentMaxRetries":1,"cacheTtlSec":3}' | sed 's/^/  /'
  echo
  echo "New:"
  curl -s http://localhost:8088/config | python3 -m json.tool || curl -s http://localhost:8088/config
  bar
}

case "$PART" in
  availability) step_health ;;
  performance)  step_performance ;;
  security)     step_security ;;
  config)       step_config ;;
  all)
    step_health; pause
    step_performance; pause
    step_security; pause
    step_config
    ;;
  *) echo "Unknown PART=$PART (use availability|performance|security|config|all)"; exit 1;;
esac

say "Demo complete."
