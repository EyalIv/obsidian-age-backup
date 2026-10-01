# obsidian-backup.ps1
# Weekly backup of the Obsidian folder, encrypted with a PUBLIC key (age).
# This computer can lock backups but can never open them: the private key exists
# only in your password manager. No passwords on the command line, none stored here.
# No network calls of its own; Google Drive / OneDrive apps upload the result.

# ---------------- settings ----------------
# Paths and retention come from config.json (installed next to this script by setup.ps1).
$SevenZip   = 'C:\Program Files\7-Zip\7z.exe'
$AppDir     = Join-Path $env:LOCALAPPDATA 'ObsidianBackup'
$Age        = Join-Path $AppDir 'age.exe'
$Recipient  = Join-Path $AppDir 'recipient.txt'   # public key only - cannot decrypt
$LogFile    = Join-Path $AppDir 'backup.log'
$ConfigFile = Join-Path $AppDir 'config.json'
# ------------------------------------------

[System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = 'BelowNormal'

function Write-Log($msg) {
    Add-Content -Path $LogFile -Value ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -Encoding UTF8
}
function Popup($msg, $icon) {
    try { (New-Object -ComObject WScript.Shell).Popup($msg, 0, 'Obsidian Backup', $icon) | Out-Null } catch {}
}
$stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
$plain = Join-Path $env:TEMP "Obsidian-$stamp.7z"
$name  = "Obsidian-$stamp.7z.age"
$enc   = Join-Path $env:TEMP $name
function Cleanup { foreach ($f in $plain, $enc) { if (Test-Path $f) { Remove-Item $f -Force } } }
function Fail($msg) {
    Cleanup
    Write-Log "FAILED: $msg"
    Popup "Obsidian backup failed:`n$msg`n`nLog: $LogFile" 16
    exit 1
}

New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
Write-Log 'Backup started'

if (-not (Test-Path $ConfigFile)) { Fail "config.json missing in $AppDir. Run setup.ps1 again." }
try {
    $cfg          = Get-Content $ConfigFile -Raw | ConvertFrom-Json
    $Source       = $cfg.source
    $Destinations = @($cfg.destinations)
    $KeepDays     = if ($cfg.keepDays) { [int]$cfg.keepDays } else { 56 }
    $KeepMin      = if ($cfg.keepMin)  { [int]$cfg.keepMin }  else { 3 }
} catch { Fail "config.json could not be read: $_" }
if (-not $Source -or $Destinations.Count -eq 0) { Fail 'config.json needs a source and at least one destination' }

if (-not (Test-Path $SevenZip))  { Fail "7-Zip not found at $SevenZip" }
if (-not (Test-Path $Age))       { Fail "age.exe not found in $AppDir. Run setup.ps1 again." }
if (-not (Test-Path $Recipient)) { Fail "Public key missing. Run setup.ps1 again." }
if (-not (Test-Path $Source))    { Fail "Source folder not reachable: $Source (is Google Drive running?)" }

# a destination inside the source would back up previous backups, doubling size every run
function Norm($p) { ([IO.Path]::GetFullPath($p)).TrimEnd('\','/') + '\' }
foreach ($d in $Destinations) {
    if ((Norm $d.path).StartsWith((Norm $Source), [StringComparison]::OrdinalIgnoreCase)) {
        Fail "Destination is inside the source folder: $($d.path). Choose a folder outside it."
    }
}

# 1. compress (no password here - encryption happens in step 3 with the public key)
#    The temporary archive is no more exposed than the vault itself, which sits on this disk anyway.
$out  = & $SevenZip a -t7z -mx1 -mmt=2 '-xr!.trash' -bso0 -bsp0 $plain "$Source\*" 2>&1
$code = $LASTEXITCODE
if ($code -gt 1) {
    $out | ForEach-Object { "$_" } | Where-Object { $_ -match '\S' } | Select-Object -First 20 | ForEach-Object { Write-Log "  7z: $_" }
    Fail "7-Zip error (code $code)"
}
$partial = ($code -eq 1)
if ($partial) {
    $out | ForEach-Object { "$_" } | Where-Object { $_ -match '\S' } | Select-Object -First 30 | ForEach-Object { Write-Log "  skipped: $_" }
}

# 2. verify the archive is readable
& $SevenZip t -bso0 -bsp0 $plain | Out-Null
if ($LASTEXITCODE -ne 0) { Fail 'Archive integrity test failed' }

# 3. encrypt with the public key, then remove the unencrypted temp file
& $Age -R $Recipient -o $enc $plain
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $enc)) { Fail 'Encryption with age failed' }
Remove-Item $plain -Force

# 4. sanity check: the result must be an age file
$fs = [IO.File]::OpenRead($enc); $buf = New-Object byte[] 21; [void]$fs.Read($buf, 0, 21); $fs.Close()
if ([Text.Encoding]::ASCII.GetString($buf) -ne 'age-encryption.org/v1') { Fail 'Encrypted file has an unexpected format' }

$sizeMB = [math]::Round((Get-Item $enc).Length / 1MB)
Write-Log "Encrypted archive ready: $name ($sizeMB MB)"

# 5. copy to each destination; retention by AGE, never below $KeepMin copies
$ok = 0
foreach ($d in $Destinations) {
    $dest = $d.path
    try {
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        $target = Join-Path $dest $name
        Copy-Item $enc $target -Force -ErrorAction Stop
        if ((Get-Item $target).Length -ne (Get-Item $enc).Length) {
            Remove-Item $target -Force -ErrorAction SilentlyContinue
            throw 'copied file size does not match (incomplete copy)'
        }
        $cutoff = (Get-Date).AddDays(-$KeepDays)
        Get-ChildItem $dest -Filter 'Obsidian-*.7z.age' |
            Sort-Object LastWriteTime -Descending |
            Select-Object -Skip $KeepMin |
            Where-Object { $_.LastWriteTime -lt $cutoff } |
            ForEach-Object { Remove-Item $_.FullName -Force; Write-Log "Removed old copy: $($_.FullName)" }
        Write-Log "Copied to: $dest"
        $ok++
    } catch { Write-Log "Copy failed for $dest : $_" }
}
Cleanup

if ($ok -eq 0) { Fail 'Could not copy the backup to any destination' }
if ($ok -lt $Destinations.Count) { Fail "Backup saved to only $ok of $($Destinations.Count) destinations" }

$lines = Get-Content $LogFile
if ($lines.Count -gt 400) { $lines | Select-Object -Last 400 | Set-Content $LogFile -Encoding UTF8 }

if ($partial) {
    Write-Log 'Backup finished PARTIAL (some files were skipped - see lines above)'
    Popup "Obsidian backup finished, but some files were skipped.`nDetails in: $LogFile" 48
    exit 2
}
Write-Log 'Backup finished OK'
exit 0
