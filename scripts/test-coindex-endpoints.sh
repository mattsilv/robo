#!/bin/bash
# Smoke test: verify Coindex OAuth2 + album API endpoints exist and respond.
# A non-404 response means the route exists. 400/401/502 are acceptable —
# they prove the endpoint is wired up even without valid auth credentials.

set -euo pipefail

BASE_URL="https://coindex.app"
PASS=0
FAIL=0

check() {
    local description="$1"
    local status="$2"
    local method="$3"
    local path="$4"

    if [[ -z "$status" || "$status" == "000" ]]; then
        echo "FAIL  $description — no response from $method $path"
        FAIL=$((FAIL + 1))
    elif [[ "$status" == "404" ]]; then
        echo "FAIL  $description — $method $path → 404 (endpoint not found!)"
        FAIL=$((FAIL + 1))
    else
        echo "PASS  $description — $method $path → $status"
        PASS=$((PASS + 1))
    fi
}

echo "=== Coindex Endpoint Smoke Tests ==="
echo "Base URL: $BASE_URL"
echo ""

# 1. OAuth2 authorize (GET)
path="/api/oauth2/authorize?response_type=code&client_id=robo_mobile_client&redirect_uri=robo://oauth/callback"
status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${BASE_URL}${path}")
check "OAuth2 authorize endpoint" "$status" "GET" "/api/oauth2/authorize"

# 2. OAuth2 token (POST)
path="/api/oauth2/token"
status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X POST -H "Content-Type: application/json" -d '{}' "${BASE_URL}${path}")
check "OAuth2 token endpoint" "$status" "POST" "$path"

# 3. Presigned album upload (POST)
path="/api/presigned-album-upload"
status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X POST -H "Content-Type: application/json" -d '{}' "${BASE_URL}${path}")
check "Presigned album upload endpoint" "$status" "POST" "$path"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "ENDPOINT MISMATCH — check CoindexService.swift URLs against Coindex API spec"
    exit 1
fi
