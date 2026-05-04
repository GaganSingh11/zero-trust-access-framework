# Demo Flow

End-to-end walkthrough of the Zero Trust Access Framework. Runs in ~5 minutes.

## Prerequisites

- Docker and Docker Compose installed
- `curl` and `jq` available

## 1. Start the Stack

```bash
docker compose up --build -d
```

Wait ~60 seconds for Keycloak to finish importing the realm.
Check readiness:

```bash
curl -s http://localhost:8000/health | jq
# {"status": "ok", "service": "zt-platform-api"}
```

## 2. Verify the Public Endpoint (No Token Required)

```bash
curl -s http://localhost:8000/ | jq
```

Expected: service info with list of protected endpoints.

## 3. Obtain Tokens for Each User

```bash
# Admin
ADMIN_TOKEN=$(curl -s -X POST http://localhost:8000/auth/token \
  -H "Content-Type: application/json" \
  -d '{"username":"alice.admin","password":"Admin@1234"}' | jq -r .access_token)

# Developer
DEV_TOKEN=$(curl -s -X POST http://localhost:8000/auth/token \
  -H "Content-Type: application/json" \
  -d '{"username":"bob.developer","password":"Dev@1234"}' | jq -r .access_token)

# Security Auditor
AUDIT_TOKEN=$(curl -s -X POST http://localhost:8000/auth/token \
  -H "Content-Type: application/json" \
  -d '{"username":"sara.auditor","password":"Audit@1234"}' | jq -r .access_token)

# Readonly
RO_TOKEN=$(curl -s -X POST http://localhost:8000/auth/token \
  -H "Content-Type: application/json" \
  -d '{"username":"ron.readonly","password":"Read@1234"}' | jq -r .access_token)
```

## 4. Demo Access Control

### Admin — full access

```bash
curl -s -H "Authorization: Bearer $ADMIN_TOKEN" http://localhost:8000/admin/dashboard | jq
curl -s -H "Authorization: Bearer $ADMIN_TOKEN" http://localhost:8000/developer/api | jq
curl -s -H "Authorization: Bearer $ADMIN_TOKEN" http://localhost:8000/monitoring/dashboard | jq
curl -s -H "Authorization: Bearer $ADMIN_TOKEN" http://localhost:8000/security/audit | jq
```

### Developer — developer API only

```bash
# ALLOW
curl -s -H "Authorization: Bearer $DEV_TOKEN" http://localhost:8000/developer/api | jq

# DENY (403)
curl -s -H "Authorization: Bearer $DEV_TOKEN" http://localhost:8000/admin/dashboard | jq
curl -s -H "Authorization: Bearer $DEV_TOKEN" http://localhost:8000/security/audit | jq
```

### Security Auditor — monitoring + audit

```bash
# ALLOW
curl -s -H "Authorization: Bearer $AUDIT_TOKEN" http://localhost:8000/monitoring/dashboard | jq
curl -s -H "Authorization: Bearer $AUDIT_TOKEN" http://localhost:8000/security/audit | jq

# DENY (403)
curl -s -H "Authorization: Bearer $AUDIT_TOKEN" http://localhost:8000/admin/dashboard | jq
curl -s -H "Authorization: Bearer $AUDIT_TOKEN" http://localhost:8000/developer/api | jq
```

### Readonly — monitoring only

```bash
# ALLOW
curl -s -H "Authorization: Bearer $RO_TOKEN" http://localhost:8000/monitoring/dashboard | jq

# DENY (403)
curl -s -H "Authorization: Bearer $RO_TOKEN" http://localhost:8000/security/audit | jq
curl -s -H "Authorization: Bearer $RO_TOKEN" http://localhost:8000/admin/dashboard | jq
```

### No token — 401 Unauthorized

```bash
curl -s http://localhost:8000/admin/dashboard | jq
```

## 5. View Audit Logs

```bash
cat logs/audit.log | jq
```

Each log entry shows:

```json
{
  "timestamp": "2024-05-04T10:23:01.123456+00:00",
  "user": "bob.developer",
  "roles": ["developer"],
  "endpoint": "/admin/dashboard",
  "method": "GET",
  "client_ip": "172.18.0.1",
  "decision": "DENY",
  "reason": "requires one of ['admin']"
}
```

## 6. Automated Test Script

Run the full access matrix test in one command:

```bash
bash scripts/test_access.sh
```

## 7. Interactive API Docs

Open in your browser:

```
http://localhost:8000/docs
```

Use the Swagger UI to test endpoints interactively. Paste a Bearer token
in the `Authorize` button to test protected routes.

## 8. Keycloak Admin Console

```
http://localhost:8080
Username: admin
Password: admin
Realm: zero-trust-demo
```

From here you can inspect users, roles, sessions, MFA configuration,
and OIDC client settings.

## Teardown

```bash
docker compose down
```
