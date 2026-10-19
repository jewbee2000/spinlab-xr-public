param([switch]$SkipTests)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$taskGodot=Join-Path $taskRoot '.tools\godot\Godot_v4.7.2-stable_win64_console.exe'
$taskJdk=(Get-ChildItem -LiteralPath (Join-Path $taskRoot '.tools\jdk') -Directory | Select-Object -First 1).FullName
$taskSdk=Join-Path $taskRoot '.tools\android-sdk'
if(-not (Test-Path -LiteralPath $taskGodot)){throw 'Local Godot toolchain missing. Follow docs/APK_SETUP.md.'}
$env:JAVA_HOME=$taskJdk
$env:ANDROID_HOME=$taskSdk
$env:ANDROID_SDK_ROOT=$taskSdk
# Meta's shell resolves the actual VR activity rather than the generic Android
# launcher alias. Export that activity in our own Gradle base manifest.
$taskManifest=Join-Path $taskRoot 'native\android\build\src\main\AndroidManifest.xml'
if(-not(Test-Path -LiteralPath $taskManifest)){throw 'Install the Android build template first with Setup-NativeToolchain.ps1.'}
[IO.File]::WriteAllText((Join-Path $taskRoot 'native\android\.gdignore'),'')
# Recover generated resource sidecars from older setups that omitted .gdignore.
$taskResourceRoot=[IO.Path]::GetFullPath((Join-Path $taskRoot 'native\android\build\res'))
if(Test-Path -LiteralPath $taskResourceRoot){
  foreach($taskSidecar in Get-ChildItem -LiteralPath $taskResourceRoot -Filter '*.import' -File -Recurse){
    if(-not $taskSidecar.FullName.StartsWith($taskResourceRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected generated-resource path.'}
    Remove-Item -LiteralPath $taskSidecar.FullName
  }
}
[xml]$taskManifestXml=Get-Content -LiteralPath $taskManifest -Raw
$taskAndroidNamespace='http://schemas.android.com/apk/res/android'
$taskMainActivity=@($taskManifestXml.manifest.application.activity) | Where-Object {$_.GetAttribute('name',$taskAndroidNamespace) -eq '.GodotApp'}
if(-not $taskMainActivity){throw 'Unexpected Godot Android manifest: main activity not found. No export attempted.'}
$null=$taskMainActivity.SetAttribute('exported',$taskAndroidNamespace,'true')
$taskManifestXml.Save($taskManifest)
if(-not $SkipTests){
  & $taskGodot --headless --xr-mode off --path (Join-Path $taskRoot 'native') --script res://tests/test_science.gd
  if($LASTEXITCODE -ne 0){throw 'Native science tests failed.'}
  & $taskGodot --headless --xr-mode off --path (Join-Path $taskRoot 'native') --script res://tests/test_app.gd
  if($LASTEXITCODE -ne 0){throw 'Native app workflow tests failed.'}
  foreach($taskTest in @('test_direct_interaction.gd','test_hand_visual.gd','test_hands_app.gd','test_tutorial.gd','test_tutorial_panel.gd','test_tutorial_app.gd','test_navigation.gd','test_workcell_geometry.gd','test_operator_ui.gd')){
    & $taskGodot --headless --xr-mode off --path (Join-Path $taskRoot 'native') --script "res://tests/$taskTest"
    if($LASTEXITCODE -ne 0){throw "Native direct-hand tests failed: $taskTest"}
  }
}
$taskEngine=$taskGodot.Replace('_console.exe','.exe')
$taskStdout=Join-Path $taskRoot '.local\native-export.stdout.log'
$taskStderr=Join-Path $taskRoot '.local\native-export.stderr.log'
$taskArguments='--headless --xr-mode off --path "'+(Join-Path $taskRoot 'native')+'" --export-debug "Quest 2" "'+(Join-Path $taskRoot 'artifacts\SpinLabXR-v0.5.0.apk')+'" --quit'
$taskExport=Start-Process -FilePath $taskEngine -WindowStyle Hidden -ArgumentList $taskArguments -RedirectStandardOutput $taskStdout -RedirectStandardError $taskStderr -Wait -PassThru
Get-Content -LiteralPath $taskStdout
Get-Content -LiteralPath $taskStderr
if($taskExport.ExitCode -ne 0){throw 'APK export failed. Check Godot and Gradle diagnostics above.'}
Get-FileHash -LiteralPath (Join-Path $taskRoot 'artifacts\SpinLabXR-v0.5.0.apk') -Algorithm SHA256
