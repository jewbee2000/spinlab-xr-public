param([string]$Serial)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$taskAdb=Join-Path $taskRoot '.tools\platform-tools\adb.exe'
if(-not (Test-Path -LiteralPath $taskAdb)){$taskAdb=Join-Path $taskRoot '.tools\android-sdk\platform-tools\adb.exe'}
if(-not (Test-Path -LiteralPath $taskAdb)){$taskAdb=(Get-Command adb -ErrorAction Stop).Source}
$taskSelect=@()
if($Serial){$taskSelect=@('-s',$Serial)}
$taskOutput=Join-Path $taskRoot 'artifacts\quest-reports'
New-Item -ItemType Directory -Force $taskOutput | Out-Null
$taskFiles=& $taskAdb @taskSelect shell run-as us.teitelbaum.spinlabxr ls files/reports
if($LASTEXITCODE -ne 0){throw 'Could not access reports. Save a report in the debug app first and check USB authorization.'}
foreach($taskName in $taskFiles){
  $taskName=$taskName.Trim()
  if($taskName -notmatch '^spinlab-[A-Za-z0-9._-]+\.json$'){continue}
  $taskData=& $taskAdb @taskSelect shell run-as us.teitelbaum.spinlabxr cat "files/reports/$taskName"
  if($LASTEXITCODE -ne 0){throw "Report retrieval failed: $taskName"}
  $taskJson=$taskData -join "`n"
  $null=$taskJson | ConvertFrom-Json
  [IO.File]::WriteAllText((Join-Path $taskOutput $taskName),$taskJson,[Text.UTF8Encoding]::new($false))
  Write-Output (Join-Path $taskOutput $taskName)
}
