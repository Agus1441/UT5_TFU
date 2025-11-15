#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../common/demo_lib.sh"

ENDPOINT="${ENDPOINT:-http://localhost:8080}"
APIKEY="${APIKEY:-demo}"

title "GATEWAY HEALTH"
curl_demo "GET" "$ENDPOINT/health"

title "SERVICES HEALTH (proxied via gateway path)"
echo "(This demo uses the same /health routed to orders-read)"
curl_demo "GET" "$ENDPOINT/health"
