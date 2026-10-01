# restore.ps1 - decrypt an Obsidian backup. You will need the private key from your password manager.
Add-Type -AssemblyName System.Windows.Forms

$AppDir       = Join-Path $env:LOCALAPPDATA 'ObsidianBackup'
$Age          = Join-Path $AppDir 'age.exe'
if (-not (Test-Path $Age)) { $Age = Join-Path $PSScriptRoot 'age.exe' }
$BackupFolder = $null
try { $BackupFolder = @((Get-Content (Join-Path $AppDir 'config.json') -Raw | ConvertFrom-Json).destinations)[0].path } catch {}
$OutDir       = Join-Path $env:USERPROFILE 'Downloads'

if (-not (Test-Path $Age)) { Write-Host 'age.exe not found.' -ForegroundColor Red; Read-Host 'Press Enter to close'; exit 1 }

$dlg = New-Object System.Windows.Forms.OpenFileDialog
$dlg.Title  = 'Choose the backup to restore'
$dlg.Filter = 'Obsidian backup (*.age)|*.age'
if ($BackupFolder -and (Test-Path $BackupFolder)) { $dlg.InitialDirectory = $BackupFolder }
if ($dlg.ShowDialog() -ne 'OK') { exit 0 }

$target = Join-Path $OutDir ([IO.Path]::GetFileNameWithoutExtension($dlg.FileName))   # ...7z
$sec = Read-Host 'Paste your private key (starts with AGE-SECRET-KEY-)' -AsSecureString
$b   = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
$key = ([Runtime.InteropServices.Marshal]::PtrToStringBSTR($b)).Trim()
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)
if ($key -notmatch '^AGE-SECRET-KEY-1[0-9A-Z]+$') { Write-Host 'That is not a valid age private key.' -ForegroundColor Red; Read-Host 'Press Enter to close'; exit 1 }

# age needs the key as a file: written to your private TEMP folder for a few seconds, then deleted
$keyFile = Join-Path $env:TEMP ([guid]::NewGuid().ToString() + '.key')
try {
    Set-Content -Path $keyFile -Value $key -Encoding ASCII
    $key = $null
    & $Age -d -i $keyFile -o $target $dlg.FileName
    $code = $LASTEXITCODE
} finally { if (Test-Path $keyFile) { Remove-Item $keyFile -Force } }

if ($code -ne 0) { Write-Host 'Decryption failed - wrong key or damaged file.' -ForegroundColor Red; Read-Host 'Press Enter to close'; exit 1 }
Write-Host "Restored to: $target" -ForegroundColor Green
Write-Host 'Opening it in 7-Zip. Extract what you need, then delete this file when done.'
Start-Process 'C:\Program Files\7-Zip\7zFM.exe' "`"$target`""
Read-Host 'Press Enter to close'
