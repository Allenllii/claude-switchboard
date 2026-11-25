# Creates a desktop shortcut that launches Claude Switchboard with pwsh.
# Usage: pwsh -File .\Install-Shortcut.ps1

$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot 'ClaudeSwitchboard.ps1'
if (-not (Test-Path -LiteralPath $script)) { throw "ClaudeSwitchboard.ps1 not found next to this script." }

$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) {
    $candidate = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe'
    if (Test-Path -LiteralPath $candidate) { $pwsh = $candidate }
}
if (-not $pwsh) { throw 'PowerShell 7 (pwsh) was not found. Install it from https://aka.ms/powershell.' }

$ws = New-Object -ComObject WScript.Shell
$desktop = [Environment]::GetFolderPath('Desktop')
$lnk = $ws.CreateShortcut((Join-Path $desktop 'Claude Switchboard.lnk'))
$lnk.TargetPath = $pwsh
$lnk.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $script + '"'
$lnk.WorkingDirectory = $PSScriptRoot
$lnk.IconLocation = $pwsh + ',0'
$lnk.Description = 'Switch Claude Desktop between the official account and third-party gateways'
$lnk.Save()

Write-Host "Shortcut created: $(Join-Path $desktop 'Claude Switchboard.lnk')"
