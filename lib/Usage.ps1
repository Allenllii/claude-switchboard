# Usage.ps1 — local token/cost aggregation from Claude Code transcripts.
# The transcripts live in %USERPROFILE%\.claude\projects and are shared by every
# login mode, so this dashboard works for official and gateway alike. Nothing is
# uploaded; no credentials are read.

$script:ModelPrices = @{
    'claude-opus-5-5'   = @{ input = 4;  output = 20 }
    'claude-opus-5'     = @{ input = 5;  output = 25 }
    'claude-opus-4-8'   = @{ input = 5;  output = 25 }
    'claude-opus-4-7'   = @{ input = 5;  output = 25 }
    'claude-opus-4-6'   = @{ input = 5;  output = 25 }
    'claude-opus-4-5'   = @{ input = 5;  output = 25 }
    'claude-opus-4-1'   = @{ input = 15; output = 75 }
    'claude-opus-4'     = @{ input = 15; output = 75 }
    'claude-sonnet-5-5' = @{ input = 2;  output = 10 }
    'claude-sonnet-5'   = @{ input = 2;  output = 10 }
    'claude-sonnet-4-6' = @{ input = 3;  output = 15 }
    'claude-sonnet-4-5' = @{ input = 3;  output = 15 }
    'claude-sonnet-4'   = @{ input = 3;  output = 15 }
    'claude-haiku-5-5'  = @{ input = 0.1; output = 0.5 }
    'claude-haiku-4-5'  = @{ input = 1;  output = 5 }
    'claude-fable-5-2'  = @{ input = 8;  output = 40 }
    'claude-fable-5-1'  = @{ input = 10; output = 50 }
    'claude-fable-5'    = @{ input = 10; output = 50 }
}

function Get-ModelPrice([string]$model) {
    $key = ($model -split '\[')[0]
    if ($script:ModelPrices.ContainsKey($key)) { return $script:ModelPrices[$key] }
    foreach ($k in $script:ModelPrices.Keys) {
        if ($key -like "$k*") { return $script:ModelPrices[$k] }
    }
    return @{ input = 3; output = 15 }
}

function Get-TranscriptRoot {
    return (Join-Path $env:USERPROFILE '.claude\projects')
}

function Get-ClaudeUsage {
    param(
        [int]$Days = 7,
        [scriptblock]$Progress = { param($done, $total, $file) }
    )
    $root = Get-TranscriptRoot
    $result = [pscustomobject]@{
        Days       = $Days
        Messages   = 0
        Input      = 0
        Output     = 0
        CacheRead  = 0
        CacheWrite = 0
        Cost       = 0.0
        ByModel    = @()
        ByProject  = @()
        ByDay      = @()
        ScannedAt  = (Get-Date)
        Root       = $root
        Available  = (Test-Path -LiteralPath $root)
    }
    if (-not $result.Available) { return $result }

    $cutoff = (Get-Date).AddDays(-$Days)
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $cutoff })
    $total = $files.Count
    if ($total -eq 0) { return $result }

    $models = @{}
    $projects = @{}
    $dayStats = @{}
    $idx = 0

    foreach ($file in $files) {
        $idx++
        & $Progress $idx $total $file.Name
        $project = Split-Path -Leaf (Split-Path -Parent $file.FullName)
        $cwd = $null
        $probe = [System.IO.File]::OpenText($file.FullName)
        try {
            for ($i = 0; $i -lt 6; $i++) {
                $pl = $probe.ReadLine()
                if ($null -eq $pl) { break }
                if ($pl.IndexOf('"cwd"', [StringComparison]::Ordinal) -lt 0) { continue }
                try { $pd = $pl | ConvertFrom-Json } catch { continue }
                if ($pd.cwd) { $cwd = [string]$pd.cwd; break }
            }
        } finally { $probe.Close() }
        if ($cwd) { $project = $cwd }
        $reader = [System.IO.File]::OpenText($file.FullName)
        try {
            while ($null -ne ($line = $reader.ReadLine())) {
                if ($line.IndexOf('"usage"', [StringComparison]::Ordinal) -lt 0) { continue }
                try { $d = $line | ConvertFrom-Json } catch { continue }
                if (-not $d.message -or -not $d.message.usage) { continue }
                if ($d.type -and $d.type -ne 'assistant') { continue }
                $ts = $null
                if ($d.timestamp) {
                    try { $ts = [datetime]::Parse($d.timestamp).ToLocalTime() } catch { $ts = $null }
                }
                if ($ts -and $ts -lt $cutoff) { continue }
                $u = $d.message.usage
                $model = [string]$d.message.model
                if (-not $model) { $model = 'unknown' }
                if ($model -eq '<synthetic>') { continue }
                $price = Get-ModelPrice $model
                $inTok = [int]($u.input_tokens | ForEach-Object { $_ })
                $outTok = [int]($u.output_tokens | ForEach-Object { $_ })
                $crTok = [int]($u.cache_read_input_tokens | ForEach-Object { $_ })
                $cwTok = [int]($u.cache_creation_input_tokens | ForEach-Object { $_ })

                $cost = 0.0
                $cost += $inTok / 1e6 * $price.input
                $cost += $outTok / 1e6 * $price.output
                $cost += $crTok / 1e6 * $price.input * 0.1
                $w1h = 0; $w5m = 0
                if ($u.cache_creation) {
                    $w1h = [int]($u.cache_creation.ephemeral_1h_input_tokens | ForEach-Object { $_ })
                    $w5m = [int]($u.cache_creation.ephemeral_5m_input_tokens | ForEach-Object { $_ })
                }
                if ($w1h -or $w5m) {
                    $cost += $w1h / 1e6 * $price.input * 2.0
                    $cost += $w5m / 1e6 * $price.input * 1.25
                } else {
                    $cost += $cwTok / 1e6 * $price.input * 1.25
                }

                $result.Messages++
                $result.Input += $inTok
                $result.Output += $outTok
                $result.CacheRead += $crTok
                $result.CacheWrite += $cwTok
                $result.Cost += $cost

                if (-not $models.ContainsKey($model)) {
                    $models[$model] = [pscustomobject]@{ Model = $model; Messages = 0; Input = 0; Output = 0; CacheRead = 0; CacheWrite = 0; Cost = 0.0 }
                }
                $m = $models[$model]
                $m.Messages++; $m.Input += $inTok; $m.Output += $outTok
                $m.CacheRead += $crTok; $m.CacheWrite += $cwTok; $m.Cost += $cost

                if (-not $projects.ContainsKey($project)) {
                    $projects[$project] = [pscustomobject]@{ Project = $project; Messages = 0; Input = 0; Output = 0; Cost = 0.0 }
                }
                $p = $projects[$project]
                $p.Messages++; $p.Input += $inTok; $p.Output += $outTok; $p.Cost += $cost

                $dayKey = if ($ts) { $ts.ToString('yyyy-MM-dd') } else { 'unknown' }
                if (-not $dayStats.ContainsKey($dayKey)) {
                    $dayStats[$dayKey] = [pscustomobject]@{ Day = $dayKey; Messages = 0; Input = 0; Output = 0; Cost = 0.0 }
                }
                $dd = $dayStats[$dayKey]
                $dd.Messages++; $dd.Input += $inTok; $dd.Output += $outTok; $dd.Cost += $cost
            }
        } finally { $reader.Close() }
    }

    $result.ByModel = @($models.Values | Sort-Object Cost -Descending)
    $result.ByProject = @($projects.Values | Sort-Object Cost -Descending)
    $result.ByDay = @($dayStats.Values | Sort-Object Day -Descending)
    return $result
}

function Format-Tokens([long]$n) {
    if ($n -ge 1000000) { return ('{0:N2}M' -f ($n / 1e6)) }
    if ($n -ge 1000) { return ('{0:N1}K' -f ($n / 1e3)) }
    return [string]$n
}
