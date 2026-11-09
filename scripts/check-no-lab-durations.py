#!/usr/bin/env python3
"""Reject duration estimates in student lab readmes."""
from pathlib import Path
import re
import sys

patterns = [
    re.compile(r"\b(?:estimated\s+(?:time|duration)|duraci[oó]n(?:\s+(?:estimada|total))?|tiempo\s+estimado)\s*:", re.I),
    re.compile(r"(?:^|\s)(?:~|aprox(?:\.|imadamente)?\s*)?\d+(?:\s*[-–]\s*\d+)?\s*(?:minutos?|minutes?|horas?|hours?)\b", re.I),
    re.compile(r"^\s*#{1,6}\s+.*?\s+[-–—:]\s*\d+\s*(?:min|m|h)(?:\s|$)", re.I),
]
violations = []
for path in sorted(Path("labs").glob("*/README.md")):
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if any(p.search(line) for p in patterns):
            violations.append(f"{path}:{lineno}: {line.strip()}")
if violations:
    print("Estimated lab and phase durations must not appear in student materials:")
    print("\n".join(violations))
    sys.exit(1)
print("PASS: no estimated lab/phase durations in student materials.")
