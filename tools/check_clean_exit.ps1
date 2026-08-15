[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)]
	[string]$GodotBinary,
	[ValidateSet("Editor", "Game")]
	[string]$Mode = "Editor",
	[ValidateRange(1, 10)]
	[int]$Runs = 1
)

$ErrorActionPreference = "Continue"
$projectRoot = Split-Path -Parent $PSScriptRoot
$consoleBinary = Join-Path (Split-Path -Parent $GodotBinary) (([System.IO.Path]::GetFileNameWithoutExtension($GodotBinary)) + "_console.exe")
if (-not $GodotBinary.EndsWith("_console.exe", [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $consoleBinary)) {
	$GodotBinary = $consoleBinary
}
$arguments = @("--headless", "--path", $projectRoot, "--quit", "--verbose")
if ($Mode -eq "Editor") {
	$arguments = @("--headless", "--editor", "--path", $projectRoot, "--quit", "--verbose")
}

for ($run = 1; $run -le $Runs; $run++) {
	$output = (& $GodotBinary @arguments 2>&1 | Out-String)
	$exitCode = $LASTEXITCODE
	$leakPattern = "Leaked instance:|ObjectDB instances were leaked|resources still in use at exit"
	$leakLines = @($output -split "`r?`n" | Where-Object { $_ -match $leakPattern })
	if ($exitCode -ne 0 -or $leakLines.Count -gt 0) {
		Write-Output "Godot $Mode clean-exit check failed on run $run (exit=$exitCode)."
		$leakLines | ForEach-Object { Write-Output $_ }
		exit 1
	}
}

Write-Output "Godot $Mode clean-exit check passed for $Runs run(s)."
