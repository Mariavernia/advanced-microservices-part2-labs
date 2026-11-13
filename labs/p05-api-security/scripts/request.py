#!/usr/bin/env python3
"""Make individual GET requests without exposing bearer tokens to shell arguments."""
import argparse
import base64
import http.client
import json
import os
from pathlib import Path
import stat
import sys
from urllib.parse import urlsplit

CACHE = Path.home() / ".cache" / "advanced-orders"


def read_token(profile):
    path = CACHE / f"{profile}.jwt"
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "r", encoding="utf-8") as handle:
        info = os.fstat(handle.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise ValueError("token file must be an owner-only regular file")
        token = handle.read(32769).strip()
    if not token or len(token) > 32768 or any(c.isspace() for c in token):
        raise ValueError("invalid token file")
    return token


def claims(token):
    # Inspection ONLY, no signature validation. Do not use these claims as trust.
    segment = token.split(".")[1]
    payload = json.loads(base64.urlsafe_b64decode(segment + "=" * (-len(segment) % 4)))
    realm = payload.get("realm_access", {})
    print(json.dumps({
        "iss": payload.get("iss"), "aud": payload.get("aud"),
        "exp": payload.get("exp"), "roles": realm.get("roles", []),
    }, ensure_ascii=False))
    print("LOCAL DECODE ONLY: signature not verified", file=sys.stderr)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("profile", choices=["none", "invalid", "reader", "admin"])
    p.add_argument("path", nargs="?")
    p.add_argument("--claims", action="store_true")
    p.add_argument("--repeat", type=int, default=1, choices=range(1, 13))
    p.add_argument("--status-only", action="store_true")
    a = p.parse_args()
    try:
        token = read_token(a.profile) if a.profile in ("reader", "admin") else (
            "invalid-training-token" if a.profile == "invalid" else None)
        if a.claims:
            if a.profile not in ("reader", "admin") or a.path or a.repeat != 1:
                p.error("--claims requires reader/admin and no path")
            claims(token)
            return 0
        if not a.path:
            p.error("provide an API path or /actuator/health")
        u = urlsplit(a.path)
        if (not a.path.startswith("/") or a.path.startswith("//") or u.scheme or u.netloc
                or u.fragment or any(ord(c) < 32 or ord(c) == 127 for c in a.path)
                or not (u.path.startswith("/api/") or u.path == "/actuator/health")):
            p.error("only local /api/ paths or /actuator/health are allowed")
        if a.repeat > 1 and (a.profile not in ("reader", "admin") or u.path != "/api/orders/preview"):
            p.error("repeat is allowed only for authenticated Orders preview")
        if a.status_only and a.repeat != 1:
            p.error("--status-only requires a single request")
        for i in range(a.repeat):
            # Fixed loopback destination. http.client does not follow redirects.
            connection = http.client.HTTPConnection("127.0.0.1", 8080, timeout=10)
            try:
                headers = {"Accept": "application/json"}
                if token:
                    headers["Authorization"] = "Bearer " + token
                connection.request("GET", a.path, headers=headers)
                response = connection.getresponse()
                retry = response.getheader("Retry-After")
                response.read(65536)
                if a.status_only:
                    print(response.status)
                else:
                    print(f"{i+1}: {a.profile} {u.path} -> HTTP {response.status}"
                          + (f" Retry-After={retry}s" if retry and retry.isdigit() else ""))
            finally:
                connection.close()
        return 0
    except (OSError, ValueError, IndexError, TypeError, AttributeError, http.client.HTTPException):
        # Do not echo exceptions that could contain a header or token.
        print("Request/claim inspection failed. Check private token file and port-forward.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
