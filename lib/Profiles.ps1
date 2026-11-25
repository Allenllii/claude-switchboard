# Profiles.ps1 — profile store with DPAPI-encrypted API keys.

Add-Type -AssemblyName System.Security.Cryptography.ProtectedData

function Get-ProfilesFilePath {
    $paths = Get-ClaudeDesktopPaths
    if (-not (Test-Path -LiteralPath $paths.DataRoot)) {
        New-Item -ItemType Directory -Path $paths.DataRoot -Force | Out-Null
    }
    return Join-Path $paths.DataRoot 'profiles.json'
}

function Protect-Secret([string]$plain) {
    if ([string]::IsNullOrEmpty($plain)) { return '' }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($plain)
    $enc = [System.Security.Cryptography.ProtectedData]::Protect(
        $bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    return [Convert]::ToBase64String($enc)
}

function Unprotect-Secret([string]$encoded) {
    if ([string]::IsNullOrEmpty($encoded)) { return '' }
    $enc = [Convert]::FromBase64String($encoded)
    $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $enc, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function New-DefaultProfilesDoc {
    return [pscustomobject]@{
        version         = 1
        activeProfileId = 'official'
        profiles        = @(
            [pscustomobject]@{
                id      = 'official'
                name    = 'Claude Max (official sign-in)'
                kind    = 'official'
                models  = @()
                notes   = ''
            }
        )
    }
}

function Get-ProfilesDoc {
    $file = Get-ProfilesFilePath
    if (-not (Test-Path -LiteralPath $file)) {
        $doc = New-DefaultProfilesDoc
        Write-JsonFile $file $doc
        return $doc
    }
    $doc = Read-JsonFile $file
    if (-not $doc.profiles -or @($doc.profiles).Count -eq 0) {
        $doc = New-DefaultProfilesDoc
        Write-JsonFile $file $doc
    }
    if (-not ($doc.profiles | Where-Object { $_.id -eq 'official' })) {
        $doc.profiles = @([pscustomobject]@{ id = 'official'; name = 'Claude Max (official sign-in)'; kind = 'official'; models = @(); notes = '' }) + @($doc.profiles)
        Write-JsonFile $file $doc
    }
    return $doc
}

function Save-ProfilesDoc($doc) {
    Write-JsonFile (Get-ProfilesFilePath) $doc
}

function New-ProfileId { return [guid]::NewGuid().ToString() }

function Get-ProfileById($doc, [string]$id) {
    return @($doc.profiles) | Where-Object { $_.id -eq $id } | Select-Object -First 1
}

function Get-ProfilePlainKey($profile) {
    if (-not $profile.apiKeyEnc) { return '' }
    return Unprotect-Secret $profile.apiKeyEnc
}

function Add-GatewayProfile {
    param(
        [string]$Name,
        [string]$BaseUrl,
        [string]$ApiKey,
        [array]$Models,
        [string]$Notes = ''
    )
    $doc = Get-ProfilesDoc
    $profile = [pscustomobject]@{
        id        = (New-ProfileId)
        name      = $Name
        kind      = 'gateway'
        baseUrl   = $BaseUrl.TrimEnd('/')
        apiKeyEnc = (Protect-Secret $ApiKey)
        models    = @($Models)
        notes     = $Notes
        createdAt = (Get-Date).ToString('s')
    }
    $doc.profiles = @($doc.profiles) + $profile
    Save-ProfilesDoc $doc
    return $profile
}

function Update-GatewayProfile {
    param($Profile, [string]$Name, [string]$BaseUrl, [string]$ApiKey, [array]$Models, [string]$Notes = '')
    $doc = Get-ProfilesDoc
    $target = Get-ProfileById $doc $Profile.id
    if (-not $target) { throw 'Profile not found.' }
    $target.name = $Name
    $target.baseUrl = $BaseUrl.TrimEnd('/')
    if ($ApiKey) { $target.apiKeyEnc = (Protect-Secret $ApiKey) }
    $target.models = @($Models)
    $target.notes = $Notes
    Save-ProfilesDoc $doc
    return $target
}

function Remove-Profile([string]$id) {
    if ($id -eq 'official') { throw 'The official profile cannot be removed.' }
    $doc = Get-ProfilesDoc
    $doc.profiles = @($doc.profiles | Where-Object { $_.id -ne $id })
    if ($doc.activeProfileId -eq $id) { $doc.activeProfileId = 'official' }
    Save-ProfilesDoc $doc
}

function Set-ActiveProfile([string]$id) {
    $doc = Get-ProfilesDoc
    $doc.activeProfileId = $id
    Save-ProfilesDoc $doc
}

function ConvertFrom-ModelText([string]$text) {
    # One model per line: id | label | tier (opus/sonnet/haiku/fable) [| 1m]
    # The 1M flag is off by default so the desktop picker shows one entry per model.
    $list = @()
    foreach ($line in ($text -split "`r?`n")) {
        $t = $line.Trim()
        if (-not $t) { continue }
        $parts = $t -split '\|' | ForEach-Object { $_.Trim() }
        $id = $parts[0]
        if (-not $id) { continue }
        $list += [pscustomobject]@{
            id         = $id
            label      = if ($parts.Count -gt 1 -and $parts[1]) { $parts[1] } else { $id }
            tier       = if ($parts.Count -gt 2) { $parts[2].ToLower() } else { '' }
            supports1m = if ($parts.Count -gt 3) { $parts[3] -eq '1m' } else { $false }
        }
    }
    return $list
}

function ConvertTo-ModelText($models) {
    $lines = @()
    foreach ($m in @($models)) {
        $line = ('{0} | {1} | {2}' -f $m.id, $m.label, $m.tier)
        if ($m.supports1m) { $line += ' | 1m' }
        $lines += $line
    }
    return ($lines -join "`r`n")
}

function Get-DefaultClaudeModels {
    return @(
        [pscustomobject]@{ id = 'claude-opus-5-5'; label = 'Claude Opus 5.5'; tier = 'opus'; supports1m = $false }
        [pscustomobject]@{ id = 'claude-sonnet-5-5'; label = 'Claude Sonnet 5.5'; tier = 'sonnet'; supports1m = $false }
        [pscustomobject]@{ id = 'claude-haiku-5-5'; label = 'Claude Haiku 5.5'; tier = 'haiku'; supports1m = $false }
        [pscustomobject]@{ id = 'claude-fable-5-2'; label = 'Claude Fable 5.2'; tier = 'fable'; supports1m = $false }
    )
}
