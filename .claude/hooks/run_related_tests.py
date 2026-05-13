#!/usr/bin/env python3
# PostToolUse hook: run GUT tests when server-side GDScript is edited.
# Only triggers for files under scripts/server/ or test/unit/.
# Runs `make test` and reports failures via stderr (non-zero exit = warning shown to user).

import json
import os
import subprocess
import sys

TRIGGER_PATHS = (
    "/scripts/server/",
    "/scripts/state/",
    "/scripts/core/",
    "/scripts/autoload/",
    "/test/unit/",
)


def should_run_tests(file_path: str) -> bool:
    if not file_path.endswith(".gd"):
        return False
    p = "/" + file_path.replace("\\", "/").lstrip("/")
    return any(s in p for s in TRIGGER_PATHS)


def main():
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    tool_name = data.get("tool_name", "")
    tool_input = data.get("tool_input", {})

    if tool_name not in ("Edit", "Write", "MultiEdit"):
        sys.exit(0)

    file_path = tool_input.get("file_path", "")
    if not should_run_tests(file_path):
        sys.exit(0)

    project_dir = os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())

    result = subprocess.run(
        ["make", "test"],
        cwd=project_dir,
        capture_output=True,
        text=True,
        timeout=120,
    )

    if result.returncode != 0:
        failing_lines = [
            line for line in result.stdout.splitlines()
            if "FAILED" in line or "ERROR" in line or "Failing" in line
        ]
        summary = "\n".join(failing_lines[-10:]) if failing_lines else result.stdout[-500:]
        sys.stderr.write(f"Tests failed after editing {os.path.basename(file_path)}:\n{summary}\n")
        sys.exit(1)

    passed = [line for line in result.stdout.splitlines() if "passed" in line.lower()]
    if passed:
        sys.stderr.write(f"{passed[-1].strip()}\n")

    sys.exit(0)


if __name__ == "__main__":
    main()
