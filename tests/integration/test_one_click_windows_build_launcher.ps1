[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$launcher = Join-Path $projectRoot "重新打包试玩版.cmd"
$archive = Join-Path $projectRoot "dist\game-prototype\GamePrototype-Windows-x86_64.zip"

if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
	throw "One-click Windows build launcher is missing: $launcher"
}

$startedAt = Get-Date
$commandLine = 'call "' + $launcher + '" < nul'
& $env:ComSpec /d /s /c $commandLine
$launcherExitCode = $LASTEXITCODE

if ($launcherExitCode -ne 0) {
	throw "One-click Windows build launcher failed with exit code $launcherExitCode."
}
if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
	throw "One-click Windows build launcher did not create the playtest archive: $archive"
}
if ((Get-Item -LiteralPath $archive).LastWriteTime -lt $startedAt.AddSeconds(-2)) {
	throw "One-click Windows build launcher did not refresh the playtest archive: $archive"
}

Write-Output "One-click Windows build launcher passed: $archive"
