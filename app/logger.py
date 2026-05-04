import json
import logging
import os
from datetime import datetime, timezone

os.makedirs("logs", exist_ok=True)

_fmt = logging.Formatter("%(message)s")

_console = logging.StreamHandler()
_console.setFormatter(_fmt)

_file = logging.FileHandler("logs/audit.log")
_file.setFormatter(_fmt)

_log = logging.getLogger("audit")
_log.setLevel(logging.INFO)
_log.addHandler(_console)
_log.addHandler(_file)
_log.propagate = False


class _AuditLogger:
    def log(
        self,
        *,
        user: str,
        roles: list,
        endpoint: str,
        method: str,
        client_ip: str,
        decision: str,
        reason: str = "",
    ) -> None:
        entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "user": user,
            "roles": roles,
            "endpoint": endpoint,
            "method": method,
            "client_ip": client_ip,
            "decision": decision,
        }
        if reason:
            entry["reason"] = reason
        _log.info(json.dumps(entry))


audit_logger = _AuditLogger()
