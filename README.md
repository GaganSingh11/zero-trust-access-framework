# Zero Trust Access Framework

A practical Zero Trust Access Framework for cloud-native regulated infrastructure.
Demonstrates centralized identity, SSO, MFA, RBAC, JWT validation, secrets management,
and structured audit logging — mapped to enterprise tools used in healthcare, banking,
and critical infrastructure environments.

## Architecture

```
Client ──► FastAPI (port 8000) ──► Keycloak (port 8080)
              │                         │
              │  validate JWT (JWKS)    │  issue JWT
              │◄────────────────────────┘
              │
              ├── ALLOW → return resource
              └── DENY  → 403 + audit log entry
```

Full architecture diagram: [docs/architecture.md](docs/architecture.md)

## Stack

| Component | Technology | Enterprise Equivalent |
|---|---|---|
| Identity Provider | Keycloak 24 | Okta, Azure AD |
| Auth Protocol | OpenID Connect / JWT | Same |
| MFA | Keycloak OTP | Okta MFA, Duo |
| Protected API | FastAPI (Python) | Any backend |
| Policy Enforcement | FastAPI middleware | OPA, Envoy |
| Secrets | `.env` → Vault pattern | HashiCorp Vault, AWS Secrets Manager |
| Audit Logging | JSON to file | Splunk, ELK, OpenSearch |
| Container Orchestration | Docker Compose | Kubernetes |

## Users and Roles

| Username | Role | Password |
|---|---|---|
| `alice.admin` | `admin` | `Admin@1234` |
| `bob.developer` | `developer` | `Dev@1234` |
| `sara.auditor` | `security-auditor` | `Audit@1234` |
| `ron.readonly` | `readonly` | `Read@1234` |

## Access Control Matrix

| Endpoint | admin | developer | security-auditor | readonly |
|---|:---:|:---:|:---:|:---:|
| `GET /health` | ✅ | ✅ | ✅ | ✅ |
| `GET /admin/dashboard` | ✅ | ❌ | ❌ | ❌ |
| `GET /developer/api` | ✅ | ✅ | ❌ | ❌ |
| `GET /monitoring/dashboard` | ✅ | ❌ | ✅ | ✅ |
| `GET /security/audit` | ✅ | ❌ | ✅ | ❌ |

## Quick Start

### Prerequisites

- Docker Desktop (running)
- Docker Compose v2+
- `curl` and `jq` (for testing)

### 1. Clone and configure

```bash
git clone https://github.com/GaganSingh11/zero-trust-access-framework.git
cd zero-trust-access-framework
cp .env.example .env
```

### 2. Start the stack

```bash
docker compose up --build -d
```

Wait ~60 seconds for Keycloak to import the realm, then verify:

```bash
curl http://localhost:8000/health
# {"status": "ok", "service": "zt-platform-api"}
```

### 3. Get a token

```bash
TOKEN=$(curl -s -X POST http://localhost:8000/auth/token \
  -H "Content-Type: application/json" \
  -d '{"username":"alice.admin","password":"Admin@1234"}' | jq -r .access_token)
```

### 4. Call a protected endpoint

```bash
curl -H "Authorization: Bearer $TOKEN" http://localhost:8000/admin/dashboard | jq
```

### 5. Run the full access matrix test

```bash
bash scripts/test_access.sh
```

### 6. View audit logs

```bash
cat logs/audit.log | jq
```

### 7. Interactive API docs

Open [http://localhost:8000/docs](http://localhost:8000/docs) in your browser.
Click **Authorize**, paste a Bearer token, and test protected routes.

### 8. Keycloak admin console

Open [http://localhost:8080](http://localhost:8080) — username: `admin`, password: `admin`

## MFA (Browser Login)

MFA via TOTP is configured in the Keycloak browser flow:

1. Open `http://localhost:8080/realms/zero-trust-demo/account`
2. Log in as any test user
3. You will be prompted to configure an OTP device (Google Authenticator / Authy)
4. On subsequent browser logins, the OTP code is required

For API/machine-to-machine flows, the direct grant bypasses browser MFA — this is the
standard pattern for service-to-service token issuance.

## Project Structure

```
zero-trust-access-framework/
├── app/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── main.py          # FastAPI routes (public + protected)
│   ├── auth.py          # JWT validation against Keycloak JWKS
│   ├── rbac.py          # Role-based access control middleware
│   └── logger.py        # Structured JSON audit logger
├── keycloak/
│   └── realm-export.json  # Pre-configured realm (users, roles, client, MFA)
├── docs/
│   ├── architecture.md            # System design and request flow
│   ├── access-control-matrix.md   # RBAC matrix + enterprise tool mapping
│   └── demo-flow.md               # Step-by-step demo commands
├── scripts/
│   └── test_access.sh   # Automated access matrix test
├── logs/                # Audit log output (git-ignored)
├── docker-compose.yml
├── .env.example
└── README.md
```

## Zero Trust Principles

| Principle | Implementation |
|---|---|
| Never trust, always verify | Every request requires a valid JWT — no implicit trust |
| Least privilege | Each role accesses only what it needs |
| Verify explicitly | JWT validated against Keycloak's public JWKS on every request |
| Assume breach | All access decisions (ALLOW + DENY) written to audit log |
| Short-lived credentials | Tokens expire in 5 minutes (`accessTokenLifespan: 300`) |

## Audit Log Format

```json
{
  "timestamp": "2026-05-04T10:23:01.123456+00:00",
  "user": "bob.developer",
  "roles": ["developer"],
  "endpoint": "/admin/dashboard",
  "method": "GET",
  "client_ip": "172.18.0.1",
  "decision": "DENY",
  "reason": "requires one of ['admin']"
}
```

## Enterprise Tool Mapping

| This Project | Enterprise Equivalent |
|---|---|
| Keycloak | Okta, Azure AD / Entra ID, Ping Identity |
| OIDC / JWT | Same protocol used everywhere |
| `.env` secrets | AWS Secrets Manager, HashiCorp Vault, K8s Secrets |
| Audit log (JSON file) | Splunk, ELK Stack, OpenSearch |
| FastAPI RBAC middleware | OPA (Open Policy Agent), Envoy, Kong |
| Docker Compose | Kubernetes + Helm |
| Architecture | Palo Alto Prisma Cloud posture model |

## Security Notes

- `.env` is git-ignored — use HashiCorp Vault or AWS Secrets Manager in production
- JWT audience verification is relaxed for the demo; add a Keycloak audience mapper and enable `verify_aud` for production
- Rotate `KEYCLOAK_CLIENT_SECRET` before any non-local deployment

## Teardown

```bash
docker compose down
```
