param([string]$Serial)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$taskAdb=Join-Path $taskRoot '.tools\platform-tools\adb.exe'
if(-not (Test-Path -LiteralPath $taskAdb)){$taskAdb=Join-Path $taskRoot '.tools\android-sdk\platform-tools\adb.exe'}
if(-not (Test-Path -LiteralPath $taskAdb)){$taskAdb=(Get-Command adb -ErrorAction Stop).Source}
$taskSelect=@()
if($Serial){$taskSelect=@('-s',$Serial)}
& $taskAdb @taskSelect install -r (Join-Path $taskRoot 'artifacts\SpinLabXR-v0.6.0.apk')
if($LASTEXITCODE -ne 0){throw 'Install failed. Enable Developer Mode and approve USB debugging; see docs/APK_SETUP.md.'}
& $taskAdb @taskSelect shell am start -a android.intent.action.MAIN -c com.oculus.intent.category.VR -n us.teitelbaum.spinlabxr/com.godot.game.GodotAppLauncher
if($LASTEXITCODE -ne 0){Write-Warning 'Select SpinLab XR under Apps > Unknown Sources in the headset.'}
