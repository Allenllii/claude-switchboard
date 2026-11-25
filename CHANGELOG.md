# Changelog

## 0.3.0 — 2026-11-25

- Rebuilt the panel in the visual language of
  [claude-account-switcher](https://github.com/SnlperStripes/claude-account-switcher):
  dark palette (`#262624` / `#30302E` / `#D97757`), menu-style profile rows with a
  green check on the active one, orange primary action, compact 700×540 window.
- Custom title bar (drag region, minimise / maximise / close) and a four-tab header:
  Switch, Usage, Activity, About.
- Tray icon: a ring that is green for the official account and orange for a gateway.
  Right-click gives a dark menu with the profile list, add-gateway, open console and
  quit; closing the window now hides it to the tray. Left-click reopens the panel.
- Activity log moved from a permanent box on the switch page to its own tab; the
  switch page shows only the latest line.
- Add/edit gateway dialog rebuilt as a dark 560×680 form with the app icon, dark
  scrollbars and the orange save button. API keys remain DPAPI-encrypted.
- Dark DWM title bar and rounded window corners; popup menus use the app palette.
- Tab pages reset to the top when opened.

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
