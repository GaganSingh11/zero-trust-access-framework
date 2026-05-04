# Access Control Matrix

## Users and Roles

| Username | Role | Password |
|---|---|---|
| alice.admin | `admin` | `Admin@1234` |
| bob.developer | `developer` | `Dev@1234` |
| sara.auditor | `security-auditor` | `Audit@1234` |
| ron.readonly | `readonly` | `Read@1234` |

## Endpoint Access Matrix

| Endpoint | `admin` | `developer` | `security-auditor` | `readonly` |
|---|:---:|:---:|:---:|:---:|
| `GET /health` | ✅ | ✅ | ✅ | ✅ |
| `POST /auth/token` | ✅ | ✅ | ✅ | ✅ |
| `GET /admin/dashboard` | ✅ | ❌ | ❌ | ❌ |
| `GET /developer/api` | ✅ | ✅ | ❌ | ❌ |
| `GET /monitoring/dashboard` | ✅ | ❌ | ✅ | ✅ |
| `GET /security/audit` | ✅ | ❌ | ✅ | ❌ |

## Zero Trust Principles Applied

| Principle | Implementation |
|---|---|
| Never trust, always verify | Every request requires a valid JWT — no implicit trust |
| Least privilege | Each role can access only the endpoints it needs |
| Verify explicitly | JWT signature validated against Keycloak JWKS on every request |
| Assume breach | All access attempts (allow and deny) are written to the audit log |
| Token expiry | Keycloak access tokens expire in 5 minutes (`accessTokenLifespan: 300`) |
| Strong authentication | MFA (OTP) supported via Keycloak browser flow |

## Enterprise Tool Mapping

| Component | This Project | Enterprise Equivalent |
|---|---|---|
| Identity Provider | Keycloak | Okta, Azure AD, Ping Identity |
| Auth Protocol | OpenID Connect / JWT | Same |
| MFA | Keycloak OTP flow | Okta MFA, Duo |
| RBAC enforcement | FastAPI middleware | OPA, Envoy, Kong |
| Secrets management | `.env` file | HashiCorp Vault, AWS Secrets Manager, K8s Secrets |
| Audit logging | JSON to file | Splunk, ELK Stack, OpenSearch |
| Cloud posture | Architecture docs | Palo Alto Prisma Cloud, AWS Security Hub |
