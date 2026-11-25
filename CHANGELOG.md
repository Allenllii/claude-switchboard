# Changelog

## 0.1.0 — 2026-11-25

- Initial release.
- Switch Claude Desktop between the official claude.ai account (`deploymentMode = 1p`)
  and third-party Anthropic-compatible gateways (`deploymentMode = 3p`).
- Gateway profile manager with DPAPI-encrypted API keys.
- Two-way session-card sync (`local_*.json`, `archived-sessions.idx`) so projects and
  history stay visible across modes.
- `preferences.sidebarMode = "code"` support for grouped projects.
- Local usage dashboard parsed from `~/.claude/projects`: messages, input/output,
  cache read/write and estimated cost, by model and by project.
- UTF-8 without BOM writes; correct stop → sync → write → start order.
