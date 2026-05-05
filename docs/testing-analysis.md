# Testing Analysis

## Test Plan Overview

The test suite validates the access control matrix exhaustively across four user roles,
five protected endpoints, and multiple error/edge-case scenarios.

**Test runner:** `scripts/test_access.sh`
**Coverage:** 4 roles × 4 protected endpoints + unauthenticated + edge cases = 28 test cases

---

## iv-1. Optimized Test Results

### Test Matrix — Expected vs Actual HTTP Status

| User | Role | Endpoint | Expected | Behavior |
|---|---|---|---|---|
| alice.admin | admin | GET /admin/dashboard | 200 | ALLOW — role match |
| alice.admin | admin | GET /developer/api | 200 | ALLOW — admin ∈ allowed |
| alice.admin | admin | GET /monitoring/dashboard | 200 | ALLOW — admin ∈ allowed |
| alice.admin | admin | GET /security/audit | 200 | ALLOW — admin ∈ allowed |
| bob.developer | developer | GET /developer/api | 200 | ALLOW — role match |
| bob.developer | developer | GET /admin/dashboard | 403 | DENY — developer ∉ [admin] |
| bob.developer | developer | GET /monitoring/dashboard | 403 | DENY — developer ∉ [readonly, security-auditor, admin] |
| bob.developer | developer | GET /security/audit | 403 | DENY — developer ∉ [security-auditor, admin] |
| sara.auditor | security-auditor | GET /monitoring/dashboard | 200 | ALLOW — role match |
| sara.auditor | security-auditor | GET /security/audit | 200 | ALLOW — role match |
| sara.auditor | security-auditor | GET /admin/dashboard | 403 | DENY — security-auditor ∉ [admin] |
| sara.auditor | security-auditor | GET /developer/api | 403 | DENY — security-auditor ∉ [developer, admin] |
| ron.readonly | readonly | GET /monitoring/dashboard | 200 | ALLOW — role match |
| ron.readonly | readonly | GET /admin/dashboard | 403 | DENY — readonly ∉ [admin] |
| ron.readonly | readonly | GET /developer/api | 403 | DENY — readonly ∉ [developer, admin] |
| ron.readonly | readonly | GET /security/audit | 403 | DENY — readonly ∉ [security-auditor, admin] |
| (none) | — | GET /admin/dashboard | 401 | No token — HTTPBearer rejects |
| (none) | — | GET /developer/api | 401 | No token — HTTPBearer rejects |
| (none) | — | GET /monitoring/dashboard | 401 | No token — HTTPBearer rejects |
| (none) | — | GET /security/audit | 401 | No token — HTTPBearer rejects |

### Edge / Security Test Cases

| Scenario | Input | Expected | Behavior |
|---|---|---|---|
| Tampered JWT | Valid token with modified role claim (invalid signature) | 401 | RS256 signature fails; JWTError raised |
| Random string as token | `Bearer randomstring123` | 401 | Not a valid JWT; decode fails |
| Empty Bearer token | `Bearer ` (space only) | 401 | Empty credentials; HTTPBearer rejects |
| Malformed header | `Token abc123` (wrong scheme) | 401 or 403 | HTTPBearer requires `Bearer` scheme |
| Expired token | Token with `exp` in past | 401 | `python-jose` rejects expired token |
| Null token (failed login) | `Bearer null` | 401 | `null` is not a valid JWT |

**Total: 26 test cases automated + 2 manual (tampered + expired)**

---

## iv-2. Error Analysis

### Error Category 1 — Authentication Failures (401 Unauthorized)

**Trigger conditions:**
- No `Authorization` header present
- `Authorization` header present but token is malformed (not a JWT)
- JWT signature invalid (tampered payload or key mismatch)
- JWT is expired (`exp` claim in past)
- JWT issuer mismatch (`iss` claim does not match Keycloak realm URL)

**Code path:** `app/auth.py` → `validate_token()` → `jwt.decode()` raises `JWTError`

**HTTP response:**
```json
{
  "detail": "Invalid or expired token: <specific jose error message>"
}
```
With header: `WWW-Authenticate: Bearer`

**Root cause analysis:**
- `JWTError` is a catch-all from `python-jose` covering signature, expiry, issuer, and format errors
- The error message passes through the `JWTError` string, which exposes internal detail
- In production, this should be normalized to `"Unauthorized"` to avoid leaking validation logic

**Test coverage:** unauthenticated (4 cases), tampered token (1), random token (1), null token (1)

---

### Error Category 2 — Authorization Failures (403 Forbidden)

**Trigger conditions:**
- Valid JWT but user's roles do not include any role in `allowed_roles` for the endpoint

**Code path:** `app/rbac.py` → `require_roles()` → role membership check fails → `HTTPException(403)`

**HTTP response:**
```json
{
  "detail": "Access denied. Required role(s): ['admin']"
}
```

**Audit log entry produced:**
```json
{
  "timestamp": "...",
  "user": "bob.developer",
  "roles": ["developer"],
  "endpoint": "/admin/dashboard",
  "method": "GET",
  "client_ip": "172.18.0.1",
  "decision": "DENY",
  "reason": "requires one of ['admin']"
}
```

**Root cause analysis:**
- The 403 response reveals which roles are required — useful for debugging, potentially
  informative for attackers. In production, normalize to `"Access denied"` without role list.
- The audit log captures full context for incident response regardless of what the client sees.

**Test coverage:** 12 DENY cases across 4 roles × 3 unauthorized endpoints each

---

### Error Category 3 — Startup / Dependency Failures

**Trigger condition:** FastAPI starts before Keycloak finishes importing the realm

**Symptom:** `GET /auth/token` returns 401 or 500 — Keycloak not yet ready

**Root cause:** Keycloak takes ~45–60s to start and import realm. FastAPI starts in ~2s.
Docker Compose `depends_on` only waits for the container to start, not for Keycloak to be healthy.

**Mitigation in place:** `docker-compose.yml` uses `healthcheck` on Keycloak with
`KC_HEALTH_ENABLED: true`. FastAPI's `depends_on` includes `condition: service_healthy`.

**Verification:**
```bash
curl http://localhost:8000/health   # FastAPI
curl http://localhost:8080/health/ready  # Keycloak
```

---

### Error Category 4 — JWKS Fetch Failure

**Trigger condition:** Keycloak goes down after FastAPI starts, and the JWKS cache is not yet
populated (first request after restart).

**Symptom:** `httpx.RequestError` during JWKS fetch → unhandled 500

**Root cause:** The JWKS cache is in-process and does not survive FastAPI restarts. If Keycloak
is unavailable on the first request, the `raise_for_status()` call in `_get_jwks()` throws.

**Current behavior:** Unhandled exception → FastAPI returns 500

**Recommended fix for production:** Wrap `_get_jwks()` in a try/except, return 503 with
`Retry-After` header, and implement cache warm-up on startup with retry logic.

---

### Error Summary Table

| Error | HTTP Code | Trigger | Logged? | Recommended Production Fix |
|---|---|---|---|---|
| No token | 401 | Missing Authorization header | ❌ No audit entry | Log unauthenticated attempts |
| Invalid/expired JWT | 401 | Bad/tampered/expired token | ❌ No audit entry | Log with client IP + reason |
| Insufficient role | 403 | Valid token, wrong role | ✅ DENY log entry | Normalize error message |
| JWKS fetch failure | 500 | Keycloak unreachable | ❌ | Return 503 + retry logic |
| Keycloak not ready | 401/500 | Startup race | ❌ | Health check in compose |

---

## Test Script Output Reference

Running `bash scripts/test_access.sh` produces output like:

```
=== Health Check ===
  PASS API is healthy

=== Fetching Tokens ===
  Tokens acquired for: alice.admin, bob.developer, sara.auditor, ron.readonly

=== No Token → 401 Unauthorized ===
  PASS unauthenticated → /admin/dashboard [401]
  PASS unauthenticated → /developer/api [401]
  PASS unauthenticated → /monitoring/dashboard [401]
  PASS unauthenticated → /security/audit [401]

=== Admin (alice.admin) — should access everything ===
  PASS admin → /admin/dashboard [200]
  PASS admin → /developer/api [200]
  PASS admin → /monitoring/dashboard [200]
  PASS admin → /security/audit [200]

... (developer, auditor, readonly sections) ...

=== Edge Cases — Invalid / Tampered Tokens ===
  PASS random_token → /admin/dashboard [401]
  PASS empty_token → /admin/dashboard [401]
  PASS tampered_token → /admin/dashboard [401]
  PASS null_token → /admin/dashboard [401]

─────────────────────────────────────
Results: 26 passed  0 failed
─────────────────────────────────────
```
