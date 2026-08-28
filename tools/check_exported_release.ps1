[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)]
	[string]$GodotBinary,
	[Parameter(Mandatory = $true)]
	[string]$ExecutablePath,
	[string]$EvidenceDirectory = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Split-Path -Parent $PSScriptRoot)).Path
$consoleBinary = Join-Path (Split-Path -Parent $GodotBinary) (([System.IO.Path]::GetFileNameWithoutExtension($GodotBinary)) + "_console.exe")
if (-not $GodotBinary.EndsWith("_console.exe", [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $consoleBinary)) {
	$GodotBinary = $consoleBinary
}
if (-not (Test-Path -LiteralPath $GodotBinary -PathType Leaf)) {
	throw "Godot console executable not found: $GodotBinary"
}
$resolvedExecutable = (Resolve-Path -LiteralPath $ExecutablePath).Path
$pckPath = [System.IO.Path]::ChangeExtension($resolvedExecutable, ".pck")
if (-not (Test-Path -LiteralPath $pckPath -PathType Leaf)) {
	throw "Exported PCK not found beside executable: $pckPath"
}
if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
	$EvidenceDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("gogobro-exported-release-" + [Guid]::NewGuid().ToString("N"))
}
$resolvedEvidence = [System.IO.Path]::GetFullPath($EvidenceDirectory)
New-Item -ItemType Directory -Force -Path $resolvedEvidence | Out-Null
$profileRoot = Join-Path $resolvedEvidence "profile"
$appData = Join-Path $profileRoot "AppData\Roaming"
$localAppData = Join-Path $profileRoot "AppData\Local"
New-Item -ItemType Directory -Force -Path $appData, $localAppData | Out-Null

$previousAppData = $env:APPDATA
$previousLocalAppData = $env:LOCALAPPDATA
$previousUserProfile = $env:USERPROFILE
try {
	$env:APPDATA = $appData
	$env:LOCALAPPDATA = $localAppData
	$env:USERPROFILE = $profileRoot

	$inspectorSource = Join-Path $projectRoot "tools\release_smoke"
	$inspectorProject = Join-Path $resolvedEvidence "inspector-project"
	New-Item -ItemType Directory -Force -Path $inspectorProject | Out-Null
	Copy-Item -LiteralPath (Join-Path $inspectorSource "project.godot.template") -Destination (Join-Path $inspectorProject "project.godot") -Force
	Copy-Item -LiteralPath (Join-Path $inspectorSource "inspect_gogobro_pck.gd") -Destination $inspectorProject -Force
	$inspectorLog = Join-Path $resolvedEvidence "pck-inspector.log"
	$previousErrorActionPreference = $ErrorActionPreference
	$ErrorActionPreference = "Continue"
	try {
		$inspectorOutput = @(& $GodotBinary --headless --path $inspectorProject --script "res://inspect_gogobro_pck.gd" -- $pckPath 2>&1)
		$inspectorExitCode = $LASTEXITCODE
	} finally {
		$ErrorActionPreference = $previousErrorActionPreference
	}
	$inspectorOutput | Set-Content -LiteralPath $inspectorLog
	$inspectorOutput | ForEach-Object { Write-Output $_ }
	$inspectorText = ($inspectorOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
	if ($inspectorExitCode -ne 0 -or $inspectorText -notmatch "GOGOBRO_RELEASE_PCK_SMOKE_OK route=main_menu") {
		throw "Exported PCK boot inspection failed (exit=$inspectorExitCode). See $inspectorLog"
	}
	if ($inspectorText -match "GOGOBRO_RELEASE_DIAGNOSTIC:|SCRIPT ERROR:|ERROR:") {
		throw "Exported PCK boot inspection reported an error or diagnostic route. See $inspectorLog"
	}

	$runtimeLog = Join-Path $resolvedEvidence "runtime.log"
	$stdoutLog = Join-Path $resolvedEvidence "stdout.log"
	$stderrLog = Join-Path $resolvedEvidence "stderr.log"
	$runtimeProcess = Start-Process `
		-FilePath $resolvedExecutable `
		-WorkingDirectory (Split-Path -Parent $resolvedExecutable) `
		-ArgumentList @("--headless", "--quit-after", "10", "--verbose", "--log-file", $runtimeLog) `
		-WindowStyle Hidden `
		-RedirectStandardOutput $stdoutLog `
		-RedirectStandardError $stderrLog `
		-PassThru
	$null = $runtimeProcess.Handle
	if (-not $runtimeProcess.WaitForExit(30000)) {
		$runtimeProcess.Kill()
		$runtimeProcess.WaitForExit()
		throw "Exported release did not exit within 30 seconds."
	}
	if ($runtimeProcess.ExitCode -ne 0) {
		throw "Exported release exited with code $($runtimeProcess.ExitCode)."
	}
	$runtimeFiles = @($runtimeLog, $stdoutLog, $stderrLog) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
	$runtimeText = ($runtimeFiles | ForEach-Object { Get-Content -LiteralPath $_ -Raw }) -join [Environment]::NewLine
	if ($runtimeText -match "SCRIPT ERROR:|ERROR:|GOGOBRO_RELEASE_DIAGNOSTIC:") {
		throw "Exported release logged an error or diagnostic startup. See $resolvedEvidence"
	}
	Write-Output "GOGOBRO_EXPORTED_RELEASE_SMOKE_OK pck=valid route=main_menu runtime_errors=0"
} finally {
	$env:APPDATA = $previousAppData
	$env:LOCALAPPDATA = $previousLocalAppData
	$env:USERPROFILE = $previousUserProfile
}
