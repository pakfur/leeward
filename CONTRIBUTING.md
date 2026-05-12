# Contributing to Leeward

This guide covers development setup, project conventions, and optional Claude Code integration. For gameplay/design background, see `README.md`, `QUICKSTART.md`, and `docs/`.

## Prerequisites

- **Godot 4.6** on `PATH` as `godot` (the `Makefile` calls `godot ...` directly)
- **GNU Make** (Linux/macOS default; Windows users: use WSL or run the equivalent commands manually)
- **Python 3** for the print() hook (only if you use Claude Code — see below)
- **Node.js 18+** for the optional Godot MCP bridge (only if you use Claude Code)

Verify:

```bash
godot --version          # expect 4.6.x
make help                # lists available targets
```

## Local setup

```bash
git clone <repo-url> leeward
cd leeward
make import              # rebuild Godot's import cache
make run                 # boots the splash screen
make play                # skip menus, go straight to a scenario
make editor              # open the Godot editor
```

If you see import errors, `make clean && make import` does a hard reset of `.godot/`.

## Running tests

Tests use the [GUT](https://github.com/bitwes/Gut) framework vendored at `addons/gut/`.

```bash
make test                # run everything headless
make test-verbose        # detailed output
make test-file F=test/unit/test_movement_validator.gd    # single file
```

Test files live in `test/unit/`, named `test_*.gd`, extending `GutTest`. Use `before_all()` / `before_each()` for setup. Run `make test` before opening a PR.

## Project conventions

`CLAUDE.md` is the authoritative reference; key rules:

- **Use `Trace`, not `print()`.** Runtime code calls `Trace.info / Trace.warn / Trace.error`. `print()` is only allowed in `scripts/util/`, `scripts/utils/`, `scripts/autoload/trace.gd`, `scripts/autoload/mcp_server.gd`, and `addons/`. If you're using Claude Code, the hook described below enforces this automatically.
- **Server authority.** All state mutations happen in `scripts/server/` controllers, guarded by `if not is_server: push_error(...)`. Views and UI never mutate game state.
- **State-Controller-View split.** `scripts/state/` is pure data (immutable `Ship`, mutable `ShipState`), `scripts/server/` owns logic, `scripts/view/` + `scripts/ui/` only render.
- **Hex grid.** Axial `(q, r)` with pointy-top orientation. Direction numbering: 0=E, 1=SE, 2=SW, 3=W, 4=NW, 5=NE. All ships are 1-hex — `ShipState.get_ship_size()` is deprecated, hardcoded to 1.
- **Rule-table lookup keys are strings**, including `wind_speed` and `rigging_quality`. Wind facing `"L"` (luffing) always returns 0.

## Submitting changes

1. Branch off `main`. Milestone branches use `milestone/MNNN`.
2. Keep commits focused; follow the existing style (`git log` for examples).
3. Run `make test` and confirm it passes.
4. Open a PR with a one-paragraph "what + why" and a manual-test checklist if UI is involved.

---

## Claude Code integration (optional)

This repo ships some opt-in Claude Code automation. Skip this section if you don't use Claude Code.

### What's in the repo

- `.claude/skills/` — project-relevant skills (e.g. `godot-gdscript-patterns`). Loaded automatically when Claude Code starts in this directory.
- `.claude/settings.json` — committed, team-wide settings. Currently configures the print() guard hook (below).
- `.claude/hooks/block_raw_print.py` — the hook script.
- `.claude/settings.local.json` — your personal overrides (already in `.gitignore`).
- `.mcp.json` — your personal MCP-server configuration (already in `.gitignore`). Each developer creates their own.

### The print() guard hook

Lives at `.claude/hooks/block_raw_print.py`, wired through `.claude/settings.json` as a `PreToolUse` hook on `Edit|Write|MultiEdit`. It blocks raw `print(` from being introduced into `.gd` files outside the exempt paths listed in the project conventions above.

- Per-line bypass: append `# allow-print` to the offending line.
- The hook is pure Python 3, no dependencies. It silently no-ops on JSON-parse failure so a malformed hook input never blocks your edit.
- To disable temporarily, comment out the `PreToolUse` block in `.claude/settings.json`, or move the hook config to `settings.local.json` and toggle it there.

### Setting up the Godot MCP bridge

The bridge gives Claude tools to launch the editor, run scenes headlessly, capture debug output, list project info, etc. It is **per-developer** — `.mcp.json` is not committed.

#### Important name clash

There are two unrelated projects called "godot-mcp":

| Name | Where | What it does |
|------|-------|--------------|
| `addons/godot_mcp/` (in this repo) | Editor plugin | Runs a WebSocket server on port 9080 *inside* the running Godot editor. Has no Claude Code bridge component. |
| `Coding-Solo/godot-mcp` (external) | Standalone Node app | An MCP stdio server that invokes the Godot CLI via subprocess. **This is what you install for Claude Code.** |

The two do **not** talk to each other. Installing the Node bridge below does not connect Claude to the in-editor WebSocket; it gives Claude its own subprocess-based access to your Godot CLI.

#### Install

```bash
# Pick a location outside the project tree
mkdir -p ~/tools && cd ~/tools
git clone --depth 1 https://github.com/Coding-Solo/godot-mcp.git
cd godot-mcp
npm install
npm run build
ls build/index.js       # the executable entry point
```

#### Find your Godot binary

```bash
which godot             # e.g. /usr/local/bin/godot or /opt/homebrew/bin/godot
```

If `godot` isn't on `PATH`, point at the actual binary. On macOS that's typically `/Applications/Godot.app/Contents/MacOS/Godot`. On Linux it's wherever you installed it (`~/godot/godot`, `/usr/local/bin/godot`, etc.). On Windows use the full `.exe` path.

#### Configure `.mcp.json`

Create `.mcp.json` at the **repo root** (not inside `.claude/`). Substitute your absolute paths:

```json
{
  "mcpServers": {
    "godot": {
      "command": "node",
      "args": ["/ABSOLUTE/PATH/TO/godot-mcp/build/index.js"],
      "env": {
        "GODOT_PATH": "/ABSOLUTE/PATH/TO/godot",
        "DEBUG": "false"
      }
    }
  }
}
```

`.mcp.json` is gitignored, so each developer maintains their own copy.

#### Verify it loads

```bash
GODOT_PATH=/usr/local/bin/godot timeout 3 node ~/tools/godot-mcp/build/index.js < /dev/null
# expect:
#   [SERVER] Using Godot at: /usr/local/bin/godot
#   Godot MCP server running on stdio
```

The bridge runs persistently, so the 3-second timeout exits cleanly. If it errors or prints "Could not find Godot", fix `GODOT_PATH` and re-test.

Then restart Claude Code (or run `/mcp`) so the new `.mcp.json` is picked up. Project-level MCP servers trigger an approval prompt on first use — accept it. After that, Claude has access to tools like `launch_editor`, `run_project`, `get_debug_output`, `list_projects`, `get_project_info`, `create_scene`, `add_node`, `save_scene`, and friends.

#### Troubleshooting

- **"Could not find Godot"** — `GODOT_PATH` is wrong or empty. Use an absolute path to the binary itself, not a directory.
- **Server doesn't appear in `/mcp`** — Confirm `.mcp.json` is at the repo root (not in `.claude/`) and valid JSON: `jq . .mcp.json`. Restart Claude Code.
- **Permissions prompt loops** — Check `.claude/settings.local.json` for stale `enabledMcpjsonServers` / `disabledMcpjsonServers` entries.
- **Bridge needs an update** — `cd ~/tools/godot-mcp && git pull && npm install && npm run build`.

#### Alternative: npx (no local clone)

You can replace the local-clone setup with the npm-published version:

```json
{
  "mcpServers": {
    "godot": {
      "command": "npx",
      "args": ["@coding-solo/godot-mcp"],
      "env": { "GODOT_PATH": "/usr/local/bin/godot" }
    }
  }
}
```

This pulls the package on first run and caches it. Simpler, but you don't pin a specific version.
