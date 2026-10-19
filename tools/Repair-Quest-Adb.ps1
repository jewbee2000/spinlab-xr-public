param([switch]$Apply)
$ErrorActionPreference='Stop'
# Microsoft's WinUSB interface registration, using the ADB GUID declared in
# Meta's signed android_winusb.inf. No driver binaries or signing settings change.
# https://learn.microsoft.com/windows-hardware/drivers/usbcon/winusb-installation
$taskRoot=Split-Path -Parent $PSScriptRoot
$taskLog=Join-Path $taskRoot '.local\quest-adb-repair.log'
New-Item -ItemType Directory -Force (Split-Path -Parent $taskLog) | Out-Null
function Write-RepairLog([string]$Message){$Message | Tee-Object -FilePath $taskLog -Append}
$taskGuid='{F72FE0D4-CBCB-407D-8814-9ED673D0DD6B}'
$taskCandidates=@()
foreach($taskDevice in (Get-PnpDevice -PresentOnly | Where-Object InstanceId -match '^USB\\VID_2833&PID_[0-9A-F]{4}&MI_[0-9A-F]{2}\\')){
  $taskCompatible=(Get-PnpDeviceProperty -InstanceId $taskDevice.InstanceId -KeyName 'DEVPKEY_Device_CompatibleIds' -ErrorAction SilentlyContinue).Data
  $taskService=(Get-PnpDeviceProperty -InstanceId $taskDevice.InstanceId -KeyName 'DEVPKEY_Device_Service' -ErrorAction SilentlyContinue).Data
  if($taskCompatible -contains 'USB\Class_ff&SubClass_42&Prot_01' -and $taskService -eq 'WINUSB'){$taskCandidates+=$taskDevice}
}
if($taskCandidates.Count -ne 1){throw "Expected one connected Meta WinUSB ADB interface; found $($taskCandidates.Count). No changes made."}
$taskDevice=$taskCandidates[0]
$taskKey='HKLM:\SYSTEM\CurrentControlSet\Enum\'+$taskDevice.InstanceId+'\Device Parameters'
$taskProperties=Get-ItemProperty -LiteralPath $taskKey
$taskExisting=@($taskProperties.DeviceInterfaceGUIDs) | Where-Object {$_}
Write-RepairLog "Matched only the connected Meta ADB protocol interface: $($taskDevice.FriendlyName)."
Write-RepairLog "Existing discovery GUIDs: $($taskExisting -join ', ')"
if(-not $Apply){Write-RepairLog 'Audit only. Use -Apply in an administrator PowerShell to register ADB discovery and restart this interface.';exit 0}
$taskPrincipal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $taskPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Windows administrator access is required for this device registration.'}
if($taskExisting -contains $taskGuid){Write-RepairLog 'ADB discovery is already registered; no registry change required.';exit 0}
$taskBackup=[pscustomobject]@{deviceInstanceId=$taskDevice.InstanceId;registryPath=$taskKey;hadDeviceInterfaceGUIDs=($taskProperties.PSObject.Properties.Name -contains 'DeviceInterfaceGUIDs');previousDeviceInterfaceGUIDs=@($taskExisting);addedGuid=$taskGuid;time=(Get-Date).ToString('o')}
$taskBackupPath=Join-Path $taskRoot ('.local\quest-adb-registration-backup-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json')
$taskBackup | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $taskBackupPath -Encoding UTF8
New-ItemProperty -LiteralPath $taskKey -Name DeviceInterfaceGUIDs -PropertyType MultiString -Value @($taskExisting+$taskGuid) -Force | Out-Null
Write-RepairLog 'Registered the standard ADB discovery GUID, preserving any existing values. Backup saved in .local.'
& pnputil.exe /restart-device $taskDevice.InstanceId | Tee-Object -FilePath $taskLog -Append
if($LASTEXITCODE -ne 0){Write-RepairLog 'Windows could not restart the interface. Reconnect the USB cable to apply its registration.'}
Write-RepairLog 'Registration finished. Recheck adb devices and approve USB debugging inside the headset if requested.'
