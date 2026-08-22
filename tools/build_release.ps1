[CmdletBinding()]
param(
	[string]$GodotBinary = $env:GODOT_BIN,
	[ValidateSet("Windows", "Linux", "macOS")]
	[string[]]$Platforms = @("Windows", "Linux", "macOS"),
	[string]$SkinManifest = "res://content_packs/skins/lets_gooooo/skin.tres",
	[switch]$SkipAcceptance
)

$ErrorActionPreference = "Stop"

function Get-Sha256Hex([string]$Path) {
	$stream = $null
	$sha256 = $null
	try {
		$stream = [System.IO.File]::OpenRead($Path)
		$sha256 = [System.Security.Cryptography.SHA256]::Create()
		$hashBytes = $sha256.ComputeHash($stream)
		return ([System.BitConverter]::ToString($hashBytes)).Replace("-", "")
	} finally {
		if ($null -ne $sha256) { $sha256.Dispose() }
		if ($null -ne $stream) { $stream.Dispose() }
	}
}

$projectRoot = (Resolve-Path (Split-Path -Parent $PSScriptRoot)).Path
$buildRoot = Join-Path $projectRoot "builds"
$stagingRoot = Join-Path $buildRoot "release_staging"
$stagingProject = Join-Path $stagingRoot "core_project"
$distRoot = Join-Path $projectRoot "dist\game-prototype"
$contentPack = Join-Path $buildRoot "content\default_content.pck"
$NikoRuntimeSourceRoot = Join-Path $projectRoot "tools\sprites\niko_character_library\runtime"
$NikoRuntimeSourceResourceRoot = "res://tools/sprites/niko_character_library/runtime/"
$NikoRuntimeStagingResourceRoot = "res://assets/sprites/Players/NikoRuntime/"
$FormalSkinManifest = "res://content_packs/skins/lets_gooooo/skin.tres"
$FormalGlobalFontResource = "res://assets/font/brotato_font_stack.tres"
$FormalPrimaryFontResource = "res://assets/font/Anybody-Medium.ttf"
$FormalFallbackFontResource = "res://assets/font/NotoSansCJKsc-Medium.otf"
$DefaultContentReadyMarker = "MECHANICS_CONTENT_READY weapons=24 passives=60 upgrades=64 presentation_icons=0"
$GodotFailureOutputPattern = "SCRIPT ERROR|ERROR:|Unicode parsing error|ObjectDB instances were leaked|resources still in use"
$RuntimeFailureOutputPattern = "$GodotFailureOutputPattern|Default content pack failed"
$ApprovedSkinArtExtensions = @(".png", ".svg")
$ForbiddenSkinArtifactTokens = @(
	"/identity/", "/review/", "/source/", "/candidate/", "/candidates/",
	"/prompt/", "/prompts/", "/raw/", "/frames/", "/qa/", "/exports/",
	"/curated/", ".prompt.", ".qa.", "contact-sheet", ".ds_store",
	".jpg", ".jpeg", ".psd", ".psb", ".ase", ".aseprite", ".kra",
	".xcf", ".blend", ".zip", ".7z", ".rar", ".tar", ".gz", ".mp4",
	".webm", ".mov", ".avi", ".mkv", ".gif"
)

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

function Assert-FormalSkinAssetManifest([string]$AssetManifestPath, [string]$SkinDirectory) {
	if (-not (Test-Path -LiteralPath $AssetManifestPath -PathType Leaf)) {
		throw "Asset manifest is required for the formal release skin: $AssetManifestPath"
	}
	try {
		$manifest = Get-Content -LiteralPath $AssetManifestPath -Raw | ConvertFrom-Json
	} catch {
		throw "Formal skin asset manifest is not valid JSON: $AssetManifestPath`n$($_.Exception.Message)"
	}
	if ($null -eq $manifest -or $manifest.skin_id -ne "lets_gooooo" -or $null -eq $manifest.assets) {
		throw "Formal skin asset manifest has an invalid identity or assets list: $AssetManifestPath"
	}

	$skinDirectoryFull = [System.IO.Path]::GetFullPath($SkinDirectory)
	$skinResourceRoot = "res://content_packs/skins/lets_gooooo/assets/"
	$approvedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
	foreach ($asset in @($manifest.assets)) {
		$resourcePath = [string]$asset.path
		if ([string]::IsNullOrWhiteSpace($resourcePath) -or -not $resourcePath.StartsWith($skinResourceRoot, [System.StringComparison]::Ordinal)) {
			throw "Formal skin asset path is outside the shipping assets root: $resourcePath"
		}
		if (-not $approvedPaths.Add($resourcePath)) {
			throw "Formal skin asset manifest contains a duplicate path: $resourcePath"
		}
		$extension = [System.IO.Path]::GetExtension($resourcePath).ToLowerInvariant()
		if ($ApprovedSkinArtExtensions -notcontains $extension) {
			throw "Formal skin asset uses a non-shipping extension: $resourcePath"
		}
		if ($asset.shipping_allowed -ne $true -or [string]$asset.approval.status -ne "approved" -or [string]$asset.rights.status -ne "cleared") {
			throw "Formal skin asset is not approved, rights-cleared, and shipping_allowed=true: $resourcePath"
		}
		$relativePath = $resourcePath.Substring(6).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
		$sourcePath = Join-Path $projectRoot $relativePath
		Assert-ChildPath $sourcePath $skinDirectoryFull
		if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
			throw "Approved formal skin asset is missing: $resourcePath"
		}
	}
	if ($approvedPaths.Count -eq 0) {
		throw "Formal skin asset manifest must approve at least one shipping asset."
	}

	Get-ChildItem -LiteralPath $skinDirectoryFull -File -Recurse | ForEach-Object {
		$relativePath = $_.FullName.Substring($skinDirectoryFull.Length + 1).Replace('\', '/')
		$lowered = "/" + $relativePath.ToLowerInvariant()
		foreach ($token in $ForbiddenSkinArtifactTokens) {
			if ($lowered.Contains($token)) {
				throw "Forbidden source/review artifact found in formal skin: $relativePath"
			}
		}
	}

	$shippingArtRoot = Join-Path $skinDirectoryFull "assets"
	Get-ChildItem -LiteralPath $shippingArtRoot -File -Recurse | Where-Object {
		$ApprovedSkinArtExtensions -contains $_.Extension.ToLowerInvariant()
	} | ForEach-Object {
		$projectRelative = $_.FullName.Substring($projectRoot.Length + 1).Replace('\', '/')
		$resourcePath = "res://$projectRelative"
		if (-not $approvedPaths.Contains($resourcePath)) {
			throw "Shipping skin art is missing from asset_manifest.json: $resourcePath"
		}
	}
}

function Set-StagingBootstrapFontConfiguration([string]$ProjectText) {
	$fontSettingPattern = '(?m)^theme/custom_font="[^"]*"\r?$'
	if (-not [regex]::IsMatch($ProjectText, $fontSettingPattern)) {
		throw "Staged project has no gui/theme/custom_font setting."
	}
	# A newly copied staging project has no .godot/imported directory yet. Do
	# not ask ThemeDB to resolve the source project's UID until the first import
	# has produced the fontdata file in this isolated project.
	return $ProjectText -replace $fontSettingPattern, 'theme/custom_font=""'
}

function Set-FormalGlobalFontConfiguration([string]$ProjectText, [string]$StagedProjectRoot) {
	if (-not $FormalGlobalFontResource.StartsWith("res://", [System.StringComparison]::Ordinal)) {
		throw "Formal global font must be a res:// resource: $FormalGlobalFontResource"
	}
	$fontRelativePath = $FormalGlobalFontResource.Substring(6).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
	$fontPath = Join-Path $StagedProjectRoot $fontRelativePath
	Assert-ChildPath $fontPath $StagedProjectRoot
	if (-not (Test-Path -LiteralPath $fontPath -PathType Leaf)) {
		throw "Formal global font is missing from the staged project: $FormalGlobalFontResource"
	}
	$fontResourceText = Get-Content -LiteralPath $fontPath -Raw
	$fontUidMatch = [regex]::Match($fontResourceText, '\[gd_resource [^\]]*uid="(?<uid>uid://[^"]+)"\]')
	if (-not $fontUidMatch.Success) {
		throw "Formal global font resource has no UID: $fontPath"
	}
	foreach ($fontBinaryResource in @($FormalPrimaryFontResource, $FormalFallbackFontResource)) {
		$fontBinaryPath = Join-Path $StagedProjectRoot $fontBinaryResource.Substring(6).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
		Assert-ChildPath $fontBinaryPath $StagedProjectRoot
		$fontImportPath = "$fontBinaryPath.import"
		if (-not (Test-Path -LiteralPath $fontImportPath -PathType Leaf)) {
			throw "Formal font binary import metadata is missing: $fontImportPath"
		}
		$fontImportText = Get-Content -LiteralPath $fontImportPath -Raw
		$fontDataMatch = [regex]::Match($fontImportText, '(?m)^path="(?<path>res://[^"]+\.fontdata)"\r?$')
		if (-not $fontDataMatch.Success) {
			throw "Formal font binary import metadata has no fontdata destination: $fontImportPath"
		}
		$fontDataPath = Join-Path $StagedProjectRoot $fontDataMatch.Groups["path"].Value.Substring(6).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
		Assert-ChildPath $fontDataPath $StagedProjectRoot
		if (-not (Test-Path -LiteralPath $fontDataPath -PathType Leaf)) {
			throw "Formal font binary imported data is missing: $fontDataPath"
		}
	}
	$fontSettingPattern = '(?m)^theme/custom_font="[^"]*"\r?$'
	if (-not [regex]::IsMatch($ProjectText, $fontSettingPattern)) {
		throw "Staged project has no gui/theme/custom_font setting."
	}
	$fontUid = $fontUidMatch.Groups["uid"].Value
	return $ProjectText -replace $fontSettingPattern, ('theme/custom_font="' + $fontUid + '"')
}

function Invoke-Godot([string[]]$Arguments) {
	$previousErrorActionPreference = $ErrorActionPreference
	$ErrorActionPreference = "Continue"
	try {
		$output = @(& $GodotBinary @Arguments 2>&1)
		$exitCode = $LASTEXITCODE
	} finally {
		$ErrorActionPreference = $previousErrorActionPreference
	}
	$output | ForEach-Object { Write-Output $_ }
	$errorLines = @($output | ForEach-Object { $_.ToString() } | Where-Object {
		$_ -match $GodotFailureOutputPattern
	})
	if ($exitCode -ne 0) {
		throw "Godot failed with exit code ${exitCode}: $($Arguments -join ' ')"
	}
	if ($errorLines.Count -gt 0) {
		throw "Godot logged errors while running $($Arguments -join ' '):$([Environment]::NewLine)$($errorLines -join [Environment]::NewLine)"
	}
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
	$requiredFiles = @("GamePrototype.exe", "GamePrototype.pck", "default_content.pck", "PLAYTEST.md", "THIRD_PARTY.md")
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
	Assert-WindowsX64Executable (Join-Path $PlatformDirectory "GamePrototype.exe")
}

function Assert-WindowsReleaseArchive([string]$ArchivePath) {
	Add-Type -AssemblyName System.IO.Compression
	Add-Type -AssemblyName System.IO.Compression.FileSystem
	$requiredFiles = @("GamePrototype.exe", "GamePrototype.pck", "default_content.pck", "PLAYTEST.md", "THIRD_PARTY.md")
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
	$smokeRoot = Join-Path $tempRoot ("game-prototype-release-smoke-" + [Guid]::NewGuid().ToString("N"))
	Assert-ChildPath $smokeRoot $tempRoot
	$smokePackage = Join-Path $smokeRoot "package"
	$isolatedAppData = Join-Path $smokeRoot "isolated-appdata"
	$isolatedLocalAppData = Join-Path $smokeRoot "isolated-localappdata"
	$smokeLog = Join-Path $smokeRoot "exported-windows.log"
	$smokeStdout = Join-Path $smokeRoot "exported-windows.stdout.log"
	$smokeStderr = Join-Path $smokeRoot "exported-windows.stderr.log"
	New-Item -ItemType Directory -Force -Path $smokePackage, $isolatedAppData, $isolatedLocalAppData | Out-Null
	Get-ChildItem -LiteralPath $PlatformDirectory | ForEach-Object {
		Copy-Item -LiteralPath $_.FullName -Destination $smokePackage -Recurse -Force
	}

	$previousAppData = $env:APPDATA
	$previousLocalAppData = $env:LOCALAPPDATA
	try {
		$env:APPDATA = $isolatedAppData
		$env:LOCALAPPDATA = $isolatedLocalAppData
		$smokeExecutable = Join-Path $smokePackage "GamePrototype.exe"
		$smokeProcess = Start-Process `
			-FilePath $smokeExecutable `
			-WorkingDirectory $smokePackage `
			-ArgumentList @("--headless", "--quit-after", "5", "--verbose", "--log-file", $smokeLog) `
			-WindowStyle Hidden `
			-RedirectStandardOutput $smokeStdout `
			-RedirectStandardError $smokeStderr `
			-PassThru
		# Windows PowerShell 5.1 can lose ExitCode for redirected processes unless
		# the native process handle is materialized before waiting.
		$null = $smokeProcess.Handle
		if (-not $smokeProcess.WaitForExit(30000)) {
			$smokeProcess.Kill()
			$smokeProcess.WaitForExit()
			throw "Exported Windows smoke test did not exit within 30 seconds."
		}
		if ($smokeProcess.ExitCode -ne 0) { throw "Exported Windows smoke test failed with exit code $($smokeProcess.ExitCode)." }
		if (-not (Test-Path -LiteralPath $smokeLog -PathType Leaf)) { throw "Exported Windows smoke test did not produce a log." }
		$runtimeLogs = @($smokeLog, $smokeStdout, $smokeStderr) | Where-Object {
			Test-Path -LiteralPath $_ -PathType Leaf
		}
		# The formal product uses an isolated user-data namespace. Developer-era
		# Older developer saves must not make a clean playtest package look pre-played.
		$gameLog = Join-Path $isolatedAppData "LETS_GOOOOO\logs\latest.log"
		if (Test-Path -LiteralPath $gameLog -PathType Leaf) { $runtimeLogs += $gameLog }
		$smokeErrors = @($runtimeLogs | ForEach-Object {
			Get-Content -LiteralPath $_ | Where-Object { $_ -match $RuntimeFailureOutputPattern
			}
		})
		if ($smokeErrors.Count -gt 0) { throw "Exported Windows smoke test logged errors: $($smokeErrors -join [Environment]::NewLine)" }
		$runtimeText = ($runtimeLogs | ForEach-Object { Get-Content -LiteralPath $_ -Raw }) -join [Environment]::NewLine
		if ($runtimeText.IndexOf($FormalGlobalFontResource, [System.StringComparison]::Ordinal) -lt 0) {
			throw "Exported runtime did not load the formal global font: $FormalGlobalFontResource"
		}
		if ($runtimeText.IndexOf($DefaultContentReadyMarker, [System.StringComparison]::Ordinal) -lt 0) {
			throw "Exported runtime did not deserialize the presentation-neutral default mechanics contract."
		}
		Write-Output "WINDOWS_RELEASE_SMOKE passed: external package, isolated user data, clean exit"
	} finally {
		$env:APPDATA = $previousAppData
		$env:LOCALAPPDATA = $previousLocalAppData
		if (Test-Path -LiteralPath $smokeRoot) { Remove-Item -LiteralPath $smokeRoot -Recurse -Force }
	}
}

if (-not $SkinManifest.Equals($FormalSkinManifest, [System.StringComparison]::Ordinal)) {
	throw "Release builds require the formal skin manifest: $FormalSkinManifest"
}
$skinRelativePath = $SkinManifest.Substring(6).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
$selectedSkinSource = Join-Path $projectRoot $skinRelativePath
$sourceSkinRoot = Join-Path $projectRoot "content_packs\skins"
Assert-ChildPath $selectedSkinSource $sourceSkinRoot
if (-not (Test-Path -LiteralPath $selectedSkinSource -PathType Leaf)) {
	throw "Selected skin manifest is missing: $selectedSkinSource"
}
$selectedSkinName = Split-Path -Leaf (Split-Path -Parent $selectedSkinSource)
$selectedSkinAssetManifest = Join-Path (Split-Path -Parent $selectedSkinSource) "asset_manifest.json"
$selectedSkinAssetManifestResource = "res://content_packs/skins/$selectedSkinName/asset_manifest.json"
Assert-FormalSkinAssetManifest $selectedSkinAssetManifest (Split-Path -Parent $selectedSkinSource)
Invoke-Godot @(
	"--headless", "--path", $projectRoot,
	"--script", "res://tools/assets/validate_skin_assets.gd", "--",
	"--skin-root", "res://content_packs/skins/$selectedSkinName"
)

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
	"scenes", "shaders", "styles", "default_bus_layout.tres", "project.godot",
	"export_presets.cfg"
)
New-Item -ItemType Directory -Force -Path $stagingProject | Out-Null
foreach ($entry in $releaseEntries) {
	$source = Join-Path $projectRoot $entry
	if (-not (Test-Path -LiteralPath $source)) { throw "Release source is missing: $source" }
	Copy-Item -LiteralPath $source -Destination $stagingProject -Recurse -Force
}

$nikoRuntimeFiles = @(
	"niko_runtime_frames.tres",
	"runtime_atlas_001.png",
	"runtime_atlas_002.png",
	"runtime_atlas_003.png"
)
$stagedNikoRuntimeRoot = Join-Path $stagingProject "assets\sprites\Players\NikoRuntime"
New-Item -ItemType Directory -Force -Path $stagedNikoRuntimeRoot | Out-Null
foreach ($runtimeFile in $nikoRuntimeFiles) {
	$runtimeSource = Join-Path $NikoRuntimeSourceRoot $runtimeFile
	if (-not (Test-Path -LiteralPath $runtimeSource -PathType Leaf)) {
		throw "Niko shipping runtime asset is missing: $runtimeSource"
	}
	Copy-Item -LiteralPath $runtimeSource -Destination (Join-Path $stagedNikoRuntimeRoot $runtimeFile) -Force
}
$stagedNikoFrames = Join-Path $stagedNikoRuntimeRoot "niko_runtime_frames.tres"
$nikoFramesText = Get-Content -LiteralPath $stagedNikoFrames -Raw
$nikoFramesText = $nikoFramesText.Replace($NikoRuntimeSourceResourceRoot, $NikoRuntimeStagingResourceRoot)
if ($nikoFramesText.Contains($NikoRuntimeSourceResourceRoot)) {
	throw "Staged Niko SpriteFrames still references the authoring tools directory."
}
[System.IO.File]::WriteAllText($stagedNikoFrames, $nikoFramesText, [System.Text.UTF8Encoding]::new($false))

$stagedNikoScene = Join-Path $stagingProject "scenes\unit\players\player_niko.tscn"
$nikoSceneText = Get-Content -LiteralPath $stagedNikoScene -Raw
if (-not $nikoSceneText.Contains($NikoRuntimeSourceResourceRoot + "niko_runtime_frames.tres")) {
	throw "Niko player scene does not reference the expected authoring runtime resource."
}
$nikoSceneText = $nikoSceneText.Replace($NikoRuntimeSourceResourceRoot, $NikoRuntimeStagingResourceRoot)
[System.IO.File]::WriteAllText($stagedNikoScene, $nikoSceneText, [System.Text.UTF8Encoding]::new($false))

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
$projectText = Set-StagingBootstrapFontConfiguration $projectText
$projectText = $projectText -replace '(?m)^skin_manifest="[^"]*"$', ('skin_manifest="' + $SkinManifest + '"')
[System.IO.File]::WriteAllText($stagedProjectFile, $projectText, [System.Text.UTF8Encoding]::new($false))

$initialStagingImportArguments = @("--headless", "--editor", "--path", $stagingProject, "--import", "--quit")
Invoke-Godot $initialStagingImportArguments

$projectText = Get-Content -LiteralPath $stagedProjectFile -Raw
$projectText = Set-FormalGlobalFontConfiguration $projectText $stagingProject
[System.IO.File]::WriteAllText($stagedProjectFile, $projectText, [System.Text.UTF8Encoding]::new($false))
$verifiedStagingImportArguments = @("--headless", "--editor", "--path", $stagingProject, "--import", "--quit")
Invoke-Godot $verifiedStagingImportArguments

$platformConfig = @{
	Windows = @{ Preset = "Windows Desktop"; Folder = "windows"; File = "GamePrototype.exe" }
	Linux   = @{ Preset = "Linux"; Folder = "linux"; File = "GamePrototype.x86_64" }
	macOS   = @{ Preset = "macOS"; Folder = "macos"; File = "GamePrototype.zip" }
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
		Invoke-Godot @(
			"--headless", "--path", $inspectorProject, "--script", $inspectorScript,
			"--", $macCorePck,
			"--skin-manifest", $SkinManifest,
			"--asset-manifest", $selectedSkinAssetManifestResource
		)
		$releaseArchive = Join-Path $distRoot "GamePrototype-macOS-universal.zip"
		Copy-Item -LiteralPath $exportPath -Destination $releaseArchive -Force
	} else {
		$corePck = [System.IO.Path]::ChangeExtension($exportPath, ".pck")
		if (-not (Test-Path -LiteralPath $corePck)) { throw "Core PCK was not generated: $corePck" }
		Invoke-Godot @(
			"--headless", "--path", $inspectorProject, "--script", $inspectorScript,
			"--", $corePck,
			"--skin-manifest", $SkinManifest,
			"--asset-manifest", $selectedSkinAssetManifestResource
		)
		Copy-Item -LiteralPath $contentPack -Destination (Join-Path $platformDir "default_content.pck") -Force
		Copy-Item -LiteralPath (Join-Path $projectRoot "docs\PHASE_ONE_PLAYTEST.md") -Destination (Join-Path $platformDir "PLAYTEST.md") -Force
		Copy-Item -LiteralPath (Join-Path $projectRoot "docs\THIRD_PARTY.md") -Destination (Join-Path $platformDir "THIRD_PARTY.md") -Force
		if ($platform -eq "Windows") {
			Assert-WindowsReleaseDirectory $platformDir
			if ($env:OS -eq "Windows_NT") {
				Invoke-WindowsReleaseSmoke $platformDir
			}
			$releaseArchive = Join-Path $distRoot "GamePrototype-Windows-x86_64.zip"
			tar -a -cf $releaseArchive -C $platformDir .
			if ($LASTEXITCODE -ne 0) { throw "Windows archive creation failed" }
			Assert-WindowsReleaseArchive $releaseArchive
		} else {
			$releaseArchive = Join-Path $distRoot "GamePrototype-Linux-x86_64.tar.gz"
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
		sha256 = Get-Sha256Hex $_.FullName
	}
}
$manifest = [ordered]@{
	product = "Game Prototype"
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
