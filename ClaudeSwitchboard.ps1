# Claude Switchboard 0.2 — WPF UI
# Switch Claude Desktop between the official account and Anthropic-compatible
# gateways, with two-way session sync and a local usage dashboard.
#
# Run with PowerShell 7:  pwsh -File ClaudeSwitchboard.ps1

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Security.Cryptography.ProtectedData

$script:Root = $PSScriptRoot
. (Join-Path $script:Root 'lib\ClaudeDesktop.ps1')
. (Join-Path $script:Root 'lib\Profiles.ps1')
. (Join-Path $script:Root 'lib\Usage.ps1')

$script:ProfilesDoc = Get-ProfilesDoc
$script:Busy = $false

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claude Switchboard" Width="1020" Height="700"
        MinWidth="920" MinHeight="640"
        WindowStartupLocation="CenterScreen"
        Background="#F7F6F2"
        FontFamily="Segoe UI Variable Text, Microsoft YaHei UI, Segoe UI"
        FontSize="13" UseLayoutRounding="True">
  <Window.Resources>
    <SolidColorBrush x:Key="Ink" Color="#23211D"/>
    <SolidColorBrush x:Key="Muted" Color="#6F6A60"/>
    <SolidColorBrush x:Key="Faint" Color="#8A857A"/>
    <SolidColorBrush x:Key="Line" Color="#E7E3DA"/>
    <SolidColorBrush x:Key="Accent" Color="#C15F3C"/>
    <SolidColorBrush x:Key="AccentDark" Color="#A94F30"/>
    <SolidColorBrush x:Key="Card" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="Sidebar" Color="#201F1C"/>
    <SolidColorBrush x:Key="SidebarMuted" Color="#A8A296"/>

    <Style x:Key="PrimaryButton" TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="Background" Value="{StaticResource Accent}"/>
      <Setter Property="Padding" Value="18,9"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="9"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{StaticResource AccentDark}"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.45"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="SecondaryButton" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource Ink}"/>
      <Setter Property="Background" Value="{StaticResource Card}"/>
      <Setter Property="Padding" Value="16,8"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}"
                    BorderBrush="{StaticResource Line}" BorderThickness="1"
                    CornerRadius="9" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#F2EFE8"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.45"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="NavButton" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#B9B3A6"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="0,0,0,4"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="Bd" Background="Transparent" CornerRadius="9" Padding="14,10">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#2A2824"/>
                <Setter Property="Foreground" Value="#F5F2EC"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#34312B"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
                <Setter Property="FontWeight" Value="SemiBold"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="TextBox">
      <Setter Property="Padding" Value="10,7"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Background" Value="White"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>

    <Style TargetType="ComboBox">
      <Setter Property="Padding" Value="8,5"/>
      <Setter Property="Background" Value="White"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
    </Style>

    <Style x:Key="CardBorder" TargetType="Border">
      <Setter Property="Background" Value="{StaticResource Card}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="12"/>
      <Setter Property="Padding" Value="18,14"/>
    </Style>

    <Style x:Key="ProfileItem" TargetType="ListBoxItem">
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="Bd" Background="{StaticResource Card}"
                    BorderBrush="{StaticResource Line}" BorderThickness="1"
                    CornerRadius="11" Padding="16,12" Margin="0,0,0,8" Cursor="Hand">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="BorderBrush" Value="#D8D2C6"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Accent}"/>
                <Setter TargetName="Bd" Property="Background" Value="#FFF8F3"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="DataGrid">
      <Setter Property="Background" Value="White"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="GridLinesVisibility" Value="None"/>
      <Setter Property="HeadersVisibility" Value="Column"/>
      <Setter Property="RowHeight" Value="30"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="CanUserAddRows" Value="False"/>
      <Setter Property="IsReadOnly" Value="True"/>
      <Setter Property="AlternatingRowBackground" Value="#FBFAF7"/>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="220"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>

    <!-- sidebar -->
    <Border Grid.Column="0" Background="{StaticResource Sidebar}">
      <DockPanel Margin="16,20,16,18">
        <StackPanel DockPanel.Dock="Top">
          <TextBlock Text="Claude" Foreground="#F5F2EC" FontSize="19" FontWeight="SemiBold"/>
          <TextBlock Text="Switchboard" Foreground="{StaticResource SidebarMuted}" FontSize="13" Margin="0,1,0,0"/>
          <StackPanel Margin="0,28,0,0">
            <RadioButton x:Name="NavSwitch" Style="{StaticResource NavButton}" Content="Switch" IsChecked="True"/>
            <RadioButton x:Name="NavUsage" Style="{StaticResource NavButton}" Content="Usage"/>
            <RadioButton x:Name="NavAbout" Style="{StaticResource NavButton}" Content="About"/>
          </StackPanel>
        </StackPanel>
        <TextBlock DockPanel.Dock="Bottom" Text="v0.2.0 · local only" Foreground="#7C766B" FontSize="11"/>
      </DockPanel>
    </Border>

    <!-- content -->
    <Grid Grid.Column="1" Margin="30,24,30,24">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>

      <Grid Grid.Row="0" Margin="0,0,0,18">
        <StackPanel>
          <TextBlock x:Name="PageTitle" Text="Switch profile" FontSize="25" FontWeight="SemiBold"
                     Foreground="{StaticResource Ink}"/>
          <TextBlock x:Name="PageSubtitle" Margin="0,4,0,0" Foreground="{StaticResource Muted}"
                     Text="Choose the account or gateway Claude Desktop should use."/>
        </StackPanel>
        <Border HorizontalAlignment="Right" VerticalAlignment="Top" CornerRadius="14" Padding="14,7"
                Background="#FFF1E8">
          <StackPanel Orientation="Horizontal">
            <Ellipse x:Name="ModeDot" Width="8" Height="8" Fill="{StaticResource Accent}"
                     VerticalAlignment="Center" Margin="0,0,8,0"/>
            <TextBlock x:Name="ModeText" Text="BirdAPI gateway" Foreground="#8A3B1E" FontWeight="SemiBold"/>
          </StackPanel>
        </Border>
      </Grid>

      <Grid Grid.Row="1">
        <!-- ===== Switch page ===== -->
        <Grid x:Name="PageSwitch">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="170"/>
          </Grid.RowDefinitions>

          <Border Grid.Row="0" Style="{StaticResource CardBorder}">
            <Grid>
              <StackPanel>
                <TextBlock Text="CURRENT MODE" FontSize="10" FontWeight="SemiBold"
                           Foreground="{StaticResource Faint}"/>
                <TextBlock x:Name="CurrentMode" Text="BirdAPI gateway" FontSize="19" FontWeight="SemiBold"
                           Foreground="{StaticResource Ink}" Margin="0,5,0,0"/>
                <TextBlock x:Name="SessionInfo" Text="sessions: official 0 · gateway 0"
                           Foreground="{StaticResource Muted}" Margin="0,4,0,0"/>
              </StackPanel>
              <Button x:Name="BtnOpen" Content="Open Claude" Style="{StaticResource SecondaryButton}"
                      HorizontalAlignment="Right" VerticalAlignment="Center"/>
            </Grid>
          </Border>

          <ListBox x:Name="ProfileList" Grid.Row="1" Margin="0,14,0,0" Background="Transparent"
                   BorderThickness="0" ItemContainerStyle="{StaticResource ProfileItem}"
                   ScrollViewer.HorizontalScrollBarVisibility="Disabled">
            <ListBox.ItemTemplate>
              <DataTemplate>
                <Grid>
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>
                  <StackPanel>
                    <TextBlock Text="{Binding Name}" FontSize="14" FontWeight="SemiBold"
                               Foreground="{StaticResource Ink}"/>
                    <TextBlock Text="{Binding Subtitle}" FontSize="12" Foreground="{StaticResource Muted}"
                               Margin="0,3,0,0"/>
                  </StackPanel>
                  <Border x:Name="Badge" Grid.Column="1" Background="#E8F0FE" CornerRadius="9"
                          Padding="9,3" VerticalAlignment="Center" Margin="0,0,12,0">
                    <TextBlock x:Name="BadgeText" Text="{Binding KindLabel}" FontSize="10"
                               FontWeight="SemiBold" Foreground="#1E4FA8"/>
                  </Border>
                  <StackPanel Grid.Column="2" VerticalAlignment="Center" HorizontalAlignment="Right">
                    <TextBlock Text="{Binding ActiveLabel}" FontSize="11" FontWeight="SemiBold"
                               Foreground="{StaticResource Accent}" HorizontalAlignment="Right"/>
                    <TextBlock Text="{Binding ModelsLabel}" FontSize="11"
                               Foreground="{StaticResource Faint}" HorizontalAlignment="Right" Margin="0,2,0,0"/>
                  </StackPanel>
                </Grid>
                <DataTemplate.Triggers>
                  <DataTrigger Binding="{Binding Kind}" Value="official">
                    <Setter TargetName="Badge" Property="Background" Value="#FDF0E4"/>
                    <Setter TargetName="BadgeText" Property="Foreground" Value="#8A3B1E"/>
                  </DataTrigger>
                </DataTemplate.Triggers>
              </DataTemplate>
            </ListBox.ItemTemplate>
          </ListBox>

          <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,12,0,0">
            <Button x:Name="BtnSwitch" Content="Switch to selected" Style="{StaticResource PrimaryButton}"
                    MinWidth="180"/>
            <Button x:Name="BtnAdd" Content="Add gateway…" Style="{StaticResource SecondaryButton}"
                    Margin="10,0,0,0"/>
            <Button x:Name="BtnEdit" Content="Edit…" Style="{StaticResource SecondaryButton}"
                    Margin="8,0,0,0"/>
            <Button x:Name="BtnRemove" Content="Remove" Style="{StaticResource SecondaryButton}"
                    Margin="8,0,0,0"/>
          </StackPanel>

          <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,14,0,0">
            <CheckBox x:Name="ChkSync" Content="Sync sessions and projects" IsChecked="True"
                      Foreground="{StaticResource Ink}" Margin="0,0,22,0"/>
            <CheckBox x:Name="ChkCode" Content="Show Code sidebar" IsChecked="True"
                      Foreground="{StaticResource Ink}"/>
          </StackPanel>

          <Border Grid.Row="4" Margin="0,14,0,0" Background="{StaticResource Sidebar}" CornerRadius="10"
                  Padding="14,10">
            <TextBox x:Name="LogBox" Background="Transparent" Foreground="#D8D3C8"
                     BorderThickness="0" IsReadOnly="True" TextWrapping="Wrap"
                     VerticalScrollBarVisibility="Auto"
                     FontFamily="Cascadia Mono, Consolas, Microsoft YaHei UI" FontSize="11"/>
          </Border>
        </Grid>

        <!-- ===== Usage page ===== -->
        <Grid x:Name="PageUsage" Visibility="Collapsed">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>

          <StackPanel Grid.Row="0" Orientation="Horizontal">
            <TextBlock Text="Range" VerticalAlignment="Center" Foreground="{StaticResource Muted}"/>
            <ComboBox x:Name="CboDays" Width="90" Margin="10,0,0,0" SelectedIndex="0">
              <ComboBoxItem Content="7"/>
              <ComboBoxItem Content="30"/>
            </ComboBox>
            <Button x:Name="BtnRefresh" Content="Refresh" Style="{StaticResource SecondaryButton}"
                    Margin="10,0,0,0"/>
            <TextBlock x:Name="UsageStatus" Text="Not scanned yet." VerticalAlignment="Center"
                       Margin="14,0,0,0" Foreground="{StaticResource Faint}" FontSize="12"/>
          </StackPanel>

          <UniformGrid Grid.Row="1" Columns="4" Margin="0,16,0,0">
            <Border Style="{StaticResource CardBorder}" Margin="0,0,10,0">
              <StackPanel>
                <TextBlock Text="MESSAGES" FontSize="10" FontWeight="SemiBold"
                           Foreground="{StaticResource Faint}"/>
                <TextBlock x:Name="SumMessages" Text="—" FontSize="22" FontWeight="SemiBold"
                           Foreground="{StaticResource Ink}" Margin="0,4,0,0"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBorder}" Margin="0,0,10,0">
              <StackPanel>
                <TextBlock Text="EST. COST" FontSize="10" FontWeight="SemiBold"
                           Foreground="{StaticResource Faint}"/>
                <TextBlock x:Name="SumCost" Text="—" FontSize="22" FontWeight="SemiBold"
                           Foreground="{StaticResource Ink}" Margin="0,4,0,0"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBorder}" Margin="0,0,10,0">
              <StackPanel>
                <TextBlock Text="INPUT" FontSize="10" FontWeight="SemiBold"
                           Foreground="{StaticResource Faint}"/>
                <TextBlock x:Name="SumInput" Text="—" FontSize="22" FontWeight="SemiBold"
                           Foreground="{StaticResource Ink}" Margin="0,4,0,0"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource CardBorder}">
              <StackPanel>
                <TextBlock Text="OUTPUT" FontSize="10" FontWeight="SemiBold"
                           Foreground="{StaticResource Faint}"/>
                <TextBlock x:Name="SumOutput" Text="—" FontSize="22" FontWeight="SemiBold"
                           Foreground="{StaticResource Ink}" Margin="0,4,0,0"/>
              </StackPanel>
            </Border>
          </UniformGrid>

          <Grid Grid.Row="2" Margin="0,16,0,0">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <TextBlock Grid.Row="0" Text="By model" FontWeight="SemiBold" Foreground="{StaticResource Ink}"
                       Margin="2,0,0,6"/>
            <DataGrid x:Name="GridModels" Grid.Row="1" AutoGenerateColumns="False">
              <DataGrid.Columns>
                <DataGridTextColumn Header="Model" Binding="{Binding Model}" Width="*"/>
                <DataGridTextColumn Header="Messages" Binding="{Binding Messages}" Width="100"/>
                <DataGridTextColumn Header="Input" Binding="{Binding Input}" Width="110"/>
                <DataGridTextColumn Header="Output" Binding="{Binding Output}" Width="110"/>
                <DataGridTextColumn Header="Est. cost" Binding="{Binding Cost}" Width="110"/>
              </DataGrid.Columns>
            </DataGrid>
            <TextBlock Grid.Row="2" Text="By project" FontWeight="SemiBold" Foreground="{StaticResource Ink}"
                       Margin="2,14,0,6"/>
            <DataGrid x:Name="GridProjects" Grid.Row="3" AutoGenerateColumns="False">
              <DataGrid.Columns>
                <DataGridTextColumn Header="Project" Binding="{Binding Project}" Width="*"/>
                <DataGridTextColumn Header="Messages" Binding="{Binding Messages}" Width="100"/>
                <DataGridTextColumn Header="Input" Binding="{Binding Input}" Width="110"/>
                <DataGridTextColumn Header="Output" Binding="{Binding Output}" Width="110"/>
                <DataGridTextColumn Header="Est. cost" Binding="{Binding Cost}" Width="110"/>
              </DataGrid.Columns>
            </DataGrid>
          </Grid>
        </Grid>

        <!-- ===== About page ===== -->
        <ScrollViewer x:Name="PageAbout" Visibility="Collapsed" VerticalScrollBarVisibility="Auto">
          <Border Style="{StaticResource CardBorder}" Padding="26,22">
            <StackPanel>
              <TextBlock Text="Claude Switchboard" FontSize="20" FontWeight="SemiBold"
                         Foreground="{StaticResource Ink}"/>
              <TextBlock x:Name="AboutVersion" Text="v0.2.0" Foreground="{StaticResource Faint}"
                         Margin="0,3,0,18"/>
              <TextBlock x:Name="AboutText" TextWrapping="Wrap" Foreground="{StaticResource Muted}"
                         LineHeight="21"/>
            </StackPanel>
          </Border>
        </ScrollViewer>
      </Grid>
    </Grid>
  </Grid>
</Window>
'@

$script:Window = [Windows.Markup.XamlReader]::Parse($xaml)

# ---- control bindings ----
foreach ($name in @(
    'NavSwitch','NavUsage','NavAbout','PageSwitch','PageUsage','PageAbout',
    'PageTitle','PageSubtitle','ModeDot','ModeText','CurrentMode','SessionInfo',
    'ProfileList','BtnSwitch','BtnAdd','BtnEdit','BtnRemove','BtnOpen',
    'ChkSync','ChkCode','LogBox','CboDays','BtnRefresh','UsageStatus',
    'SumMessages','SumCost','SumInput','SumOutput','GridModels','GridProjects',
    'AboutText','AboutVersion')) {
    Set-Variable -Name "ui$name" -Value $script:Window.FindName($name) -Scope Script
}

# ---------------- helpers ----------------
function Write-Log([string]$msg) {
    $line = "[{0}] {1}" -f ([DateTime]::Now.ToString('HH:mm:ss')), $msg
    $script:uiLogBox.AppendText($line + "`r`n")
    $script:uiLogBox.ScrollToEnd()
}

function Set-Page([string]$page) {
    $script:uiPageSwitch.Visibility = if ($page -eq 'switch') { 'Visible' } else { 'Collapsed' }
    $script:uiPageUsage.Visibility = if ($page -eq 'usage') { 'Visible' } else { 'Collapsed' }
    $script:uiPageAbout.Visibility = if ($page -eq 'about') { 'Visible' } else { 'Collapsed' }
    $script:uiNavSwitch.IsChecked = ($page -eq 'switch')
    $script:uiNavUsage.IsChecked = ($page -eq 'usage')
    $script:uiNavAbout.IsChecked = ($page -eq 'about')
    switch ($page) {
        'switch' { $script:uiPageTitle.Text = 'Switch profile'; $script:uiPageSubtitle.Text = 'Choose the account or gateway Claude Desktop should use.' }
        'usage'  { $script:uiPageTitle.Text = 'Usage'; $script:uiPageSubtitle.Text = 'Local token accounting from Claude Code transcripts.' }
        'about'  { $script:uiPageTitle.Text = 'About'; $script:uiPageSubtitle.Text = 'How switching works and where data lives.' }
    }
}

function Update-ModeStatus {
    $mode = Get-CurrentDeploymentMode
    $counts = Get-SessionCounts
    $label = switch ($mode) {
        'official' { 'Official Claude Max' }
        'gateway'  { 'BirdAPI gateway' }
        default    { 'Unknown' }
    }
    $script:uiCurrentMode.Text = $label
    $script:uiModeText.Text = $label
    $script:uiSessionInfo.Text = ("sessions: official {0} · gateway {1}" -f $counts.Official, $counts.Gateway)
    if ($mode -eq 'official') {
        $script:uiModeDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#C15F3C')
        $script:uiModeText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#8A3B1E')
    } else {
        $script:uiModeDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#2F6FEB')
        $script:uiModeText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#1E4FA8')
    }
}

function Get-SelectedProfile {
    $item = $script:uiProfileList.SelectedItem
    if (-not $item) { return $null }
    return Get-ProfileById $script:ProfilesDoc $item.Id
}

function Set-Busy([bool]$value) {
    $script:Busy = $value
    foreach ($b in @($script:uiBtnSwitch, $script:uiBtnAdd, $script:uiBtnEdit, $script:uiBtnRemove, $script:uiBtnOpen)) {
        $b.IsEnabled = -not $value
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Refresh-ProfileList {
    $script:ProfilesDoc = Get-ProfilesDoc
    $items = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    foreach ($p in @($script:ProfilesDoc.profiles)) {
        $isActive = ($p.id -eq $script:ProfilesDoc.activeProfileId)
        $items.Add([pscustomobject]@{
            Id          = $p.id
            Name        = $p.name
            Kind        = $p.kind
            KindLabel   = if ($p.kind -eq 'official') { 'OFFICIAL' } else { 'GATEWAY' }
            Subtitle    = if ($p.kind -eq 'official') { 'claude.ai sign-in · OAuth token cache' } else { [string]$p.baseUrl }
            ModelsLabel = if ($p.kind -eq 'official') { '' } else { (@($p.models).Count.ToString() + ' models') }
            ActiveLabel = if ($isActive) { '● Active' } else { '' }
        }) | Out-Null
    }
    $script:uiProfileList.ItemsSource = $items
    foreach ($it in $items) {
        if ($it.Id -eq $script:ProfilesDoc.activeProfileId) { $script:uiProfileList.SelectedItem = $it; break }
    }
    if (-not $script:uiProfileList.SelectedItem -and $items.Count -gt 0) {
        $script:uiProfileList.SelectedIndex = 0
    }
    Update-ModeStatus
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
            -SyncSessions ([bool]$script:uiChkSync.IsChecked) `
            -CodeSidebar ([bool]$script:uiChkCode.IsChecked) `
            -Log { param($m) Write-Log $m }
        Set-ActiveProfile $profile.id
        $script:ProfilesDoc = Get-ProfilesDoc
        Write-Log 'Done.'
    } catch {
        Write-Log ('ERROR: ' + $_.Exception.Message)
    } finally {
        Set-Busy $false
        Refresh-ProfileList
    }
}

function New-LabeledField([string]$label, [string]$value, [bool]$multiline = $false) {
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Margin = New-Object System.Windows.Thickness(0, 0, 0, 12)
    $lbl = New-Object System.Windows.Controls.TextBlock
    $lbl.Text = $label
    $lbl.FontSize = 11
    $lbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#6F6A60')
    $lbl.Margin = New-Object System.Windows.Thickness(0, 0, 0, 5)
    $tb = New-Object System.Windows.Controls.TextBox
    $tb.Text = $value
    $tb.Padding = New-Object System.Windows.Thickness(9, 7, 9, 7)
    if ($multiline) {
        $tb.AcceptsReturn = $true
        $tb.TextWrapping = 'NoWrap'
        $tb.VerticalScrollBarVisibility = 'Auto'
        $tb.Height = 190
        $tb.FontFamily = New-Object System.Windows.Media.FontFamily('Cascadia Mono, Consolas')
        $tb.FontSize = 11
    }
    $sp.Children.Add($lbl) | Out-Null
    $sp.Children.Add($tb) | Out-Null
    return [pscustomobject]@{ Panel = $sp; Box = $tb }
}

function Show-ProfileDialog($existing) {
    $dlg = New-Object System.Windows.Window
    $dlg.Title = if ($existing) { 'Edit gateway profile' } else { 'Add gateway profile' }
    $dlg.Width = 620
    $dlg.Height = 720
    $dlg.WindowStartupLocation = 'CenterOwner'
    $dlg.Owner = $script:Window
    $dlg.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#F7F6F2')

    $root = New-Object System.Windows.Controls.Grid
    $root.Margin = New-Object System.Windows.Thickness(24, 20, 24, 18)
    $r0 = New-Object System.Windows.Controls.RowDefinition
    $r0.Height = [System.Windows.GridLength]::Auto
    $r1 = New-Object System.Windows.Controls.RowDefinition
    $r1.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $r2 = New-Object System.Windows.Controls.RowDefinition
    $r2.Height = [System.Windows.GridLength]::Auto
    $root.RowDefinitions.Add($r0) | Out-Null
    $root.RowDefinitions.Add($r1) | Out-Null
    $root.RowDefinitions.Add($r2) | Out-Null

    $scroll = New-Object System.Windows.Controls.ScrollViewer
    $scroll.VerticalScrollBarVisibility = 'Auto'
    $panel = New-Object System.Windows.Controls.StackPanel
    $scroll.Content = $panel
    [System.Windows.Controls.Grid]::SetRow($scroll, 1)
    $root.Children.Add($scroll) | Out-Null

    $fName = New-LabeledField 'Name' $(if ($existing) { $existing.name } else { '' })
    $fUrl = New-LabeledField 'Base URL' $(if ($existing) { $existing.baseUrl } else { 'https://' })
    $fKey = New-LabeledField 'API key' ''
    if ($existing) { $fKey.Box.ToolTip = 'Leave empty to keep the current key' }
    $fModels = New-LabeledField 'Models — one per line: id | label | opus/sonnet/haiku/fable' `
        $(if ($existing) { ConvertTo-ModelText $existing.models } else { ConvertTo-ModelText (Get-DefaultClaudeModels) }) $true
    $fNotes = New-LabeledField 'Notes (optional)' $(if ($existing) { $existing.notes } else { '' })

    foreach ($f in @($fName, $fUrl, $fKey, $fModels, $fNotes)) { $panel.Children.Add($f.Panel) | Out-Null }

    $buttons = New-Object System.Windows.Controls.StackPanel
    $buttons.Orientation = 'Horizontal'
    $buttons.HorizontalAlignment = 'Right'
    $buttons.Margin = New-Object System.Windows.Thickness(0, 12, 0, 0)
    [System.Windows.Controls.Grid]::SetRow($buttons, 2)

    $ok = New-Object System.Windows.Controls.Button
    $ok.Content = 'Save'
    $ok.Padding = New-Object System.Windows.Thickness(22, 9, 22, 9)
    $ok.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#C15F3C')
    $ok.Foreground = [System.Windows.Media.Brushes]::White
    $ok.BorderThickness = New-Object System.Windows.Thickness(0)
    $ok.Cursor = 'Hand'
    $cancel = New-Object System.Windows.Controls.Button
    $cancel.Content = 'Cancel'
    $cancel.Padding = New-Object System.Windows.Thickness(20, 9, 20, 9)
    $cancel.Margin = New-Object System.Windows.Thickness(10, 0, 0, 0)
    $cancel.Cursor = 'Hand'
    $buttons.Children.Add($ok) | Out-Null
    $buttons.Children.Add($cancel) | Out-Null
    $root.Children.Add($buttons) | Out-Null
    $dlg.Content = $root

    $cancel.Add_Click({ $dlg.DialogResult = $false; $dlg.Close() })
    $ok.Add_Click({
        if (-not $fName.Box.Text.Trim() -or -not $fUrl.Box.Text.Trim()) {
            [System.Windows.MessageBox]::Show('Name and Base URL are required.')
            return
        }
        if (-not $existing -and -not $fKey.Box.Text.Trim()) {
            [System.Windows.MessageBox]::Show('An API key is required for a gateway profile.')
            return
        }
        $models = ConvertFrom-ModelText $fModels.Box.Text
        if ($existing) {
            Update-GatewayProfile -Profile $existing -Name $fName.Box.Text.Trim() `
                -BaseUrl $fUrl.Box.Text.Trim() -ApiKey $fKey.Box.Text -Models $models `
                -Notes $fNotes.Box.Text | Out-Null
            Write-Log ('Updated profile: ' + $fName.Box.Text.Trim())
        } else {
            Add-GatewayProfile -Name $fName.Box.Text.Trim() -BaseUrl $fUrl.Box.Text.Trim() `
                -ApiKey $fKey.Box.Text -Models $models -Notes $fNotes.Box.Text | Out-Null
            Write-Log ('Added profile: ' + $fName.Box.Text.Trim())
        }
        $dlg.DialogResult = $true
        $dlg.Close()
    })

    [void]$dlg.ShowDialog()
    Refresh-ProfileList
}

function Refresh-Usage {
    if ($script:Busy) { return }
    $script:Busy = $true
    $script:uiBtnRefresh.IsEnabled = $false
    $days = [int]$script:uiCboDays.SelectedItem.Content
    $script:uiUsageStatus.Text = 'Scanning transcripts…'
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $u = Get-ClaudeUsage -Days $days -Progress {
            param($done, $total, $file)
            $script:uiUsageStatus.Text = "Scanning $done/$total"
            [System.Windows.Forms.Application]::DoEvents()
        }
        if (-not $u.Available) {
            $script:uiUsageStatus.Text = "No transcripts at $($u.Root)"
            return
        }
        $script:uiSumMessages.Text = [string]$u.Messages
        $script:uiSumCost.Text = ('${0:N2}' -f $u.Cost)
        $script:uiSumInput.Text = (Format-Tokens $u.Input)
        $script:uiSumOutput.Text = (Format-Tokens $u.Output)
        $script:uiUsageStatus.Text = ('Scanned {0} · cache read {1} · cache write {2}' -f `
            $u.ScannedAt.ToString('HH:mm:ss'), (Format-Tokens $u.CacheRead), (Format-Tokens $u.CacheWrite))

        $mItems = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
        foreach ($m in $u.ByModel) {
            $mItems.Add([pscustomobject]@{
                Model = $m.Model; Messages = $m.Messages
                Input = (Format-Tokens $m.Input); Output = (Format-Tokens $m.Output)
                Cost = ('${0:N2}' -f $m.Cost)
            }) | Out-Null
        }
        $script:uiGridModels.ItemsSource = $mItems

        $pItems = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
        foreach ($p in $u.ByProject) {
            $pItems.Add([pscustomobject]@{
                Project = $p.Project; Messages = $p.Messages
                Input = (Format-Tokens $p.Input); Output = (Format-Tokens $p.Output)
                Cost = ('${0:N2}' -f $p.Cost)
            }) | Out-Null
        }
        $script:uiGridProjects.ItemsSource = $pItems
    } catch {
        $script:uiUsageStatus.Text = 'ERROR: ' + $_.Exception.Message
    } finally {
        $script:Busy = $false
        $script:uiBtnRefresh.IsEnabled = $true
    }
}

# ---------------- events ----------------
$script:uiNavSwitch.Add_Click({ Set-Page 'switch' })
$script:uiNavUsage.Add_Click({ Set-Page 'usage' })
$script:uiNavAbout.Add_Click({ Set-Page 'about' })
$script:uiBtnSwitch.Add_Click({ Invoke-SwitchTo (Get-SelectedProfile) })
$script:uiProfileList.Add_MouseDoubleClick({ Invoke-SwitchTo (Get-SelectedProfile) })
$script:uiBtnAdd.Add_Click({ Show-ProfileDialog $null })
$script:uiBtnEdit.Add_Click({ $p = Get-SelectedProfile; if ($p -and $p.kind -ne 'official') { Show-ProfileDialog $p } })
$script:uiBtnRemove.Add_Click({
    $p = Get-SelectedProfile
    if (-not $p -or $p.kind -eq 'official') { return }
    $r = [System.Windows.MessageBox]::Show("Remove profile '$($p.name)'?", 'Claude Switchboard', 'YesNo')
    if ($r -eq 'Yes') {
        Remove-Profile $p.id
        Write-Log ('Removed profile: ' + $p.name)
        Refresh-ProfileList
    }
})
$script:uiBtnOpen.Add_Click({ Start-ClaudeDesktop; Write-Log 'Claude launched.' })
$script:uiBtnRefresh.Add_Click({ Refresh-Usage })

# ---------------- about ----------------
$paths = Get-ClaudeDesktopPaths
$script:uiAboutText.Text = @"
A Windows GUI for switching Claude Desktop between the official claude.ai account
and third-party Anthropic-compatible gateways.

How it works
  Official mode  deploymentMode = "1p"; the OAuth login in %APPDATA%\Claude stays intact.
  Gateway mode   writes a profile into Claude-3p\configLibrary and sets appliedId.
  Sessions       cards in %APPDATA%\Claude\claude-code-sessions and
                 %LOCALAPPDATA%\Claude-3p\claude-code-sessions; newer files win.
  Config         written as UTF-8 without BOM; the app ignores a BOM.
  Order          stop Claude -> sync -> write config -> start Claude.

Paths
  Local config   $($paths.LocalConfig)
  Profiles       $(Get-ProfilesFilePath)
  Transcripts    $(Get-TranscriptRoot)

Privacy
  API keys are encrypted with Windows DPAPI (CurrentUser) in profiles.json.
  Usage is computed locally; nothing is uploaded.

License: MIT
"@

# ---------------- startup ----------------
Set-Page 'switch'
Refresh-ProfileList
Write-Log 'Ready.'
[void]$script:Window.ShowDialog()
