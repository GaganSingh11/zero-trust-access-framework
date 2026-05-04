import os

import httpx
from fastapi import HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt

KEYCLOAK_URL = os.getenv("KEYCLOAK_URL", "http://keycloak:8080")
KEYCLOAK_REALM = os.getenv("KEYCLOAK_REALM", "zero-trust-demo")
KEYCLOAK_CLIENT_ID = os.getenv("KEYCLOAK_CLIENT_ID", "zt-platform-api")
KEYCLOAK_CLIENT_SECRET = os.getenv("KEYCLOAK_CLIENT_SECRET", "zt-secret-change-me")

JWKS_URL = f"{KEYCLOAK_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/certs"
TOKEN_URL = f"{KEYCLOAK_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/token"
ISSUER = f"{KEYCLOAK_URL}/realms/{KEYCLOAK_REALM}"

security = HTTPBearer()

_jwks_cache: dict | None = None


async def _get_jwks() -> dict:
    global _jwks_cache
    if _jwks_cache is None:
        async with httpx.AsyncClient() as client:
            r = await client.get(JWKS_URL, timeout=10)
            r.raise_for_status()
            _jwks_cache = r.json()
    return _jwks_cache


async def validate_token(credentials: HTTPAuthorizationCredentials) -> dict:
    token = credentials.credentials
    try:
        jwks = await _get_jwks()
        claims = jwt.decode(
            token,
            jwks,
            algorithms=["RS256"],
            issuer=ISSUER,
            # Keycloak sets aud=["account"] by default; add an audience mapper in prod
            options={"verify_aud": False},
        )
        return claims
    except JWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid or expired token: {exc}",
            headers={"WWW-Authenticate": "Bearer"},
        )


async def fetch_token(username: str, password: str) -> dict:
    async with httpx.AsyncClient() as client:
        r = await client.post(
            TOKEN_URL,
            data={
                "grant_type": "password",
                "client_id": KEYCLOAK_CLIENT_ID,
                "client_secret": KEYCLOAK_CLIENT_SECRET,
                "username": username,
                "password": password,
            },
            timeout=10,
        )
    if r.status_code != 200:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials",
        )
    return r.json()
