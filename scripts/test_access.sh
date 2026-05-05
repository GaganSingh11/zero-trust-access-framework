#!/usr/bin/env bash
# Automated access matrix test for the Zero Trust Access Framework.
# Run: bash scripts/test_access.sh

set -euo pipefail

BASE_URL="http://localhost:8000"
PASS=0
FAIL=0
ERRORS=()

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_pass() { echo -e "${GREEN}  PASS${NC} $1"; ((PASS++)); }
log_fail() { echo -e "${RED}  FAIL${NC} $1"; ((FAIL++)); ERRORS+=("$1"); }
log_section() { echo -e "\n${YELLOW}=== $1 ===${NC}"; }
log_info() { echo -e "${CYAN}  INFO${NC} $1"; }

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

check_no_auth() {
  local label=$1 endpoint=$2
  actual=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL$endpoint")
  if [[ "$actual" == "401" || "$actual" == "403" ]]; then
    log_pass "$label → $endpoint [$actual]"
  else
    log_fail "$label → $endpoint [expected 401, got $actual]"
  fi
}

check_raw_header() {
  local label=$1 header=$2 endpoint=$3 expected_status=$4
  actual=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "$header" "$BASE_URL$endpoint")
  if [[ "$actual" == "$expected_status" ]]; then
    log_pass "$label → $endpoint [$actual]"
  else
    log_fail "$label → $endpoint [expected $expected_status, got $actual]"
  fi
}

tamper_token() {
  local token=$1
  local header payload signature
  header=$(echo "$token" | cut -d'.' -f1)
  payload=$(echo "$token" | cut -d'.' -f2)
  signature=$(echo "$token" | cut -d'.' -f3)

  # Decode payload, inject admin role, re-encode — signature becomes invalid
  local pad decoded tampered_payload
  pad=$(echo "$payload" | awk '{ n=length($0)%4; if(n==2) print $0"=="; else if(n==3) print $0"="; else print $0 }')
  decoded=$(echo "$pad" | base64 -d 2>/dev/null || echo "{}")
  tampered_payload=$(echo "$decoded" | jq -c '.roles = ["admin"]' 2>/dev/null \
    | base64 | tr -d '=' | tr '+/' '-_' | tr -d '\n')

  echo "${header}.${tampered_payload}.${signature}"
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

for tok in "$ADMIN_TOKEN" "$DEV_TOKEN" "$AUDIT_TOKEN" "$RO_TOKEN"; do
  if [[ "$tok" == "null" || -z "$tok" ]]; then
    echo -e "${RED}ERROR: Token acquisition failed. Is Keycloak ready? (wait ~60s after compose up)${NC}"
    exit 1
  fi
done
log_info "Tokens acquired for: alice.admin, bob.developer, sara.auditor, ron.readonly"

# ── No token (unauthenticated) ─────────────────────────────────────────────────
log_section "No Token → 401 Unauthorized"
for ep in /admin/dashboard /developer/api /monitoring/dashboard /security/audit; do
  check_no_auth "unauthenticated" "$ep"
done

# ── Admin (alice.admin) ───────────────────────────────────────────────────────
log_section "Admin (alice.admin) — full access"
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

# ── Edge Cases — Invalid / Tampered Tokens ────────────────────────────────────
log_section "Edge Cases — Invalid / Tampered Tokens"

# Random string (not a JWT at all)
check "random_token"     "randomstring123notajwt" "/admin/dashboard" 401

# "null" string (what jq outputs when token field is absent)
check "null_token"       "null"                   "/admin/dashboard" 401

# Empty / whitespace token
check "empty_token"      " "                      "/admin/dashboard" 401

# Tampered JWT — valid header/signature structure but role claim injected;
# RS256 signature no longer matches → rejected with 401
TAMPERED=$(tamper_token "$DEV_TOKEN")
check "tampered_jwt_role_escalation" "$TAMPERED"  "/admin/dashboard" 401

# Wrong auth scheme (Token instead of Bearer)
check_raw_header "wrong_scheme" "Token $DEV_TOKEN" "/admin/dashboard" 403

# ── Cross-Role Boundary Confirmation ─────────────────────────────────────────
log_section "Cross-Role Boundary — No Accidental Access"
check "developer_no_admin"   "$DEV_TOKEN"   "/admin/dashboard"  403
check "developer_no_audit"   "$DEV_TOKEN"   "/security/audit"   403
check "readonly_no_audit"    "$RO_TOKEN"    "/security/audit"   403
check "readonly_no_admin"    "$RO_TOKEN"    "/admin/dashboard"  403
check "auditor_no_admin"     "$AUDIT_TOKEN" "/admin/dashboard"  403
check "auditor_no_developer" "$AUDIT_TOKEN" "/developer/api"    403

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────"
echo -e "Results: ${GREEN}$PASS passed${NC}  ${RED}$FAIL failed${NC}"
echo "─────────────────────────────────────"

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo -e "${RED}Failed tests:${NC}"
  for err in "${ERRORS[@]}"; do
    echo "  • $err"
  done
fi

echo ""
echo "Audit log (last 5 entries):"
tail -5 logs/audit.log 2>/dev/null | jq . || echo "  (no log entries yet)"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
