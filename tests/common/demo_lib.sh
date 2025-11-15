#!/usr/bin/env bash
set -euo pipefail
if command -v tput >/dev/null 2>&1; then
  C_BOLD=$(tput bold); C_DIM=$(tput dim); C_RED=$(tput setaf 1); C_GRN=$(tput setaf 2)
  C_YLW=$(tput setaf 3); C_BLU=$(tput setaf 4); C_CYN=$(tput setaf 6); C_RST=$(tput sgr0)
else
  C_BOLD=""; C_DIM=""; C_RED=""; C_GRN=""; C_YLW=""; C_BLU=""; C_CYN=""; C_RST=""
fi
bar() { printf "\n${C_DIM}────────────────────────────────────────────────────────────${C_RST}\n"; }
title() { printf "\n${C_BOLD}%s${C_RST}\n" "$1"; }
kv() { printf "  ${C_DIM}%s${C_RST}: %s\n" "$1" "$2"; }

pp_json() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY' 2>/dev/null || cat
import sys, json
try:
  print(json.dumps(json.loads(sys.stdin.read()), indent=2, ensure_ascii=False))
except Exception:
  sys.stdout.write(sys.stdin.read())
PY
  else
    cat
  fi
}

curl_demo() {
  local method="$1"; shift
  local url="$1"; shift
  local apikey="${APIKEY:-demo}"
  local data="${1-}"
  title "$method $url"
  kv "Header" "apikey: $apikey"
  if [[ -n "${data:-}" ]]; then
    kv "Payload" "" && echo "$data" | pp_json
  fi
  bar
  local tmp_resp tmp_hdr http_code
  tmp_resp=$(mktemp); tmp_hdr=$(mktemp)
  http_code=$(curl -s -o "$tmp_resp" -D "$tmp_hdr" -w "%{http_code}" \
    -H "apikey: $apikey" -H "Content-Type: application/json" \
    -X "$method" "$url" ${data:+--data "$data"})
  printf "${C_DIM}Response headers:${C_RST}\n"; sed -n '1,25p' "$tmp_hdr"
  printf "\n${C_DIM}Response body:${C_RST}\n"; cat "$tmp_resp" | pp_json
  printf "\n${C_BLU}HTTP ${http_code}${C_RST}\n"
  rm -f "$tmp_resp" "$tmp_hdr"
  bar
}
