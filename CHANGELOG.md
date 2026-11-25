# Changelog

## 0.2.0 — 2026-11-25

- New WPF interface: dark sidebar navigation, profile cards with kind badges and an
  active marker, status pill, summary cards and tables on the usage page.
- 1M-context variants are off by default, so the model picker shows a single entry per
  model. A model can opt in with a fourth `| 1m` field.
- `anthropicFamilyTier` is written only for the valid `opus`/`sonnet`/`haiku` slots.
- Existing profiles are migrated to the single-entry model list.

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
