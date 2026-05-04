#!/usr/bin/env bash
# Automated access matrix test for the Zero Trust Access Framework.
# Run: bash scripts/test_access.sh

set -euo pipefail

BASE_URL="http://localhost:8000"
PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_pass() { echo -e "${GREEN}  PASS${NC} $1"; ((PASS++)); }
log_fail() { echo -e "${RED}  FAIL${NC} $1"; ((FAIL++)); }
log_section() { echo -e "\n${YELLOW}=== $1 ===${NC}"; }

get_token() {
  local user=$1 pass=$2
  curl -s -X POST "$BASE_URL/auth/token" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$user\",\"password\":\"$pass\"}" | jq -r .access_token
}

check() {
  local label=$1 token=$2 endpoint=$3 expected_status=$4
  actual=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $token" "$BASE_URL$endpoint")
  if [[ "$actual" == "$expected_status" ]]; then
    log_pass "$label → $endpoint [$actual]"
  else
    log_fail "$label → $endpoint [expected $expected_status, got $actual]"
  fi
}

# ── Startup check ─────────────────────────────────────────────────────────────
log_section "Health Check"
health=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/health")
if [[ "$health" == "200" ]]; then
  log_pass "API is healthy"
else
  echo -e "${RED}ERROR: API not reachable at $BASE_URL (got $health). Is docker compose running?${NC}"
  exit 1
fi

# ── Fetch tokens ──────────────────────────────────────────────────────────────
log_section "Fetching Tokens"
ADMIN_TOKEN=$(get_token "alice.admin" "Admin@1234")
DEV_TOKEN=$(get_token "bob.developer" "Dev@1234")
AUDIT_TOKEN=$(get_token "sara.auditor" "Audit@1234")
RO_TOKEN=$(get_token "ron.readonly" "Read@1234")
echo "  Tokens acquired for: alice.admin, bob.developer, sara.auditor, ron.readonly"

# ── No token ──────────────────────────────────────────────────────────────────
log_section "No Token → 401 Unauthorized"
for ep in /admin/dashboard /developer/api /monitoring/dashboard /security/audit; do
  actual=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL$ep")
  if [[ "$actual" == "401" || "$actual" == "403" ]]; then
    log_pass "unauthenticated → $ep [$actual]"
  else
    log_fail "unauthenticated → $ep [expected 401/403, got $actual]"
  fi
done

# ── Admin (alice.admin) ───────────────────────────────────────────────────────
log_section "Admin (alice.admin) — should access everything"
check "admin" "$ADMIN_TOKEN" "/admin/dashboard"      200
check "admin" "$ADMIN_TOKEN" "/developer/api"        200
check "admin" "$ADMIN_TOKEN" "/monitoring/dashboard" 200
check "admin" "$ADMIN_TOKEN" "/security/audit"       200

# ── Developer (bob.developer) ─────────────────────────────────────────────────
log_section "Developer (bob.developer) — developer/api only"
check "developer" "$DEV_TOKEN" "/developer/api"        200
check "developer" "$DEV_TOKEN" "/admin/dashboard"      403
check "developer" "$DEV_TOKEN" "/monitoring/dashboard" 403
check "developer" "$DEV_TOKEN" "/security/audit"       403

# ── Security Auditor (sara.auditor) ───────────────────────────────────────────
log_section "Security Auditor (sara.auditor) — monitoring + audit"
check "security-auditor" "$AUDIT_TOKEN" "/monitoring/dashboard" 200
check "security-auditor" "$AUDIT_TOKEN" "/security/audit"       200
check "security-auditor" "$AUDIT_TOKEN" "/admin/dashboard"      403
check "security-auditor" "$AUDIT_TOKEN" "/developer/api"        403

# ── Readonly (ron.readonly) ───────────────────────────────────────────────────
log_section "Readonly (ron.readonly) — monitoring only"
check "readonly" "$RO_TOKEN" "/monitoring/dashboard" 200
check "readonly" "$RO_TOKEN" "/admin/dashboard"      403
check "readonly" "$RO_TOKEN" "/developer/api"        403
check "readonly" "$RO_TOKEN" "/security/audit"       403

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────"
echo -e "Results: ${GREEN}$PASS passed${NC}  ${RED}$FAIL failed${NC}"
echo "─────────────────────────────────────"
echo ""
echo "Audit log (last 5 entries):"
tail -5 logs/audit.log 2>/dev/null | jq . || echo "  (no log entries yet)"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
