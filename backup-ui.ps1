# backup-ui.ps1 - window for the Obsidian backup: status, schedule, run now, restore.
# Run with -Preview to see the window without installing or changing anything.
param([switch]$Preview)
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$TaskName    = 'Obsidian Backup'
$AppDir      = Join-Path $env:LOCALAPPDATA 'ObsidianBackup'
$LogFile     = Join-Path $AppDir 'backup.log'
$ConfigFile  = Join-Path $AppDir 'config.json'
$DayNames    = @('Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday')
$DayShort    = @('Su','Mo','Tu','We','Th','Fr','Sa')
$Inv         = [Globalization.CultureInfo]::InvariantCulture

if ($Preview) {
    $Destinations = @(
        [pscustomobject]@{ name = 'Google Drive'; path = 'G:\Backups\Obsidian' },
        [pscustomobject]@{ name = 'OneDrive';     path = 'C:\OneDrive\Backups\Obsidian' })
} else {
    try { $Destinations = @((Get-Content $ConfigFile -Raw | ConvertFrom-Json).destinations) } catch { $Destinations = @() }
}

if (-not $Preview -and -not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
    [System.Windows.MessageBox]::Show('Backup task not found. Run setup.ps1 first.', 'Obsidian Backup') | Out-Null
    exit 1
}

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Obsidian Backup" Width="460" SizeToContent="Height" ResizeMode="NoResize"
        WindowStartupLocation="CenterScreen"
        Background="#EEF2F5" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="14" Foreground="#1B2733">
  <Window.Resources>
    <Style x:Key="Day" TargetType="ToggleButton">
      <Setter Property="Width" Value="44"/>
      <Setter Property="Height" Value="44"/>
      <Setter Property="Margin" Value="0,0,8,0"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="#1E4D7B"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Border x:Name="b" CornerRadius="22" Background="White" BorderBrush="#C9D3DC" BorderThickness="1">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="BorderBrush" Value="#1E4D7B"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="b" Property="Background" Value="#1E4D7B"/>
                <Setter TargetName="b" Property="BorderBrush" Value="#1E4D7B"/>
                <Setter Property="Foreground" Value="White"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="b" Property="BorderThickness" Value="2"/>
                <Setter TargetName="b" Property="BorderBrush" Value="#1B2733"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="#1E4D7B" CornerRadius="6" Padding="20,10" BorderBrush="#1E4D7B" BorderThickness="1">
              <ContentPresenter HorizontalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="#173D63"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="b" Property="BorderBrush" Value="#1B2733"/>
                <Setter TargetName="b" Property="BorderThickness" Value="2"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Secondary" TargetType="Button">
      <Setter Property="Foreground" Value="#1E4D7B"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="White" CornerRadius="6" Padding="20,10" BorderBrush="#1E4D7B" BorderThickness="1">
              <ContentPresenter HorizontalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="#E4ECF3"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="b" Property="BorderThickness" Value="2"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <StackPanel Margin="28,24,28,24">
    <TextBlock Text="Obsidian Backup" FontSize="24" FontWeight="SemiBold" Margin="0,0,0,20"/>

    <Border Background="White" CornerRadius="8" Padding="16,14" BorderBrush="#D6DEE5" BorderThickness="1">
      <StackPanel>
        <StackPanel Orientation="Horizontal">
          <Ellipse x:Name="Dot" Width="10" Height="10" Fill="#9AA5B1" Margin="0,0,8,0" VerticalAlignment="Center"/>
          <TextBlock x:Name="LastRun" FontWeight="SemiBold" TextWrapping="Wrap" MaxWidth="360"/>
        </StackPanel>
        <TextBlock x:Name="NextRun" Foreground="#6B7785" Margin="18,4,0,0"/>
        <TextBlock x:Name="KeyInfo" Foreground="#6B7785" FontSize="12" Margin="18,6,0,0"/>
      </StackPanel>
    </Border>

    <TextBlock Text="Days" FontWeight="SemiBold" Margin="0,24,0,10"/>
    <StackPanel x:Name="DaysPanel" Orientation="Horizontal"/>

    <TextBlock Text="Time" FontWeight="SemiBold" Margin="0,22,0,10"/>
    <StackPanel Orientation="Horizontal">
      <ComboBox x:Name="Hour" Width="64" FontSize="15"/>
      <TextBlock Text=":" Margin="6,0" VerticalAlignment="Center" FontSize="18"/>
      <ComboBox x:Name="Minute" Width="64" FontSize="15"/>
    </StackPanel>

    <TextBlock x:Name="Msg" Margin="0,18,0,0" TextWrapping="Wrap" MinHeight="20"/>

    <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
      <Button x:Name="Save" Content="Save schedule" Style="{StaticResource Primary}"/>
      <Button x:Name="RunNow" Content="Back up now" Style="{StaticResource Secondary}" Margin="10,0,0,0"/>
    </StackPanel>

    <StackPanel x:Name="Links" Margin="0,10,0,0"/>
    <TextBlock Margin="0,8,0,0"><Hyperlink x:Name="Restore" Foreground="#1E4D7B">Restore from a backup</Hyperlink></TextBlock>
  </StackPanel>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Parse($xaml)
if ($Preview) { $win.Title = 'Obsidian Backup (preview)' }
$c = @{}
'Dot','LastRun','NextRun','KeyInfo','DaysPanel','Hour','Minute','Msg','Save','RunNow','Links','Restore' |
    ForEach-Object { $c[$_] = $win.FindName($_) }

$Green = '#2E7D6B'; $Red = '#B23A3A'; $Amber = '#C98A1B'; $Grey = '#9AA5B1'
function Brush($hex) { (New-Object Windows.Media.BrushConverter).ConvertFromString($hex) }
function Say($text, $hex) { $c.Msg.Text = $text; $c.Msg.Foreground = Brush $hex }
function Preview-Note { Say 'Preview: nothing was saved or run.' $Amber }

# ---- day buttons ----
$dayButtons = @()
for ($i = 0; $i -lt 7; $i++) {
    $tb = New-Object Windows.Controls.Primitives.ToggleButton
    $tb.Content = $DayShort[$i]
    $tb.ToolTip = $DayNames[$i]
    $tb.Style   = $win.FindResource('Day')
    [void]$c.DaysPanel.Children.Add($tb)
    $dayButtons += $tb
}

# ---- time lists ----
0..23 | ForEach-Object { [void]$c.Hour.Items.Add($_.ToString('00')) }
0..11 | ForEach-Object { [void]$c.Minute.Items.Add(($_ * 5).ToString('00')) }

# ---- load current schedule ----
if ($Preview) { $mask = 16; $start = [datetime]'2026-01-01 17:00' }
else {
    $trig  = (Get-ScheduledTask -TaskName $TaskName).Triggers[0]
    $mask  = [int]$trig.DaysOfWeek            # Sunday=1, Monday=2, ... Saturday=64
    $start = [datetime]$trig.StartBoundary
}
for ($i = 0; $i -lt 7; $i++) { $dayButtons[$i].IsChecked = [bool]($mask -band (1 -shl $i)) }
$c.Hour.SelectedItem = $start.ToString('HH')
$mm = $start.ToString('mm')
if (-not $c.Minute.Items.Contains($mm)) { [void]$c.Minute.Items.Add($mm) }
$c.Minute.SelectedItem = $mm

# ---- which public key the backups are locked to (compare with the one you saved) ----
function Short-Key($k) { if ($k -and $k.Length -gt 16) { $k.Substring(0,10) + '...' + $k.Substring($k.Length - 6) } else { $k } }
if ($Preview) { $c.KeyInfo.Text = 'Locked to key age1qz7x4r...v8k4m' }
else {
    $rf = Join-Path $AppDir 'recipient.txt'
    if (Test-Path $rf) { $c.KeyInfo.Text = 'Locked to key ' + (Short-Key ((Get-Content $rf -Raw).Trim())) }
    else { $c.KeyInfo.Text = 'No public key found. Run setup.ps1 again.' }
}

# ---- status ----
function Refresh-Status {
    if ($Preview) {
        $c.LastRun.Text = 'Last backup succeeded: Thu 1 Oct 2026, 17:03'; $c.Dot.Fill = Brush $Green
        $c.NextRun.Text = 'Next backup: Thursday 8 Oct, 17:00'
        return
    }
    $info = Get-ScheduledTaskInfo -TaskName $TaskName
    $task = Get-ScheduledTask -TaskName $TaskName
    if ($info.NextRunTime -and $info.NextRunTime.Year -gt 2000) {
        $c.NextRun.Text = 'Next backup: ' + $info.NextRunTime.ToString('dddd d MMM, HH:mm', $Inv)
    } else { $c.NextRun.Text = '' }

    $state = 'none'; $when = $null
    if (Test-Path $LogFile) {
        $lines = Get-Content $LogFile -Encoding UTF8
        for ($k = $lines.Count - 1; $k -ge 0; $k--) {
            $l = $lines[$k]
            if ($l -match 'Backup finished OK')      { $state = 'ok'; break }
            if ($l -match 'Backup finished PARTIAL') { $state = 'partial'; break }
            if ($l -match 'FAILED:')                 { $state = 'fail'; break }
            if ($l -match 'Backup started')          { $state = 'started'; break }
        }
        if ($state -ne 'none') {
            try { $when = [datetime]::ParseExact($lines[$k].Substring(0,19), 'yyyy-MM-dd HH:mm:ss', $Inv) } catch {}
        }
    }
    $stamp = if ($when) { $when.ToString('ddd d MMM yyyy, HH:mm', $Inv) } else { '' }

    # trust the log: the task can stay "running" while a failure popup waits to be closed
    if ($task.State -eq 'Running' -and $state -eq 'started') {
        $c.LastRun.Text = 'Backup running in the background'; $c.Dot.Fill = Brush $Amber
    } elseif ($state -eq 'ok') {
        $c.LastRun.Text = "Last backup succeeded: $stamp"; $c.Dot.Fill = Brush $Green
    } elseif ($state -eq 'partial') {
        $c.LastRun.Text = "Last backup was partial: $stamp. Some files were skipped. Details in the log: $LogFile"; $c.Dot.Fill = Brush $Amber
    } elseif ($state -eq 'fail') {
        $c.LastRun.Text = "Last backup failed: $stamp. Details in the log: $LogFile"; $c.Dot.Fill = Brush $Red
    } elseif ($state -eq 'started') {
        $c.LastRun.Text = "Last backup didn't finish: $stamp. Run it again."; $c.Dot.Fill = Brush $Red
    } else {
        $c.LastRun.Text = 'No backup yet'; $c.Dot.Fill = Brush $Grey
    }
}

# ---- actions ----
$c.Save.Add_Click({
    if ($Preview) { Preview-Note; return }
    $days = @(); $short = @()
    for ($i = 0; $i -lt 7; $i++) { if ($dayButtons[$i].IsChecked) { $days += $DayNames[$i]; $short += $DayShort[$i] } }
    if ($days.Count -eq 0) { Say 'Pick at least one day.' $Red; return }
    $time = '{0}:{1}' -f $c.Hour.SelectedItem, $c.Minute.SelectedItem
    try {
        $t = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $days -At $time
        Set-ScheduledTask -TaskName $TaskName -Trigger $t -ErrorAction Stop | Out-Null
        Say ("Saved: {0} at {1}" -f ($short -join ', '), $time) $Green
        Refresh-Status
    } catch { Say "Couldn't save the schedule: $_" $Red }
})

$c.RunNow.Add_Click({
    if ($Preview) { Preview-Note; return }
    Start-ScheduledTask -TaskName $TaskName
    Say "Backup started in the background. You can keep working; the status above updates when it's done." $Green
    Start-Sleep -Milliseconds 800
    Refresh-Status
})

function Open-Folder($path) {
    if ($Preview) { Preview-Note; return }
    if (Test-Path $path) { Start-Process explorer.exe "`"$path`"" }
    else { Say "This folder doesn't exist yet. The first backup creates it: $path" $Amber }
}
# one link per destination from config.json
foreach ($d in $Destinations) {
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Margin = '0,8,0,0'
    $h = New-Object Windows.Documents.Hyperlink
    [void]$h.Inlines.Add("Backups in $($d.name)")
    $h.Foreground = Brush '#1E4D7B'
    $h.Tag = $d.path
    $h.Add_Click({ Open-Folder $this.Tag })
    [void]$tb.Inlines.Add($h)
    [void]$c.Links.Children.Add($tb)
}

$c.Restore.Add_Click({
    if ($Preview) { Preview-Note; return }
    $r = Join-Path $AppDir 'restore.ps1'
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$r`""
})

# refresh status every 5 seconds while the window is open
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(5)
$timer.Add_Tick({ Refresh-Status })
if (-not $Preview) { $timer.Start() }

Refresh-Status
[void]$win.ShowDialog()
