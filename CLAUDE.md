# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This repo is a personal sync/setup toolkit for Claude Code and Codex CLI on Windows. It distributes a single source-of-truth rules file (`AGENTS_template.md`) into the locations each CLI reads from, deploys helper launcher batch files into `C:\env`, and installs a custom Claude Code statusline. There is no application code, no test suite, and no build step.

## Common Commands

- `sync-rule.bat` — One-shot sync. Re-runs `sync-rule.ps1` in Windows Terminal when available, otherwise falls back to plain `cmd`. Use this after editing `AGENTS_template.md`, `clauded.bat`, `codexd.bat`, or `statusline.sh` to push changes out to `%USERPROFILE%\.claude`, `%USERPROFILE%\.codex`, and `C:\env`.
- `powershell -ExecutionPolicy Bypass -File .\sync-rule.ps1` — Direct invocation of the sync script (skips the Windows Terminal launcher).
- `bash ./setup-statusline.sh` — Unix-style standalone installer for just the statusline (requires `jq`). The PowerShell sync also handles statusline setup, so this is for non-Windows / WSL environments only.

There are no `build`, `lint`, or `test` commands — verification means re-running `sync-rule.bat` and inspecting the resulting `%USERPROFILE%\.claude\CLAUDE.md`, `%USERPROFILE%\.codex\AGENTS.md`, and `%USERPROFILE%\.claude\settings.json`.

## Architecture

The repo follows a single-source-of-truth fan-out pattern:

```
AGENTS_template.md ──► %USERPROFILE%\.claude\CLAUDE.md   (read by Claude Code)
                  └──► %USERPROFILE%\.codex\AGENTS.md    (read by Codex CLI)

clauded.bat, codexd.bat ──► C:\env\                       (must be on PATH)

statusline.sh ──► %USERPROFILE%\.claude\statusline.sh    (referenced by settings.json)
```

`sync-rule.ps1` is the orchestrator and has three phases — keep this layout in mind when editing it:

1. **Rules fan-out** — copies `AGENTS_template.md` to both `.claude\CLAUDE.md` and `.codex\AGENTS.md` via the `$targets` array.
2. **Launcher deploy** — copies `clauded.bat` and `codexd.bat` to `C:\env`. These wrap `claude --dangerously-skip-permissions` and `codex --dangerously-bypass-approvals-and-sandbox` respectively, so they intentionally bypass approval flows. Do not rename these or remove the flags without understanding the implication.
3. **Statusline + settings.json** — copies `statusline.sh` to `~/.claude/`, then **idempotently** patches `settings.json`. Each of `statusLine`, `env`, and `model` is added only if the key is missing. The script never overwrites existing values, so to change an already-configured key you must edit `settings.json` by hand or delete the key first.

The `env` block injected into `settings.json` contains placeholder values (`hocai-api-cua-ban`, `https://danglamgiau.com`, etc.). These are the defaults written on first run; real credentials are expected to replace them post-sync. Do not commit real credentials back into `sync-rule.ps1`.

`statusline.sh` reads JSON from stdin (provided by Claude Code) and parses it with `grep`/`sed` rather than `jq` so it has no runtime dependency. It caches the git branch per-cwd in `$TMPDIR/claudible-statusline/` with a 300s TTL — stale-looking branch names are usually a cache issue, not a parse bug.

## Editing Rules

`AGENTS_template.md` is the canonical rules file consumed by both Claude Code and Codex. Anything written there propagates to both CLIs on the next sync. The current contents enforce: Vietnamese responses addressing the user as "Mr Low Tech", English-only generated code, no code comments of any kind, Tilth MCP preferred over shell equivalents for codebase navigation/edits, and shell commands prefixed with `rtk` (Rust Token Killer proxy) for token-optimized output.

When editing the template, remember it ships verbatim to two different agents — keep instructions tool-agnostic where possible, and qualify Claude-specific or Codex-specific guidance explicitly.
