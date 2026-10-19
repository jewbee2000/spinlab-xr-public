param([int]$Port = 8080)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskNode = Get-Command node -ErrorAction SilentlyContinue
if (-not $taskNode) {
  $taskBundledNode = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
  $taskNode = Get-Command $taskBundledNode -ErrorAction SilentlyContinue
}
if (-not $taskNode) { throw 'Install Node.js 22 or 24 LTS from https://nodejs.org/ and reopen PowerShell.' }
& $taskNode.Source (Join-Path $PSScriptRoot 'serve.mjs') --port $Port
