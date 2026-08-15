[CmdletBinding()]
param(
	[string]$GodotBinary = $env:GODOT_BIN,
	[string]$SourceRoot = "res://content_packs/default",
	[string]$ManifestPath = "res://content_packs/default/pack.tres",
	[string]$OutputPath = "res://builds/content/default_content.pck"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($GodotBinary)) {
	$godotCommand = Get-Command godot -ErrorAction SilentlyContinue
	if ($null -ne $godotCommand) {
		$GodotBinary = $godotCommand.Source
	}
}
if ([string]::IsNullOrWhiteSpace($GodotBinary) -or -not (Test-Path -LiteralPath $GodotBinary)) {
	throw "Godot 4.7.1 was not found. Pass -GodotBinary or set GODOT_BIN."
}
$consoleBinary = Join-Path (Split-Path -Parent $GodotBinary) (([System.IO.Path]::GetFileNameWithoutExtension($GodotBinary)) + "_console.exe")
if (-not $GodotBinary.EndsWith("_console.exe", [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $consoleBinary)) {
	$GodotBinary = $consoleBinary
}

& $GodotBinary --headless --path $projectRoot res://tools/content/validate_content_pack.tscn -- `
	--manifest $ManifestPath --source-root $SourceRoot
if ($LASTEXITCODE -ne 0) {
	exit $LASTEXITCODE
}

& $GodotBinary --headless --path $projectRoot res://tools/content/build_content_pack.tscn -- `
	--manifest $ManifestPath --source-root $SourceRoot --output $OutputPath
exit $LASTEXITCODE
