# Architecture

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Client (curl / browser)                  │
└───────────────────┬─────────────────────────┬───────────────────┘
                    │ 1. POST /auth/token      │ 3. GET /protected
                    │    (username + password) │    (Bearer <JWT>)
                    ▼                          ▼
┌───────────────────────────┐    ┌─────────────────────────────────┐
│   Keycloak (port 8080)    │    │   FastAPI App (port 8000)        │
│                           │    │                                  │
│  • Realm: zero-trust-demo │    │  ┌──────────────────────────┐   │
│  • Users + Roles          │◄───│  │  auth.py                 │   │
│  • OIDC / JWT issuance    │    │  │  • Fetch JWKS from KC    │   │
│  • MFA (OTP flow)         │    │  │  • Validate JWT signature│   │
│  • JWKS endpoint          │    │  │  • Extract claims/roles  │   │
└───────────────────────────┘    │  └──────────────────────────┘   │
         │ 2. Returns JWT        │  ┌──────────────────────────┐   │
         └───────────────────────►  │  rbac.py                 │   │
                                 │  │  • Check required roles  │   │
                                 │  │  • ALLOW or DENY         │   │
                                 │  └──────────────────────────┘   │
                                 │  ┌──────────────────────────┐   │
                                 │  │  logger.py               │   │
                                 │  │  • Write JSON audit log  │   │
                                 │  │  • Console + file output │   │
                                 │  └──────────────────────────┘   │
                                 └─────────────────────────────────┘
                                                │
                                                ▼
                                 ┌─────────────────────────────────┐
                                 │  logs/audit.log                 │
                                 │  { user, roles, endpoint,       │
                                 │    decision, timestamp }        │
                                 └─────────────────────────────────┘
```

## Request Flow

1. **Client requests a token** — `POST /auth/token` with username + password
2. **FastAPI proxies** the credential to Keycloak's token endpoint (direct grant)
3. **Keycloak authenticates** the user, checks MFA if configured, and returns a signed JWT
4. **Client sends the JWT** as a `Bearer` token on all subsequent requests
5. **FastAPI validates** the JWT signature against Keycloak's public JWKS
6. **RBAC check** — the required roles for the endpoint are compared against the `roles` claim in the token
7. **Audit log entry** is written (ALLOW or DENY) with user, roles, endpoint, IP, and timestamp
8. **Response returned** — `200 OK` with data, or `401`/`403` on failure

## Token Lifecycle

```
Login ──► JWT issued (TTL: 5 min) ──► API calls ──► Token expires ──► Re-login
                                                         │
                                              Refresh token (TTL: 30 min)
```

## Docker Network

```
zt-network (bridge)
  ├── keycloak:8080   (internal hostname used by app)
  └── zt-api:8000     (exposed to host on port 8000)
```

The FastAPI container connects to Keycloak using the internal Docker hostname
`keycloak:8080`, which matches the `KEYCLOAK_URL` env var.

## Component Responsibilities

| Component | File | Responsibility |
|---|---|---|
| API entrypoint | `app/main.py` | Routes, public + protected endpoints |
| Token validation | `app/auth.py` | JWKS fetch, JWT decode, issuer check |
| Access control | `app/rbac.py` | Role enforcement, ALLOW/DENY decision |
| Audit logging | `app/logger.py` | Structured JSON log to console + file |
| Identity provider | Keycloak | Users, roles, SSO, MFA, OIDC tokens |
| Realm config | `keycloak/realm-export.json` | Pre-configured realm, clients, users |
| Secrets | `.env` | Runtime config (maps to Vault / K8s Secrets in prod) |
