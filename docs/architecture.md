# Architecture

## 1. System Architecture

> All components run inside a Docker bridge network. Only ports 8000 and 8080 are exposed to the host.

```mermaid
flowchart TB
    CLIENT["🖥️  Client\ncurl · Browser · Application"]

    subgraph DOCKER["🐳  Docker Network — zt-network"]
        subgraph KC["  Keycloak  ·  port 8080  "]
            KC_A["Realm: zero-trust-demo\nUsers · Roles · Client Config"]
            KC_B["🔐  MFA — TOTP Browser Flow"]
            KC_C["POST /token\nJWT Issuance"]
            KC_D["GET /certs\nJWKS Public Keys"]
        end

        subgraph FASTAPI["  FastAPI  ·  port 8000  "]
            F_MAIN["main.py\nRoute Definitions\nPublic + Protected Endpoints"]
            F_AUTH["auth.py\nJWT Decode · JWKS Cache\nIssuer + Expiry Validation"]
            F_RBAC["rbac.py\nRole Enforcement\nALLOW / DENY Decision"]
            F_LOG["logger.py\nStructured JSON\nAudit Logger"]
            F_MAIN --> F_AUTH
            F_AUTH --> F_RBAC
            F_RBAC --> F_LOG
        end
    end

    AUDITLOG[("📄 logs/audit.log\nJSON entries per request")]
    REALMCFG["📄 keycloak/realm-export.json\nPre-configured realm"]
    DOTENV["🔐 .env\nSecrets — maps to Vault in prod"]

    CLIENT -->|"① POST /auth/token\n    username + password"| F_MAIN
    F_MAIN -->|"② password grant"| KC_C
    KC_C -->|"③ signed JWT  RS256"| F_MAIN
    F_MAIN -->|"④ JWT  TTL 5 min"| CLIENT

    CLIENT -->|"⑤ GET /protected\n    Authorization: Bearer JWT"| F_RBAC
    F_AUTH -->|"⑥ fetch JWKS\n    cached per process"| KC_D
    F_LOG -->|"⑦ append"| AUDITLOG

    REALMCFG -->|"auto-import on startup"| KC
    DOTENV -->|"env vars injected"| FASTAPI
```

---

## 2. Authentication & Access Request Flow

> Step-by-step sequence for every protected API call.

```mermaid
sequenceDiagram
    actor Client as 🖥️ Client
    participant API  as FastAPI  :8000
    participant KC   as Keycloak  :8080
    participant JWKS as JWKS Cache (in-process)
    participant LOG  as logs/audit.log

    rect rgb(220, 240, 255)
        Note over Client,LOG: ── Phase 1 · Authentication ──
        Client->>API: POST /auth/token<br/>{ username, password }
        API->>KC: POST /realms/zero-trust-demo/protocol/openid-connect/token<br/>grant_type=password · client_id · client_secret
        KC-->>API: 200 OK  { access_token, refresh_token, expires_in: 300 }
        API-->>Client: JWT  (RS256, signed by Keycloak)
    end

    rect rgb(220, 255, 230)
        Note over Client,LOG: ── Phase 2 · Authorized Access ──
        Client->>API: GET /admin/dashboard<br/>Authorization: Bearer &lt;JWT&gt;
        API->>JWKS: fetch /realms/zero-trust-demo/protocol/openid-connect/certs
        JWKS-->>API: RSA public keys (cached after first request)
        Note over API: Validate signature · issuer · expiry<br/>Extract preferred_username + roles claim
        Note over API: role "admin" ∈ allowed_roles ✅
        API->>LOG: { user, roles, endpoint, ip, decision: ALLOW }
        API-->>Client: 200 OK  { endpoint, user, roles, message }
    end

    rect rgb(255, 230, 220)
        Note over Client,LOG: ── Phase 3 · Denied Access ──
        Client->>API: GET /admin/dashboard<br/>Authorization: Bearer &lt;developer JWT&gt;
        API->>JWKS: (cache hit — no network call)
        JWKS-->>API: RSA public keys
        Note over API: role "developer" ∉ allowed_roles ❌
        API->>LOG: { user, roles, endpoint, ip, decision: DENY, reason }
        API-->>Client: 403 Forbidden  { detail: "Access denied. Required: ['admin']" }
    end

    rect rgb(255, 245, 200)
        Note over Client,LOG: ── Phase 4 · Invalid / Expired Token ──
        Client->>API: GET /admin/dashboard<br/>Authorization: Bearer &lt;expired or tampered&gt;
        Note over API: JWTError — signature invalid or token expired
        API-->>Client: 401 Unauthorized<br/>WWW-Authenticate: Bearer
    end
```

---

## 3. RBAC Decision Flow

> What happens inside `rbac.py` on every protected request.

```mermaid
flowchart TD
    START(["📥 Incoming Request"])

    START --> HASTOKEN{"Authorization header\npresent?"}

    HASTOKEN -->|"No"| UNAUTH["🔴 401 Unauthorized\nMissing credentials"]

    HASTOKEN -->|"Yes"| DECODE{"Decode JWT\nvalidate RS256 signature\ncheck issuer + expiry"}

    DECODE -->|"Invalid signature\nor expired"| UNAUTH

    DECODE -->|"Valid"| EXTRACT["Extract claims\n─────────────────\npreferred_username\nroles: list of strings"]

    EXTRACT --> ROLECHECK{"User role ∈\nendpoint allowed roles?"}

    ROLECHECK -->|"❌ No match"| DENY["🔴 403 Forbidden\nAccess Denied"]
    DENY --> LOGDENY["📄 Audit Log — DENY\n────────────────────────\nuser · roles · endpoint\nclient_ip · timestamp\nreason: required roles"]

    ROLECHECK -->|"✅ Match found"| ALLOW["🟢 200 OK\nReturn protected resource"]
    ALLOW --> LOGALLOW["📄 Audit Log — ALLOW\n────────────────────────\nuser · roles · endpoint\nclient_ip · timestamp"]
```

---

## 4. Role Access Matrix

```mermaid
flowchart LR
    subgraph USERS["Users"]
        U1["👤 alice.admin\nrole: admin"]
        U2["👤 bob.developer\nrole: developer"]
        U3["👤 sara.auditor\nrole: security-auditor"]
        U4["👤 ron.readonly\nrole: readonly"]
    end

    subgraph ENDPOINTS["Protected Endpoints"]
        E1["🔴 /admin/dashboard\nrequires: admin"]
        E2["🔵 /developer/api\nrequires: developer · admin"]
        E3["🟡 /monitoring/dashboard\nrequires: readonly · security-auditor · admin"]
        E4["🟠 /security/audit\nrequires: security-auditor · admin"]
    end

    U1 -->|"✅"| E1
    U1 -->|"✅"| E2
    U1 -->|"✅"| E3
    U1 -->|"✅"| E4

    U2 -->|"✅"| E2
    U2 -. "❌ 403" .-> E1
    U2 -. "❌ 403" .-> E4

    U3 -->|"✅"| E3
    U3 -->|"✅"| E4
    U3 -. "❌ 403" .-> E1
    U3 -. "❌ 403" .-> E2

    U4 -->|"✅"| E3
    U4 -. "❌ 403" .-> E1
    U4 -. "❌ 403" .-> E2
    U4 -. "❌ 403" .-> E4
```

---

## 5. Token Lifecycle

```mermaid
flowchart LR
    LOGIN(["🔑 Login\nPOST /auth/token"]) -->|"issued"| AT["Access Token\nTTL: 5 min"]
    LOGIN -->|"issued"| RT["Refresh Token\nTTL: 30 min"]
    AT -->|"attach to every request"| API["API Call\nBearer JWT"]
    AT -->|"expires"| REAUTH(["Re-authenticate\nor use refresh token"])
    RT -->|"exchange"| AT2["New Access Token"]
    RT -->|"expires"| LOGIN
```

---

## Component Responsibilities

| Component | File | Responsibility |
|---|---|---|
| API entrypoint | `app/main.py` | Route definitions, public + protected endpoints |
| Token validation | `app/auth.py` | JWKS fetch + cache, JWT decode, issuer/expiry check |
| Access control | `app/rbac.py` | Role enforcement, ALLOW/DENY decision, triggers logger |
| Audit logging | `app/logger.py` | Structured JSON to console and `logs/audit.log` |
| Identity provider | Keycloak | Users, roles, SSO, MFA, OIDC token issuance |
| Realm config | `keycloak/realm-export.json` | Pre-configured realm, clients, users, MFA flow |
| Secrets | `.env` | Runtime config — maps to HashiCorp Vault or K8s Secrets in prod |

## MFA Behaviour

| Login Method | MFA Triggered | Use Case |
|---|---|---|
| Browser → Keycloak UI | ✅ Yes — TOTP required | Human user login |
| API → `POST /auth/token` | ❌ No — direct grant bypasses browser flow | M2M, CI/CD, service accounts |

This is intentional. In production, human users authenticate through the Keycloak browser flow (with MFA enforced). Service accounts and API clients use client credentials or direct grants — standard practice for regulated infrastructure.
