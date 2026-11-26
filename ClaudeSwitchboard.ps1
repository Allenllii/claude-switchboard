# Claude Switchboard 0.3 — WPF UI in the Claude Account Switcher idiom.
# Dark panel, menu-style profile rows, orange primary action, tray menu with
# one-click switching, two-way session sync, local usage dashboard.
#
# Run with PowerShell 7:  pwsh -File ClaudeSwitchboard.ps1

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security.Cryptography.ProtectedData

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeChrome {
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
    [DllImport("user32.dll")]
    public static extern bool DestroyIcon(IntPtr handle);
}
"@

$script:Root = $PSScriptRoot
. (Join-Path $script:Root 'lib\ClaudeDesktop.ps1')
. (Join-Path $script:Root 'lib\Profiles.ps1')
. (Join-Path $script:Root 'lib\Usage.ps1')

$script:ProfilesDoc = Get-ProfilesDoc
$script:Busy = $false
$script:Quitting = $false
$script:HideTipShown = $false

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claude Switchboard" Width="700" Height="540"
        MinWidth="640" MinHeight="520"
        WindowStyle="None" ResizeMode="CanResize"
        BorderBrush="#3A3A37" BorderThickness="1"
        WindowStartupLocation="CenterScreen"
        Background="#262624" Foreground="#F5F4EF"
        FontFamily="Segoe UI Variable Text, Microsoft YaHei UI, Segoe UI"
        FontSize="13" UseLayoutRounding="True">
  <WindowChrome.WindowChrome>
    <WindowChrome CaptionHeight="52" ResizeBorderThickness="6"
                  GlassFrameThickness="0" CornerRadius="0" UseAeroCaptionButtons="False"/>
  </WindowChrome.WindowChrome>
  <Window.Resources>
    <SolidColorBrush x:Key="Bg" Color="#262624"/>
    <SolidColorBrush x:Key="Card" Color="#30302E"/>
    <SolidColorBrush x:Key="Line" Color="#42413D"/>
    <SolidColorBrush x:Key="Text" Color="#F5F4EF"/>
    <SolidColorBrush x:Key="Muted" Color="#A6A39A"/>
    <SolidColorBrush x:Key="Accent" Color="#D97757"/>
    <SolidColorBrush x:Key="AccentHover" Color="#E48B6E"/>
    <SolidColorBrush x:Key="OnAccent" Color="#1F1E1D"/>
    <SolidColorBrush x:Key="Green" Color="#34C759"/>
    <SolidColorBrush x:Key="Hover" Color="#3A3A37"/>

    <Style x:Key="H1" TargetType="TextBlock">
      <Setter Property="FontSize" Value="20"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
    </Style>
    <Style x:Key="Sub" TargetType="TextBlock">
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="Foreground" Value="{StaticResource Muted}"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
      <Setter Property="LineHeight" Value="18"/>
    </Style>
    <Style x:Key="SectionLabel" TargetType="TextBlock">
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="{StaticResource Muted}"/>
      <Setter Property="Margin" Value="2,0,0,7"/>
    </Style>

    <Style x:Key="PrimaryButton" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource OnAccent}"/>
      <Setter Property="Background" Value="{StaticResource Accent}"/>
      <Setter Property="Height" Value="34"/>
      <Setter Property="Padding" Value="16,0"/>
      <Setter Property="FontSize" Value="13.5"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="9"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{StaticResource AccentHover}"/>
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
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Height" Value="34"/>
      <Setter Property="Padding" Value="14,0"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
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
                <Setter TargetName="Bd" Property="Background" Value="{StaticResource Card}"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.45"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="IconButton" TargetType="Button">
      <Setter Property="Width" Value="26"/>
      <Setter Property="Height" Value="26"/>
      <Setter Property="Foreground" Value="{StaticResource Muted}"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="FontSize" Value="16"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{StaticResource Hover}"/>
                <Setter Property="Foreground" Value="{StaticResource Text}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="CardBorder" TargetType="Border">
      <Setter Property="Background" Value="{StaticResource Card}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="12"/>
    </Style>

    <Style x:Key="RowButton" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Padding" Value="14,12"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}"
                    BorderBrush="{StaticResource Line}" BorderThickness="0,0,0,1"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Stretch" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#383834"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{StaticResource Hover}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="MenuRow" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Padding" Value="14,0"/>
      <Setter Property="Height" Value="44"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Stretch" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#383834"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Switch" TargetType="CheckBox">
      <Setter Property="Width" Value="38"/>
      <Setter Property="Height" Value="22"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Grid Background="Transparent">
              <Border x:Name="Track" CornerRadius="11" Background="#4A4A46"/>
              <Ellipse x:Name="Thumb" Width="16" Height="16" Fill="#F5F4EF"
                       HorizontalAlignment="Left" Margin="3,0,0,0"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Track" Property="Background" Value="{StaticResource Accent}"/>
                <Setter TargetName="Thumb" Property="HorizontalAlignment" Value="Right"/>
                <Setter TargetName="Thumb" Property="Margin" Value="0,0,3,0"/>
                <Setter TargetName="Thumb" Property="Fill" Value="{StaticResource OnAccent}"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Track" Property="Opacity" Value="0.45"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="NavTab" TargetType="RadioButton">
      <Setter Property="Foreground" Value="{StaticResource Muted}"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="Bd" Background="Transparent" CornerRadius="7" Padding="12,5" Margin="1,0">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Foreground" Value="{StaticResource Text}"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#42413D"/>
                <Setter Property="Foreground" Value="{StaticResource Text}"/>
                <Setter Property="FontWeight" Value="SemiBold"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="CaptionButton" TargetType="Button">
      <Setter Property="Width" Value="44"/>
      <Setter Property="Height" Value="30"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{StaticResource Muted}"/>
      <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="10"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="5">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{StaticResource Hover}"/>
                <Setter Property="Foreground" Value="{StaticResource Text}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="CloseButton" TargetType="Button">
      <Setter Property="Width" Value="44"/>
      <Setter Property="Height" Value="30"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{StaticResource Muted}"/>
      <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="10"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="5">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#C42B1C"/>
                <Setter Property="Foreground" Value="White"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="ContextMenu">
      <Setter Property="Background" Value="{StaticResource Card}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ContextMenu">
            <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="1" CornerRadius="10" Padding="4">
              <StackPanel IsItemsHost="True"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="MenuItem">
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="MenuItem">
            <Border x:Name="Bd" Background="Transparent" CornerRadius="6" Padding="10,7" Margin="2,1">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="16"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <TextBlock x:Name="Check" Text="✓" FontSize="12" FontWeight="Bold"
                           Foreground="{StaticResource Green}" Visibility="Collapsed"
                           VerticalAlignment="Center"/>
                <ContentPresenter Grid.Column="1" ContentSource="Header" RecognizesAccessKey="True"
                                  VerticalAlignment="Center"/>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{StaticResource Hover}"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Check" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Foreground" Value="{StaticResource Muted}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
    </Style>

    <Style TargetType="DataGrid">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="GridLinesVisibility" Value="None"/>
      <Setter Property="HeadersVisibility" Value="Column"/>
      <Setter Property="RowBackground" Value="Transparent"/>
      <Setter Property="AlternatingRowBackground" Value="Transparent"/>
      <Setter Property="RowHeight" Value="30"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="CanUserAddRows" Value="False"/>
      <Setter Property="CanUserResizeRows" Value="False"/>
      <Setter Property="IsReadOnly" Value="True"/>
      <Setter Property="SelectionMode" Value="Single"/>
      <Setter Property="SelectionUnit" Value="FullRow"/>
    </Style>
    <Style TargetType="DataGridColumnHeader">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{StaticResource Muted}"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="8,7"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="0,0,0,1"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
    </Style>
    <Style TargetType="DataGridRow">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderThickness" Value="0"/>
    </Style>
    <Style TargetType="DataGridCell">
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="Padding" Value="8,0"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="DataGridCell">
            <Border x:Name="Bd" Background="Transparent" Padding="{TemplateBinding Padding}">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{StaticResource Hover}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="ScrollBar">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Width" Value="10"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid Background="Transparent">
              <Track x:Name="PART_Track" Orientation="{TemplateBinding Orientation}"
                     IsDirectionReversed="True"/>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="Orientation" Value="Horizontal">
          <Setter Property="Width" Value="Auto"/>
          <Setter Property="Height" Value="10"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style TargetType="Thumb">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Thumb">
            <Border Background="#4A4A46" CornerRadius="4" Margin="2"/>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="Separator">
      <Setter Property="Background" Value="{StaticResource Line}"/>
      <Setter Property="Margin" Value="8,5,8,5"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Separator">
            <Border Background="{TemplateBinding Background}" Height="1"/>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="52"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="38"/>
    </Grid.RowDefinitions>

    <!-- header / title bar -->
    <Border Grid.Row="0" BorderBrush="{StaticResource Line}" BorderThickness="0,0,0,1">
      <Grid Margin="18,0,8,0">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <Grid Width="18" Height="18" Margin="0,0,10,0">
            <Ellipse Stroke="{StaticResource Accent}" StrokeThickness="2.2"/>
            <Ellipse Width="5" Height="5" Fill="{StaticResource Accent}"/>
          </Grid>
          <TextBlock Text="Claude Switchboard" FontSize="13.5" FontWeight="SemiBold" VerticalAlignment="Center"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
          <Border Background="#2B2B29" BorderBrush="{StaticResource Line}" BorderThickness="1"
                  CornerRadius="8" Padding="2" Margin="0,0,8,0"
                  WindowChrome.IsHitTestVisibleInChrome="True">
            <StackPanel Orientation="Horizontal">
              <RadioButton x:Name="NavSwitch" Style="{StaticResource NavTab}" Content="切换" IsChecked="True"
                           WindowChrome.IsHitTestVisibleInChrome="True"/>
              <RadioButton x:Name="NavUsage" Style="{StaticResource NavTab}" Content="用量"
                           WindowChrome.IsHitTestVisibleInChrome="True"/>
              <RadioButton x:Name="NavLog" Style="{StaticResource NavTab}" Content="活动"
                           WindowChrome.IsHitTestVisibleInChrome="True"/>
              <RadioButton x:Name="NavAbout" Style="{StaticResource NavTab}" Content="关于"
                           WindowChrome.IsHitTestVisibleInChrome="True"/>
            </StackPanel>
          </Border>
          <Button x:Name="BtnMin" Style="{StaticResource CaptionButton}" Content="&#xE921;"
                  AutomationProperties.Name="最小化" WindowChrome.IsHitTestVisibleInChrome="True"/>
          <Button x:Name="BtnMax" Style="{StaticResource CaptionButton}" Content="&#xE922;"
                  AutomationProperties.Name="最大化" WindowChrome.IsHitTestVisibleInChrome="True"/>
          <Button x:Name="BtnClose" Style="{StaticResource CloseButton}" Content="&#xE8BB;"
                  AutomationProperties.Name="关闭窗口" WindowChrome.IsHitTestVisibleInChrome="True"/>
        </StackPanel>
      </Grid>
    </Border>

    <!-- content -->
    <Grid Grid.Row="1" Margin="18,16,18,10">
      <ScrollViewer x:Name="PageSwitch" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <StackPanel Margin="0,0,2,0">
          <StackPanel Margin="2,0,2,14">
            <TextBlock Text="切换配置" Style="{StaticResource H1}"/>
            <TextBlock Text="点击一行即可切换。Claude Desktop 在启动时读取连接，切换会重启应用；项目和会话会先同步。"
                       Style="{StaticResource Sub}" Margin="0,5,0,0"/>
          </StackPanel>

          <Border Style="{StaticResource CardBorder}" Padding="0">
            <ItemsControl x:Name="ProfileList">
              <ItemsControl.ItemTemplate>
                <DataTemplate>
                  <Button x:Name="RowButton" Style="{StaticResource RowButton}" Tag="{Binding Id}">
                    <Grid>
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="24"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="30"/>
                      </Grid.ColumnDefinitions>
                      <TextBlock x:Name="Check" Text="✓" FontSize="13" FontWeight="Bold"
                                 Foreground="{StaticResource Green}" VerticalAlignment="Center"
                                 Visibility="Collapsed"/>
                      <StackPanel Grid.Column="1" VerticalAlignment="Center">
                        <TextBlock Text="{Binding Name}" FontSize="14" FontWeight="SemiBold"
                                   TextTrimming="CharacterEllipsis"/>
                        <TextBlock Text="{Binding Subtitle}" FontSize="12" Foreground="{StaticResource Muted}"
                                   Margin="0,2,0,0" TextTrimming="CharacterEllipsis"/>
                      </StackPanel>
                      <TextBlock Grid.Column="2" Text="{Binding Meta}" FontSize="12"
                                 Foreground="{StaticResource Muted}" VerticalAlignment="Center"
                                 Margin="12,0,10,0"/>
                      <Button x:Name="RowMenu" Grid.Column="3" Style="{StaticResource IconButton}"
                              Content="⋯" Tag="{Binding Id}" ToolTip="编辑或删除" AutomationProperties.Name="更多操作"/>
                    </Grid>
                  </Button>
                  <DataTemplate.Triggers>
                    <DataTrigger Binding="{Binding IsActive}" Value="True">
                      <Setter TargetName="Check" Property="Visibility" Value="Visible"/>
                      <Setter TargetName="RowButton" Property="Background" Value="#34342F"/>
                    </DataTrigger>
                    <DataTrigger Binding="{Binding IsGateway}" Value="False">
                      <Setter TargetName="RowMenu" Property="Visibility" Value="Collapsed"/>
                    </DataTrigger>
                  </DataTemplate.Triggers>
                </DataTemplate>
              </ItemsControl.ItemTemplate>
            </ItemsControl>
          </Border>

          <Border Style="{StaticResource CardBorder}" Padding="0" Margin="0,12,0,0">
            <StackPanel>
              <Button x:Name="BtnAdd" Style="{StaticResource MenuRow}" AutomationProperties.Name="添加中转">
                <Grid>
                  <TextBlock Text="添加中转…" VerticalAlignment="Center"/>
                  <TextBlock Text="+" FontSize="17" Foreground="{StaticResource Accent}"
                             HorizontalAlignment="Right" VerticalAlignment="Center"/>
                </Grid>
              </Button>
              <Border Height="1" Background="{StaticResource Line}" Margin="14,0"/>
              <Grid Height="44" Margin="14,0">
                <TextBlock Text="同步会话与项目" VerticalAlignment="Center"/>
                <CheckBox x:Name="ChkSync" Style="{StaticResource Switch}" IsChecked="True"
                          HorizontalAlignment="Right" VerticalAlignment="Center"/>
              </Grid>
              <Grid Height="44" Margin="14,0">
                <TextBlock Text="显示 Code 侧栏" VerticalAlignment="Center"/>
                <CheckBox x:Name="ChkCode" Style="{StaticResource Switch}" IsChecked="True"
                          HorizontalAlignment="Right" VerticalAlignment="Center"/>
              </Grid>
              <Border Height="1" Background="{StaticResource Line}" Margin="14,0"/>
              <Button x:Name="BtnLog" Style="{StaticResource MenuRow}" AutomationProperties.Name="活动记录">
                <Grid>
                  <TextBlock Text="活动记录" VerticalAlignment="Center"/>
                  <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <TextBlock x:Name="LogHint" Text="就绪" FontSize="12" Foreground="{StaticResource Muted}"
                               MaxWidth="240" TextTrimming="CharacterEllipsis" Margin="0,0,8,0"/>
                    <TextBlock x:Name="LogChevron" Text="›" FontSize="15" Foreground="{StaticResource Muted}"
                               VerticalAlignment="Center"/>
                  </StackPanel>
                </Grid>
              </Button>
            </StackPanel>
          </Border>
        </StackPanel>
      </ScrollViewer>

      <ScrollViewer x:Name="PageUsage" VerticalScrollBarVisibility="Auto"
                    HorizontalScrollBarVisibility="Disabled" Visibility="Collapsed">
        <StackPanel Margin="0,0,2,0">
          <Grid Margin="2,0,2,14">
            <StackPanel>
              <TextBlock Text="用量" Style="{StaticResource H1}"/>
              <TextBlock Text="来自本机 Claude Code 转录的 token 统计，不联网。"
                         Style="{StaticResource Sub}" Margin="0,5,0,0"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
              <Border Background="#2B2B29" BorderBrush="{StaticResource Line}" BorderThickness="1"
                      CornerRadius="8" Padding="2">
                <StackPanel Orientation="Horizontal">
                  <RadioButton x:Name="R7" Style="{StaticResource NavTab}" Content="7 天" IsChecked="True"/>
                  <RadioButton x:Name="R30" Style="{StaticResource NavTab}" Content="30 天"/>
                </StackPanel>
              </Border>
              <Button x:Name="BtnRefresh" Content="刷新" Style="{StaticResource SecondaryButton}"
                      Margin="8,0,0,0"/>
            </StackPanel>
          </Grid>

          <Border Style="{StaticResource CardBorder}" Padding="16,14">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
              </Grid.RowDefinitions>
              <StackPanel Grid.Row="0" Grid.Column="0" Margin="0,0,0,12">
                <TextBlock Text="消息" Style="{StaticResource SectionLabel}"/>
                <TextBlock x:Name="SumMessages" Text="—" FontSize="18" FontWeight="SemiBold"/>
              </StackPanel>
              <StackPanel Grid.Row="0" Grid.Column="1" Margin="0,0,0,12">
                <TextBlock Text="预估费用" Style="{StaticResource SectionLabel}"/>
                <TextBlock x:Name="SumCost" Text="—" FontSize="18" FontWeight="SemiBold"/>
              </StackPanel>
              <StackPanel Grid.Row="1" Grid.Column="0">
                <TextBlock Text="输入" Style="{StaticResource SectionLabel}"/>
                <TextBlock x:Name="SumInput" Text="—" FontSize="18" FontWeight="SemiBold"/>
              </StackPanel>
              <StackPanel Grid.Row="1" Grid.Column="1">
                <TextBlock Text="输出" Style="{StaticResource SectionLabel}"/>
                <TextBlock x:Name="SumOutput" Text="—" FontSize="18" FontWeight="SemiBold"/>
              </StackPanel>
            </Grid>
          </Border>

          <TextBlock Text="按模型" Style="{StaticResource SectionLabel}" Margin="2,16,0,7"/>
          <Border Style="{StaticResource CardBorder}" Padding="6,2">
            <DataGrid x:Name="GridModels" AutoGenerateColumns="False" Height="176">
              <DataGrid.Columns>
                <DataGridTextColumn Header="模型" Binding="{Binding Model}" Width="*"/>
                <DataGridTextColumn Header="消息" Binding="{Binding Messages}" Width="70"/>
                <DataGridTextColumn Header="输入" Binding="{Binding Input}" Width="86"/>
                <DataGridTextColumn Header="输出" Binding="{Binding Output}" Width="86"/>
                <DataGridTextColumn Header="费用" Binding="{Binding Cost}" Width="84"/>
              </DataGrid.Columns>
            </DataGrid>
          </Border>

          <TextBlock Text="按项目" Style="{StaticResource SectionLabel}" Margin="2,16,0,7"/>
          <Border Style="{StaticResource CardBorder}" Padding="6,2">
            <DataGrid x:Name="GridProjects" AutoGenerateColumns="False" Height="176">
              <DataGrid.Columns>
                <DataGridTextColumn Header="项目" Binding="{Binding Project}" Width="*"/>
                <DataGridTextColumn Header="消息" Binding="{Binding Messages}" Width="70"/>
                <DataGridTextColumn Header="输入" Binding="{Binding Input}" Width="86"/>
                <DataGridTextColumn Header="输出" Binding="{Binding Output}" Width="86"/>
                <DataGridTextColumn Header="费用" Binding="{Binding Cost}" Width="84"/>
              </DataGrid.Columns>
            </DataGrid>
          </Border>

          <TextBlock x:Name="UsageStatus" Text="尚未扫描。" FontSize="11.5"
                     Foreground="{StaticResource Muted}" Margin="2,10,0,0"/>
        </StackPanel>
      </ScrollViewer>

      <ScrollViewer x:Name="PageAbout" VerticalScrollBarVisibility="Auto"
                    HorizontalScrollBarVisibility="Disabled" Visibility="Collapsed">
        <StackPanel Margin="0,0,2,0">
          <StackPanel Margin="2,0,2,14">
            <TextBlock Text="关于" Style="{StaticResource H1}"/>
            <TextBlock x:Name="AboutVersion" Text="v0.3.0" Style="{StaticResource Sub}" Margin="0,5,0,0"/>
          </StackPanel>
          <Border Style="{StaticResource CardBorder}" Padding="18,16">
            <TextBlock x:Name="AboutText" TextWrapping="Wrap" Foreground="{StaticResource Muted}"
                       LineHeight="20" FontSize="12.5"/>
          </Border>
          <Button x:Name="BtnQuit" Content="退出应用" Style="{StaticResource SecondaryButton}"
                  HorizontalAlignment="Left" Margin="0,14,0,0"/>
        </StackPanel>
      </ScrollViewer>

      <ScrollViewer x:Name="PageLog" VerticalScrollBarVisibility="Auto"
                    HorizontalScrollBarVisibility="Disabled" Visibility="Collapsed">
        <StackPanel Margin="0,0,2,0">
          <StackPanel Margin="2,0,2,14">
            <TextBlock Text="活动记录" Style="{StaticResource H1}"/>
            <TextBlock Text="切换过程的日志。关闭窗口后程序仍在托盘运行，这里会继续记录。"
                       Style="{StaticResource Sub}" Margin="0,5,0,0"/>
          </StackPanel>
          <Border Style="{StaticResource CardBorder}" Padding="12" Background="#232321" Height="360">
            <TextBox x:Name="LogBox" Background="Transparent" Foreground="#C9C6BE"
                     BorderThickness="0" IsReadOnly="True" TextWrapping="Wrap"
                     VerticalScrollBarVisibility="Auto"
                     FontFamily="Cascadia Mono, Consolas, Microsoft YaHei UI" FontSize="11"/>
          </Border>
        </StackPanel>
      </ScrollViewer>
    </Grid>

    <!-- status bar -->
    <Border Grid.Row="2" Background="#232321" BorderBrush="{StaticResource Line}" BorderThickness="0,1,0,0">
      <Grid Margin="18,0">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <Ellipse x:Name="ModeDot" Width="7" Height="7" Fill="{StaticResource Green}" Margin="0,0,8,0"/>
          <TextBlock x:Name="ModeText" Text="Claude Max 官方" FontSize="12"/>
          <TextBlock Text="  ·  " FontSize="12" Foreground="{StaticResource Muted}"/>
          <TextBlock x:Name="SessionInfo" Text="会话 0 / 0" FontSize="12"
                     Foreground="{StaticResource Muted}"/>
        </StackPanel>
        <TextBlock Text="v0.3.0" FontSize="11" Foreground="{StaticResource Muted}"
                   HorizontalAlignment="Right" VerticalAlignment="Center"/>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

$script:Window = [Windows.Markup.XamlReader]::Parse($xaml)

foreach ($name in @(
    'NavSwitch','NavUsage','NavLog','NavAbout','BtnMin','BtnMax','BtnClose','PageSwitch','PageUsage','PageAbout',
    'ModeDot','ModeText','SessionInfo','ProfileList','BtnAdd','ChkSync','ChkCode',
    'BtnLog','LogHint','LogChevron','LogBox','PageLog','R7','R30','BtnRefresh',
    'UsageStatus','SumMessages','SumCost','SumInput','SumOutput','GridModels',
    'GridProjects','AboutText','AboutVersion','BtnQuit')) {
    Set-Variable -Name "ui$name" -Value $script:Window.FindName($name) -Scope Script
}

# ---------------- window chrome ----------------
function Set-DarkTitleBar($window) {
    try {
        $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
        $h = $helper.Handle
        if ($h -eq [IntPtr]::Zero) { return }
        $on = 1
        [NativeChrome]::DwmSetWindowAttribute($h, 20, [ref]$on, 4) | Out-Null
        [NativeChrome]::DwmSetWindowAttribute($h, 19, [ref]$on, 4) | Out-Null
        $round = 2
        [NativeChrome]::DwmSetWindowAttribute($h, 33, [ref]$round, 4) | Out-Null
    } catch { }
}

function Enable-DarkChrome($window) {
    $window.Add_SourceInitialized({ param($s, $e) Set-DarkTitleBar $s })
}

Enable-DarkChrome $script:Window

# ---------------- tray ----------------
function New-RingIcon([string]$hex) {
    $bmp = New-Object System.Drawing.Bitmap(32, 32)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $color = [System.Drawing.ColorTranslator]::FromHtml($hex)
    $pen = New-Object System.Drawing.Pen($color, 4)
    $g.DrawEllipse($pen, 6, 6, 20, 20)
    $brush = New-Object System.Drawing.SolidBrush($color)
    $g.FillEllipse($brush, 13, 13, 6, 6)
    $pen.Dispose(); $brush.Dispose(); $g.Dispose()
    $handle = $bmp.GetHicon()
    return [pscustomobject]@{
        Icon   = [System.Drawing.Icon]::FromHandle($handle)
        Handle = $handle
        Bitmap = $bmp
    }
}

[System.Windows.Forms.Application]::EnableVisualStyles()
$script:Notify = New-Object System.Windows.Forms.NotifyIcon
$script:Notify.Visible = $true
$script:Notify.Text = 'Claude Switchboard'
$script:TrayIconObj = $null

function Set-TrayIcon([bool]$official) {
    if ($script:TrayIconObj) {
        $script:Notify.Icon = $null
        [NativeChrome]::DestroyIcon($script:TrayIconObj.Handle) | Out-Null
        $script:TrayIconObj.Bitmap.Dispose()
    }
    $script:TrayIconObj = New-RingIcon $(if ($official) { '#34C759' } else { '#D97757' })
    $script:Notify.Icon = $script:TrayIconObj.Icon
    if (-not $script:Window.Icon) {
        try {
            $script:Window.Icon = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
                $script:TrayIconObj.Icon.Handle,
                [System.Windows.Int32Rect]::Empty,
                [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
        } catch { }
    }
}

function Show-Window {
    $script:Window.Show()
    if ($script:Window.WindowState -eq 'Minimized') { $script:Window.WindowState = 'Normal' }
    $script:Window.Activate()
}

function Exit-App {
    $script:Quitting = $true
    try {
        $script:Notify.Visible = $false
        $script:Notify.Dispose()
        if ($script:TrayIconObj) {
            [NativeChrome]::DestroyIcon($script:TrayIconObj.Handle) | Out-Null
            $script:TrayIconObj.Bitmap.Dispose()
        }
    } catch { }
    $script:App.Shutdown()
}

function New-TrayMenuItem([string]$text, [bool]$checked, $onClick) {
    $mi = New-Object System.Windows.Controls.MenuItem
    $mi.Header = $text
    $mi.IsCheckable = $true
    $mi.IsChecked = $checked
    $mi.Add_Click($onClick)
    return $mi
}

function Show-TrayMenu {
    $cm = New-Object System.Windows.Controls.ContextMenu
    $cm.MinWidth = 230

    $head = New-Object System.Windows.Controls.MenuItem
    $head.Header = 'Claude Switchboard'
    $head.IsEnabled = $false
    $cm.Items.Add($head) | Out-Null

    $mode = Get-CurrentDeploymentMode
    $active = @($script:ProfilesDoc.profiles) | Where-Object { $_.id -eq $script:ProfilesDoc.activeProfileId } | Select-Object -First 1
    $modeName = if ($mode -eq 'official') { 'Claude Max 官方' } elseif ($active) { $active.name } else { '第三方中转' }
    $modeItem = New-Object System.Windows.Controls.MenuItem
    $modeItem.Header = "当前：$modeName"
    $modeItem.IsEnabled = $false
    $cm.Items.Add($modeItem) | Out-Null

    $sep = New-Object System.Windows.Controls.Separator
    $sep.Margin = New-Object System.Windows.Thickness(8, 5, 8, 5)
    $cm.Items.Add($sep) | Out-Null

    foreach ($p in @($script:ProfilesDoc.profiles)) {
        $id = [string]$p.id
        $isActive = ($id -eq [string]$script:ProfilesDoc.activeProfileId)
        $mi = New-TrayMenuItem $p.name $isActive {
            param($s, $e)
            $target = Get-ProfileById $script:ProfilesDoc ([string]$s.Tag)
            if ($target -and $target.id -ne $script:ProfilesDoc.activeProfileId) {
                Invoke-SwitchTo $target
            }
        }
        $mi.Tag = $id
        $cm.Items.Add($mi) | Out-Null
    }

    $cm.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null

    $open = New-TrayMenuItem '打开控制台' $false { Show-Window }
    $cm.Items.Add($open) | Out-Null
    $add = New-TrayMenuItem '添加中转…' $false { Show-Window; Show-ProfileDialog $null }
    $cm.Items.Add($add) | Out-Null
    $cm.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
    $quit = New-TrayMenuItem '退出' $false { Exit-App }
    $cm.Items.Add($quit) | Out-Null

    $cm.Placement = [System.Windows.Controls.Primitives.PlacementMode]::MousePoint
    $cm.IsOpen = $true
}

$script:Notify.Add_MouseUp({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
        Show-TrayMenu
    } elseif ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        Show-Window
    }
})

$script:Window.Add_Closing({
    param($s, $e)
    if (-not $script:Quitting) {
        $e.Cancel = $true
        $s.Hide()
        if (-not $script:HideTipShown) {
            $script:HideTipShown = $true
            $script:Notify.ShowBalloonTip(2600, 'Claude Switchboard',
                '仍在托盘运行。右键托盘图标可切换配置或退出。',
                [System.Windows.Forms.ToolTipIcon]::Info)
        }
    }
})

# ---------------- helpers ----------------
function Write-Log([string]$msg) {
    $line = "[{0}] {1}" -f ([DateTime]::Now.ToString('HH:mm:ss')), $msg
    $script:uiLogBox.AppendText($line + "`r`n")
    $script:uiLogBox.ScrollToEnd()
    $hint = $msg
    if ($hint.Length -gt 38) { $hint = $hint.Substring(0, 37) + '…' }
    $script:uiLogHint.Text = $hint
}

function Set-Page([string]$page) {
    $script:uiPageSwitch.Visibility = if ($page -eq 'switch') { 'Visible' } else { 'Collapsed' }
    $script:uiPageUsage.Visibility = if ($page -eq 'usage') { 'Visible' } else { 'Collapsed' }
    $script:uiPageLog.Visibility = if ($page -eq 'log') { 'Visible' } else { 'Collapsed' }
    $script:uiPageAbout.Visibility = if ($page -eq 'about') { 'Visible' } else { 'Collapsed' }
    $script:uiNavSwitch.IsChecked = ($page -eq 'switch')
    $script:uiNavUsage.IsChecked = ($page -eq 'usage')
    $script:uiNavLog.IsChecked = ($page -eq 'log')
    $script:uiNavAbout.IsChecked = ($page -eq 'about')
    if ($page -eq 'switch') { $script:uiPageSwitch.ScrollToTop() }
    elseif ($page -eq 'usage') { $script:uiPageUsage.ScrollToTop() }
    elseif ($page -eq 'log') { $script:uiPageLog.ScrollToTop() }
    elseif ($page -eq 'about') { $script:uiPageAbout.ScrollToTop() }
    if ($page -eq 'usage') { Refresh-Usage }
}

function Update-ModeStatus {
    $mode = Get-CurrentDeploymentMode
    $counts = Get-SessionCounts
    $active = @($script:ProfilesDoc.profiles) |
        Where-Object { $_.id -eq $script:ProfilesDoc.activeProfileId } | Select-Object -First 1
    $label = if ($mode -eq 'official') { 'Claude Max 官方' }
             elseif ($active) { $active.name }
             else { '第三方中转' }
    $script:uiModeText.Text = $label
    $script:uiSessionInfo.Text = ("会话 {0} / {1}" -f $counts.Official, $counts.Gateway)
    $brush = if ($mode -eq 'official') { '#34C759' } else { '#D97757' }
    $script:uiModeDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString($brush)
    Set-TrayIcon ($mode -eq 'official')
    $short = if ($label.Length -gt 40) { $label.Substring(0, 39) + '…' } else { $label }
    $script:Notify.Text = "Claude Switchboard · $short"
}

function Set-Busy([bool]$value) {
    $script:Busy = $value
    foreach ($b in @($script:uiBtnAdd, $script:uiBtnRefresh, $script:uiBtnQuit)) {
        $b.IsEnabled = -not $value
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Refresh-ProfileList {
    $script:ProfilesDoc = Get-ProfilesDoc
    $items = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    foreach ($p in @($script:ProfilesDoc.profiles)) {
        $isActive = ($p.id -eq $script:ProfilesDoc.activeProfileId)
        $isGateway = ($p.kind -eq 'gateway')
        $meta = if ($isGateway) { (@($p.models).Count.ToString() + ' 个模型') } else { '官方订阅' }
        $items.Add([pscustomobject]@{
            Id         = $p.id
            Name       = $p.name
            Subtitle   = if ($isGateway) { [string]$p.baseUrl } else { 'claude.ai 登录 · OAuth token' }
            Meta       = $meta
            IsActive   = $isActive
            IsGateway  = $isGateway
        }) | Out-Null
    }
    $script:uiProfileList.ItemsSource = $items
    Update-ModeStatus
}

function Invoke-SwitchTo($profile) {
    if (-not $profile) { Write-Log '先选择一个配置。'; return }
    if ($script:Busy) { return }
    if ($profile.id -eq $script:ProfilesDoc.activeProfileId) { return }
    $key = ''
    if ($profile.kind -ne 'official') {
        $key = Get-ProfilePlainKey $profile
        if (-not $key) { Write-Log '这个配置没有 API Key，请先编辑。'; return }
    }
    $hidden = -not $script:Window.IsVisible
    if ($hidden) {
        $script:Notify.ShowBalloonTip(1800, 'Claude Switchboard',
            "正在切换到 $($profile.name)…", [System.Windows.Forms.ToolTipIcon]::Info)
    }
    Set-Busy $true
    try {
        Invoke-ClaudeSwitch -Profile $profile -PlainKey $key `
            -SyncSessions ([bool]$script:uiChkSync.IsChecked) `
            -CodeSidebar ([bool]$script:uiChkCode.IsChecked) `
            -Log { param($m) Write-Log $m }
        Set-ActiveProfile $profile.id
        $script:ProfilesDoc = Get-ProfilesDoc
        Write-Log '完成。'
        if ($hidden) {
            $script:Notify.ShowBalloonTip(2600, 'Claude Switchboard',
                "已切换到 $($profile.name)", [System.Windows.Forms.ToolTipIcon]::Info)
        }
    } catch {
        Write-Log ('错误：' + $_.Exception.Message)
    } finally {
        Set-Busy $false
        Refresh-ProfileList
    }
}

function Show-ProfileMenu($anchor) {
    $p = Get-ProfileById $script:ProfilesDoc ([string]$anchor.Tag)
    if (-not $p -or $p.kind -eq 'official') { return }
    $cm = New-Object System.Windows.Controls.ContextMenu
    $cm.MinWidth = 150
    $cm.PlacementTarget = $anchor
    $cm.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Bottom

    $edit = New-TrayMenuItem '编辑…' $false {
        param($s, $e)
        $target = Get-ProfileById $script:ProfilesDoc ([string]$s.Tag)
        if ($target) { Show-ProfileDialog $target }
    }
    $edit.Tag = $p.id
    $cm.Items.Add($edit) | Out-Null

    $del = New-TrayMenuItem '删除' $false {
        param($s, $e)
        $target = Get-ProfileById $script:ProfilesDoc ([string]$s.Tag)
        if (-not $target) { return }
        if (Show-Confirm "删除配置「$($target.name)」？`nAPI Key 和模型列表会一起删除。") {
            Remove-Profile $target.id
            Write-Log ('已删除：' + $target.name)
            Refresh-ProfileList
        }
    }
    $del.Tag = $p.id
    $cm.Items.Add($del) | Out-Null

    $cm.IsOpen = $true
}

$script:uiProfileList.AddHandler([System.Windows.Controls.Button]::ClickEvent,
    [System.Windows.RoutedEventHandler]{
        param($s, $e)
        # Routed through the ItemsControl: Source is the list, the real button is OriginalSource.
        $node = $e.OriginalSource
        while ($node -and -not ($node -is [System.Windows.Controls.Button])) {
            if ($node -is [System.Windows.Media.Visual]) {
                $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node)
            } elseif ($node -is [System.Windows.FrameworkContentElement]) {
                $node = $node.Parent
            } else {
                $node = $null
            }
        }
        if (-not $node -or -not $node.Tag) { return }
        if ($node.Name -eq 'RowMenu') {
            Show-ProfileMenu $node
            return
        }
        if ($script:Busy) { return }
        $target = Get-ProfileById $script:ProfilesDoc ([string]$node.Tag)
        if ($target -and $target.id -ne $script:ProfilesDoc.activeProfileId) {
            Invoke-SwitchTo $target
        }
    })

# ---------------- dialogs ----------------
$script:DialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Gateway profile" Width="560" Height="680"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize" ShowInTaskbar="False"
        Background="#262624" Foreground="#F5F4EF"
        FontFamily="Segoe UI Variable Text, Microsoft YaHei UI, Segoe UI"
        FontSize="13" UseLayoutRounding="True">
  <Window.Resources>
    <SolidColorBrush x:Key="Line" Color="#42413D"/>
    <SolidColorBrush x:Key="Muted" Color="#A6A39A"/>
    <SolidColorBrush x:Key="Accent" Color="#D97757"/>
    <SolidColorBrush x:Key="AccentHover" Color="#E48B6E"/>
    <Style x:Key="Field" TargetType="TextBox">
      <Setter Property="Background" Value="#30302E"/>
      <Setter Property="Foreground" Value="#F5F4EF"/>
      <Setter Property="CaretBrush" Value="#F5F4EF"/>
      <Setter Property="BorderBrush" Value="#42413D"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,8"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border x:Name="Bd" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8">
              <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"
                            VerticalScrollBarVisibility="{TemplateBinding VerticalScrollBarVisibility}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Accent}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button">
      <Setter Property="Foreground" Value="#1F1E1D"/>
      <Setter Property="Background" Value="{StaticResource Accent}"/>
      <Setter Property="Height" Value="34"/>
      <Setter Property="Padding" Value="18,0"/>
      <Setter Property="FontSize" Value="13.5"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="9"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{StaticResource AccentHover}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Secondary" TargetType="Button">
      <Setter Property="Foreground" Value="#F5F4EF"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Height" Value="34"/>
      <Setter Property="Padding" Value="16,0"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}"
                    BorderBrush="{StaticResource Line}" BorderThickness="1" CornerRadius="9"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#30302E"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Label" TargetType="TextBlock">
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Foreground" Value="{StaticResource Muted}"/>
      <Setter Property="Margin" Value="0,0,0,6"/>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Width" Value="10"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid Background="Transparent">
              <Track x:Name="PART_Track" Orientation="{TemplateBinding Orientation}"
                     IsDirectionReversed="True"/>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="Orientation" Value="Horizontal">
          <Setter Property="Width" Value="Auto"/>
          <Setter Property="Height" Value="10"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style TargetType="Thumb">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Thumb">
            <Border Background="#4A4A46" CornerRadius="4" Margin="2"/>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Grid Margin="22,18,22,18">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <StackPanel Grid.Row="0" Margin="0,0,0,14">
      <TextBlock x:Name="DlgTitle" Text="添加中转" FontSize="17" FontWeight="SemiBold"/>
      <TextBlock Text="Base URL 要能直接提供 /v1/messages。API Key 用 DPAPI 加密，只存在本机。"
                 FontSize="12.5" Foreground="{StaticResource Muted}" Margin="0,4,0,0" TextWrapping="Wrap"/>
    </StackPanel>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
      <StackPanel>
        <TextBlock Text="名称" Style="{StaticResource Label}"/>
        <TextBox x:Name="FName" Style="{StaticResource Field}" Margin="0,0,0,12"/>
        <TextBlock Text="Base URL" Style="{StaticResource Label}"/>
        <TextBox x:Name="FUrl" Style="{StaticResource Field}" Margin="0,0,0,12"/>
        <TextBlock x:Name="KeyLabel" Text="API Key" Style="{StaticResource Label}"/>
        <TextBox x:Name="FKey" Style="{StaticResource Field}" Margin="0,0,0,12"/>
        <TextBlock Text="模型（每行一个：id | 显示名 | 档位）" Style="{StaticResource Label}"/>
        <TextBox x:Name="FModels" Style="{StaticResource Field}" Height="140" AcceptsReturn="True"
                 TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"
                 FontFamily="Cascadia Mono, Consolas" FontSize="11.5" Margin="0,0,0,12"/>
        <TextBlock Text="备注（可选）" Style="{StaticResource Label}"/>
        <TextBox x:Name="FNotes" Style="{StaticResource Field}"/>
        <TextBlock x:Name="DlgError" Foreground="#FF6B5E" FontSize="12" Margin="0,10,0,0"
                   TextWrapping="Wrap" Visibility="Collapsed"/>
      </StackPanel>
    </ScrollViewer>
    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0">
      <Button x:Name="DlgCancel" Content="取消" Style="{StaticResource Secondary}"/>
      <Button x:Name="DlgSave" Content="保存" Style="{StaticResource Primary}" Margin="10,0,0,0"/>
    </StackPanel>
  </Grid>
</Window>
'@

function Show-ProfileDialog($existing) {
    $dlg = [Windows.Markup.XamlReader]::Parse($script:DialogXaml)
    $dlg.Owner = $script:Window
    Enable-DarkChrome $dlg

    $title = $dlg.FindName('DlgTitle')
    $dlg.Title = if ($existing) { '编辑中转' } else { '添加中转' }
    $dlg.Icon = $script:Window.Icon
    $fName = $dlg.FindName('FName')
    $fUrl = $dlg.FindName('FUrl')
    $fKey = $dlg.FindName('FKey')
    $fModels = $dlg.FindName('FModels')
    $fNotes = $dlg.FindName('FNotes')
    $keyLabel = $dlg.FindName('KeyLabel')
    $err = $dlg.FindName('DlgError')
    $cancel = $dlg.FindName('DlgCancel')
    $save = $dlg.FindName('DlgSave')

    $title.Text = if ($existing) { '编辑中转' } else { '添加中转' }
    $fName.Text = if ($existing) { $existing.name } else { '' }
    $fUrl.Text = if ($existing) { $existing.baseUrl } else { 'https://' }
    $fModels.Text = if ($existing) { ConvertTo-ModelText $existing.models } else { ConvertTo-ModelText (Get-DefaultClaudeModels) }
    $fNotes.Text = if ($existing) { $existing.notes } else { '' }
    if ($existing) { $keyLabel.Text = 'API Key（留空表示不修改）' }

    $cancel.Add_Click({ $dlg.DialogResult = $false; $dlg.Close() })
    $save.Add_Click({
        $name = $fName.Text.Trim()
        $url = $fUrl.Text.Trim()
        if (-not $name -or -not $url) {
            $err.Text = '名称和 Base URL 都不能为空。'
            $err.Visibility = 'Visible'
            return
        }
        if (-not $existing -and -not $fKey.Text.Trim()) {
            $err.Text = '中转配置必须填 API Key。'
            $err.Visibility = 'Visible'
            return
        }
        $models = ConvertFrom-ModelText $fModels.Text
        if (@($models).Count -eq 0) {
            $err.Text = '至少写一个模型。'
            $err.Visibility = 'Visible'
            return
        }
        if ($existing) {
            Update-GatewayProfile -Profile $existing -Name $name -BaseUrl $url `
                -ApiKey $fKey.Text -Models $models -Notes $fNotes.Text | Out-Null
            Write-Log ('已更新：' + $name)
        } else {
            Add-GatewayProfile -Name $name -BaseUrl $url -ApiKey $fKey.Text `
                -Models $models -Notes $fNotes.Text | Out-Null
            Write-Log ('已添加：' + $name)
        }
        $dlg.DialogResult = $true
        $dlg.Close()
    })

    [void]$dlg.ShowDialog()
    Refresh-ProfileList
}

function Show-Confirm([string]$message) {
    $dlg = New-Object System.Windows.Window
    $dlg.Title = '确认'
    $dlg.Width = 420
    $dlg.SizeToContent = 'Height'
    $dlg.WindowStartupLocation = 'CenterOwner'
    $dlg.Owner = $script:Window
    $dlg.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#262624')
    $dlg.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#F5F4EF')
    $dlg.FontFamily = $script:Window.FontFamily
    $dlg.FontSize = 13
    Enable-DarkChrome $dlg

    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = New-Object System.Windows.Thickness(20, 18, 20, 16)
    $r0 = New-Object System.Windows.Controls.RowDefinition
    $r0.Height = [System.Windows.GridLength]::Auto
    $r1 = New-Object System.Windows.Controls.RowDefinition
    $r1.Height = [System.Windows.GridLength]::Auto
    $grid.RowDefinitions.Add($r0) | Out-Null
    $grid.RowDefinitions.Add($r1) | Out-Null

    $text = New-Object System.Windows.Controls.TextBlock
    $text.Text = $message
    $text.TextWrapping = 'Wrap'
    $text.LineHeight = 20
    $grid.Children.Add($text) | Out-Null

    $buttons = New-Object System.Windows.Controls.StackPanel
    $buttons.Orientation = 'Horizontal'
    $buttons.HorizontalAlignment = 'Right'
    $buttons.Margin = New-Object System.Windows.Thickness(0, 18, 0, 0)
    [System.Windows.Controls.Grid]::SetRow($buttons, 1)

    $cancel = New-Object System.Windows.Controls.Button
    $cancel.Content = '取消'
    $cancel.Padding = New-Object System.Windows.Thickness(16, 7, 16, 7)
    $cancel.Margin = New-Object System.Windows.Thickness(0, 0, 10, 0)
    $cancel.Cursor = 'Hand'
    $cancel.Background = [System.Windows.Media.Brushes]::Transparent
    $cancel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#F5F4EF')
    $cancel.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#42413D')

    $ok = New-Object System.Windows.Controls.Button
    $ok.Content = '删除'
    $ok.Padding = New-Object System.Windows.Thickness(18, 7, 18, 7)
    $ok.Cursor = 'Hand'
    $ok.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#D97757')
    $ok.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#1F1E1D')
    $ok.BorderThickness = New-Object System.Windows.Thickness(0)
    $ok.FontWeight = 'SemiBold'

    $buttons.Children.Add($cancel) | Out-Null
    $buttons.Children.Add($ok) | Out-Null
    $grid.Children.Add($buttons) | Out-Null
    $dlg.Content = $grid

    $cancel.Add_Click({ $dlg.DialogResult = $false; $dlg.Close() })
    $ok.Add_Click({ $dlg.DialogResult = $true; $dlg.Close() })
    [void]$dlg.ShowDialog()
    return ($dlg.DialogResult -eq $true)
}

# ---------------- usage ----------------
function Refresh-Usage {
    if ($script:Busy) { return }
    $script:Busy = $true
    $script:uiBtnRefresh.IsEnabled = $false
    $days = if ($script:uiR30.IsChecked) { 30 } else { 7 }
    $script:uiUsageStatus.Text = '正在扫描转录…'
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $u = Get-ClaudeUsage -Days $days -Progress {
            param($done, $total, $file)
            $script:uiUsageStatus.Text = "扫描 $done/$total"
            [System.Windows.Forms.Application]::DoEvents()
        }
        if (-not $u.Available) {
            $script:uiUsageStatus.Text = "没有找到转录：$($u.Root)"
            return
        }
        $script:uiSumMessages.Text = [string]$u.Messages
        $script:uiSumCost.Text = ('${0:N2}' -f $u.Cost)
        $script:uiSumInput.Text = (Format-Tokens $u.Input)
        $script:uiSumOutput.Text = (Format-Tokens $u.Output)
        $script:uiUsageStatus.Text = ('扫描于 {0} · 缓存读 {1} · 缓存写 {2}' -f `
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
        $script:uiUsageStatus.Text = '错误：' + $_.Exception.Message
    } finally {
        $script:Busy = $false
        $script:uiBtnRefresh.IsEnabled = $true
    }
}

# ---------------- events ----------------
$script:uiNavSwitch.Add_Checked({ if ($script:uiNavSwitch.IsChecked) { Set-Page 'switch' } })
$script:uiNavUsage.Add_Checked({ if ($script:uiNavUsage.IsChecked) { Set-Page 'usage' } })
$script:uiNavLog.Add_Checked({ if ($script:uiNavLog.IsChecked) { Set-Page 'log' } })
$script:uiNavAbout.Add_Checked({ if ($script:uiNavAbout.IsChecked) { Set-Page 'about' } })
$script:uiBtnMin.Add_Click({ $script:Window.WindowState = 'Minimized' })
$script:uiBtnMax.Add_Click({
    if ($script:Window.WindowState -eq 'Maximized') { $script:Window.WindowState = 'Normal' }
    else { $script:Window.WindowState = 'Maximized' }
})
$script:uiBtnClose.Add_Click({ $script:Window.Close() })
$script:Window.Add_StateChanged({
    if ($script:uiBtnMax) {
        if ($script:Window.WindowState -eq 'Maximized') {
            $script:uiBtnMax.Content = [char]0xE923
            $script:uiBtnMax.ToolTip = '还原'
        } else {
            $script:uiBtnMax.Content = [char]0xE922
            $script:uiBtnMax.ToolTip = '最大化'
        }
    }
})
$script:uiR7.Add_Checked({ if ($script:uiR7.IsChecked) { Refresh-Usage } })
$script:uiR30.Add_Checked({ if ($script:uiR30.IsChecked) { Refresh-Usage } })
$script:uiBtnRefresh.Add_Click({ Refresh-Usage })
$script:uiBtnAdd.Add_Click({ Show-ProfileDialog $null })
$script:uiBtnQuit.Add_Click({ Exit-App })

$script:uiBtnLog.Add_Click({ Set-Page 'log'; $script:uiLogBox.ScrollToEnd() })

# ---------------- about ----------------
$paths = Get-ClaudeDesktopPaths
$script:uiAboutText.Text = @"
一个 Windows 控制台：在 Claude Desktop 的官方 Claude Max 账号和第三方
Anthropic 兼容中转之间切换，切换时双向复制会话卡片。

工作方式
  官方模式   deploymentMode = "1p"，%APPDATA%\Claude 里的登录状态不动。
  中转模式   把配置写进 Claude-3p\configLibrary，并更新 appliedId。
  会话       %APPDATA%\Claude\claude-code-sessions 与
             %LOCALAPPDATA%\Claude-3p\claude-code-sessions，较新的文件覆盖较旧的。
  顺序       退出 Claude → 同步会话 → 写配置 → 启动；先写会被应用退出时覆盖。
  编码       配置必须是 UTF-8 无 BOM；带 BOM 时应用会静默保持旧模式。

托盘
  关闭窗口不会退出，程序留在托盘。右键托盘图标可直接切换配置、新建或退出。
  圆环颜色：绿色是官方账号，橙色是中转。

路径
  配置文件   $($paths.LocalConfig)
  配置库     $($paths.LocalLibrary)
  本工具     $(Get-ProfilesFilePath)
  转录       $(Get-TranscriptRoot)

API Key 用 Windows DPAPI（当前用户）加密，只存在本机；用量统计全部在本地完成。
"@

# ---------------- startup ----------------
$script:App = New-Object System.Windows.Application
$script:App.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
$script:App.MainWindow = $script:Window

# Popup menus are not in the window tree, so copy their implicit styles to the app.
foreach ($type in @([System.Windows.Controls.ContextMenu],
                    [System.Windows.Controls.MenuItem],
                    [System.Windows.Controls.Separator])) {
    $style = $script:Window.Resources[$type]
    if ($style) { $script:App.Resources[$type] = $style }
}

Set-Page 'switch'
Refresh-ProfileList
Write-Log '就绪。'
[void]$script:App.Run($script:Window)
