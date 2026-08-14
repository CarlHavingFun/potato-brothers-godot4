[CmdletBinding()]
param(
	[string]$GodotBinary = $env:GODOT_BIN,
	[ValidateSet("Windows", "Linux", "macOS")]
	[string[]]$Platforms = @("Windows", "Linux", "macOS"),
	[switch]$SkipAcceptance
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Split-Path -Parent $PSScriptRoot)).Path
$buildRoot = Join-Path $projectRoot "builds"
$stagingRoot = Join-Path $buildRoot "release_staging"
$stagingProject = Join-Path $stagingRoot "core_project"
$distRoot = Join-Path $projectRoot "dist\potato-brothers-phase1"
$contentPack = Join-Path $buildRoot "content\default_content.pck"

if ([string]::IsNullOrWhiteSpace($GodotBinary)) {
	$godotCommand = Get-Command godot -ErrorAction SilentlyContinue
	if ($null -ne $godotCommand) { $GodotBinary = $godotCommand.Source }
}
if ([string]::IsNullOrWhiteSpace($GodotBinary) -or -not (Test-Path -LiteralPath $GodotBinary)) {
	throw "Godot 4.7.1 was not found. Pass -GodotBinary or set GODOT_BIN."
}

function Assert-ChildPath([string]$Path, [string]$Parent) {
	$fullPath = [System.IO.Path]::GetFullPath($Path)
	$fullParent = [System.IO.Path]::GetFullPath($Parent).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
	if (-not $fullPath.StartsWith($fullParent, [System.StringComparison]::OrdinalIgnoreCase)) {
		throw "Unsafe generated path outside expected root: $fullPath"
	}
}

function Reset-GeneratedDirectory([string]$Path, [string]$Parent) {
	Assert-ChildPath $Path $Parent
	if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Recurse -Force }
	New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Invoke-Godot([string[]]$Arguments) {
	& $GodotBinary @Arguments
	if ($LASTEXITCODE -ne 0) { throw "Godot failed with exit code ${LASTEXITCODE}: $($Arguments -join ' ')" }
}

Reset-GeneratedDirectory $stagingRoot $buildRoot
if (-not $SkipAcceptance) {
	& (Join-Path $PSScriptRoot "run_phase_one_acceptance.ps1") -GodotBinary $GodotBinary
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
& (Join-Path $PSScriptRoot "build_content_pack.ps1") -GodotBinary $GodotBinary
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Reset-GeneratedDirectory $distRoot (Join-Path $projectRoot "dist")

$releaseEntries = @(
	"assets", "autoloads", "content_packs", "core", "effects", "resources",
	"scenes", "shaders", "styles", "default_bus_layout.tres", "icon.svg",
	"icon.svg.import", "project.godot", "export_presets.cfg"
)
New-Item -ItemType Directory -Force -Path $stagingProject | Out-Null
foreach ($entry in $releaseEntries) {
	$source = Join-Path $projectRoot $entry
	if (-not (Test-Path -LiteralPath $source)) { throw "Release source is missing: $source" }
	Copy-Item -LiteralPath $source -Destination $stagingProject -Recurse -Force
}

$stagedProjectFile = Join-Path $stagingProject "project.godot"
$projectText = Get-Content -LiteralPath $stagedProjectFile -Raw
$projectText = $projectText -replace '(?m)^MCPGameInspector=.*\r?\n', ''
$projectText = $projectText -replace '(?m)^MCPGameInput=.*\r?\n', ''
$projectText = $projectText -replace '(?m)^enabled=PackedStringArray\(.*\)$', 'enabled=PackedStringArray()'
$projectText = $projectText -replace '(?m)^theme/custom_font=.*\r?\n', ''
[System.IO.File]::WriteAllText($stagedProjectFile, $projectText, [System.Text.UTF8Encoding]::new($false))

Invoke-Godot @("--headless", "--editor", "--path", $stagingProject, "--import", "--quit")

$platformConfig = @{
	Windows = @{ Preset = "Windows Desktop"; Folder = "windows"; File = "PotatoBrothers.exe" }
	Linux   = @{ Preset = "Linux"; Folder = "linux"; File = "PotatoBrothers.x86_64" }
	macOS   = @{ Preset = "macOS"; Folder = "macos"; File = "PotatoBrothers.zip" }
}
$inspectorSource = Join-Path $projectRoot "tools\release_inspector"
$inspectorProject = Join-Path $stagingRoot "inspector_project"
$null = New-Item -ItemType Directory -Force -Path $inspectorProject
Copy-Item -LiteralPath (Join-Path $inspectorSource "project.godot.template") -Destination (Join-Path $inspectorProject "project.godot") -Force
Copy-Item -LiteralPath (Join-Path $inspectorSource "inspect_core_pck.gd") -Destination $inspectorProject -Force
$inspectorScript = "res://inspect_core_pck.gd"

foreach ($platform in $Platforms) {
	$config = $platformConfig[$platform]
	$platformDir = Join-Path $distRoot $config.Folder
	New-Item -ItemType Directory -Force -Path $platformDir | Out-Null
	$exportPath = Join-Path $platformDir $config.File
	Invoke-Godot @("--headless", "--path", $stagingProject, "--export-release", $config.Preset, $exportPath)

	if ($platform -eq "macOS") {
		Add-Type -AssemblyName System.IO.Compression
		Add-Type -AssemblyName System.IO.Compression.FileSystem
		$archive = [System.IO.Compression.ZipFile]::Open($exportPath, [System.IO.Compression.ZipArchiveMode]::Update)
		try {
			$executableEntry = $archive.Entries | Where-Object { $_.FullName -match '\.app/Contents/MacOS/[^/]+$' } | Select-Object -First 1
			if ($null -eq $executableEntry) { throw "macOS application executable was not found in $exportPath" }
			$coreEntry = $archive.Entries | Where-Object { $_.FullName -match '\.app/Contents/Resources/[^/]+\.pck$' } | Select-Object -First 1
			if ($null -eq $coreEntry) { throw "macOS core PCK was not found in $exportPath" }
			$macCorePck = Join-Path $stagingRoot "macos_core.pck"
			$coreStream = $coreEntry.Open()
			try {
				$coreFile = [System.IO.File]::Create($macCorePck)
				try { $coreStream.CopyTo($coreFile) } finally { $coreFile.Dispose() }
			} finally { $coreStream.Dispose() }
			$macosDirectory = $executableEntry.FullName.Substring(0, $executableEntry.FullName.LastIndexOf('/') + 1)
			$contentEntry = $archive.CreateEntry($macosDirectory + "default_content.pck", [System.IO.Compression.CompressionLevel]::Optimal)
			$entryStream = $contentEntry.Open()
			try {
				$packStream = [System.IO.File]::OpenRead($contentPack)
				try { $packStream.CopyTo($entryStream) } finally { $packStream.Dispose() }
			} finally { $entryStream.Dispose() }
			$noticeFiles = @{
				"PLAYTEST.md" = (Join-Path $projectRoot "docs\PHASE_ONE_PLAYTEST.md")
				"THIRD_PARTY.md" = (Join-Path $projectRoot "docs\THIRD_PARTY.md")
			}
			foreach ($noticeName in $noticeFiles.Keys) {
				$noticeEntry = $archive.CreateEntry($noticeName, [System.IO.Compression.CompressionLevel]::Optimal)
				$noticeStream = $noticeEntry.Open()
				try {
					$noticeFile = [System.IO.File]::OpenRead($noticeFiles[$noticeName])
					try { $noticeFile.CopyTo($noticeStream) } finally { $noticeFile.Dispose() }
				} finally { $noticeStream.Dispose() }
			}
		} finally { $archive.Dispose() }
		Invoke-Godot @("--headless", "--path", $inspectorProject, "--script", $inspectorScript, "--", $macCorePck)
		$releaseArchive = Join-Path $distRoot "PotatoBrothers-Phase1-macOS-universal.zip"
		Copy-Item -LiteralPath $exportPath -Destination $releaseArchive -Force
	} else {
		$corePck = [System.IO.Path]::ChangeExtension($exportPath, ".pck")
		if (-not (Test-Path -LiteralPath $corePck)) { throw "Core PCK was not generated: $corePck" }
		Invoke-Godot @("--headless", "--path", $inspectorProject, "--script", $inspectorScript, "--", $corePck)
		Copy-Item -LiteralPath $contentPack -Destination (Join-Path $platformDir "default_content.pck") -Force
		Copy-Item -LiteralPath (Join-Path $projectRoot "docs\PHASE_ONE_PLAYTEST.md") -Destination (Join-Path $platformDir "PLAYTEST.md") -Force
		Copy-Item -LiteralPath (Join-Path $projectRoot "docs\THIRD_PARTY.md") -Destination (Join-Path $platformDir "THIRD_PARTY.md") -Force
		if ($platform -eq "Windows") {
			if ($env:OS -eq "Windows_NT") {
				$smokeLog = Join-Path $stagingRoot "exported_windows.log"
				$smokeProcess = Start-Process -FilePath $exportPath -ArgumentList @("--headless", "--quit", "--verbose", "--log-file", $smokeLog) -WindowStyle Hidden -Wait -PassThru
				if ($smokeProcess.ExitCode -ne 0) { throw "Exported Windows smoke test failed with exit code $($smokeProcess.ExitCode)" }
				$smokeErrors = @(Get-Content -LiteralPath $smokeLog | Where-Object { $_ -match "SCRIPT ERROR|ERROR:|ObjectDB instances were leaked|resources still in use" })
				if ($smokeErrors.Count -gt 0) { throw "Exported Windows smoke test logged errors: $($smokeErrors -join [Environment]::NewLine)" }
			}
			$releaseArchive = Join-Path $distRoot "PotatoBrothers-Phase1-Windows-x86_64.zip"
			tar -a -cf $releaseArchive -C $platformDir .
			if ($LASTEXITCODE -ne 0) { throw "Windows archive creation failed" }
		} else {
			$releaseArchive = Join-Path $distRoot "PotatoBrothers-Phase1-Linux-x86_64.tar.gz"
			tar -czf $releaseArchive -C $platformDir .
			if ($LASTEXITCODE -ne 0) { throw "Linux archive creation failed" }
		}
	}
}

$commit = (& git -C $projectRoot rev-parse HEAD).Trim()
$fileRecords = @()
Get-ChildItem -LiteralPath $distRoot -File -Recurse | Where-Object Name -ne "release_manifest.json" | ForEach-Object {
	$fileRecords += [ordered]@{
		path = $_.FullName.Substring($distRoot.Length + 1).Replace('\', '/')
		bytes = $_.Length
		sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
	}
}
$manifest = [ordered]@{
	product = "Potato Brothers"
	phase = 1
	version = "0.1.0-playtest"
	godot = "4.7.1"
	commit = $commit
	created_utc = [DateTime]::UtcNow.ToString("o")
	content_pack = "potato_default"
	platforms = $Platforms
	files = $fileRecords
}
$manifestPath = Join-Path $distRoot "release_manifest.json"
[System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))
Write-Output "Phase-one release assembled: $distRoot"
