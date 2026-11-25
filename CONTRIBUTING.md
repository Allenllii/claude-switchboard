# Contributing

Thanks for taking a look. Issues and pull requests are welcome.

## Ground rules

- Target Windows 10/11 and PowerShell 7 (`pwsh`). Keep Windows PowerShell 5.1 in mind:
  do not rely on BOM-less UTF-8 parsing there.
- Do not add telemetry, analytics or background network calls.
- Never commit API keys, tokens, session transcripts or screenshots that contain
  personal paths or account names.

## Development

```powershell
git clone https://github.com/Allenllii/claude-switchboard.git
cd claude-switchboard
pwsh -File .\ClaudeSwitchboard.ps1
```

Before opening a PR:

1. Open the app, switch to a test gateway profile and back to the official account.
2. Confirm both modes still show the same sessions/projects.
3. Open the Usage tab with 7 and 30 days and check totals are non-zero.
4. Confirm `profiles.json` lives in `%LOCALAPPDATA%\ClaudeSwitchboard` and no secrets
   appear in the diff.

## Scope

Changes that depend on undocumented Claude Desktop internals are acceptable, but they
must fail with a clear error message and must not corrupt existing configuration.
