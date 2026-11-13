#!/usr/bin/env python3
"""Offline release policy: no Azure credentials, no Kubernetes access."""
import json
import re
import sys
from pathlib import Path


def validate(doc):
    # A strategic patch may change only the two approved environment variables.
    containers = doc["spec"]["template"]["spec"]["containers"]
    if len(containers) != 1 or containers[0].get("name") != "orders":
        raise ValueError("patch must target only container orders")
    env = containers[0]["env"]
    if len(env) != 2 or {item["name"] for item in env} != {"APP_VERSION", "INVENTORY_BASE_URL"}:
        raise ValueError("expected exactly APP_VERSION and INVENTORY_BASE_URL")
    values = {item["name"]: item["value"] for item in env}
    if not isinstance(values["APP_VERSION"], str) or not re.fullmatch(r"\d+\.\d+\.\d+-lab", values["APP_VERSION"]):
        raise ValueError("APP_VERSION must have the form X.Y.Z-lab")
    if values["INVENTORY_BASE_URL"] != "http://inventory:8080":
        raise ValueError("INVENTORY_BASE_URL violates the internal service DNS/port contract")
    expected = {"spec": {"template": {"spec": {"containers": [
        {"name": "orders", "env": env}
    ]}}}}
    if doc != expected or any(set(item) != {"name", "value"} for item in env):
        raise ValueError("release patch may only change the approved environment variables")


def main():
    if len(sys.argv) != 2:
        print("Usage: check-release.py <release.patch.json>", file=sys.stderr)
        return 2
    try:
        validate(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")))
    except (OSError, ValueError, TypeError, KeyError, IndexError, AttributeError) as exc:
        print(f"RELEASE POLICY FAIL: {exc}", file=sys.stderr)
        return 1
    print("RELEASE POLICY PASS: Orders patch satisfies the static contract")
    return 0


if __name__ == "__main__":
    sys.exit(main())
