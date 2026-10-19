param([string]$AdbPath = 'adb', [string]$Serial, [int]$Port = 8080)
$ErrorActionPreference = 'Stop'
$taskAdb = Get-Command $AdbPath -ErrorAction SilentlyContinue
if (-not $taskAdb -and $AdbPath -eq 'adb') {
  $taskLocalAdb = Join-Path (Split-Path -Parent $PSScriptRoot) '.tools\platform-tools\adb.exe'
  $taskAdb = Get-Command $taskLocalAdb -ErrorAction SilentlyContinue
}
if (-not $taskAdb) { throw 'ADB not found. Pass -AdbPath C:\path\to\platform-tools\adb.exe. See docs/INSTALL_QUEST2.md.' }
$taskSelect = @()
if ($Serial) { $taskSelect = @('-s', $Serial) }
& $taskAdb.Source devices
& $taskAdb.Source @taskSelect reverse "tcp:$Port" "tcp:$Port"
if ($LASTEXITCODE -ne 0) { throw 'USB reverse failed. Check developer mode and accept USB debugging inside the headset; if multiple devices, supply -Serial.' }
& $taskAdb.Source @taskSelect shell am start -a android.intent.action.VIEW -d "http://localhost:$Port"
if ($LASTEXITCODE -ne 0) { Write-Warning "Open http://localhost:$Port manually in Quest Browser." }
Write-Host "Quest tunnel ready. Keep the USB cable attached and the SpinLab server running on port $Port."
