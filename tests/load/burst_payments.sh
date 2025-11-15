#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../common/demo_lib.sh"

ENDPOINT="${ENDPOINT:-http://localhost:8080}"
APIKEY="${APIKEY:-demo}"
ORDERS="${ORDERS:-50}"         # cuántas órdenes crear
AMOUNT="${AMOUNT:-15}"         # monto a pagar
CONCURRENCY="${CONCURRENCY:-10}" # pagos concurrentes

title "BURST PAYMENTS (Queue + CB) — create ${ORDERS} real orders, then pay with concurrency=${CONCURRENCY}"
kv "Endpoint" "$ENDPOINT"
kv "Amount" "$AMOUNT"
bar

# 1) Crear N órdenes reales y recolectar IDs
ids=()
for i in $(seq 1 "$ORDERS"); do
  payload='{"items":[{"sku":"A","qty":1}]}'
  resp=$(curl -s -H "apikey: $APIKEY" -H "Content-Type: application/json" \
            -X POST "$ENDPOINT/orders" --data "$payload")
  id=$(echo "$resp" | python3 -c 'import sys,json; import re
try:
  d=json.load(sys.stdin)
  print(d.get("id") or d.get("orderId") or d.get("order_id") or "")
except Exception:
  s=sys.stdin.read()
  m=re.search(r"\"id\"\\s*:\\s*\"?(\\d+)", s)
  print(m.group(1) if m else "")' 2>/dev/null || true)
  if [[ -z "$id" ]]; then
    echo "WARN: No pude extraer ID de respuesta: $resp" >&2
  else
    ids+=("$id")
    printf "%s\n" "${C_DIM}[created]${C_RST} order_id=$id"
  fi
done
bar
echo "Total creadas: ${#ids[@]}"

if [[ "${#ids[@]}" -eq 0 ]]; then
  echo "ERROR: no se pudo crear ninguna orden; abortando." >&2
  exit 1
fi

# 2) Pagar en paralelo (control de concurrencia)
title "Pay burst (concurrency=$CONCURRENCY)"
bar
pids=()
sem=$(mktemp)
mkfifo "$sem" || true
# Implementamos un semáforo simple con xargs si está, sino con jobs
if command -v xargs >/dev/null 2>&1; then
  printf "%s\n" "${ids[@]}" | xargs -I{} -P "$CONCURRENCY" bash -c '
    id="$1"; endpoint="$2"; apikey="$3"; amount="$4";
    payload=$(printf "{\"amount\": %s}" "$amount")
    code=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "apikey: '"$APIKEY"'" -H "Content-Type: application/json" \
      -X POST "$endpoint/orders/$id/pay" --data "$payload")
    printf "%s " "$code"
  ' _ {} "$ENDPOINT" "$APIKEY" "$AMOUNT"
  echo
else
  # fallback sin xargs: limitar con jobs
  active=0
  for id in "${ids[@]}"; do
    (
      payload=$(printf '{"amount": %s}' "$AMOUNT")
      code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "apikey: $APIKEY" -H "Content-Type: application/json" \
        -X POST "$ENDPOINT/orders/$id/pay" --data "$payload")
      printf "%s " "$code"
    ) &
    active=$((active+1))
    if (( active % CONCURRENCY == 0 )); then wait; fi
  done
  wait || true
  echo
fi

bar
echo "RabbitMQ UI http://localhost:15672 look for 'payments' (Ready/Unacked)."
