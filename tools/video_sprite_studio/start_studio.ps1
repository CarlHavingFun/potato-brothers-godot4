[CmdletBinding()]
param(
    [int]$Port = 8766,
    [string]$Workspace = "",
    [switch]$NoOpen
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $Workspace = Join-Path $env:LOCALAPPDATA "VideoSpriteStudio\workspace"
}
$url = "http://127.0.0.1:$Port/studio/?lang=cn"
$stateUrl = "http://127.0.0.1:$Port/api/studio/state"

function Test-StudioServer {
    try {
        $state = Invoke-RestMethod -Uri $stateUrl -TimeoutSec 2
        return ($null -ne $state.workspace -and $null -ne $state.dependencies)
    } catch {
        return $false
    }
}

if (Test-StudioServer) {
    if (-not $NoOpen) { Start-Process $url }
    Write-Host "Video Sprite Studio is already running: $url"
    exit 0
}

$portOpen = $false
$client = [System.Net.Sockets.TcpClient]::new()
try {
    $connect = $client.ConnectAsync("127.0.0.1", $Port)
    if ($connect.Wait(700)) { $portOpen = $client.Connected }
} catch {
    $portOpen = $false
} finally {
    $client.Dispose()
}
if ($portOpen) {
    throw "Port $Port is occupied by another program. Nothing was terminated; close the owner or use -Port."
}

$spritePython = Join-Path $env:USERPROFILE ".codex\skills\sprite-gen\.venv\Scripts\python.exe"
if (-not (Test-Path -LiteralPath $spritePython -PathType Leaf)) {
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($null -eq $pythonCommand) { throw "Python was not found. Install the sprite-gen environment first." }
    $spritePython = $pythonCommand.Source
}
$logRoot = Join-Path $env:LOCALAPPDATA "VideoSpriteStudio"
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$arguments = @(
    "-m", "tools.video_sprite_studio.studio_server",
    "--workspace", $Workspace,
    "--port", $Port,
    "--no-open"
)
$legacyRun = Join-Path (Split-Path $repoRoot -Parent) "pixelmotion-2d-niko\work\godot-proof\niko-walk-happy-all-frames-selection"
if (Test-Path -LiteralPath (Join-Path $legacyRun "sprite-request.json") -PathType Leaf) {
    $arguments += @("--legacy-run", $legacyRun)
}
Start-Process -FilePath $spritePython -ArgumentList $arguments -WorkingDirectory $repoRoot `
    -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logRoot "studio.stdout.log") `
    -RedirectStandardError (Join-Path $logRoot "studio.stderr.log")

$ready = $false
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    Start-Sleep -Milliseconds 200
    if (Test-StudioServer) { $ready = $true; break }
}
if (-not $ready) {
    throw "Video Sprite Studio did not start. See $logRoot\studio.stderr.log"
}
if (-not $NoOpen) { Start-Process $url }
Write-Host "Video Sprite Studio started: $url"
Write-Host "External workspace: $Workspace"
