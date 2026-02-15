#!/bin/bash
# Integration tests for demo flows against the live API.
# Run: bash workers/test-demo-flows.sh
# These validate that the deployed backend accepts the exact payloads
# our iOS app sends for demo scenarios.

set -euo pipefail
API="https://api.robo.app"
PASS=0
FAIL=0
CLEANUP_IDS=()

red() { printf "\033[31m%s\033[0m\n" "$1"; }
green() { printf "\033[32m%s\033[0m\n" "$1"; }
bold() { printf "\033[1m%s\033[0m\n" "$1"; }

assert_status() {
  local test_name="$1" expected="$2" actual="$3"
  if [ "$actual" -eq "$expected" ]; then
    green "  ✓ $test_name (HTTP $actual)"
    PASS=$((PASS + 1))
  else
    red "  ✗ $test_name — expected HTTP $expected, got HTTP $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_json_field() {
  local test_name="$1" json="$2" field="$3" expected="$4"
  local actual
  actual=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('$field',''))" 2>/dev/null || echo "PARSE_ERROR")
  if [ "$actual" = "$expected" ]; then
    green "  ✓ $test_name"
    PASS=$((PASS + 1))
  else
    red "  ✗ $test_name — expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

cleanup() {
  for id in "${CLEANUP_IDS[@]}"; do
    curl -s -X DELETE "$API/api/hits/$id" > /dev/null 2>&1 || true
  done
}
trap cleanup EXIT

# ─── Test 1: group_poll HIT type is accepted ───
bold "Test 1: Create group_poll HIT"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API/api/hits" \
  -H "Content-Type: application/json" \
  -d '{
    "recipient_name": "Group Poll",
    "task_description": "Vote on dates for: Ski Trip",
    "hit_type": "group_poll",
    "config": {
      "title": "Ski Trip",
      "date_options": ["2027-02-13", "2027-02-20", "2027-02-27"],
      "participants": ["Vince", "E", "Turtle"],
      "context": "Ski Trip"
    }
  }')
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
assert_status "group_poll accepted" 201 "$HTTP_CODE"
HIT_ID=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
if [ -n "$HIT_ID" ]; then
  CLEANUP_IDS+=("$HIT_ID")
  assert_json_field "returns URL" "$BODY" "url" "https://robo.app/hit/$HIT_ID"
  green "  ✓ HIT ID: $HIT_ID"
else
  red "  ✗ No HIT ID returned"
  FAIL=$((FAIL + 1))
fi

# ─── Test 2: Demo text — ski trip with natural language ───
bold "Test 2: Demo scenario — ski trip with weekends in Feb/March 2027"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API/api/hits" \
  -H "Content-Type: application/json" \
  -d '{
    "recipient_name": "Group Poll",
    "task_description": "Vote on dates for: Boys ski trip in Tahoe",
    "hit_type": "group_poll",
    "config": {
      "title": "Boys ski trip in Tahoe",
      "date_options": ["2027-02-13", "2027-02-20", "2027-02-27", "2027-03-06", "2027-03-13", "2027-03-20", "2027-03-27"],
      "participants": ["Vince", "Eric", "Turtle", "Drama"],
      "context": "Boys ski trip in Tahoe"
    }
  }')
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
assert_status "ski trip poll created" 201 "$HTTP_CODE"
HIT_ID2=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
[ -n "$HIT_ID2" ] && CLEANUP_IDS+=("$HIT_ID2")

# ─── Test 3: Respond to group poll ───
if [ -n "$HIT_ID" ]; then
  bold "Test 3: Respond to group poll"
  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API/api/hits/$HIT_ID/respond" \
    -H "Content-Type: application/json" \
    -d '{
      "respondent_name": "Vince",
      "response_data": {"selected_dates": ["2027-02-20"]}
    }')
  HTTP_CODE=$(echo "$RESPONSE" | tail -1)
  assert_status "valid participant can respond" 201 "$HTTP_CODE"

  # Test 4: Duplicate response rejected
  bold "Test 4: Duplicate response rejected"
  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API/api/hits/$HIT_ID/respond" \
    -H "Content-Type: application/json" \
    -d '{
      "respondent_name": "Vince",
      "response_data": {"selected_dates": ["2027-02-27"]}
    }')
  HTTP_CODE=$(echo "$RESPONSE" | tail -1)
  assert_status "duplicate rejected" 409 "$HTTP_CODE"

  # Test 5: Non-participant rejected
  bold "Test 5: Non-participant rejected"
  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API/api/hits/$HIT_ID/respond" \
    -H "Content-Type: application/json" \
    -d '{
      "respondent_name": "RandomPerson",
      "response_data": {"selected_dates": ["2027-02-20"]}
    }')
  HTTP_CODE=$(echo "$RESPONSE" | tail -1)
  assert_status "non-participant rejected" 400 "$HTTP_CODE"
fi

# ─── Test 6: Standard HIT types still work ───
bold "Test 6: Standard photo HIT still works"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API/api/hits" \
  -H "Content-Type: application/json" \
  -d '{"recipient_name": "Test User", "task_description": "Take a photo", "hit_type": "photo"}')
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
assert_status "photo HIT accepted" 201 "$HTTP_CODE"
HIT_ID3=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
[ -n "$HIT_ID3" ] && CLEANUP_IDS+=("$HIT_ID3")

bold "Test 7: Availability HIT still works"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API/api/hits" \
  -H "Content-Type: application/json" \
  -d '{"recipient_name": "Test User", "task_description": "When are you free?", "hit_type": "availability"}')
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
assert_status "availability HIT accepted" 201 "$HTTP_CODE"
HIT_ID4=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
[ -n "$HIT_ID4" ] && CLEANUP_IDS+=("$HIT_ID4")

# ─── Test 8: Invalid hit_type rejected ───
bold "Test 8: Invalid hit_type rejected"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API/api/hits" \
  -H "Content-Type: application/json" \
  -d '{"recipient_name": "Test", "task_description": "test", "hit_type": "invalid_type"}')
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
assert_status "invalid type rejected" 400 "$HTTP_CODE"

# ─── Summary ───
echo ""
bold "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && green "All tests passed!" || red "Some tests failed!"
exit "$FAIL"
