param(
    [ValidateSet('Source','Pck')][string]$Mode = 'Source',
    [string]$SubjectRoot = (Join-Path $PSScriptRoot '../..'),
    [string]$GodotBinary = 'E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64.exe',
    [string]$EvidenceDirectory = (Join-Path $PSScriptRoot '../../reports/checkpoint-cross-process')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-NoReparse([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if ((Test-Path -LiteralPath $cursor) -and
            ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Reparse traversal rejected: $cursor"
        }
        $parent = Split-Path -Parent $cursor
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
}

function Assert-NoReparseDirectories([string]$Root) {
    Assert-NoReparse $Root
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return }
    # Get-ChildItem does not follow directory links by default, but it does return
    # the link node. Reject every directory node before enumerating files so a
    # subject cannot hide executable res:// content behind an unhashed junction.
    foreach ($directory in @(Get-ChildItem -LiteralPath $Root -Directory -Recurse -Force)) {
        Assert-NoReparse $directory.FullName
    }
}

function Get-GuardedSha256([string]$Path) {
    Assert-NoReparse $Path
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Guarded file is missing: $Path" }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-GuardedLength([string]$Path) {
    Assert-NoReparse $Path
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Guarded file is missing: $Path" }
    return [long](Get-Item -LiteralPath $Path -Force).Length
}

function Copy-GuardedFile([string]$Source,[string]$Destination) {
    Assert-NoReparse $Source
    Assert-NoReparse $Destination
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "Guarded source is missing: $Source" }
    Copy-Item -LiteralPath $Source -Destination $Destination
    Assert-NoReparse $Destination
}

function Canonical([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd('\','/').Replace('\','/')
}

function Assert-PinnedFiles([System.Collections.IDictionary]$Pins,[string]$Stage) {
    foreach ($name in $Pins.Keys) {
        $entry = $Pins[$name]
        Assert-NoReparse $entry.path
        if (-not (Test-Path -LiteralPath $entry.path -PathType Leaf) -or
            (Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash -cne $entry.sha256) {
            throw "Pinned input changed at $Stage`: $name"
        }
    }
}

function Assert-FrozenBindings([System.Collections.IDictionary]$Pins,[string]$Stage) {
    foreach ($pair in @(@('fixture','fixture_source'),@('lifecycle','lifecycle_source'),@('verifier','verifier_source'))) {
        if ($Pins[$pair[0]].sha256 -cne $Pins[$pair[1]].sha256) {
            throw "Frozen/source binding mismatch at $Stage`: $($pair[0])"
        }
    }
}

function Assert-JsonInteger($Value,[long]$Expected,[string]$Name) {
    if (($Value -isnot [long] -and $Value -isnot [int]) -or [long]$Value -ne $Expected) {
        throw "$Name must be the exact JSON integer $Expected."
    }
}

function Assert-JsonBoolean($Value,[bool]$Expected,[string]$Name) {
    if ($Value -isnot [bool] -or $Value -ne $Expected) {
        throw "$Name must be the exact JSON boolean $Expected."
    }
}

function Assert-JsonString($Value,[string]$Name) {
    if ($Value -isnot [string]) { throw "$Name must be a JSON string." }
}

function Assert-DecimalString($Value,[string]$Name) {
    Assert-JsonString $Value $Name
    if ($Value -notmatch '^-?[0-9]+$') { throw "$Name must be an exact decimal integer string." }
}

function Assert-HexSha256($Value,[string]$Name) {
    Assert-JsonString $Value $Name
    if ($Value -notmatch '^[A-F0-9]{64}$') { throw "$Name must be an uppercase SHA-256 string." }
}

function Assert-DecimalStringArray($Value,[int]$Count,[string]$Name) {
    if ($Value -isnot [Array] -or $Value.Count -ne $Count) { throw "$Name must be a $Count-element JSON array." }
    for ($index = 0; $index -lt $Value.Count; $index++) {
        Assert-DecimalString $Value[$index] "${Name}[$index]"
    }
}

function Assert-RichW22Summary($Summary,[string]$Name) {
    foreach ($field in @('phase','elapsed_seconds','economy_remainder','current_health','max_health')) {
        Assert-JsonString $Summary.$field "$Name $field"
    }
    foreach ($field in @('endless','shop_initialized')) {
        Assert-JsonBoolean $Summary.$field $true "$Name $field"
    }
    $expectedIntegers = [ordered]@{
        wave=22;total_waves=20;weapon_count=6;item_count=4;upgrade_count=4
        shop_offer_wave=21;shop_offer_count=4;locked_count=2;level=12;materials=98765
        base_stat_count=8;final_stat_count=10;shop_initialization_id=41
        reroll_count=5;upgrade_reroll_count=3;pending_upgrade_count=0
    }
    foreach ($field in $expectedIntegers.Keys) {
        Assert-JsonInteger $Summary.$field ([long]$expectedIntegers[$field]) "$Name $field"
    }
    if ($Summary.phase -cne 'combat' -or $Summary.elapsed_seconds -cne '987.625' -or
        $Summary.economy_remainder -cne '0.375' -or $Summary.current_health -cne '37.25' -or
        $Summary.max_health -cne '64.5') {
        throw "$Name rich W22 literal summary mismatch."
    }
}

function Get-SubjectInventory([string]$Root,[string]$Kind) {
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $rootPrefix = $rootPath + [IO.Path]::DirectorySeparatorChar
    $items = if ($Kind -ieq 'Source') {
        $list = @()
        foreach ($relative in @('project.godot','export_presets.cfg','default_bus_layout.tres','icon.svg','icon.svg.import')) {
            $path = Join-Path $rootPath $relative
            if (Test-Path -LiteralPath $path -PathType Leaf) { $list += Get-Item -LiteralPath $path -Force }
        }
        $gameRoot = Join-Path $rootPath 'game'
        Assert-NoReparseDirectories $gameRoot
        $list += @(Get-ChildItem -LiteralPath $gameRoot -File -Recurse -Force)
        @($list | Sort-Object FullName)
    } else {
        Assert-NoReparseDirectories $rootPath
        @(Get-ChildItem -LiteralPath $rootPath -File -Recurse -Force | Sort-Object FullName)
    }
    $records = @()
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($item in $items) {
        Assert-NoReparse $item.FullName
        $full = [IO.Path]::GetFullPath($item.FullName)
        if (-not $full.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase)) {
            throw 'Subject inventory escaped its root.'
        }
        $relative = $full.Substring($rootPrefix.Length).Replace('\','/')
        $hash = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
        $records += [ordered]@{path=$relative;bytes=[long]$item.Length;sha256=$hash}
        $lines.Add($relative + "`t" + $item.Length + "`t" + $hash)
    }
    $utf8 = [Text.UTF8Encoding]::new($false)
    $fingerprint = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData($utf8.GetBytes(($lines.ToArray() -join "`n")))
    )
    return [pscustomobject]@{records=$records;fingerprint=$fingerprint;count=$records.Count}
}

function Assert-OwnedSuccess($Record,[string]$Role) {
    if (-not $Record.started -or -not $Record.owned -or $Record.pid -isnot [int] -or $Record.pid -le 0 -or
        -not $Record.start_receipt_written -or $Record.end_pid -ne $Record.pid -or
        $Record.has_exited -ne $true -or $Record.exit_code -ne 0 -or $Record.timed_out -or
        $Record.kill_requested -or -not $Record.stdout_complete -or -not $Record.stderr_complete -or
        -not $Record.stdout_written -or -not $Record.stderr_written -or
        -not $Record.stdout_disposed -or -not $Record.stderr_disposed -or
        -not $Record.streams_disposed -or -not $Record.disposed -or
        $Record.cleanup_errors.Count -or $Record.exception) {
        throw "Role $Role owned process lifecycle is incomplete."
    }
}

function Assert-PidAbsent([int]$ProcessId) {
    try {
        $probe = [Diagnostics.Process]::GetProcessById($ProcessId)
        try {
            if (-not $probe.HasExited) { throw "Previously owned PID $ProcessId still exists; B cannot start." }
        } finally { $probe.Dispose() }
    } catch [ArgumentException] {
        return
    }
}

function Get-Marker([string]$Output,[string]$Name) {
    $lines = @($Output -split '\r?\n' | Where-Object { $_ -match ('^' + [regex]::Escape($Name) + ' ') })
    if ($lines.Count -ne 1) { throw "Expected exactly one $Name marker." }
    return $lines[0].Substring($Name.Length + 1) | ConvertFrom-Json
}

function Assert-Guard($Guard,[string]$Role,[string]$ModeName,$Record,$Child,[string]$Subject) {
    Assert-JsonInteger $Guard.schema_version 1 "Role $Role guard schema_version"
    Assert-JsonInteger $Guard.pid ([long]$Record.pid) "Role $Role guard pid"
    foreach ($field in @('phase','role','mode','subject_root')) { Assert-JsonString $Guard.$field "Role $Role guard $field" }
    if ($Guard.schema_version -ne 1 -or $Guard.phase -cne 'before-project-profile-read' -or
        $Guard.pid -ne $Record.pid -or $Guard.role -cne $Role -or $Guard.mode -cne $ModeName -or
        (Canonical $Guard.subject_root) -cne (Canonical $Subject)) {
        throw "Role $Role guard identity mismatch."
    }
    foreach ($pair in @(
        @('appdata','APPDATA'),@('localappdata','LOCALAPPDATA'),@('temp','TEMP'),@('tmp','TMP'),
        @('userprofile','USERPROFILE'),@('expected_appdata','GOGOBRO_TEST_EXPECTED_APPDATA'),
        @('expected_localappdata','GOGOBRO_TEST_EXPECTED_LOCALAPPDATA'),
		@('expected_temp','GOGOBRO_TEST_EXPECTED_TEMP'),@('expected_tmp','GOGOBRO_TEST_EXPECTED_TMP'),
		@('expected_userprofile','GOGOBRO_TEST_EXPECTED_USERPROFILE'),
        @('expected_user_data','GOGOBRO_TEST_EXPECTED_USER_DATA_DIR'),
        @('user_data','GOGOBRO_TEST_EXPECTED_USER_DATA_DIR')
    )) {
        if ($Guard.($pair[0]) -isnot [string] -or
            (Canonical $Guard.($pair[0])) -cne (Canonical $Child[$pair[1]])) {
            throw "Role $Role guard path mismatch: $($pair[0])"
        }
    }
    $expectedProfile = $Role -ceq 'B'
    if ($Guard.profile_before.profile -isnot [bool] -or
        $Guard.profile_before.temporary -isnot [bool] -or
        $Guard.profile_before.backup -isnot [bool] -or
        $Guard.profile_before.profile -ne $expectedProfile -or
        $Guard.profile_before.temporary -or $Guard.profile_before.backup) {
        throw "Role $Role guard profile presence mismatch."
    }
}

function New-RoleProcess(
    [string]$Role,[string]$ModeName,[string]$Subject,[string]$Fixture,
    [string]$Engine,[System.Collections.IDictionary]$Child,[string]$Working
) {
    $arguments = [Collections.Generic.List[string]]::new()
    foreach ($argument in @('--headless','--verbose','--max-fps','60','--quit-after','1200')) {
        $arguments.Add($argument)
    }
    if ($ModeName -ceq 'source') {
        $arguments.Add('--path'); $arguments.Add($Subject)
    } else {
        $arguments.Add('--main-pack'); $arguments.Add((Join-Path $Subject 'GOGOBRO.pck'))
    }
    $arguments.Add('--script'); $arguments.Add($Fixture); $arguments.Add('--')
    foreach ($argument in @('--role',$Role,'--mode',$ModeName,'--subject-root',$Subject)) {
        $arguments.Add($argument)
    }
    $psi = [Diagnostics.ProcessStartInfo]::new($Engine)
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $Working
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($argument in $arguments) { $psi.ArgumentList.Add([string]$argument) }
    foreach ($key in $Child.Keys) { $psi.Environment[$key] = [string]$Child[$key] }
    return [pscustomobject]@{psi=$psi;arguments=@($arguments)}
}

function Invoke-Role(
    [string]$Role,[string]$ModeName,[string]$Subject,[string]$Fixture,
    [string]$Engine,[System.Collections.IDictionary]$Child,[string]$Working,[string]$RunDirectory
) {
    $completionPath = Join-Path $RunDirectory ("role-$Role.completion.json")
    $record = [ordered]@{
        role=$Role;arguments=@();working_directory=$Working
        stdout_path=(Join-Path $RunDirectory ("role-$Role.stdout.log"))
        stderr_path=(Join-Path $RunDirectory ("role-$Role.stderr.log"))
        verification_exception=$null;cleanup_errors=@()
        final_receipt=$completionPath;final_receipt_written=$false
    }
    $output = [pscustomobject]@{out='';err=''}
    $roleFailure = $null
    try {
        $configured = New-RoleProcess $Role $ModeName $Subject $Fixture $Engine $Child $Working
        $record.arguments = $configured.arguments
        foreach ($key in $Child.Keys) {
            if ($configured.psi.Environment[$key] -cne [string]$Child[$key]) {
                throw "Role $Role child environment mismatch: $key"
            }
        }
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $configured.psi
        $output = Invoke-OwnedProcess $process $record $record.stdout_path $record.stderr_path `
            (Join-Path $RunDirectory ("role-$Role.start.json"))
        Assert-OwnedSuccess $record $Role
        if ($output.err.Trim().Length -gt 0 -or
            $output.out -match 'SCRIPT ERROR:|(?m)^ERROR:|CROSS_ISOLATION_FAIL|CROSS_FAILED') {
            throw "Role $Role emitted an engine/fixture error."
        }
        $finalLine = @($output.out -split '\r?\n' | Where-Object { $_ -match '^CROSS_PROCESS_RESULT ' })
        if ($finalLine.Count -ne 1 -or $finalLine[0] -cne 'CROSS_PROCESS_RESULT failures=0') {
            throw "Role $Role did not report an exact zero-failure completion."
        }
    } catch {
        $roleFailure = $_
        $record.verification_exception = $_.Exception.Message
    } finally {
        Write-OwnedCompletion $record $completionPath
    }
    if (-not $record.final_receipt_written -and -not $roleFailure) {
        $roleFailure = [InvalidOperationException]::new("Role $Role completion receipt was not written.")
    }
    return [pscustomobject]@{record=$record;output=$output.out;failure=$roleFailure}
}

$subject = [IO.Path]::GetFullPath($SubjectRoot).TrimEnd('\','/')
Assert-NoReparse $subject
if (-not (Test-Path -LiteralPath $subject -PathType Container)) { throw 'SubjectRoot must be an existing directory.' }
$modeName = $Mode.ToLowerInvariant()
if ($Mode -ieq 'Source') {
    if (-not (Test-Path -LiteralPath (Join-Path $subject 'project.godot') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $subject 'game') -PathType Container)) {
        throw 'Source subject is missing project.godot or game/.'
    }
} elseif (-not (Test-Path -LiteralPath (Join-Path $subject 'GOGOBRO.pck') -PathType Leaf)) {
    throw 'Pck subject is missing GOGOBRO.pck.'
}

$engine = [IO.Path]::GetFullPath($GodotBinary)
if ($engine.EndsWith('_console.exe',[StringComparison]::OrdinalIgnoreCase)) {
    $engine = $engine -replace '_console\.exe$','.exe'
}
Assert-NoReparse $engine
if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) { throw 'GodotBinary must be an existing executable.' }

# Admission is read-only. The verifier never kills by image name; timeout cleanup
# is restricted to the exact Process object/PID captured by owned_process_lifecycle.
$active = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(Godot.*|GOGOBRO)\.exe$' })
if ($active.Count) { throw 'Godot/GOGOBRO process already exists; refusing cross-process verification.' }

$evidenceBase = [IO.Path]::GetFullPath($EvidenceDirectory)
Assert-NoReparse $evidenceBase
if (-not (Test-Path -LiteralPath $evidenceBase)) { $null = New-Item -ItemType Directory -Path $evidenceBase }
$runDirectory = Join-Path $evidenceBase ('run-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ') + '-' + [guid]::NewGuid().ToString('N'))
if (Test-Path -LiteralPath $runDirectory) { throw 'Fresh evidence directory collision.' }
$null = New-Item -ItemType Directory -Path $runDirectory

$parentLocalAppData = [Environment]::GetEnvironmentVariable('LOCALAPPDATA','Process')
if ([string]::IsNullOrWhiteSpace($parentLocalAppData) -or -not [IO.Path]::IsPathRooted($parentLocalAppData)) {
    throw 'Parent LOCALAPPDATA must be an absolute path for the external scratch root.'
}
$scratchBase = Join-Path $parentLocalAppData 'Temp\GOGOBRO-Codex\checkpoint-cross-process'
Assert-NoReparse $scratchBase
$scratch = Join-Path $scratchBase ('run-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ') + '-' + [guid]::NewGuid().ToString('N'))
$subjectCanonical = Canonical $subject
$scratchCanonical = Canonical $scratch
$subjectPrefix = $subjectCanonical + '/'
$scratchPrefix = $scratchCanonical + '/'
if ($scratchCanonical.Equals($subjectCanonical,[StringComparison]::OrdinalIgnoreCase) -or
    $scratchCanonical.StartsWith($subjectPrefix,[StringComparison]::OrdinalIgnoreCase) -or
    $subjectCanonical.StartsWith($scratchPrefix,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'Synthetic profile scratch must be outside SubjectRoot.'
}
if (Test-Path -LiteralPath $scratch) { throw 'Fresh scratch directory collision.' }
$null = New-Item -ItemType Directory -Path $scratch
$child = [ordered]@{
    APPDATA=(Join-Path $scratch 'Roaming')
    LOCALAPPDATA=(Join-Path $scratch 'Local')
    TEMP=(Join-Path $scratch 'Temp')
    TMP=(Join-Path $scratch 'Temp')
    USERPROFILE=(Join-Path $scratch 'UserProfile')
    GOGOBRO_TEST_EXPECTED_APPDATA=(Join-Path $scratch 'Roaming')
    GOGOBRO_TEST_EXPECTED_LOCALAPPDATA=(Join-Path $scratch 'Local')
	GOGOBRO_TEST_EXPECTED_TEMP=(Join-Path $scratch 'Temp')
	GOGOBRO_TEST_EXPECTED_TMP=(Join-Path $scratch 'Temp')
	GOGOBRO_TEST_EXPECTED_USERPROFILE=(Join-Path $scratch 'UserProfile')
    GOGOBRO_TEST_EXPECTED_USER_DATA_DIR=(Join-Path (Join-Path $scratch 'Roaming') 'GOGOBRO')
}
foreach ($path in @($child.APPDATA,$child.LOCALAPPDATA,$child.TEMP,$child.USERPROFILE)) {
    Assert-NoReparse $path
    $null = New-Item -ItemType Directory -Path $path
}
$workingA = Join-Path $scratch 'working-A'
$null = New-Item -ItemType Directory -Path $workingA
$workingB = Join-Path $scratch 'working-B'
$null = New-Item -ItemType Directory -Path $workingB
$profilePath = Join-Path $child.GOGOBRO_TEST_EXPECTED_USER_DATA_DIR 'GOGOBRO/profile.json'
$tempProfilePath = Join-Path $child.GOGOBRO_TEST_EXPECTED_USER_DATA_DIR 'GOGOBRO/profile.tmp'
$backupProfilePath = Join-Path $child.GOGOBRO_TEST_EXPECTED_USER_DATA_DIR 'GOGOBRO/profile.backup'
foreach ($path in @($profilePath,$tempProfilePath,$backupProfilePath)) {
    if (Test-Path -LiteralPath $path) { throw 'Fresh synthetic profile path unexpectedly exists.' }
}

$fixtureSource = Join-Path $PSScriptRoot '../../tools/playtest_packaging/checkpoint_cross_process_smoke.gd'
$lifecycleSource = Join-Path $PSScriptRoot '../../tools/playtest_packaging/owned_process_lifecycle.ps1'
foreach ($path in @($fixtureSource,$lifecycleSource,$PSCommandPath)) { Assert-NoReparse $path }
$fixture = Join-Path $runDirectory 'checkpoint_cross_process_smoke.gd'
$verifierAtRun = Join-Path $runDirectory 'verifier.at-run.ps1'
$lifecycleAtRun = Join-Path $runDirectory 'owned_process_lifecycle.at-run.ps1'
Copy-GuardedFile $fixtureSource $fixture
if ((Get-GuardedSha256 $fixture) -cne (Get-GuardedSha256 $fixtureSource)) {
    throw 'Frozen fixture copy mismatch.'
}
Copy-GuardedFile $PSCommandPath $verifierAtRun
Copy-GuardedFile $lifecycleSource $lifecycleAtRun
$pinnedFiles = [ordered]@{
    engine=[ordered]@{path=$engine;sha256=(Get-GuardedSha256 $engine)}
    fixture=[ordered]@{path=$fixture;sha256=(Get-GuardedSha256 $fixture)}
    fixture_source=[ordered]@{path=$fixtureSource;sha256=(Get-GuardedSha256 $fixtureSource)}
    lifecycle=[ordered]@{path=$lifecycleAtRun;sha256=(Get-GuardedSha256 $lifecycleAtRun)}
    lifecycle_source=[ordered]@{path=$lifecycleSource;sha256=(Get-GuardedSha256 $lifecycleSource)}
    verifier=[ordered]@{path=$verifierAtRun;sha256=(Get-GuardedSha256 $verifierAtRun)}
    verifier_source=[ordered]@{path=$PSCommandPath;sha256=(Get-GuardedSha256 $PSCommandPath)}
}
Assert-PinnedFiles $pinnedFiles 'initialization'
Assert-FrozenBindings $pinnedFiles 'initialization'
. $lifecycleAtRun

$parentEnvironment = [ordered]@{}
foreach ($key in $child.Keys) {
    $parentEnvironment[$key] = [ordered]@{
        present=(Test-Path "Env:$key")
        value=[Environment]::GetEnvironmentVariable($key,'Process')
    }
}
$subjectBefore = Get-SubjectInventory $subject $Mode
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $runDirectory 'subject-before.json'),($subjectBefore.records | ConvertTo-Json -Depth 4),$utf8)

$result = [ordered]@{
    schema_version=1;mode=$modeName;subject=$subject;evidence_directory=$runDirectory
    engine=$engine;engine_sha256=$pinnedFiles.engine.sha256
    fixture_source=$fixtureSource;fixture=$fixture;fixture_sha256=$pinnedFiles.fixture.sha256
    lifecycle_source=$lifecycleSource;lifecycle=$lifecycleAtRun;lifecycle_sha256=$pinnedFiles.lifecycle.sha256
    verifier=$verifierAtRun;pinned_files=$pinnedFiles;pinned_inputs_unchanged=$false;frozen_bindings_unchanged=$false
    environment=$child;parent_environment=$parentEnvironment
    process_count=0;pid_distinct=$false;temporal_non_overlap=$false;guards_ok=$false;same_scratch=$false
    continue_button_pressed=$false;published_once=$false;profile_sha_stable=$false;sidecars_absent=$false;w1_disk_immediate=$false
    rich_w22_boundary_exact=$false
    variant_type_array_order_exact=$false;rng_state_exact=$false;rng_next_sequence_exact=$false
    source_or_pck_unchanged=$false;fixture_unchanged=$false;parent_environment_unchanged=$false
    wave_boundary_restart=$false;mid_wave_claim=$false;resume_claim=$false
    role_a=$null;role_b=$null;a_finalize_return_utc=$null;guard_a=$null;guard_b=$null;receipt_a=$null;receipt_b=$null
    profile_after_a=$null;profile_after_b=$null;state_artifact=$null;raw_artifact=$null;exception=$null
    cleanup_errors=@();final_receipt=(Join-Path $runDirectory 'completion.json');final_receipt_written=$false
}
$failure = $null
try {
    Assert-PinnedFiles $pinnedFiles 'before-role-A'
    $a = Invoke-Role 'A' $modeName $subject $fixture $engine $child $workingA $runDirectory
    $result.role_a = $a.record
    if ($a.record.Contains('started') -and $a.record.started) { $result.process_count = 1 }
    if ($a.failure) { throw $a.failure }
    $guardA = Get-Marker $a.output 'CROSS_ISOLATION_OK'
    $result.guard_a = $guardA
    $receiptA = Get-Marker $a.output 'CROSS_A_SAVED'
    $result.receipt_a = $receiptA
    Assert-Guard $guardA 'A' $modeName $a.record $child $subject
    Assert-JsonInteger $receiptA.pid ([long]$a.record.pid) 'A receipt pid'
    Assert-JsonInteger $receiptA.schema 3 'A receipt schema'
    Assert-JsonInteger $receiptA.wave 22 'A receipt wave'
    Assert-JsonString $receiptA.phase 'A receipt phase'
    Assert-JsonBoolean $receiptA.variant_type_array_order_exact $true 'A receipt variant_type_array_order_exact'
    Assert-JsonBoolean $receiptA.w1_disk_immediate $true 'A receipt w1_disk_immediate'
    Assert-JsonBoolean $receiptA.rich_w22_boundary_exact $true 'A receipt rich_w22_boundary_exact'
    Assert-RichW22Summary $receiptA.rich_summary 'A receipt rich_summary'
    Assert-HexSha256 $receiptA.w1_profile_sha256 'A receipt w1_profile_sha256'
    foreach ($field in @('profile','temporary','backup')) {
        Assert-JsonBoolean $receiptA.w1_profile_presence.$field ($field -ceq 'profile') "A receipt w1_profile_presence.$field"
        Assert-JsonBoolean $receiptA.profile_presence.$field ($field -ceq 'profile') "A receipt profile_presence.$field"
    }
    foreach ($field in @('rng_state_exact','wave_boundary_restart')) {
        Assert-JsonBoolean $receiptA.$field $true "A receipt $field"
    }
    Assert-JsonBoolean $receiptA.mid_wave_claim $false 'A receipt mid_wave_claim'
    Assert-DecimalString $receiptA.run_seed 'A receipt run_seed'
    if ($receiptA.run_seed -cne '9007199254740993') { throw 'A receipt run_seed mismatch.' }
    Assert-DecimalString $receiptA.rng_state 'A receipt rng_state'
    Assert-DecimalStringArray $receiptA.rng_next 3 'A receipt rng_next'
    foreach ($field in @('state_digest','state_bytes_sha256','raw_digest','raw_bytes_sha256','profile_sha256')) {
        Assert-HexSha256 $receiptA.$field "A receipt $field"
    }
    if ($receiptA.pid -ne $a.record.pid -or $receiptA.schema -ne 3 -or $receiptA.wave -ne 22 -or
        $receiptA.phase -cne 'combat' -or $receiptA.variant_type_array_order_exact -ne $true -or
        $receiptA.w1_disk_immediate -ne $true -or $receiptA.w1_profile_sha256 -notmatch '^[A-F0-9]{64}$' -or
        $receiptA.w1_profile_presence.profile -ne $true -or $receiptA.w1_profile_presence.temporary -ne $false -or
        $receiptA.w1_profile_presence.backup -ne $false -or
        $receiptA.rng_state_exact -ne $true -or $receiptA.rich_w22_boundary_exact -ne $true -or
        $receiptA.wave_boundary_restart -ne $true -or
        $receiptA.mid_wave_claim -ne $false) {
        throw 'A checkpoint receipt mismatch.'
    }
    $result.w1_disk_immediate = $true
    $aFinalize = [DateTimeOffset]::UtcNow
    $result.a_finalize_return_utc = $aFinalize.ToString('o')
    Assert-PidAbsent $a.record.pid
    foreach ($path in @($profilePath,$tempProfilePath,$backupProfilePath)) { Assert-NoReparse $path }
    if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf) -or
        (Test-Path -LiteralPath $tempProfilePath) -or (Test-Path -LiteralPath $backupProfilePath)) {
        throw 'A parent-side profile presence mismatch.'
    }
    Assert-NoReparse $profilePath
    $profileShaA = Get-GuardedSha256 $profilePath
    if ($profileShaA -cne $receiptA.profile_sha256) { throw 'A parent/fixture profile SHA mismatch.' }
    $profileCopyA = Join-Path $runDirectory 'profile-after-A.json'
    Copy-GuardedFile $profilePath $profileCopyA
    if ((Get-GuardedSha256 $profileCopyA) -cne $profileShaA) { throw 'A profile evidence copy mismatch.' }
    $stateArtifact = Join-Path $child.TEMP 'checkpoint-cross-process-a-state.bin'
    Assert-NoReparse $stateArtifact
    if (-not (Test-Path -LiteralPath $stateArtifact -PathType Leaf)) { throw 'A state artifact is missing.' }
    $stateArtifactCopy = Join-Path $runDirectory 'state-after-A.bin'
    Copy-GuardedFile $stateArtifact $stateArtifactCopy
    $rawArtifact = Join-Path $child.TEMP 'checkpoint-cross-process-a-raw.bin'
    Assert-NoReparse $rawArtifact
    if (-not (Test-Path -LiteralPath $rawArtifact -PathType Leaf)) { throw 'A raw artifact is missing.' }
    $rawArtifactCopy = Join-Path $runDirectory 'raw-after-A.bin'
    Copy-GuardedFile $rawArtifact $rawArtifactCopy
    if ((Get-GuardedSha256 $stateArtifactCopy) -cne (Get-GuardedSha256 $stateArtifact) -or
        (Get-GuardedSha256 $rawArtifactCopy) -cne (Get-GuardedSha256 $rawArtifact)) {
        throw 'A typed state/raw evidence copy mismatch.'
    }
    $result.profile_after_a = [ordered]@{path=$profilePath;copy=$profileCopyA;sha256=$profileShaA;bytes=(Get-GuardedLength $profilePath)}
    $result.state_artifact = [ordered]@{path=$stateArtifact;copy=$stateArtifactCopy;sha256=(Get-GuardedSha256 $stateArtifact);bytes=(Get-GuardedLength $stateArtifact)}
    $result.raw_artifact = [ordered]@{path=$rawArtifact;copy=$rawArtifactCopy;sha256=(Get-GuardedSha256 $rawArtifact);bytes=(Get-GuardedLength $rawArtifact)}

    # B is constructed only after A's Process object has fully finalized and its
    # exact PID has been proven absent. No process-name termination is used.
    Assert-PinnedFiles $pinnedFiles 'before-role-B'
    $b = Invoke-Role 'B' $modeName $subject $fixture $engine $child $workingB $runDirectory
    $result.role_b = $b.record
    if ($b.record.Contains('started') -and $b.record.started) { $result.process_count = 2 }
    if ($b.failure) { throw $b.failure }
    $guardB = Get-Marker $b.output 'CROSS_ISOLATION_OK'
    $result.guard_b = $guardB
    $receiptB = Get-Marker $b.output 'CROSS_B_RESUMED'
    $result.receipt_b = $receiptB
    Assert-Guard $guardB 'B' $modeName $b.record $child $subject
    Assert-JsonInteger $receiptB.pid ([long]$b.record.pid) 'B receipt pid'
    Assert-JsonInteger $receiptB.schema 3 'B receipt schema'
    Assert-JsonInteger $receiptB.wave 22 'B receipt wave'
    Assert-JsonInteger $receiptB.published_count 1 'B receipt published_count'
    Assert-JsonBoolean $receiptB.rich_w22_boundary_exact $true 'B receipt rich_w22_boundary_exact'
    Assert-RichW22Summary $receiptB.rich_summary 'B receipt rich_summary'
    foreach ($field in @('phase','route')) { Assert-JsonString $receiptB.$field "B receipt $field" }
    foreach ($field in @('world_running','continue_button_pressed','ui_control_signal',
        'variant_type_array_order_exact','rng_state_exact','wave_boundary_restart')) {
        Assert-JsonBoolean $receiptB.$field $true "B receipt $field"
    }
    foreach ($field in @('os_input','mid_wave_claim')) {
        Assert-JsonBoolean $receiptB.$field $false "B receipt $field"
    }
    foreach ($field in @('profile','temporary','backup')) {
        Assert-JsonBoolean $receiptB.profile_presence.$field ($field -ceq 'profile') "B receipt profile_presence.$field"
    }
    Assert-DecimalString $receiptB.run_seed 'B receipt run_seed'
    Assert-DecimalString $receiptB.rng_state 'B receipt rng_state'
    Assert-DecimalStringArray $receiptB.rng_next 3 'B receipt rng_next'
    foreach ($field in @('state_digest','state_bytes_sha256','raw_digest','raw_bytes_sha256',
        'profile_sha_preboot','profile_sha_postboot','profile_sha_postcontinue')) {
        Assert-HexSha256 $receiptB.$field "B receipt $field"
    }
    if ($receiptB.pid -ne $b.record.pid -or $receiptB.schema -ne 3 -or $receiptB.wave -ne 22 -or
        $receiptB.phase -cne 'combat' -or $receiptB.route -cne 'combat' -or
        $receiptB.world_running -ne $true -or $receiptB.published_count -ne 1 -or
        $receiptB.continue_button_pressed -ne $true -or $receiptB.ui_control_signal -ne $true -or
        $receiptB.os_input -ne $false -or $receiptB.variant_type_array_order_exact -ne $true -or
        $receiptB.rng_state_exact -ne $true -or $receiptB.rich_w22_boundary_exact -ne $true -or
        $receiptB.wave_boundary_restart -ne $true -or
        $receiptB.mid_wave_claim -ne $false) {
        throw 'B resume receipt mismatch.'
    }
    $result.pid_distinct = $a.record.pid -ne $b.record.pid
    $bStart = [DateTimeOffset]::Parse(
        $b.record.start_time_utc,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind
    )
	if ($bStart.Offset -ne [TimeSpan]::Zero -or $aFinalize.Offset -ne [TimeSpan]::Zero) {
		throw 'A/B lifecycle timestamps must be UTC DateTimeOffset values.'
	}
    $result.temporal_non_overlap = $result.pid_distinct -and $bStart -gt $aFinalize
    if (-not $result.pid_distinct -or -not $result.temporal_non_overlap) { throw 'A/B process overlap or PID reuse detected.' }
    Assert-PidAbsent $b.record.pid

    foreach ($path in @($profilePath,$tempProfilePath,$backupProfilePath,$stateArtifact,$rawArtifact)) {
        Assert-NoReparse $path
    }
    if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf) -or
        (Test-Path -LiteralPath $tempProfilePath) -or (Test-Path -LiteralPath $backupProfilePath)) {
        throw 'B parent-side profile presence mismatch.'
    }
    Assert-NoReparse $profilePath
    $profileShaB = Get-GuardedSha256 $profilePath
    $profileCopyB = Join-Path $runDirectory 'profile-after-B.json'
    Copy-GuardedFile $profilePath $profileCopyB
    if ((Get-GuardedSha256 $profileCopyB) -cne $profileShaB) { throw 'B profile evidence copy mismatch.' }
    $result.profile_after_b = [ordered]@{path=$profilePath;copy=$profileCopyB;sha256=$profileShaB;bytes=(Get-GuardedLength $profilePath)}
    if ((Get-GuardedSha256 $stateArtifact) -cne $result.state_artifact.sha256 -or
        (Get-GuardedSha256 $rawArtifact) -cne $result.raw_artifact.sha256) {
        throw 'B changed the A typed state/raw artifacts.'
    }

    $hashes = @($profileShaA,$profileShaB,$receiptA.profile_sha256,
        $receiptB.profile_sha_preboot,$receiptB.profile_sha_postboot,$receiptB.profile_sha_postcontinue)
    $result.profile_sha_stable = @($hashes | Select-Object -Unique).Count -eq 1
    $result.sidecars_absent = -not (Test-Path -LiteralPath $tempProfilePath) -and -not (Test-Path -LiteralPath $backupProfilePath)
    # Runtime Dictionary insertion order is not semantic. Each role's fixture
    # recursively proves the exact key set/key Variant types/values while keeping
    # Array order strict. Only the raw decoded JSON has an explicit key order.
    $result.variant_type_array_order_exact = $receiptA.variant_type_array_order_exact -eq $true -and
        $receiptB.variant_type_array_order_exact -eq $true -and
        $receiptA.state_bytes_sha256 -ceq $result.state_artifact.sha256 -and
        $receiptA.raw_digest -ceq $receiptB.raw_digest -and
        $receiptA.raw_bytes_sha256 -ceq $receiptB.raw_bytes_sha256 -and
        $receiptA.raw_bytes_sha256 -ceq $result.raw_artifact.sha256
    $result.rng_state_exact = $receiptA.run_seed -ceq $receiptB.run_seed -and
        $receiptA.rng_state -ceq $receiptB.rng_state
    $result.rng_next_sequence_exact = ($receiptA.rng_next | ConvertTo-Json -Compress) -ceq
        ($receiptB.rng_next | ConvertTo-Json -Compress)
    $result.guards_ok = $true
    $result.same_scratch = (Canonical $guardA.expected_user_data) -ceq (Canonical $guardB.expected_user_data)
    $result.continue_button_pressed = $receiptB.continue_button_pressed
    $result.published_once = $receiptB.published_count -eq 1
    $result.rich_w22_boundary_exact = $receiptA.rich_w22_boundary_exact -eq $true -and
        $receiptB.rich_w22_boundary_exact -eq $true -and
        ($receiptA.rich_summary | ConvertTo-Json -Compress -Depth 4) -ceq
        ($receiptB.rich_summary | ConvertTo-Json -Compress -Depth 4)
    $result.wave_boundary_restart = $receiptA.wave_boundary_restart -and $receiptB.wave_boundary_restart
    $result.mid_wave_claim = $false
    foreach ($required in @('w1_disk_immediate','rich_w22_boundary_exact','profile_sha_stable','sidecars_absent','variant_type_array_order_exact','rng_state_exact',
        'rng_next_sequence_exact','guards_ok','same_scratch','continue_button_pressed','published_once','wave_boundary_restart')) {
        if (-not $result[$required]) { throw "Cross-process contract failed: $required" }
    }
} catch {
    if (-not $failure) {
        $failure = $_
        $result.exception = $_.Exception.Message
    }
} finally {
    Invoke-OwnedFinalizer $result 'subject-inventory-after' {
        $subjectAfter = Get-SubjectInventory $subject $Mode
        [IO.File]::WriteAllText((Join-Path $runDirectory 'subject-after.json'),($subjectAfter.records | ConvertTo-Json -Depth 4),$utf8)
        $result.source_or_pck_unchanged = $subjectBefore.fingerprint -ceq $subjectAfter.fingerprint -and
            $subjectBefore.count -eq $subjectAfter.count
        if (-not $result.source_or_pck_unchanged) { throw 'Source/PCK inventory changed during verification.' }
    }
    Invoke-OwnedFinalizer $result 'pinned-inputs-after' {
        Assert-PinnedFiles $pinnedFiles 'finalization'
        Assert-FrozenBindings $pinnedFiles 'finalization'
        $result.pinned_inputs_unchanged = $true
        $result.frozen_bindings_unchanged = $true
        $result.fixture_unchanged = $true
    }
    Invoke-OwnedFinalizer $result 'parent-environment-after' {
        $result.parent_environment_unchanged = Test-OwnedParentEnvironment $parentEnvironment
        if (-not $result.parent_environment_unchanged) { throw 'Parent environment changed during verification.' }
    }
    if ($result.cleanup_errors.Count -gt 0 -and -not $failure) {
        $failure = [InvalidOperationException]::new('Verifier finalization reported one or more cleanup errors.')
        $result.exception = $failure.Message
    }
    $result.resume_claim = $null -eq $failure -and $result.cleanup_errors.Count -eq 0 -and
        $result.process_count -eq 2 -and
        $result.pid_distinct -and $result.temporal_non_overlap -and $result.guards_ok -and
        $result.same_scratch -and $result.continue_button_pressed -and $result.published_once -and
        $result.w1_disk_immediate -and $result.rich_w22_boundary_exact -and
        $result.profile_sha_stable -and $result.sidecars_absent -and $result.variant_type_array_order_exact -and
        $result.rng_state_exact -and $result.rng_next_sequence_exact -and $result.source_or_pck_unchanged -and
        $result.fixture_unchanged -and $result.pinned_inputs_unchanged -and $result.frozen_bindings_unchanged -and
        $result.parent_environment_unchanged -and
        $result.wave_boundary_restart -and -not $result.mid_wave_claim
    Write-OwnedCompletion $result $result.final_receipt
}

if (-not $result.final_receipt_written -and -not $failure) {
    $failure = [InvalidOperationException]::new('Overall completion receipt was not written.')
    $result.exception = $failure.Message
}
if ($failure) { throw $failure }
if (-not $result.resume_claim) { throw 'Cross-process completion did not earn resume_claim=true.' }
Write-Output ("CHECKPOINT_CROSS_PROCESS_OK " + ($result | ConvertTo-Json -Compress -Depth 5))
