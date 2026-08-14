[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)]
	[string]$GodotBinary,
	[ValidateSet("Editor", "Game")]
	[string]$Mode = "Editor"
)

$ErrorActionPreference = "Continue"
$projectRoot = Split-Path -Parent $PSScriptRoot
$arguments = @("--headless", "--path", $projectRoot, "--quit", "--verbose")
if ($Mode -eq "Editor") {
	$arguments = @("--headless", "--editor", "--path", $projectRoot, "--quit", "--verbose")
}

$output = (& $GodotBinary @arguments 2>&1 | Out-String)
$exitCode = $LASTEXITCODE
$leakPattern = "Leaked instance:|ObjectDB instances were leaked|resources still in use at exit"
$leakLines = @($output -split "`r?`n" | Where-Object { $_ -match $leakPattern })

if ($exitCode -ne 0 -or $leakLines.Count -gt 0) {
	Write-Output "Godot $Mode clean-exit check failed (exit=$exitCode)."
	$leakLines | ForEach-Object { Write-Output $_ }
	exit 1
}

Write-Output "Godot $Mode clean-exit check passed."
