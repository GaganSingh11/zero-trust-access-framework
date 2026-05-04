from typing import Callable

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials

from auth import security, validate_token
from logger import audit_logger


def require_roles(*allowed_roles: str) -> Callable:
    async def _check(
        request: Request,
        credentials: HTTPAuthorizationCredentials = Depends(security),
    ) -> dict:
        claims = await validate_token(credentials)
        user: str = claims.get("preferred_username", "unknown")
        user_roles: list = claims.get("roles", [])
        client_ip: str = request.client.host if request.client else "unknown"

        if not any(role in user_roles for role in allowed_roles):
            audit_logger.log(
                user=user,
                roles=user_roles,
                endpoint=request.url.path,
                method=request.method,
                client_ip=client_ip,
                decision="DENY",
                reason=f"requires one of {list(allowed_roles)}",
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Access denied. Required role(s): {list(allowed_roles)}",
            )

        audit_logger.log(
            user=user,
            roles=user_roles,
            endpoint=request.url.path,
            method=request.method,
            client_ip=client_ip,
            decision="ALLOW",
        )
        return claims

    return _check
