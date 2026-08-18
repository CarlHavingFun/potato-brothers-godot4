[CmdletBinding()]
param(
	[string]$GodotBinary = $env:GODOT_BIN,
	[string]$SkinManifest = "res://content_packs/skins/dev_placeholder/skin.tres",
	[switch]$SkipAcceptance,
	[switch]$SkipTemplateInstall,
	[switch]$KeepTemplateArchive
)

$ErrorActionPreference = "Stop"

if (-not $SkipTemplateInstall) {
	& (Join-Path $PSScriptRoot "install_export_templates.ps1") `
		-GodotBinary $GodotBinary `
		-KeepArchive:$KeepTemplateArchive
}

& (Join-Path $PSScriptRoot "build_release.ps1") `
	-GodotBinary $GodotBinary `
	-Platforms Windows `
	-SkinManifest $SkinManifest `
	-SkipAcceptance:$SkipAcceptance
