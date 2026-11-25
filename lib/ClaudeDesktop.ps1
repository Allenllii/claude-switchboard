# ClaudeDesktop.ps1 — Claude Desktop paths, deployment mode, 3P profiles, session sync.
# Dot-source from the main script. Windows 10/11, MSIX (Microsoft Store) build preferred.

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-ClaudeDesktopPaths {
    $local3p = Join-Path $env:LOCALAPPDATA 'Claude-3p'
    $roaming3p = Join-Path $env:APPDATA 'Claude-3p'
    $roamingClaude = Join-Path $env:APPDATA 'Claude'
    return [pscustomobject]@{
        Local3p          = $local3p
        Roaming3p        = $roaming3p
        RoamingClaude    = $roamingClaude
        LocalConfig      = Join-Path $local3p 'claude_desktop_config.json'
        Roaming3pConfig  = Join-Path $roaming3p 'claude_desktop_config.json'
        RoamingConfig    = Join-Path $roamingClaude 'claude_desktop_config.json'
        LocalLibrary     = Join-Path $local3p 'configLibrary'
        RoamingLibrary   = Join-Path $roaming3p 'configLibrary'
        OfficialSessions = Join-Path $roamingClaude 'claude-code-sessions'
        GatewaySessions  = Join-Path $local3p 'claude-code-sessions'
        DataRoot         = Join-Path $env:LOCALAPPDATA 'ClaudeSwitchboard'
    }
}

function Read-JsonFile($path) {
    $raw = [System.IO.File]::ReadAllText($path)
    if ($raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF) { $raw = $raw.Substring(1) }
    return $raw | ConvertFrom-Json
}

function Write-JsonFile($path, $obj) {
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($path, ($obj | ConvertTo-Json -Depth 40), $script:Utf8NoBom)
}

function Get-ClaudeConfigPaths {
    $p = Get-ClaudeDesktopPaths
    return @($p.LocalConfig, $p.Roaming3pConfig, $p.RoamingConfig) |
        Where-Object { Test-Path -LiteralPath $_ }
}

function Get-CurrentDeploymentMode {
    $p = Get-ClaudeDesktopPaths
    if (-not (Test-Path -LiteralPath $p.LocalConfig)) { return 'unknown' }
    try {
        $doc = Read-JsonFile $p.LocalConfig
        if ($doc.deploymentMode -eq '1p') { return 'official' }
        if ($doc.deploymentMode -eq '3p') { return 'gateway' }
        return 'any'
    } catch { return 'unknown' }
}

function Set-DeploymentMode([string]$mode, [bool]$codeSidebar = $true) {
    $value = switch ($mode) { 'official' { '1p' } 'gateway' { '3p' } default { 'any' } }
    foreach ($path in Get-ClaudeConfigPaths) {
        $doc = Read-JsonFile $path
        $doc | Add-Member -NotePropertyName deploymentMode -NotePropertyValue $value -Force
        $doc | Add-Member -NotePropertyName disableDeploymentModeChooser -NotePropertyValue $false -Force
        if ($codeSidebar -and $doc.preferences) {
            $doc.preferences | Add-Member -NotePropertyName sidebarMode -NotePropertyValue 'code' -Force
        }
        Write-JsonFile $path $doc
    }
    return $value
}

function Get-SessionCardDir([string]$root) {
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    $best = $null
    $bestCount = -1
    foreach ($acct in Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue) {
        foreach ($org in Get-ChildItem -LiteralPath $acct.FullName -Directory -ErrorAction SilentlyContinue) {
            $n = @(Get-ChildItem -LiteralPath $org.FullName -Filter 'local_*.json' -File -ErrorAction SilentlyContinue).Count
            if ($n -gt $bestCount) { $bestCount = $n; $best = $org.FullName }
        }
    }
    return $best
}

function Copy-NewerFiles([string]$from, [string]$to, [switch]$PassThru) {
    if (-not $from -or -not $to -or -not (Test-Path -LiteralPath $from)) { return 0 }
    if (-not (Test-Path -LiteralPath $to)) { New-Item -ItemType Directory -Path $to -Force | Out-Null }
    $copied = 0
    foreach ($src in Get-ChildItem -LiteralPath $from -File -ErrorAction SilentlyContinue) {
        $dst = Join-Path $to $src.Name
        $need = $true
        if (Test-Path -LiteralPath $dst) {
            $need = $src.LastWriteTimeUtc -gt (Get-Item -LiteralPath $dst).LastWriteTimeUtc
        }
        if ($need) {
            Copy-Item -LiteralPath $src.FullName -Destination $dst -Force
            $copied++
        }
    }
    return $copied
}

function Sync-ClaudeSessions {
    $p = Get-ClaudeDesktopPaths
    $official = Get-SessionCardDir $p.OfficialSessions
    $gateway = Get-SessionCardDir $p.GatewaySessions
    return [pscustomobject]@{
        OfficialDir       = $official
        GatewayDir        = $gateway
        OfficialToGateway = (Copy-NewerFiles $official $gateway)
        GatewayToOfficial = (Copy-NewerFiles $gateway $official)
    }
}

function Get-SessionCounts {
    $p = Get-ClaudeDesktopPaths
    $official = Get-SessionCardDir $p.OfficialSessions
    $gateway = Get-SessionCardDir $p.GatewaySessions
    return [pscustomobject]@{
        Official = if ($official) { @(Get-ChildItem -LiteralPath $official -Filter 'local_*.json' -File).Count } else { 0 }
        Gateway  = if ($gateway) { @(Get-ChildItem -LiteralPath $gateway -Filter 'local_*.json' -File).Count } else { 0 }
    }
}

function Write-GatewayProfile($paths, $profile, [string]$plainKey) {
    # Write one 3P profile into both config libraries and make it the applied id.
    $models = @()
    foreach ($m in $profile.models) {
        $entry = [ordered]@{
            name          = $m.id
            labelOverride = if ($m.label) { $m.label } else { $m.id }
        }
        if ($m.supports1m -eq $true) { $entry['supports1m'] = $true }
        if ($m.tier -and $m.tier -in @('opus', 'sonnet', 'haiku')) {
            $entry['anthropicFamilyTier'] = $m.tier
        }
        $models += [pscustomobject]$entry
    }
    $config = [ordered]@{
        inferenceProvider             = 'gateway'
        inferenceGatewayBaseUrl       = $profile.baseUrl
        inferenceGatewayApiKey        = $plainKey
        inferenceGatewayAuthScheme    = 'bearer'
        inferenceModels               = $models
        modelDiscoveryEnabled         = $false
        chatTabEnabled                = $true
        coworkEgressAllowedHosts      = @('*')
        inferenceStreamIdleTimeoutSec = 1800
    }
    foreach ($lib in @($paths.LocalLibrary, $paths.RoamingLibrary)) {
        if (-not (Test-Path -LiteralPath $lib)) { New-Item -ItemType Directory -Path $lib -Force | Out-Null }
        $file = Join-Path $lib ($profile.id + '.json')
        Write-JsonFile $file ([pscustomobject]$config)
        $metaPath = Join-Path $lib '_meta.json'
        $meta = if (Test-Path -LiteralPath $metaPath) { Read-JsonFile $metaPath } else { [pscustomobject]@{ appliedId = ''; entries = @() } }
        if (-not $meta.entries) { $meta | Add-Member -NotePropertyName entries -NotePropertyValue @() -Force }
        $entries = @($meta.entries | Where-Object { $_.id -ne $profile.id })
        $entries += [pscustomobject]@{ id = $profile.id; name = $profile.name }
        $meta | Add-Member -NotePropertyName entries -NotePropertyValue $entries -Force
        $meta | Add-Member -NotePropertyName appliedId -NotePropertyValue $profile.id -Force
        Write-JsonFile $metaPath $meta
    }
}

function Get-ClaudeLaunchTarget {
    # Returns @{ Kind = 'aumid'|'exe'; Target = ... }
    try {
        $pkg = Get-AppxPackage -Name 'Claude' -ErrorAction Stop | Select-Object -First 1
        if ($pkg) {
            $fam = $pkg.PackageFamilyName
            $manifest = Get-AppxPackageManifest $pkg
            $appId = @($manifest.Package.Applications.Application)[0].Id
            return [pscustomobject]@{ Kind = 'aumid'; Target = "shell:AppsFolder\$fam!$appId" }
        }
    } catch {}
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\claude\Claude.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Claude\Claude.exe')
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return [pscustomobject]@{ Kind = 'exe'; Target = $c } }
    }
    return $null
}

function Stop-ClaudeDesktop {
    Get-Process claude -ErrorAction SilentlyContinue | Stop-Process -Force
    for ($i = 0; $i -lt 24; $i++) {
        if (-not (Get-Process claude -ErrorAction SilentlyContinue)) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Start-ClaudeDesktop {
    $target = Get-ClaudeLaunchTarget
    if (-not $target) { throw 'Claude Desktop was not found (MSIX package or install folder).' }
    if ($target.Kind -eq 'aumid') { explorer.exe $target.Target }
    else { Start-Process -FilePath $target.Target }
}

function Invoke-ClaudeSwitch {
    param(
        [Parameter(Mandatory)] $Profile,
        [string]$PlainKey = '',
        [bool]$SyncSessions = $true,
        [bool]$CodeSidebar = $true,
        [scriptblock]$Log = { param($m) }
    )
    $paths = Get-ClaudeDesktopPaths
    & $Log 'Stopping Claude Desktop...'
    if (-not (Stop-ClaudeDesktop)) { throw 'Claude Desktop did not exit in time.' }
    if ($SyncSessions) {
        & $Log 'Syncing session cards...'
        $r = Sync-ClaudeSessions
        & $Log ("official->gateway {0}, gateway->official {1}" -f $r.OfficialToGateway, $r.GatewayToOfficial)
    }
    if ($Profile.kind -eq 'official') {
        $v = Set-DeploymentMode 'official' $CodeSidebar
        & $Log "deploymentMode=$v"
    } else {
        Write-GatewayProfile $paths $Profile $PlainKey
        $v = Set-DeploymentMode 'gateway' $CodeSidebar
        & $Log "deploymentMode=$v, applied profile=$($Profile.name)"
    }
    & $Log 'Starting Claude Desktop...'
    Start-ClaudeDesktop
}
