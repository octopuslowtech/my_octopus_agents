Personal preferences and tool configurations applied to all projects.

## Language And Communication Rules

- Always respond entirely in Vietnamese.
- Always address the user as "Mr Low Tech" in every response.
- All generated content, including code, text, variable names, and file names, must be written in English.
- All generated source code must not contain comments or code comments.
- Do not use comment characters of the corresponding programming language, such as `//`, `#`, `/* */`, or `<!-- -->`.
- Always verify and run tests after modifying any code.
- Keep all responses concise and high-signal by default.
- Avoid filler, pleasantries, repetition, and unnecessary explanations.
- Prefer short paragraphs or compact bullet lists when structure helps.
- Preserve technical accuracy, important caveats, commands, code, error messages, and verification details.
- Expand only when the user asks for depth, when safety or ambiguity requires it, or when a short answer would be misleading.

## Tilth MCP Workflow

- Prefer Tilth MCP for codebase navigation and source edits before using shell equivalents.
- Use `tilth_files` instead of `find`, `ls`, `dir`, or `rg --files` when discovering files by glob.
- Use `tilth_search` instead of `grep`, `rg`, or ad hoc shell searches when looking for symbols, literal text, regex matches, or call sites.
- Use `tilth_read` instead of `cat`, `type`, `Get-Content`, `sed`, or `head` when reading source files. Keep reads scoped with `section` or `sections` for large files.
- Use `tilth_edit` instead of manual shell writes when editing existing files. Read the file first, then edit with hashline anchors from `tilth_read`.
- Use `tilth_diff` instead of `git diff` for reviewing uncommitted, staged, file-to-file, patch, or log-based changes. Enable blast-radius warnings when reviewing signature or behavior changes.
- Use `tilth_deps` before planned breaking changes that alter function signatures, remove or rename exports, or modify behavior relied on by callers.
- Use `tilth_search` with `kind: "symbol"` for definitions and usages, `kind: "callers"` for call sites, `kind: "content"` for exact text, and `kind: "regex"` for patterns.
- Use `tilth_read` with `paths` for batch reads, `full` only when needed, and smart outlines for large files.
- Use `tilth_files` with `patterns` for multiple glob queries in one call and `scope` only when intentionally limiting discovery to a subdirectory.
- Use `tilth_edit` atomically for one or more anchored replacements, insertions, or deletions, and request a compact diff when useful.
- Use shell commands prefixed with `rtk` only for tasks Tilth does not cover, such as running builds, tests, scripts, Git commands that change repository state, WSL commands, or external tooling.

# RTK - Rust Token Killer (Codex CLI)

**Usage**: Token-optimized CLI proxy for shell commands.

## Rule

Always prefix shell commands with `rtk`.

Examples:

```bash
rtk git status
rtk cargo test
rtk npm run build
rtk pytest -q
```

## Meta Commands

```bash
rtk gain            # Token savings analytics
rtk gain --history  # Recent command savings history
rtk proxy <cmd>     # Run raw command without filtering
```

## Verification

```bash
rtk --version
rtk gain
which rtk
```

