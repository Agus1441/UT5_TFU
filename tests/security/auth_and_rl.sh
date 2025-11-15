#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../common/demo_lib.sh"

ENDPOINT="${ENDPOINT:-http://localhost:8080}"
APIKEY="${APIKEY:-demo}"

title "WITHOUT API KEY (should fail)"
bar
http_code=$(curl -s -o /dev/null -w "%{http_code}\n" "$ENDPOINT/orders")
echo "HTTP $http_code (expected 401)"
bar

title "WITH API KEY (should pass health)"
curl_demo "GET" "$ENDPOINT/health"

title "RATE LIMITING BURST"
kv "Requests" "50 to /health"
bar
for i in {1..50}; do
  code=$(curl -s -o /dev/null -w "%{http_code}" -H "apikey: $APIKEY" "$ENDPOINT/health")
  printf "%s " "$code"
done
echo
bar
echo "Look for 429s when the minute quota is exceeded."
