[CmdletBinding()]
param(
	[string]$GodotBinary = $env:GODOT_BIN,
	[ValidateSet("Windows", "Linux", "macOS")]
	[string[]]$Platforms = @("Windows", "Linux", "macOS"),
	[string]$SkinManifest = "res://content_packs/skins/dev_placeholder/skin.tres",
	[switch]$SkipAcceptance
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Split-Path -Parent $PSScriptRoot)).Path
$buildRoot = Join-Path $projectRoot "builds"
$stagingRoot = Join-Path $buildRoot "release_staging"
$stagingProject = Join-Path $stagingRoot "core_project"
$distRoot = Join-Path $projectRoot "dist\gobro-core-parity"
$contentPack = Join-Path $buildRoot "content\default_content.pck"

if ([string]::IsNullOrWhiteSpace($GodotBinary)) {
	$godotCommand = Get-Command godot -ErrorAction SilentlyContinue
	if ($null -ne $godotCommand) { $GodotBinary = $godotCommand.Source }
}
if ([string]::IsNullOrWhiteSpace($GodotBinary) -or -not (Test-Path -LiteralPath $GodotBinary)) {
	throw "Godot 4.7.1 was not found. Pass -GodotBinary or set GODOT_BIN."
}
$consoleBinary = Join-Path (Split-Path -Parent $GodotBinary) (([System.IO.Path]::GetFileNameWithoutExtension($GodotBinary)) + "_console.exe")
if (-not $GodotBinary.EndsWith("_console.exe", [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $consoleBinary)) {
	$GodotBinary = $consoleBinary
}
$godotVersion = (& $GodotBinary --version | Select-Object -First 1).Trim()

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

function Remove-UnselectedSkinDirectories([string]$SkinRoot, [string]$SelectedSkinDirectory) {
	$resolvedSkinRoot = [System.IO.Path]::GetFullPath($SkinRoot)
	$resolvedSelected = [System.IO.Path]::GetFullPath($SelectedSkinDirectory)
	Assert-ChildPath $resolvedSelected $resolvedSkinRoot
	Get-ChildItem -LiteralPath $resolvedSkinRoot -Directory | ForEach-Object {
		$resolvedCandidate = [System.IO.Path]::GetFullPath($_.FullName)
		Assert-ChildPath $resolvedCandidate $resolvedSkinRoot
		if (-not $resolvedCandidate.Equals($resolvedSelected, [System.StringComparison]::OrdinalIgnoreCase)) {
			Remove-Item -LiteralPath $resolvedCandidate -Recurse -Force
		}
	}
}

function Invoke-Godot([string[]]$Arguments) {
	& $GodotBinary @Arguments
	if ($LASTEXITCODE -ne 0) { throw "Godot failed with exit code ${LASTEXITCODE}: $($Arguments -join ' ')" }
}

function Assert-WindowsX64Executable([string]$ExecutablePath) {
	if (-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) {
		throw "Windows executable is missing: $ExecutablePath"
	}
	$stream = [System.IO.File]::OpenRead($ExecutablePath)
	try {
		$reader = [System.IO.BinaryReader]::new($stream)
		try {
			if ($reader.ReadUInt16() -ne 0x5A4D) { throw "Windows executable has no MZ header: $ExecutablePath" }
			$stream.Position = 0x3C
			$peOffset = $reader.ReadUInt32()
			if ($peOffset -gt ($stream.Length - 6)) { throw "Windows executable has an invalid PE offset: $ExecutablePath" }
			$stream.Position = $peOffset
			if ($reader.ReadUInt32() -ne 0x00004550) { throw "Windows executable has no PE header: $ExecutablePath" }
			if ($reader.ReadUInt16() -ne 0x8664) { throw "Windows executable is not x86_64: $ExecutablePath" }
		} finally {
			$reader.Dispose()
		}
	} finally {
		$stream.Dispose()
	}
}

function Assert-WindowsReleaseDirectory([string]$PlatformDirectory) {
	$requiredFiles = @("GOBRO.exe", "GOBRO.pck", "default_content.pck", "PLAYTEST.md", "THIRD_PARTY.md")
	$actualFiles = @(Get-ChildItem -LiteralPath $PlatformDirectory -File -Recurse | ForEach-Object {
		$_.FullName.Substring($PlatformDirectory.Length + 1).Replace('\', '/')
	})
	$unexpected = @($actualFiles | Where-Object { $requiredFiles -notcontains $_ })
	$missing = @($requiredFiles | Where-Object { $actualFiles -notcontains $_ })
	if ($unexpected.Count -gt 0) { throw "Unexpected files in Windows package: $($unexpected -join ', ')" }
	if ($missing.Count -gt 0) { throw "Required files missing from Windows package: $($missing -join ', ')" }
	$directories = @(Get-ChildItem -LiteralPath $PlatformDirectory -Directory -Recurse)
	if ($directories.Count -gt 0) { throw "Windows package must not contain source directories: $($directories.FullName -join ', ')" }
	foreach ($fileName in $requiredFiles) {
		$file = Get-Item -LiteralPath (Join-Path $PlatformDirectory $fileName)
		if ($file.Length -le 0) { throw "Windows package contains an empty file: $fileName" }
	}
	Assert-WindowsX64Executable (Join-Path $PlatformDirectory "GOBRO.exe")
}

function Assert-WindowsReleaseArchive([string]$ArchivePath) {
	Add-Type -AssemblyName System.IO.Compression
	Add-Type -AssemblyName System.IO.Compression.FileSystem
	$requiredFiles = @("GOBRO.exe", "GOBRO.pck", "default_content.pck", "PLAYTEST.md", "THIRD_PARTY.md")
	$archive = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
	try {
		$actualFiles = @($archive.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) } | ForEach-Object {
			$_.FullName.Replace('\', '/') -replace '^\./', ''
		})
		$unexpected = @($actualFiles | Where-Object { $requiredFiles -notcontains $_ })
		$missing = @($requiredFiles | Where-Object { $actualFiles -notcontains $_ })
		if ($unexpected.Count -gt 0) { throw "Unexpected files in Windows archive: $($unexpected -join ', ')" }
		if ($missing.Count -gt 0) { throw "Required files missing from Windows archive: $($missing -join ', ')" }
		if (@($actualFiles | Select-Object -Unique).Count -ne $actualFiles.Count) { throw "Windows archive contains duplicate file names." }
	} finally {
		$archive.Dispose()
	}
}

function Invoke-WindowsReleaseSmoke([string]$PlatformDirectory) {
	$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
	$smokeRoot = Join-Path $tempRoot ("GOBRO-release-smoke-" + [Guid]::NewGuid().ToString("N"))
	Assert-ChildPath $smokeRoot $tempRoot
	$smokePackage = Join-Path $smokeRoot "package"
	$isolatedAppData = Join-Path $smokeRoot "isolated-appdata"
	$isolatedLocalAppData = Join-Path $smokeRoot "isolated-localappdata"
	$smokeLog = Join-Path $smokeRoot "exported-windows.log"
	New-Item -ItemType Directory -Force -Path $smokePackage, $isolatedAppData, $isolatedLocalAppData | Out-Null
	Get-ChildItem -LiteralPath $PlatformDirectory | ForEach-Object {
		Copy-Item -LiteralPath $_.FullName -Destination $smokePackage -Recurse -Force
	}

	$previousAppData = $env:APPDATA
	$previousLocalAppData = $env:LOCALAPPDATA
	try {
		$env:APPDATA = $isolatedAppData
		$env:LOCALAPPDATA = $isolatedLocalAppData
		$smokeExecutable = Join-Path $smokePackage "GOBRO.exe"
		$smokeProcess = Start-Process `
			-FilePath $smokeExecutable `
			-WorkingDirectory $smokePackage `
			-ArgumentList @("--headless", "--quit-after", "5", "--verbose", "--log-file", $smokeLog) `
			-WindowStyle Hidden `
			-PassThru
		if (-not $smokeProcess.WaitForExit(30000)) {
			$smokeProcess.Kill()
			$smokeProcess.WaitForExit()
			throw "Exported Windows smoke test did not exit within 30 seconds."
		}
		if ($smokeProcess.ExitCode -ne 0) { throw "Exported Windows smoke test failed with exit code $($smokeProcess.ExitCode)." }
		if (-not (Test-Path -LiteralPath $smokeLog -PathType Leaf)) { throw "Exported Windows smoke test did not produce a log." }
		$runtimeLogs = @($smokeLog)
		$gameLog = Join-Path $isolatedAppData "Godot\app_userdata\GOBRO\logs\latest.log"
		if (Test-Path -LiteralPath $gameLog -PathType Leaf) { $runtimeLogs += $gameLog }
		$smokeErrors = @($runtimeLogs | ForEach-Object {
			Get-Content -LiteralPath $_ | Where-Object { $_ -match "SCRIPT ERROR|ERROR:|ObjectDB instances were leaked|resources still in use|Default content pack failed"
			}
		})
		if ($smokeErrors.Count -gt 0) { throw "Exported Windows smoke test logged errors: $($smokeErrors -join [Environment]::NewLine)" }
		Write-Output "WINDOWS_RELEASE_SMOKE passed: external package, isolated user data, clean exit"
	} finally {
		$env:APPDATA = $previousAppData
		$env:LOCALAPPDATA = $previousLocalAppData
		if (Test-Path -LiteralPath $smokeRoot) { Remove-Item -LiteralPath $smokeRoot -Recurse -Force }
	}
}

if (-not $SkinManifest.StartsWith("res://content_packs/skins/", [System.StringComparison]::Ordinal) -or -not $SkinManifest.EndsWith("/skin.tres", [System.StringComparison]::Ordinal)) {
	throw "SkinManifest must identify one skin under res://content_packs/skins/<id>/skin.tres."
}
$skinRelativePath = $SkinManifest.Substring(6).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
$selectedSkinSource = Join-Path $projectRoot $skinRelativePath
$sourceSkinRoot = Join-Path $projectRoot "content_packs\skins"
Assert-ChildPath $selectedSkinSource $sourceSkinRoot
if (-not (Test-Path -LiteralPath $selectedSkinSource -PathType Leaf)) {
	throw "Selected skin manifest is missing: $selectedSkinSource"
}
$selectedSkinName = Split-Path -Leaf (Split-Path -Parent $selectedSkinSource)

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
$stagedSkinRoot = Join-Path $stagingProject "content_packs\skins"
$stagedSelectedSkinDirectory = Join-Path $stagedSkinRoot $selectedSkinName
Remove-UnselectedSkinDirectories $stagedSkinRoot $stagedSelectedSkinDirectory
$stagedSelectedManifest = Join-Path $stagingProject $skinRelativePath
if (-not (Test-Path -LiteralPath $stagedSelectedManifest -PathType Leaf)) {
	throw "Selected skin was not staged: $stagedSelectedManifest"
}

$stagedProjectFile = Join-Path $stagingProject "project.godot"
$projectText = Get-Content -LiteralPath $stagedProjectFile -Raw
$projectText = $projectText -replace '(?m)^MCPGameInspector=.*\r?\n', ''
$projectText = $projectText -replace '(?m)^MCPGameInput=.*\r?\n', ''
$projectText = $projectText -replace '(?m)^enabled=PackedStringArray\(.*\)$', 'enabled=PackedStringArray()'
$projectText = $projectText -replace '(?m)^theme/custom_font=.*\r?\n', ''
$projectText = $projectText -replace '(?m)^skin_manifest="[^"]*"$', ('skin_manifest="' + $SkinManifest + '"')
[System.IO.File]::WriteAllText($stagedProjectFile, $projectText, [System.Text.UTF8Encoding]::new($false))

Invoke-Godot @("--headless", "--editor", "--path", $stagingProject, "--import", "--quit")

$platformConfig = @{
	Windows = @{ Preset = "Windows Desktop"; Folder = "windows"; File = "GOBRO.exe" }
	Linux   = @{ Preset = "Linux"; Folder = "linux"; File = "GOBRO.x86_64" }
	macOS   = @{ Preset = "macOS"; Folder = "macos"; File = "GOBRO.zip" }
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
		Invoke-Godot @("--headless", "--path", $inspectorProject, "--script", $inspectorScript, "--", $macCorePck, "--skin-manifest", $SkinManifest)
		$releaseArchive = Join-Path $distRoot "GOBRO-core-parity-macOS-universal.zip"
		Copy-Item -LiteralPath $exportPath -Destination $releaseArchive -Force
	} else {
		$corePck = [System.IO.Path]::ChangeExtension($exportPath, ".pck")
		if (-not (Test-Path -LiteralPath $corePck)) { throw "Core PCK was not generated: $corePck" }
		Invoke-Godot @("--headless", "--path", $inspectorProject, "--script", $inspectorScript, "--", $corePck, "--skin-manifest", $SkinManifest)
		Copy-Item -LiteralPath $contentPack -Destination (Join-Path $platformDir "default_content.pck") -Force
		Copy-Item -LiteralPath (Join-Path $projectRoot "docs\PHASE_ONE_PLAYTEST.md") -Destination (Join-Path $platformDir "PLAYTEST.md") -Force
		Copy-Item -LiteralPath (Join-Path $projectRoot "docs\THIRD_PARTY.md") -Destination (Join-Path $platformDir "THIRD_PARTY.md") -Force
		if ($platform -eq "Windows") {
			Assert-WindowsReleaseDirectory $platformDir
			if ($env:OS -eq "Windows_NT") {
				Invoke-WindowsReleaseSmoke $platformDir
			}
			$releaseArchive = Join-Path $distRoot "GOBRO-core-parity-Windows-x86_64.zip"
			tar -a -cf $releaseArchive -C $platformDir .
			if ($LASTEXITCODE -ne 0) { throw "Windows archive creation failed" }
			Assert-WindowsReleaseArchive $releaseArchive
		} else {
			$releaseArchive = Join-Path $distRoot "GOBRO-core-parity-Linux-x86_64.tar.gz"
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
	product = "GOBRO"
	phase = 1
	version = "0.1.0-playtest"
	godot = $godotVersion
	commit = $commit
	created_utc = [DateTime]::UtcNow.ToString("o")
	content_pack = "core"
	skin_manifest = $SkinManifest
	platforms = $Platforms
	files = $fileRecords
}
$manifestPath = Join-Path $distRoot "release_manifest.json"
[System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))
Write-Output "Phase-one release assembled: $distRoot"
