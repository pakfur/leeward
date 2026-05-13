#!/usr/bin/env python3
# Block raw print() being added to runtime GDScript code.
# Per CLAUDE.md, runtime code uses the Trace autoload instead of print().
# Bypass per line with a trailing `# allow-print` comment.

import json
import re
import sys

EXEMPT_SUBSTRINGS = (
    "/scripts/util/",
    "/scripts/utils/",
    "/scripts/autoload/trace.gd",
    "/scripts/autoload/mcp_server.gd",
    "/addons/",
)

PRINT_CALL = re.compile(r"\bprint\s*\(")
STRING_LITERAL = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'')


def is_exempt(file_path: str) -> bool:
    if not file_path.endswith(".gd"):
        return True
    # Prepend slash so substring checks match both absolute and relative paths.
    p = "/" + file_path.replace("\\", "/").lstrip("/")
    return any(s in p for s in EXEMPT_SUBSTRINGS)


def scan_for_print(content: str):
    for i, raw in enumerate(content.splitlines(), 1):
        if "# allow-print" in raw:
            continue
        stripped = STRING_LITERAL.sub('""', raw)
        if "#" in stripped:
            stripped = stripped.split("#", 1)[0]
        if PRINT_CALL.search(stripped):
            return (i, raw.rstrip())
    return None


def iter_new_content(tool_name, tool_input):
    file_path = tool_input.get("file_path", "")
    if tool_name == "Write":
        yield file_path, tool_input.get("content", "")
    elif tool_name == "Edit":
        yield file_path, tool_input.get("new_string", "")
    elif tool_name == "MultiEdit":
        for edit in tool_input.get("edits", []):
            yield file_path, edit.get("new_string", "")


def main():
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    tool_name = data.get("tool_name", "")
    tool_input = data.get("tool_input", {})

    for file_path, content in iter_new_content(tool_name, tool_input):
        if is_exempt(file_path):
            continue
        hit = scan_for_print(content)
        if hit:
            lineno, line = hit
            sys.stderr.write(
                f"Blocked: raw print() detected in {file_path} (added line {lineno})\n"
                f"  {line.strip()}\n\n"
                f"Use the Trace autoload instead:\n"
                f"  Trace.info(\"msg\")  Trace.warn(\"msg\")  Trace.error(\"msg\")\n\n"
                f"Exempt: scripts/util/, scripts/utils/, scripts/autoload/trace.gd,\n"
                f"        scripts/autoload/mcp_server.gd, addons/\n"
                f"Per-line bypass: append `# allow-print` to the offending line.\n"
            )
            sys.exit(2)
    sys.exit(0)


if __name__ == "__main__":
    main()
