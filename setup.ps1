# setup.ps1 - run ONCE (safe to run again later).
# 1. installs the scripts and age into a permanent folder
# 2. creates your backup key pair: the PUBLIC key stays on this computer (can only lock),
#    the PRIVATE key is shown once for your password manager and is never written to disk
# 3. creates the scheduled task and a Start-menu shortcut to the backup window

$AppDir    = Join-Path $env:LOCALAPPDATA 'ObsidianBackup'
$Script    = Join-Path $AppDir 'obsidian-backup.ps1'
$Ui        = Join-Path $AppDir 'backup-ui.ps1'
$Recipient = Join-Path $AppDir 'recipient.txt'
$TaskName  = 'Obsidian Backup'

function Stop-Setup($msg) { Write-Host $msg -ForegroundColor Red; Read-Host 'Press Enter to close'; exit 1 }
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null

# --- 1. prerequisites ---
if (-not (Test-Path 'C:\Program Files\7-Zip\7z.exe')) { Stop-Setup '7-Zip is not installed (https://www.7-zip.org, 64-bit).' }

foreach ($exe in 'age.exe', 'age-keygen.exe') {
    $found = $null
    $local = Join-Path $PSScriptRoot $exe
    if (Test-Path $local) { $found = $local }
    elseif (Get-Command $exe -ErrorAction SilentlyContinue) { $found = (Get-Command $exe).Source }
    if (-not $found) { Stop-Setup "$exe not found. Install age (winget install FiloSottile.age) or put $exe next to setup.ps1." }
    Write-Host "Using $exe from: $found"
    if ($found -ne (Join-Path $AppDir $exe)) { Copy-Item $found (Join-Path $AppDir $exe) -Force }
}

# your settings: copy config.example.json to config.json and edit the paths first
$cfgSrc = Join-Path $PSScriptRoot 'config.json'
if (-not (Test-Path $cfgSrc)) { Stop-Setup 'config.json not found. Copy config.example.json to config.json, edit the paths, and run setup again.' }
try { $cfg = Get-Content $cfgSrc -Raw | ConvertFrom-Json } catch { Stop-Setup "config.json is not valid JSON: $_" }
if (-not $cfg.source -or -not (Test-Path $cfg.source)) { Stop-Setup "Source folder in config.json not found: $($cfg.source)" }
if (@($cfg.destinations).Count -eq 0) { Stop-Setup 'config.json needs at least one destination.' }
function Norm($p) { ([IO.Path]::GetFullPath($p)).TrimEnd('\','/') + '\' }
foreach ($d in @($cfg.destinations)) {
    if (-not $d.path) { Stop-Setup 'Every destination in config.json needs a "path".' }
    if ((Norm $d.path).StartsWith((Norm $cfg.source), [StringComparison]::OrdinalIgnoreCase)) {
        Stop-Setup "Destination $($d.path) is inside the source folder. Each backup would include the previous ones. Choose a folder outside it."
    }
}
Copy-Item $cfgSrc (Join-Path $AppDir 'config.json') -Force

foreach ($f in 'obsidian-backup.ps1', 'backup-ui.ps1', 'restore.ps1') {
    $src = Join-Path $PSScriptRoot $f
    if (-not (Test-Path $src)) { Stop-Setup "Missing $f - keep all files in the same folder." }
    Copy-Item $src (Join-Path $AppDir $f) -Force
}
Write-Host "Installed in: $AppDir" -ForegroundColor Green

# --- 2. key pair ---
$makeKey = $true
if (Test-Path $Recipient) {
    $ans = Read-Host 'A backup key already exists. Keep it? (y = keep / n = create a new one)'
    if ($ans -eq 'y') { $makeKey = $false }
    else { Write-Host 'Note: older backups still need the OLD private key. Keep it in your password manager.' -ForegroundColor Yellow }
}
if ($makeKey) {
    $lines  = & (Join-Path $AppDir 'age-keygen.exe') 2>$null      # printed to memory only, never to a file
    $secret = ($lines | Where-Object { $_ -like 'AGE-SECRET-KEY-*' } | Select-Object -First 1)
    $public = (($lines | Where-Object { $_ -like '# public key:*' } | Select-Object -First 1) -replace '^# public key:\s*', '')
    if (-not $secret -or $public -notlike 'age1*') { Stop-Setup 'Key generation failed.' }

    Write-Host ''
    Write-Host '=================== YOUR PRIVATE KEY ===================' -ForegroundColor Cyan
    Write-Host 'This is the ONLY way to open your backups. It will not be shown again.'
    Write-Host 'Save it now in your password manager (select it with the mouse, then Ctrl+C).'
    Write-Host ''
    Write-Host $secret -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'If Windows clipboard history is on, clear it afterwards: Win+V > Clear all.' -ForegroundColor DarkGray
    Write-Host '========================================================' -ForegroundColor Cyan

    $tries = 0
    do {
        $tries++
        $s = Read-Host 'Paste the key back from your password manager to confirm it was saved' -AsSecureString
        $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
        $back = ([Runtime.InteropServices.Marshal]::PtrToStringBSTR($b)).Trim()
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)
        $ok = ($back -ceq $secret)
        if (-not $ok) { Write-Host 'That does not match. Check what you saved and try again.' -ForegroundColor Yellow }
    } until ($ok -or $tries -ge 5)
    $back = $null
    if (-not $ok) { $secret = $null; Clear-Host; Stop-Setup 'Key not confirmed - nothing was saved. Run setup again.' }

    $secret = $null; $lines = $null
    Clear-Host
    Set-Content -Path $Recipient -Value $public -Encoding ASCII
    Write-Host 'Key confirmed. Only the public key was stored on this computer.' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Your PUBLIC key (not secret). Save it next to the private key, e.g. in the notes field:' -ForegroundColor Cyan
    Write-Host $public -ForegroundColor White
    Write-Host 'The backup window shows the start and end of this key. If they ever differ, someone replaced it.' -ForegroundColor DarkGray
    Write-Host ''
}

# remove leftovers from the earlier password-based version, if any
$oldPw = Join-Path $AppDir 'pw.dat'; if (Test-Path $oldPw) { Remove-Item $oldPw -Force }

# --- 3. scheduled task (default Thursday 17:00 - change it in the window) ---
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
$trigger  = if ($existing) { $existing.Triggers } else { New-ScheduledTaskTrigger -Weekly -DaysOfWeek Thursday -At '17:00' }
$action   = New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Script`""
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -Priority 7 `
            -ExecutionTimeLimit (New-TimeSpan -Hours 2) -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
    -Description 'Encrypted (age, public key) backup of an Obsidian folder' -Force | Out-Null
Write-Host 'Scheduled task ready.' -ForegroundColor Green

# --- 4. Start-menu shortcut (nothing on the desktop) ---
$lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path ([Environment]::GetFolderPath('Programs')) 'Obsidian Backup.lnk'))
$lnk.TargetPath = 'powershell.exe'
$lnk.Arguments  = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Ui`""
$lnk.WorkingDirectory = $AppDir
$lnk.Save()
Write-Host 'Start menu: press the Windows key and type "Obsidian Backup".' -ForegroundColor Green

Write-Host 'Opening the backup window: pick days and time, then press the "backup now" button for a first test.'
Write-Host ''
Write-Host 'Done. CLOSE THIS WINDOW NOW - its scroll-back history may still hold your private key.' -ForegroundColor Yellow
Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Ui`""
