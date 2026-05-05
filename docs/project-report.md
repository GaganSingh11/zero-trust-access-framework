# Project Report — Zero Trust Access Framework

## i. Project Brief

**Project:** Zero Trust Access Framework
**Domain:** Cybersecurity — Identity, Access Management, and Zero Trust Architecture
**Stack:** Keycloak 24 · FastAPI · Python · Docker Compose
**Submitted by:** Gagan Multani

This project implements a working Zero Trust Access Control framework for cloud-native regulated
infrastructure. It demonstrates centralized identity management, single sign-on, MFA, JWT-based
authentication, role-based access control, and tamper-evident audit logging — all mapped to
enterprise tooling used in healthcare, banking, and critical infrastructure.

The system is deployable locally via Docker Compose and models the same patterns used with
Okta, Azure AD, HashiCorp Vault, OPA, and Splunk in production environments.

---

## 3a. Brainstorm — Identifying the Problem

### Problem Statement

Perimeter-based security assumes everything inside a network is trustworthy. This assumption
fails routinely:

- **Stolen credentials** give attackers valid identities inside the perimeter
- **Lateral movement** allows attackers to escalate from a compromised low-privilege account
- **No audit trail** means breaches go undetected for months (mean time to detect: ~200 days)
- **Hardcoded or shared secrets** make credential rotation impossible
- **Role creep** over time grants users more permissions than they need

Real incidents that motivated this design:
- **SolarWinds (2020):** Attackers moved laterally inside trusted networks for months undetected
- **Uber (2022):** Social engineering bypassed MFA; attacker reached admin dashboard
- **LastPass (2022):** Developer credentials reused; no per-resource access control
- **Capital One (2019):** Over-privileged IAM role; no audit alerting

### Zero Trust Response

The Zero Trust model (NIST SP 800-207) addresses this with three core rules:
1. **Never trust, always verify** — every request requires proof of identity, regardless of source
2. **Least privilege** — each identity gets access only to what it needs, nothing more
3. **Assume breach** — log everything; treat every access as potentially adversarial

### What to Build

Brainstorming session output:

| Option | Pros | Cons | Selected? |
|---|---|---|---|
| Build a full-stack app with auth | Realistic | Too broad for security focus | ❌ |
| Simulate an attacker with tools | Demonstrates offense | No defensive implementation | ❌ |
| Build an auth + RBAC API gateway | Focused, deployable, testable | Requires IdP integration | ✅ |
| Use cloud IAM (AWS/GCP) | Enterprise-realistic | Not self-contained, costs money | ❌ |

**Decision:** Build a self-contained API gateway backed by a real identity provider (Keycloak),
enforcing RBAC at the middleware layer, with full audit logging. Deployable via Docker Compose
in under 2 minutes.

---

## ii. Project Workflow

See [docs/demo-flow.md](demo-flow.md) for the full step-by-step walkthrough.

High-level workflow:

```
docker compose up → Keycloak imports realm → FastAPI starts → 
POST /auth/token → JWT issued → Bearer token on protected routes → 
RBAC decision → Audit log entry
```

---

## iii. Platforms Preferred

| Layer | Chosen Tool | Why | Enterprise Equivalent |
|---|---|---|---|
| Identity Provider | Keycloak 24 | Open source, OIDC-compliant, Docker-native, MFA built-in | Okta, Azure AD, Ping Identity |
| Auth Protocol | OpenID Connect / JWT | Industry standard; stateless; RS256 for tamper evidence | Same |
| API Framework | FastAPI (Python) | Async, typed, fast to iterate, Swagger UI built-in | Any backend |
| Policy Enforcement | FastAPI middleware | Inline RBAC, easy to understand and audit | OPA, Envoy, Kong |
| Secrets | `.env` → Vault pattern | Simple for demo; pattern maps directly to Vault | HashiCorp Vault, AWS SM |
| Audit Logging | JSON file | Structured, queryable, easy to demo | Splunk, ELK, OpenSearch |
| Containerization | Docker Compose | Single-command deployment, reproducible | Kubernetes + Helm |

---

## 3c. Project Timeline

| Phase | Tasks | Duration | Status |
|---|---|---|---|
| **Phase 1** — Research & Design | Problem identification, OWASP research, ZT architecture design, tool selection | Week 1 | ✅ Done |
| **Phase 2** — Core Infrastructure | Docker Compose setup, Keycloak realm config, realm-export.json, FastAPI scaffold | Week 1–2 | ✅ Done |
| **Phase 3** — Auth & RBAC | `auth.py` JWT validation, JWKS cache, `rbac.py` role enforcement, `logger.py` | Week 2 | ✅ Done |
| **Phase 4** — Testing | Access matrix test script, positive/negative/edge-case coverage, error analysis | Week 2–3 | ✅ Done |
| **Phase 5** — Documentation | Architecture diagrams (Mermaid), demo flow, access matrix, threat model | Week 3 | ✅ Done |
| **Phase 6** — Security Review | CVE analysis, STRIDE threat model, attack surface map, hardening recommendations | Week 3 | ✅ Done |
| **Phase 7** — Final Report | Project report, lessons learned, AI prompts log | Week 3–4 | ✅ Done |

---

## iv. Testing Summary

See [docs/testing-analysis.md](testing-analysis.md) for full detail.

Quick summary:

- **20 automated test cases** covering all role/endpoint combinations
- **Positive tests:** All allowed combinations return 200
- **Negative tests:** All denied combinations return 403
- **Edge cases:** No token → 401, tampered token → 401, malformed header → 401, empty token → 401
- **Error analysis:** All failure modes categorized with root cause and HTTP semantics

---

## v. Proof of Concept

**Live demo:** Run `bash scripts/test_access.sh` against a running stack.

**Video:** *(Record a screen capture of: `docker compose up`, health check, token acquisition for
all 4 users, access matrix test run, audit log review, Keycloak admin console inspection, and
one failed tampered-token attempt.)*

**Expected demo flow (~5 minutes):**
1. Start stack: `docker compose up --build -d` — show Keycloak realm import
2. Health check: `curl http://localhost:8000/health`
3. Get tokens for all 4 users
4. Show admin accessing all endpoints (200)
5. Show developer getting 403 on `/admin/dashboard`
6. Run full automated test: `bash scripts/test_access.sh`
7. Show audit log: `cat logs/audit.log | jq`
8. Optionally: show tampered token returning 401

---

## vi. AI Prompts Used

This project was developed with Claude Code (Anthropic) as a development assistant.
Below are representative prompts used during development, grouped by phase.

### Architecture & Design

```
"I'm building a Zero Trust access control demo. I want to use Keycloak as the IdP 
and FastAPI as the API layer. What's the cleanest way to validate JWTs from Keycloak 
in FastAPI without a per-request network call to Keycloak?"

"How should I structure the Keycloak realm-export.json to pre-configure users, roles, 
and a client with MFA enabled, so the whole realm imports on first startup?"

"Design a role-based access control middleware for FastAPI that takes a list of allowed 
roles, extracts roles from a validated JWT, and logs both ALLOW and DENY decisions."
```

### Security Research

```
"What are the OWASP API Security Top 10 risks most relevant to a JWT-based RBAC 
system, and how would I address each one?"

"Are there any known CVEs for python-jose 3.3.0? How serious are they for a system 
using RS256 with Keycloak-issued tokens?"

"What does a STRIDE threat model look like for an API gateway with Keycloak? I want 
to identify threats, rate their likelihood and impact, and list mitigations."
```

### Implementation

```
"Write the JWKS cache logic for FastAPI — fetch once, cache in-process, and use 
python-jose to validate RS256 tokens. Include proper error handling for expired 
and tampered tokens."

"Generate a Keycloak realm-export.json with: realm name 'zero-trust-demo', 4 users 
(admin, developer, security-auditor, readonly), corresponding roles, a client 
'zt-platform-api' with direct grants enabled and a client secret."

"Write a structured JSON audit logger in Python that writes to both stdout and a 
log file, recording user, roles, endpoint, method, client_ip, decision, and reason."
```

### Testing

```
"Write a bash test script that: fetches tokens for all 4 users, then checks every 
role/endpoint combination against the expected HTTP status code (200 or 403), 
plus unauthenticated tests (401)."

"Add edge case tests to the bash script: tampered JWT payload (base64 decode, 
modify, re-encode without valid signature), completely random token, malformed 
Authorization header, and empty Bearer token."
```

### Documentation

```
"Generate Mermaid diagrams for: system architecture, authentication sequence 
(phases 1-4), RBAC decision flowchart, role access matrix, and token lifecycle."

"Write a STRIDE threat model table for this system covering spoofing, tampering, 
repudiation, information disclosure, DoS, and elevation of privilege."
```

---

## vii. Lessons Learned

### What Worked Well

**1. Keycloak realm-export.json is powerful**
Pre-configuring the entire realm — users, roles, client, MFA flow — as a single JSON file
means the stack is fully reproducible from `docker compose up`. No manual Keycloak setup.
This pattern maps directly to infrastructure-as-code in production (Terraform, Ansible).

**2. Middleware-level RBAC is clean and auditable**
Putting all access control in `rbac.py` with a single `require_roles()` decorator keeps
`main.py` clean and makes the security policy easy to review in one place. Adding a new
endpoint means one decorator — the audit logging happens automatically.

**3. JWKS caching avoids the biggest operational mistake**
Without the in-process JWKS cache, every API request would make a network call to Keycloak.
Under load, this would make Keycloak the availability bottleneck. The cache eliminates that
while still validating every token cryptographically.

**4. Docker Compose made integration testing trivial**
Running the full stack locally (Keycloak + FastAPI + real tokens + real RBAC + real logs) meant
tests reflected actual system behavior — not mocked behavior. No surprises.

### What Was Harder Than Expected

**1. Keycloak startup time**
Keycloak takes ~45–60 seconds to import the realm on first startup. FastAPI starts in ~2 seconds.
The health check at startup had to account for this. In production, liveness/readiness probes
handle this — but in Docker Compose, the startup race is real.

**2. JWT audience validation complexity**
Keycloak sets `aud: ["account"]` by default, not the client ID. Enabling strict audience
verification requires adding a protocol mapper in the realm config. For the demo, `verify_aud`
is disabled — but the code comment and security notes document exactly what to do in production.
This was a good lesson in "secure by default vs. deployable by default."

**3. Direct grant vs. browser MFA**
The `POST /auth/token` endpoint uses Keycloak's direct grant, which bypasses the browser MFA
flow. This is intentional (standard M2M pattern), but it took effort to document clearly so
it doesn't look like a security flaw. The distinction between human and machine flows matters.

### What Would Be Done Differently in Production

| Decision | Demo Choice | Production Choice |
|---|---|---|
| Transport security | HTTP | TLS (reverse proxy with cert) |
| Secrets | `.env` file | HashiCorp Vault / K8s Secrets |
| JWT library | `python-jose` (CVE present) | `joserfc` or `PyJWT` |
| Audience verification | Disabled | Enabled with Keycloak mapper |
| Token revocation | No endpoint | Keycloak revocation + Redis blacklist |
| Rate limiting | None | `slowapi` on `/auth/token` |
| Audit log destination | File | Splunk / ELK / OpenSearch |
| Deployment | Docker Compose | Kubernetes + Helm + NetworkPolicy |
| Key rotation | Static Keycloak keys | Automated JWKS rotation |
