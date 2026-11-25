# Claude Switchboard — GUI for Claude Desktop mode switching, session sync and local usage.
# Run with PowerShell 7:  pwsh -File ClaudeSwitchboard.ps1

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security.Cryptography.ProtectedData

$script:Root = $PSScriptRoot
. (Join-Path $script:Root 'lib\ClaudeDesktop.ps1')
. (Join-Path $script:Root 'lib\Profiles.ps1')
. (Join-Path $script:Root 'lib\Usage.ps1')

$script:ProfilesDoc = Get-ProfilesDoc
$script:Busy = $false
$script:LastUsage = $null

# ---------------- helpers ----------------
function Write-Log([string]$msg) {
    $line = "[{0}] {1}" -f ([DateTime]::Now.ToString('HH:mm:ss')), $msg
    $script:logBox.AppendText($line + "`r`n")
    $script:logBox.SelectionStart = $script:logBox.TextLength
    $script:logBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-SelectedProfile {
    if ($script:profileList.SelectedItems.Count -eq 0) { return $null }
    $id = $script:profileList.SelectedItems[0].Tag
    return Get-ProfileById $script:ProfilesDoc $id
}

function Update-Status {
    $mode = Get-CurrentDeploymentMode
    $counts = Get-SessionCounts
    $label = switch ($mode) {
        'official' { 'Official Claude Max' }
        'gateway'  { 'BirdAPI gateway' }
        default    { 'Unknown / chooser' }
    }
    $script:statusLabel.Text = "Current: $label   |   sessions: official $($counts.Official), gateway $($counts.Gateway)"
    $script:statusLabel.ForeColor = if ($mode -eq 'official') {
        [System.Drawing.Color]::FromArgb(180, 95, 6)
    } else {
        [System.Drawing.Color]::FromArgb(37, 99, 235)
    }
}

function Refresh-ProfileList {
    $script:ProfilesDoc = Get-ProfilesDoc
    $script:profileList.BeginUpdate()
    $script:profileList.Items.Clear()
    foreach ($p in @($script:ProfilesDoc.profiles)) {
        $kind = if ($p.kind -eq 'official') { 'official' } else { 'gateway' }
        $models = if ($p.kind -eq 'official') { '-' } else { (@($p.models).Count.ToString() + ' models') }
        $item = New-Object System.Windows.Forms.ListViewItem($p.name)
        [void]$item.SubItems.Add($kind)
        [void]$item.SubItems.Add($models)
        $item.Tag = $p.id
        if ($p.id -eq $script:ProfilesDoc.activeProfileId) { $item.BackColor = [System.Drawing.Color]::FromArgb(235, 244, 255) }
        [void]$script:profileList.Items.Add($item)
    }
    $script:profileList.EndUpdate()
    Update-Status
}

function Set-Busy([bool]$value) {
    $script:Busy = $value
    foreach ($b in @($script:btnSwitch, $script:btnAdd, $script:btnEdit, $script:btnRemove, $script:btnOpen)) {
        $b.Enabled = -not $value
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Invoke-SwitchTo($profile) {
    if (-not $profile) { Write-Log 'Select a profile first.'; return }
    if ($script:Busy) { return }
    $key = ''
    if ($profile.kind -ne 'official') {
        $key = Get-ProfilePlainKey $profile
        if (-not $key) { Write-Log 'This profile has no API key. Edit it first.'; return }
    }
    Set-Busy $true
    try {
        Invoke-ClaudeSwitch -Profile $profile -PlainKey $key `
            -SyncSessions ([bool]$script:chkSync.Checked) `
            -CodeSidebar ([bool]$script:chkCode.Checked) `
            -Log { param($m) Write-Log $m }
        Set-ActiveProfile $profile.id
        $script:ProfilesDoc = Get-ProfilesDoc
        Write-Log 'Done.'
        Start-Sleep -Seconds 2
    } catch {
        Write-Log ('ERROR: ' + $_.Exception.Message)
    } finally {
        Set-Busy $false
        Refresh-ProfileList
    }
}

function Show-ProfileDialog($existing) {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = if ($existing) { 'Edit gateway profile' } else { 'Add gateway profile' }
    $dlg.Size = New-Object System.Drawing.Size(560, 520)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

    function Add-Field([string]$label, [int]$y, [int]$height = 27) {
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $label
        $l.Location = New-Object System.Drawing.Point(18, $y)
        $l.Size = New-Object System.Drawing.Size(110, 22)
        $dlg.Controls.Add($l)
        $t = New-Object System.Windows.Forms.TextBox
        $t.Location = New-Object System.Drawing.Point(132, $y)
        $t.Size = New-Object System.Drawing.Size(400, $height)
        $dlg.Controls.Add($t)
        return $t
    }

    $txtName = Add-Field 'Name' 16
    $txtUrl = Add-Field 'Base URL' 52
    $txtKey = Add-Field 'API key' 88
    $txtKey.UseSystemPasswordChar = $true

    $lblModels = New-Object System.Windows.Forms.Label
    $lblModels.Text = "Models (one per line: id | label | opus/sonnet/haiku/fable | 1m)"
    $lblModels.Location = New-Object System.Drawing.Point(18, 126)
    $lblModels.Size = New-Object System.Drawing.Size(520, 20)
    $dlg.Controls.Add($lblModels)

    $txtModels = New-Object System.Windows.Forms.TextBox
    $txtModels.Multiline = $true
    $txtModels.ScrollBars = 'Vertical'
    $txtModels.Location = New-Object System.Drawing.Point(18, 148)
    $txtModels.Size = New-Object System.Drawing.Size(514, 250)
    $txtModels.Font = New-Object System.Drawing.Font('Consolas', 9)
    $dlg.Controls.Add($txtModels)

    $txtNotes = Add-Field 'Notes' 410
    $txtNotes.Size = New-Object System.Drawing.Size(400, 27)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Save'
    $ok.Location = New-Object System.Drawing.Point(338, 448)
    $ok.Size = New-Object System.Drawing.Size(90, 28)
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dlg.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.Location = New-Object System.Drawing.Point(438, 448)
    $cancel.Size = New-Object System.Drawing.Size(90, 28)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($cancel)
    $dlg.AcceptButton = $ok
    $dlg.CancelButton = $cancel

    if ($existing) {
        $txtName.Text = $existing.name
        $txtUrl.Text = $existing.baseUrl
        $txtModels.Text = ConvertTo-ModelText $existing.models
        $txtNotes.Text = $existing.notes
        $txtKey.Text = ''
        $txtKey.PlaceholderText = '(unchanged)'
    } else {
        $txtUrl.Text = 'https://'
        $txtModels.Text = ConvertTo-ModelText (Get-DefaultClaudeModels)
    }

    if ($dlg.ShowDialog($script:form) -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $models = ConvertFrom-ModelText $txtModels.Text
    if (-not $txtName.Text.Trim() -or -not $txtUrl.Text.Trim()) {
        [System.Windows.Forms.MessageBox]::Show('Name and Base URL are required.', 'Claude Switchboard')
        return
    }
    if (-not $existing -and -not $txtKey.Text.Trim()) {
        [System.Windows.Forms.MessageBox]::Show('An API key is required for a gateway profile.', 'Claude Switchboard')
        return
    }
    if ($existing) {
        Update-GatewayProfile -Profile $existing -Name $txtName.Text.Trim() -BaseUrl $txtUrl.Text.Trim() `
            -ApiKey $txtKey.Text -Models $models -Notes $txtNotes.Text | Out-Null
        Write-Log ('Updated profile: ' + $txtName.Text.Trim())
    } else {
        Add-GatewayProfile -Name $txtName.Text.Trim() -BaseUrl $txtUrl.Text.Trim() `
            -ApiKey $txtKey.Text -Models $models -Notes $txtNotes.Text | Out-Null
        Write-Log ('Added profile: ' + $txtName.Text.Trim())
    }
    Refresh-ProfileList
}

function Refresh-Usage {
    if ($script:Busy) { return }
    $script:Busy = $true
    $script:btnRefreshUsage.Enabled = $false
    $days = [int]$script:cboDays.SelectedItem
    $script:usageStatus.Text = 'Scanning transcripts...'
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $u = Get-ClaudeUsage -Days $days -Progress {
            param($done, $total, $file)
            $script:usageStatus.Text = "Scanning $done/$total"
            [System.Windows.Forms.Application]::DoEvents()
        }
        $script:LastUsage = $u
        if (-not $u.Available) {
            $script:usageStatus.Text = "No transcripts found at $($u.Root)"
            return
        }
        $script:usageSummary.Text = ("Last {0} days   |   {1} messages   |   in {2}   out {3}   cache read {4}   cache write {5}   |   est. `${6:N2}" -f `
            $u.Days, $u.Messages, (Format-Tokens $u.Input), (Format-Tokens $u.Output),
            (Format-Tokens $u.CacheRead), (Format-Tokens $u.CacheWrite), $u.Cost)

        $script:lvModels.BeginUpdate(); $script:lvModels.Items.Clear()
        foreach ($m in $u.ByModel) {
            $it = New-Object System.Windows.Forms.ListViewItem($m.Model)
            [void]$it.SubItems.Add([string]$m.Messages)
            [void]$it.SubItems.Add((Format-Tokens $m.Input))
            [void]$it.SubItems.Add((Format-Tokens $m.Output))
            [void]$it.SubItems.Add(('{0:N2}' -f $m.Cost))
            [void]$script:lvModels.Items.Add($it)
        }
        $script:lvModels.EndUpdate()

        $script:lvProjects.BeginUpdate(); $script:lvProjects.Items.Clear()
        foreach ($p in $u.ByProject) {
            $it = New-Object System.Windows.Forms.ListViewItem($p.Project)
            [void]$it.SubItems.Add([string]$p.Messages)
            [void]$it.SubItems.Add((Format-Tokens $p.Input))
            [void]$it.SubItems.Add((Format-Tokens $p.Output))
            [void]$it.SubItems.Add(('{0:N2}' -f $p.Cost))
            [void]$script:lvProjects.Items.Add($it)
        }
        $script:lvProjects.EndUpdate()

        $script:usageStatus.Text = ('Scanned {0} at {1}' -f $u.Root, $u.ScannedAt.ToString('HH:mm:ss'))
    } catch {
        $script:usageStatus.Text = 'ERROR: ' + $_.Exception.Message
    } finally {
        $script:Busy = $false
        $script:btnRefreshUsage.Enabled = $true
    }
}

# ---------------- form ----------------
$script:form = New-Object System.Windows.Forms.Form
$script:form.Text = 'Claude Switchboard'
$script:form.Size = New-Object System.Drawing.Size(880, 640)
$script:form.StartPosition = 'CenterScreen'
$script:form.MinimumSize = New-Object System.Drawing.Size(780, 560)
$script:form.BackColor = [System.Drawing.Color]::FromArgb(250, 249, 246)
$script:form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$tabs.Padding = New-Object System.Drawing.Point(14, 6)
$script:form.Controls.Add($tabs)

# --- Tab 1: switch ---
$tabSwitch = New-Object System.Windows.Forms.TabPage
$tabSwitch.Text = 'Switch'
$tabSwitch.BackColor = [System.Drawing.Color]::FromArgb(250, 249, 246)
$tabs.TabPages.Add($tabSwitch)

$script:statusLabel = New-Object System.Windows.Forms.Label
$script:statusLabel.Location = New-Object System.Drawing.Point(16, 12)
$script:statusLabel.Size = New-Object System.Drawing.Size(820, 24)
$script:statusLabel.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
$tabSwitch.Controls.Add($script:statusLabel)

$script:profileList = New-Object System.Windows.Forms.ListView
$script:profileList.Location = New-Object System.Drawing.Point(16, 44)
$script:profileList.Size = New-Object System.Drawing.Size(560, 210)
$script:profileList.View = 'Details'
$script:profileList.FullRowSelect = $true
$script:profileList.MultiSelect = $false
$script:profileList.HideSelection = $false
$script:profileList.Columns.Add('Profile', 300) | Out-Null
$script:profileList.Columns.Add('Kind', 90) | Out-Null
$script:profileList.Columns.Add('Models', 150) | Out-Null
$script:profileList.Add_DoubleClick({ Invoke-SwitchTo (Get-SelectedProfile) })
$tabSwitch.Controls.Add($script:profileList)

$script:btnSwitch = New-Object System.Windows.Forms.Button
$script:btnSwitch.Text = 'Switch to selected'
$script:btnSwitch.Location = New-Object System.Drawing.Point(592, 44)
$script:btnSwitch.Size = New-Object System.Drawing.Size(244, 34)
$script:btnSwitch.Add_Click({ Invoke-SwitchTo (Get-SelectedProfile) })
$tabSwitch.Controls.Add($script:btnSwitch)

$script:btnAdd = New-Object System.Windows.Forms.Button
$script:btnAdd.Text = 'Add gateway...'
$script:btnAdd.Location = New-Object System.Drawing.Point(592, 86)
$script:btnAdd.Size = New-Object System.Drawing.Size(244, 30)
$script:btnAdd.Add_Click({ Show-ProfileDialog $null })
$tabSwitch.Controls.Add($script:btnAdd)

$script:btnEdit = New-Object System.Windows.Forms.Button
$script:btnEdit.Text = 'Edit...'
$script:btnEdit.Location = New-Object System.Drawing.Point(592, 122)
$script:btnEdit.Size = New-Object System.Drawing.Size(244, 30)
$script:btnEdit.Add_Click({ $p = Get-SelectedProfile; if ($p -and $p.kind -ne 'official') { Show-ProfileDialog $p } })
$tabSwitch.Controls.Add($script:btnEdit)

$script:btnRemove = New-Object System.Windows.Forms.Button
$script:btnRemove.Text = 'Remove'
$script:btnRemove.Location = New-Object System.Drawing.Point(592, 158)
$script:btnRemove.Size = New-Object System.Drawing.Size(244, 30)
$script:btnRemove.Add_Click({
    $p = Get-SelectedProfile
    if (-not $p -or $p.kind -eq 'official') { return }
    if ([System.Windows.Forms.MessageBox]::Show("Remove profile '$($p.name)'?", 'Claude Switchboard', 'YesNo') -eq 'Yes') {
        Remove-Profile $p.id
        Write-Log ('Removed profile: ' + $p.name)
        Refresh-ProfileList
    }
})
$tabSwitch.Controls.Add($script:btnRemove)

$script:btnOpen = New-Object System.Windows.Forms.Button
$script:btnOpen.Text = 'Open Claude'
$script:btnOpen.Location = New-Object System.Drawing.Point(592, 194)
$script:btnOpen.Size = New-Object System.Drawing.Size(244, 30)
$script:btnOpen.Add_Click({ Start-ClaudeDesktop; Write-Log 'Claude launched.' })
$tabSwitch.Controls.Add($script:btnOpen)

$script:chkSync = New-Object System.Windows.Forms.CheckBox
$script:chkSync.Text = 'Sync sessions and projects before switching (both directions)'
$script:chkSync.Checked = $true
$script:chkSync.Location = New-Object System.Drawing.Point(18, 264)
$script:chkSync.Size = New-Object System.Drawing.Size(560, 24)
$tabSwitch.Controls.Add($script:chkSync)

$script:chkCode = New-Object System.Windows.Forms.CheckBox
$script:chkCode.Text = 'Show Code sidebar (projects grouped)'
$script:chkCode.Checked = $true
$script:chkCode.Location = New-Object System.Drawing.Point(18, 290)
$script:chkCode.Size = New-Object System.Drawing.Size(560, 24)
$tabSwitch.Controls.Add($script:chkCode)

$script:logBox = New-Object System.Windows.Forms.TextBox
$script:logBox.Multiline = $true
$script:logBox.ReadOnly = $true
$script:logBox.ScrollBars = 'Vertical'
$script:logBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$script:logBox.Location = New-Object System.Drawing.Point(18, 322)
$script:logBox.Size = New-Object System.Drawing.Size(818, 210)
$script:logBox.Anchor = 'Top,Bottom,Left,Right'
$script:logBox.BackColor = [System.Drawing.Color]::White
$tabSwitch.Controls.Add($script:logBox)

# --- Tab 2: usage ---
$tabUsage = New-Object System.Windows.Forms.TabPage
$tabUsage.Text = 'Usage'
$tabUsage.BackColor = [System.Drawing.Color]::FromArgb(250, 249, 246)
$tabs.TabPages.Add($tabUsage)

$lblDays = New-Object System.Windows.Forms.Label
$lblDays.Text = 'Range'
$lblDays.Location = New-Object System.Drawing.Point(16, 16)
$lblDays.Size = New-Object System.Drawing.Size(48, 22)
$tabUsage.Controls.Add($lblDays)

$script:cboDays = New-Object System.Windows.Forms.ComboBox
$script:cboDays.DropDownStyle = 'DropDownList'
$script:cboDays.Location = New-Object System.Drawing.Point(66, 13)
$script:cboDays.Size = New-Object System.Drawing.Size(90, 25)
[void]$script:cboDays.Items.AddRange(@('7', '30'))
$script:cboDays.SelectedIndex = 0
$tabUsage.Controls.Add($script:cboDays)

$script:btnRefreshUsage = New-Object System.Windows.Forms.Button
$script:btnRefreshUsage.Text = 'Refresh'
$script:btnRefreshUsage.Location = New-Object System.Drawing.Point(166, 12)
$script:btnRefreshUsage.Size = New-Object System.Drawing.Size(90, 27)
$script:btnRefreshUsage.Add_Click({ Refresh-Usage })
$tabUsage.Controls.Add($script:btnRefreshUsage)

$script:usageStatus = New-Object System.Windows.Forms.Label
$script:usageStatus.Text = 'Not scanned yet.'
$script:usageStatus.Location = New-Object System.Drawing.Point(270, 16)
$script:usageStatus.Size = New-Object System.Drawing.Size(560, 22)
$tabUsage.Controls.Add($script:usageStatus)

$script:usageSummary = New-Object System.Windows.Forms.Label
$script:usageSummary.Text = 'Local transcripts only; no credentials are read.'
$script:usageSummary.Location = New-Object System.Drawing.Point(16, 48)
$script:usageSummary.Size = New-Object System.Drawing.Size(820, 44)
$script:usageSummary.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
$tabUsage.Controls.Add($script:usageSummary)

$lblModels = New-Object System.Windows.Forms.Label
$lblModels.Text = 'By model'
$lblModels.Location = New-Object System.Drawing.Point(16, 96)
$lblModels.Size = New-Object System.Drawing.Size(200, 20)
$tabUsage.Controls.Add($lblModels)

$script:lvModels = New-Object System.Windows.Forms.ListView
$script:lvModels.Location = New-Object System.Drawing.Point(16, 118)
$script:lvModels.Size = New-Object System.Drawing.Size(820, 190)
$script:lvModels.View = 'Details'
$script:lvModels.FullRowSelect = $true
$script:lvModels.Columns.Add('Model', 300) | Out-Null
$script:lvModels.Columns.Add('Messages', 90) | Out-Null
$script:lvModels.Columns.Add('Input', 110) | Out-Null
$script:lvModels.Columns.Add('Output', 110) | Out-Null
$script:lvModels.Columns.Add('Est. cost (USD)', 140) | Out-Null
$tabUsage.Controls.Add($script:lvModels)

$lblProjects = New-Object System.Windows.Forms.Label
$lblProjects.Text = 'By project'
$lblProjects.Location = New-Object System.Drawing.Point(16, 318)
$lblProjects.Size = New-Object System.Drawing.Size(200, 20)
$tabUsage.Controls.Add($lblProjects)

$script:lvProjects = New-Object System.Windows.Forms.ListView
$script:lvProjects.Location = New-Object System.Drawing.Point(16, 340)
$script:lvProjects.Size = New-Object System.Drawing.Size(820, 190)
$script:lvProjects.View = 'Details'
$script:lvProjects.FullRowSelect = $true
$script:lvProjects.Columns.Add('Project', 380) | Out-Null
$script:lvProjects.Columns.Add('Messages', 100) | Out-Null
$script:lvProjects.Columns.Add('Input', 120) | Out-Null
$script:lvProjects.Columns.Add('Output', 120) | Out-Null
$script:lvProjects.Columns.Add('Est. cost (USD)', 140) | Out-Null
$tabUsage.Controls.Add($script:lvProjects)

# --- Tab 3: about ---
$tabAbout = New-Object System.Windows.Forms.TabPage
$tabAbout.Text = 'About'
$tabAbout.BackColor = [System.Drawing.Color]::FromArgb(250, 249, 246)
$tabs.TabPages.Add($tabAbout)

$about = New-Object System.Windows.Forms.TextBox
$about.Multiline = $true
$about.ReadOnly = $true
$about.ScrollBars = 'Vertical'
$about.Dock = 'Fill'
$about.BorderStyle = 'None'
$about.BackColor = [System.Drawing.Color]::FromArgb(250, 249, 246)
$about.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$paths = Get-ClaudeDesktopPaths
$about.Text = @"
Claude Switchboard

Switch Claude Desktop between the official claude.ai account (deploymentMode 1p)
and third-party Anthropic-compatible gateways (deploymentMode 3p), copy session
cards and projects both ways, and read local token usage from Claude Code
transcripts.

How it works
- Official mode: deploymentMode = "1p" (the OAuth login in %APPDATA%\Claude stays intact).
- Gateway mode: writes a profile into Claude-3p\configLibrary and sets it as appliedId.
- Session cards: %APPDATA%\Claude\claude-code-sessions and
  %LOCALAPPDATA%\Claude-3p\claude-code-sessions; newer files win.
- Config files are written as UTF-8 without BOM. The app ignores a BOM.
- Order matters: stop Claude -> sync -> write config -> start Claude.

Paths
  Config (local):   $($paths.LocalConfig)
  Config (roaming): $($paths.Roaming3pConfig)
  Profiles:         $(Get-ProfilesFilePath)
  Transcripts:      $(Get-TranscriptRoot)

Privacy
API keys are encrypted with Windows DPAPI (CurrentUser) in profiles.json.
Usage is computed locally; nothing is uploaded.

License: MIT
"@
$tabAbout.Controls.Add($about)

# ---------------- startup ----------------
Refresh-ProfileList
Write-Log 'Ready.'
if (Get-Command pwsh -ErrorAction SilentlyContinue) { }
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Log 'Warning: PowerShell 7 (pwsh) is recommended; 5.1 needs a BOM for this script.'
}
[void]$script:form.ShowDialog()
