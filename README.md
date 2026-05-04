# Zero Trust Access Framework

A locally-runnable Zero Trust security demo for cloud-native regulated infrastructure.
Demonstrates SSO, MFA, OIDC/JWT, RBAC, least-privilege access, and audit logging using
Keycloak and FastAPI — fully containerized via Docker Compose.

## Prerequisites

- Docker Desktop (running)
- Docker Compose v2+

## Quick Start

```bash
# 1. Clone and enter the project
cd zero-trust-access-framework

# 2. Copy environment file (already done if you have .env)
cp .env.example .env

# 3. Start everything
docker compose up --build

# Keycloak will be ready at:  http://localhost:8080
# FastAPI will be ready at:   http://localhost:8000
# API docs:                   http://localhost:8000/docs
```

Keycloak takes ~60 seconds to start. The API waits for Keycloak to be healthy before starting.

## Test Users

| Username        | Password     | Role             | Access                          |
|-----------------|--------------|------------------|---------------------------------|
| alice.admin     | Admin@1234   | admin            | All endpoints                   |
| bob.developer   | Dev@1234     | developer        | /developer only                 |
| sara.auditor    | Audit@1234   | security-auditor | /audit and /monitoring          |
| ron.readonly    | Read@1234    | readonly         | /monitoring only                |

## API Endpoints

| Endpoint      | Allowed Roles                       |
|---------------|-------------------------------------|
| GET /public   | No auth required                    |
| GET /admin    | admin                               |
| GET /developer| developer, admin                    |
| GET /audit    | security-auditor, admin             |
| GET /monitoring| readonly, security-auditor, admin  |

## Demo Flow

### 1. Get a token (password grant — no MFA required for API demo)
```bash
curl -s -X POST http://localhost:8080/realms/zero-trust-demo/protocol/openid-connect/token \
  -d "client_id=zt-platform-api" \
  -d "client_secret=zt-secret-change-me" \
  -d "username=bob.developer" \
  -d "password=Dev@1234" \
  -d "grant_type=password" | jq .access_token
```

### 2. Call a permitted endpoint
```bash
TOKEN=<paste token here>
curl -H "Authorization: Bearer $TOKEN" http://localhost:8000/developer
```

### 3. Call a denied endpoint
```bash
curl -H "Authorization: Bearer $TOKEN" http://localhost:8000/admin
# → 403 Forbidden
```

### 4. Call without a token
```bash
curl http://localhost:8000/admin
# → 401 Unauthorized
```

### 5. Check audit logs
```bash
cat logs/audit.log
```

## MFA (Browser Login)

MFA via OTP is enforced in the browser login flow:

1. Open http://localhost:8080/realms/zero-trust-demo/account
2. Log in as any test user
3. You will be prompted to set up OTP (Google Authenticator or Authy)
4. On subsequent logins, OTP code is required

For API demo purposes, the password grant flow bypasses browser MFA — this is the
standard pattern for machine-to-machine token issuance.

## Keycloak Admin Console

URL: http://localhost:8080/admin
Username: admin
Password: admin

The `zero-trust-demo` realm is pre-imported with all users, roles, and client config.

## Audit Logs

All access decisions are written to `logs/audit.log` in structured JSON:

```json
{
  "timestamp": "2026-05-03T10:15:30Z",
  "username": "bob.developer",
  "endpoint": "/admin",
  "required_role": "admin",
  "user_roles": ["developer"],
  "decision": "DENIED",
  "reason": "missing_required_role",
  "source_ip": "172.18.0.1"
}
```

## Stop

```bash
docker compose down
```

## Enterprise Tool Mapping

| This Project       | Enterprise Equivalent              |
|--------------------|------------------------------------|
| Keycloak           | Okta, Azure AD / Entra ID          |
| OIDC / JWT         | Same protocol used everywhere      |
| .env secrets       | AWS Secrets Manager, HashiCorp Vault|
| Audit log (file)   | Splunk, ELK, OpenSearch            |
| RBAC matrix        | AWS IAM policies, Prisma Cloud     |
