from fastapi import Depends, FastAPI
from pydantic import BaseModel

from auth import fetch_token
from rbac import require_roles

app = FastAPI(
    title="Zero Trust Access Framework API",
    description="OIDC + RBAC protected API backed by Keycloak",
    version="1.0.0",
)


class LoginRequest(BaseModel):
    username: str
    password: str


# ── Public ────────────────────────────────────────────────────────────────────


@app.get("/health", tags=["public"])
async def health():
    return {"status": "ok", "service": "zt-platform-api"}


@app.get("/", tags=["public"])
async def root():
    return {
        "service": "Zero Trust Access Framework",
        "version": "1.0.0",
        "protected_endpoints": [
            "/admin/dashboard",
            "/developer/api",
            "/monitoring/dashboard",
            "/security/audit",
        ],
    }


@app.post("/auth/token", tags=["auth"])
async def login(body: LoginRequest):
    """Exchange username/password for a Keycloak JWT (direct grant)."""
    return await fetch_token(body.username, body.password)


# ── Protected ─────────────────────────────────────────────────────────────────


@app.get("/admin/dashboard", tags=["admin"])
async def admin_dashboard(claims: dict = Depends(require_roles("admin"))):
    return {
        "endpoint": "Admin Dashboard",
        "user": claims.get("preferred_username"),
        "roles": claims.get("roles", []),
        "message": "Full administrative access: user management, system config, audit logs.",
    }


@app.get("/developer/api", tags=["developer"])
async def developer_api(claims: dict = Depends(require_roles("developer", "admin"))):
    return {
        "endpoint": "Developer API",
        "user": claims.get("preferred_username"),
        "roles": claims.get("roles", []),
        "message": "Developer resources: CI/CD pipelines, service deployments, API keys.",
    }


@app.get("/monitoring/dashboard", tags=["monitoring"])
async def monitoring_dashboard(
    claims: dict = Depends(require_roles("readonly", "security-auditor", "admin")),
):
    return {
        "endpoint": "Monitoring Dashboard",
        "user": claims.get("preferred_username"),
        "roles": claims.get("roles", []),
        "message": "System metrics, uptime, resource utilization, and alert history.",
    }


@app.get("/security/audit", tags=["security"])
async def security_audit(
    claims: dict = Depends(require_roles("security-auditor", "admin")),
):
    return {
        "endpoint": "Security Audit Log",
        "user": claims.get("preferred_username"),
        "roles": claims.get("roles", []),
        "message": "Auth events, access decisions, role assignments, anomaly detections.",
    }
