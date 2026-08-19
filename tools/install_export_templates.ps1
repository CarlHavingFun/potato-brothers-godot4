[CmdletBinding()]
param(
	[string]$GodotBinary = $env:GODOT_BIN,
	[string]$CacheDirectory = (Join-Path $env:LOCALAPPDATA "LETS_GOOOOO\godot-template-cache"),
	[switch]$KeepArchive
)

$ErrorActionPreference = "Stop"

function Resolve-GodotBinary([string]$Candidate) {
	if ([string]::IsNullOrWhiteSpace($Candidate)) {
		$command = Get-Command godot -ErrorAction SilentlyContinue
		if ($null -ne $command) { $Candidate = $command.Source }
	}
	if ([string]::IsNullOrWhiteSpace($Candidate) -or -not (Test-Path -LiteralPath $Candidate -PathType Leaf)) {
		throw "Godot was not found. Pass -GodotBinary or set GODOT_BIN."
	}
	$consoleBinary = Join-Path (Split-Path -Parent $Candidate) (([System.IO.Path]::GetFileNameWithoutExtension($Candidate)) + "_console.exe")
	if (-not $Candidate.EndsWith("_console.exe", [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $consoleBinary -PathType Leaf)) {
		return $consoleBinary
	}
	return (Resolve-Path -LiteralPath $Candidate).Path
}

function Assert-ChildPath([string]$Path, [string]$Parent) {
	$fullPath = [System.IO.Path]::GetFullPath($Path)
	$fullParent = [System.IO.Path]::GetFullPath($Parent).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
	if (-not $fullPath.StartsWith($fullParent, [System.StringComparison]::OrdinalIgnoreCase)) {
		throw "Unsafe template path outside expected root: $fullPath"
	}
}

$GodotBinary = Resolve-GodotBinary $GodotBinary
$versionLines = @(& $GodotBinary --version)
$versionExitCode = $LASTEXITCODE
$versionOutput = if ($versionLines.Count -gt 0) { $versionLines[0].Trim() } else { "" }
if ($versionExitCode -ne 0 -or $versionOutput -notmatch '^(?<release>\d+\.\d+(?:\.\d+)?)\.(?<channel>stable)\.') {
	throw "Only an official stable Godot build is supported for release export. Found: $versionOutput"
}
$releaseVersion = $Matches.release
$releaseChannel = $Matches.channel
$templateVersion = "$releaseVersion.$releaseChannel"
$releaseTag = "$releaseVersion-$releaseChannel"
$assetName = "Godot_v${releaseTag}_export_templates.tpz"

# Pin the official Godot release assets used by this project. Update this table
# deliberately when the editor version changes; never execute an unverified
# export binary downloaded at build time.
$officialSha256 = @{
	"4.7.stable" = "9714459dc071907c0f3d5f17d608faf69e7cda21331fc5d39c4503ffa4e99eec"
	"4.7.1.stable" = "86409db6200b6f8fd3230989c2d2002851f3dd18acf11d7bdbafddf5a0dd0f72"
}
if (-not $officialSha256.ContainsKey($templateVersion)) {
	throw "No pinned export-template checksum exists for Godot $templateVersion. Update tools/install_export_templates.ps1 after verifying the official release asset."
}

$templateBase = Join-Path $env:APPDATA "Godot\export_templates"
$templateDirectory = Join-Path $templateBase $templateVersion
$requiredFiles = @(
	"windows_release_x86_64.exe",
	"windows_debug_x86_64.exe"
)
$missingFiles = @($requiredFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $templateDirectory $_) -PathType Leaf) })
if ($missingFiles.Count -eq 0) {
	Write-Output "Godot Windows export templates are already installed: $templateDirectory"
	return
}

New-Item -ItemType Directory -Force -Path $CacheDirectory | Out-Null
$CacheDirectory = (Resolve-Path -LiteralPath $CacheDirectory).Path
$archivePath = Join-Path $CacheDirectory $assetName
Assert-ChildPath $archivePath $CacheDirectory
$partialPath = "$archivePath.partial"
Assert-ChildPath $partialPath $CacheDirectory
$downloadUrl = "https://github.com/godotengine/godot/releases/download/$releaseTag/$assetName"

$archiveIsValid = $false
if (Test-Path -LiteralPath $archivePath -PathType Leaf) {
	$archiveIsValid = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.Equals(
		$officialSha256[$templateVersion],
		[System.StringComparison]::OrdinalIgnoreCase
	)
	if (-not $archiveIsValid) {
		Remove-Item -LiteralPath $archivePath -Force
	}
}
if (-not $archiveIsValid) {
	Write-Output "Downloading verified Godot $templateVersion export templates (first build only, about 1.3 GB)..."
	$curl = Get-Command curl.exe -ErrorAction SilentlyContinue
	if ($null -ne $curl) {
		& $curl.Source --location --fail --retry 3 --retry-delay 2 --continue-at - --output $partialPath $downloadUrl
		if ($LASTEXITCODE -ne 0) { throw "Official export-template download failed with exit code $LASTEXITCODE." }
	} else {
		if (Test-Path -LiteralPath $partialPath) { Remove-Item -LiteralPath $partialPath -Force }
		Invoke-WebRequest -Uri $downloadUrl -OutFile $partialPath -UseBasicParsing
	}
	$downloadedHash = (Get-FileHash -LiteralPath $partialPath -Algorithm SHA256).Hash
	if (-not $downloadedHash.Equals($officialSha256[$templateVersion], [System.StringComparison]::OrdinalIgnoreCase)) {
		Remove-Item -LiteralPath $partialPath -Force
		throw "Export-template checksum mismatch. Expected $($officialSha256[$templateVersion]), got $downloadedHash."
	}
	Move-Item -LiteralPath $partialPath -Destination $archivePath -Force
}

$actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
if (-not $actualHash.Equals($officialSha256[$templateVersion], [System.StringComparison]::OrdinalIgnoreCase)) {
	throw "Export-template checksum mismatch. Expected $($officialSha256[$templateVersion]), got $actualHash."
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$extractRoot = Join-Path $CacheDirectory ("extract-" + [Guid]::NewGuid().ToString("N"))
Assert-ChildPath $extractRoot $CacheDirectory
New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
try {
	$archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
	try {
		$entriesToExtract = @($requiredFiles + "version.txt")
		foreach ($fileName in $entriesToExtract) {
			$entryName = "templates/$fileName"
			$entry = $archive.Entries | Where-Object { $_.FullName -eq $entryName } | Select-Object -First 1
			if ($null -eq $entry) { throw "Official template archive is missing $entryName." }
			$destination = Join-Path $extractRoot $fileName
			[System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destination, $true)
		}
	} finally {
		$archive.Dispose()
	}

	New-Item -ItemType Directory -Force -Path $templateDirectory | Out-Null
	foreach ($fileName in @($requiredFiles + "version.txt")) {
		Copy-Item -LiteralPath (Join-Path $extractRoot $fileName) -Destination (Join-Path $templateDirectory $fileName) -Force
	}
} finally {
	if (Test-Path -LiteralPath $extractRoot) { Remove-Item -LiteralPath $extractRoot -Recurse -Force }
}

foreach ($fileName in $requiredFiles) {
	$installedPath = Join-Path $templateDirectory $fileName
	if (-not (Test-Path -LiteralPath $installedPath -PathType Leaf) -or (Get-Item -LiteralPath $installedPath).Length -le 0) {
		throw "Godot export template was not installed correctly: $installedPath"
	}
}
if (-not $KeepArchive -and (Test-Path -LiteralPath $archivePath)) {
	Remove-Item -LiteralPath $archivePath -Force
}
Write-Output "Installed verified Godot Windows export templates: $templateDirectory"
