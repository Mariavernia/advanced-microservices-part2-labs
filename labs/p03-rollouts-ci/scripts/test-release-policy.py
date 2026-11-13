#!/usr/bin/env python3
"""Exercise the gate against the starter and repaired/unsafe releases."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
gate = root / "scripts/check-release.py"
starter = json.loads((root / "templates/orders-release.patch.json").read_text())
fixed = copy.deepcopy(starter)
fixed["spec"]["template"]["spec"]["containers"][0]["env"][1]["value"] = "http://inventory:8080"
unsafe = copy.deepcopy(fixed)
unsafe["spec"]["template"]["spec"]["containers"][0]["image"] = "unapproved:latest"
extra = copy.deepcopy(fixed)
extra["spec"]["template"]["spec"]["containers"][0]["env"].append({"name": "UNAPPROVED", "value": "true"})
with tempfile.TemporaryDirectory() as temp:
    path = Path(temp) / "release.json"
    for label, doc, expected in [
        ("starter rejected", starter, 1),
        ("corrected accepted", fixed, 0),
        ("unexpected image rejected", unsafe, 1),
        ("unexpected variable rejected", extra, 1),
    ]:
        path.write_text(json.dumps(doc), encoding="utf-8")
        result = subprocess.run([sys.executable, str(gate), str(path)], capture_output=True, text=True)
        assert result.returncode == expected, (label, result.returncode, result.stdout, result.stderr)
        print(f"PASS: {label}")
