param([switch]$SkipSdk,[switch]$SkipTests)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$taskTools=Join-Path $taskRoot '.tools'
New-Item -ItemType Directory -Force $taskTools | Out-Null
$taskLocal=Join-Path $taskRoot '.local'
New-Item -ItemType Directory -Force $taskLocal | Out-Null
function Get-SpinLabDownload([string]$Url,[string]$Destination){
  if(-not(Test-Path -LiteralPath $Destination)){Invoke-WebRequest -Uri $Url -OutFile $Destination}
}
$taskGodot=Join-Path $taskTools 'godot\Godot_v4.7.2-stable_win64.exe'
$taskGodotZip=Join-Path $taskTools 'godot.zip'
if(-not(Test-Path -LiteralPath $taskGodot) -or -not(Test-Path -LiteralPath $taskGodot.Replace('.exe','_console.exe'))){
  Get-SpinLabDownload 'https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip' $taskGodotZip
  Expand-Archive -LiteralPath $taskGodotZip -DestinationPath (Join-Path $taskTools 'godot') -Force
}
$taskTemplateZip=Join-Path $taskTools 'godot-templates.tpz'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$taskTemplateRoot=Join-Path $env:APPDATA 'Godot\export_templates\4.7.2.stable'
New-Item -ItemType Directory -Force $taskTemplateRoot | Out-Null
$taskRequiredTemplates=@('android_debug.apk','android_release.apk','android_source.zip','version.txt')
$taskMissingTemplates=@($taskRequiredTemplates | Where-Object {-not(Test-Path -LiteralPath (Join-Path $taskTemplateRoot $_))})
if($taskMissingTemplates.Count -gt 0){
  Get-SpinLabDownload 'https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz' $taskTemplateZip
  $taskArchive=[IO.Compression.ZipFile]::OpenRead($taskTemplateZip)
  try{
    foreach($taskEntry in $taskArchive.Entries){
      if($taskEntry.Name -in $taskMissingTemplates){
        [IO.Compression.ZipFileExtensions]::ExtractToFile($taskEntry,(Join-Path $taskTemplateRoot $taskEntry.Name),$true)
      }
    }
  }finally{
    $taskArchive.Dispose()
  }
}
$taskJdkRoot=Join-Path $taskTools 'jdk'
$taskJava=Get-ChildItem -LiteralPath $taskJdkRoot -Directory -ErrorAction SilentlyContinue | Where-Object {Test-Path -LiteralPath (Join-Path $_.FullName 'bin\keytool.exe')} | Select-Object -First 1
if(-not $taskJava){
  Get-SpinLabDownload 'https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse' (Join-Path $taskTools 'jdk17.zip')
  Expand-Archive -LiteralPath (Join-Path $taskTools 'jdk17.zip') -DestinationPath $taskJdkRoot -Force
}
$taskJdk=(Get-ChildItem -LiteralPath $taskJdkRoot -Directory | Where-Object {Test-Path -LiteralPath (Join-Path $_.FullName 'bin\keytool.exe')} | Select-Object -First 1).FullName
if(-not $taskJdk){throw 'OpenJDK 17 could not be found after extraction.'}
$env:JAVA_HOME=$taskJdk
$taskSdk=Join-Path $taskTools 'android-sdk'
New-Item -ItemType Directory -Force $taskSdk | Out-Null
if(-not $SkipSdk){
  $taskAndroid=Join-Path $taskSdk 'cmdline-tools\latest\bin\android.exe'
  if(-not(Test-Path -LiteralPath $taskAndroid)){
    Get-SpinLabDownload 'https://dl.google.com/android/repository/commandlinetools-win-16111833_latest.zip' (Join-Path $taskTools 'android-cmdline.zip')
    Expand-Archive -LiteralPath (Join-Path $taskTools 'android-cmdline.zip') -DestinationPath (Join-Path $taskTools 'android-cmdline') -Force
    New-Item -ItemType Directory -Force (Join-Path $taskSdk 'cmdline-tools\latest') | Out-Null
    Copy-Item -Path (Join-Path $taskTools 'android-cmdline\cmdline-tools\*') -Destination (Join-Path $taskSdk 'cmdline-tools\latest') -Recurse -Force
  }
  $taskSdkPackages=[ordered]@{'platform-tools'='platform-tools\adb.exe';'platforms;android-36'='platforms\android-36\android.jar';'build-tools;36.1.0'='build-tools\36.1.0\aapt2.exe';'ndk;29.0.14206865'='ndk\29.0.14206865\source.properties'}
  foreach($taskPackage in $taskSdkPackages.GetEnumerator()){
    if(-not(Test-Path -LiteralPath (Join-Path $taskSdk $taskPackage.Value))){
      & $taskAndroid --no-metrics --sdk=$taskSdk sdk install $taskPackage.Key
      if($LASTEXITCODE -ne 0){throw "Android SDK setup failed: $($taskPackage.Key)"}
    }
  }
}
if(-not(Test-Path -LiteralPath (Join-Path $taskRoot 'native\addons\godotopenxrvendors\plugin.gdextension'))){
  Get-SpinLabDownload 'https://github.com/GodotVR/godot_openxr_vendors/releases/download/5.1.0-stable/godotopenxrvendorsaddon.zip' (Join-Path $taskTools 'vendors.zip')
  Expand-Archive -LiteralPath (Join-Path $taskTools 'vendors.zip') -DestinationPath (Join-Path $taskTools 'vendors') -Force
  Copy-Item -Path (Join-Path $taskTools 'vendors\asset\addons') -Destination (Join-Path $taskRoot 'native') -Recurse -Force
}
# The matching source archive is the Android Gradle build template. Installing
# it separately avoids the console-wrapper hang observed during Android export.
$taskAndroidRoot=Join-Path $taskRoot 'native\android'
$taskBuildRoot=Join-Path $taskAndroidRoot 'build'
$taskBuildMarker=Join-Path $taskAndroidRoot '.build_version'
$taskBuildVersion='4.7.2.stable'
if(Test-Path -LiteralPath $taskBuildMarker){
  if((Get-Content -LiteralPath $taskBuildMarker -Raw).Trim() -ne $taskBuildVersion){throw 'Existing Android build template uses another Godot version. Preserve any custom changes and replace native/android deliberately before rerunning setup.'}
}elseif(Test-Path -LiteralPath (Join-Path $taskBuildRoot 'build.gradle')){
  throw 'Existing Android build template has no version marker. Preserve any custom changes and replace native/android deliberately before rerunning setup.'
}
$taskManifest=Join-Path $taskBuildRoot 'src\main\AndroidManifest.xml'
if(-not(Test-Path -LiteralPath $taskManifest) -or -not(Test-Path -LiteralPath (Join-Path $taskBuildRoot 'gradlew.bat'))){
  New-Item -ItemType Directory -Force $taskBuildRoot | Out-Null
  Expand-Archive -LiteralPath (Join-Path $taskTemplateRoot 'android_source.zip') -DestinationPath $taskBuildRoot -Force
  [IO.File]::WriteAllText($taskBuildMarker,$taskBuildVersion,[Text.UTF8Encoding]::new($false))
}
$taskImportStdout=Join-Path $taskLocal 'native-import.stdout.log'
$taskImportStderr=Join-Path $taskLocal 'native-import.stderr.log'
$taskImportArguments='--headless --xr-mode off --path "'+(Join-Path $taskRoot 'native')+'" --editor --import --quit'
$taskImport=Start-Process -FilePath $taskGodot -WindowStyle Hidden -ArgumentList $taskImportArguments -RedirectStandardOutput $taskImportStdout -RedirectStandardError $taskImportStderr -Wait -PassThru
Get-Content -LiteralPath $taskImportStdout
Get-Content -LiteralPath $taskImportStderr
if($taskImport.ExitCode -ne 0){throw 'Godot asset import failed. Review the import diagnostics above.'}
$taskKey=Join-Path $taskLocal 'spinlab-debug.keystore'
if(-not(Test-Path -LiteralPath $taskKey)){
  & (Join-Path $taskJdk 'bin\keytool.exe') -genkeypair -keystore $taskKey -alias androiddebugkey -storepass android -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname 'CN=SpinLab Development,O=Walter Teitelbaum,C=US'
  if($LASTEXITCODE -ne 0){throw 'Development signing-key creation failed.'}
}
$taskSettings=Join-Path $env:APPDATA 'Godot\editor_settings-4.7.tres'
$taskText=Get-Content -LiteralPath $taskSettings -Raw
$taskPairs=@{'export/android/android_sdk_path'=$taskSdk;'export/android/java_sdk_path'=$taskJdk;'export/android/debug_keystore'=$taskKey;'export/android/debug_keystore_user'='androiddebugkey';'export/android/debug_keystore_pass'='android'}
foreach($taskPair in $taskPairs.GetEnumerator()){
  $taskLine=$taskPair.Key+' = "'+$taskPair.Value.Replace('\','/')+'"'
  $taskRegex='(?m)^'+[regex]::Escape($taskPair.Key)+' = .*'
  if([regex]::IsMatch($taskText,$taskRegex)){$taskText=[regex]::Replace($taskText,$taskRegex,$taskLine)}else{$taskText+="`n$taskLine"}
}
[IO.File]::WriteAllText($taskSettings,$taskText,[Text.UTF8Encoding]::new($false))
$env:ANDROID_HOME=$taskSdk
$env:ANDROID_SDK_ROOT=$taskSdk
New-Item -ItemType Directory -Force (Join-Path $taskRoot 'artifacts') | Out-Null
# Build-APK owns the supported GodotApp exported=true manifest patch, test gate,
# and GUI-engine headless export. Keep one final export path for fresh/rebuilds.
& (Join-Path $PSScriptRoot 'Build-APK.ps1') -SkipTests:$SkipTests
Write-Output 'Native toolchain prepared. Keep .local/spinlab-debug.keystore for compatible updates; it is not committed.'
