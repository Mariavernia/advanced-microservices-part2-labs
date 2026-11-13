#!/usr/bin/env python3
"""Keep student-facing materials independent of a particular course delivery."""
from pathlib import Path
import re
import sys

# Match teaching schedules and estimates, not ports, version numbers, timeouts,
# runtime latency, TTL, log timestamps in code or other technical quantities.
metadata = re.compile(
    r"^\s*(?:[-*>]\s*)*(?:\*\*)?"
    r"(?:cliente|client|edici[oó]n|edition|cohorte|cohort|"
    r"fecha(?:s)?(?:\s+de\s+impartici[oó]n)?|date|horario|schedule|"
    r"duraci[oó]n(?:\s+(?:estimada|total|core\s+objetivo))?|"
    r"tiempo\s+estimado|estimated\s+(?:time|duration))"
    r"(?:\*\*)?\s*:", re.I
)
calendar = re.compile(
    r"\b(?:20\d{2}[-/]\d{1,2}[-/]\d{1,2}|"
    r"\d{1,2}[-/]\d{1,2}[-/]20\d{2}|"
    r"(?:enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|"
    r"octubre|noviembre|diciembre|january|february|march|april|june|july|"
    r"august|september|october|november|december)\s+(?:de\s+)?20\d{2})\b",
    re.I
)
schedule = re.compile(r"\b(?:[01]?\d|2[0-3]):[0-5]\d\s*[-–—]\s*(?:[01]?\d|2[0-3]):[0-5]\d\b")
estimate = re.compile(
    r"\b(?:duraci[oó]n|tiempo\s+estimado|estimated\s+(?:time|duration))"
    r"[^\n:]{0,45}:|"
    r"(?:^|\s)(?:~|aprox(?:\.|imadamente)?\s*)?\d+(?:\s*[-–]\s*\d+)?\s*(?:minutos?|minutes?|horas?|hours?)\b|"
    r"^\s*#{1,6}\s+.*?\s+[-–—:]\s*\d+\s*(?:min|m|h)(?:\s|$)",
    re.I
)
paths = [Path("README.md"), Path("config/course.env")]
for root in (Path("docs"), Path("labs"), Path(".devcontainer"), Path("scripts")):
    paths.extend(root.rglob("*.md"))
violations = []
for path in sorted(set(paths)):
    fence = None
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        marker = re.match(r"^\s*(```+|~~~+)", line)
        if marker:
            char = marker.group(1)[0]
            fence = None if fence == char else char if fence is None else fence
            continue
        if fence:
            continue
        if metadata.search(line) or calendar.search(line) or schedule.search(line) or estimate.search(line):
            violations.append(f"{path}:{lineno}: {line.strip()}")
if violations:
    print("Delivery-specific metadata or estimated durations in student materials:")
    print("\n".join(violations))
    sys.exit(1)
print("PASS: no delivery calendar or estimated lab durations in student materials.")
