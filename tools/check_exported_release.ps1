[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)]
	[string]$GodotBinary,
	[Parameter(Mandatory = $true)]
	[string]$ExecutablePath,
	[string]$EvidenceDirectory = ""
)

$ErrorActionPreference = "Stop"


function ConvertTo-NativeProcessArgument {
	param(
		[Parameter(Mandatory = $true)]
		[AllowEmptyString()]
		[string]$Value
	)
	if ($Value.Contains('"')) {
		throw "Native process arguments containing a quote are not supported."
	}
	if ($Value.Length -gt 0 -and $Value -notmatch '\s') {
		return $Value
	}
	# Windows paths cannot contain a quote. Doubling only a trailing backslash is
	# sufficient to keep it from escaping the closing quote in CommandLineToArgvW.
	$escaped = [regex]::Replace($Value, '(\\+)$', '$1$1')
	return '"' + $escaped + '"'
}


function Join-NativeProcessArguments {
	param(
		[Parameter(Mandatory = $true)]
		[string[]]$Values
	)
	return (($Values | ForEach-Object { ConvertTo-NativeProcessArgument -Value $_ }) -join ' ')
}


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
$profileRoot = Join-Path $resolvedEvidence ("profile-" + [Guid]::NewGuid().ToString("N"))
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
	$inspectorStdoutLog = Join-Path $resolvedEvidence "pck-inspector-stdout.log"
	$inspectorStderrLog = Join-Path $resolvedEvidence "pck-inspector-stderr.log"
	$inspectorArguments = Join-NativeProcessArguments -Values @(
		"--headless", "--path", $inspectorProject,
		"--script", "res://inspect_gogobro_pck.gd", "--", $pckPath
	)
	$inspectorProcess = Start-Process `
		-FilePath $GodotBinary `
		-WorkingDirectory $inspectorProject `
		-ArgumentList $inspectorArguments `
		-WindowStyle Hidden `
		-RedirectStandardOutput $inspectorStdoutLog `
		-RedirectStandardError $inspectorStderrLog `
		-PassThru
	$null = $inspectorProcess.Handle
	$inspectorTimedOut = -not $inspectorProcess.WaitForExit(30000)
	if ($inspectorTimedOut) {
		$inspectorProcess.Kill()
		$inspectorProcess.WaitForExit()
	}
	$inspectorExitCode = $inspectorProcess.ExitCode
	$inspectorOutput = @(
		Get-Content -LiteralPath $inspectorStdoutLog -ErrorAction SilentlyContinue
		Get-Content -LiteralPath $inspectorStderrLog -ErrorAction SilentlyContinue
	)
	$inspectorOutput | Set-Content -LiteralPath $inspectorLog
	$inspectorOutput | ForEach-Object { Write-Output $_ }
	if ($inspectorTimedOut) {
		throw "Exported PCK boot inspection exceeded 30 seconds and was terminated. See $inspectorLog"
	}
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
	$runtimeArguments = Join-NativeProcessArguments -Values @(
		"--headless", "--quit-after", "10", "--verbose", "--log-file", $runtimeLog,
		"--", "--gogobro-release-smoke"
	)
	$runtimeProcess = Start-Process `
		-FilePath $resolvedExecutable `
		-WorkingDirectory (Split-Path -Parent $resolvedExecutable) `
		-ArgumentList $runtimeArguments `
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
	$runtimeFiles = @($runtimeLog, $stdoutLog, $stderrLog)
	foreach ($runtimeFile in $runtimeFiles) {
		if (-not (Test-Path -LiteralPath $runtimeFile -PathType Leaf)) {
			throw "Exported release did not produce required log: $runtimeFile"
		}
	}
	$runtimeText = ($runtimeFiles | ForEach-Object { Get-Content -LiteralPath $_ -Raw }) -join [Environment]::NewLine
	if ($runtimeText -match "SCRIPT ERROR:|ERROR:|GOGOBRO_RELEASE_DIAGNOSTIC:") {
		throw "Exported release logged an error or diagnostic startup. See $resolvedEvidence"
	}
	$successMarker = "GOGOBRO_EXPORTED_MAIN_MENU_READY route=main_menu ready=70 fallback=0 wordmark=1 buttons=1 release=1 preview=0"
	if (-not $runtimeText.Contains($successMarker)) {
		throw "Exported release did not prove the real EXE reached the authored main menu. See $resolvedEvidence"
	}
	Write-Output "GOGOBRO_EXPORTED_RELEASE_SMOKE_OK pck=valid route=main_menu ready=70 fallback=0 runtime_errors=0"
} finally {
	$env:APPDATA = $previousAppData
	$env:LOCALAPPDATA = $previousLocalAppData
	$env:USERPROFILE = $previousUserProfile
}
