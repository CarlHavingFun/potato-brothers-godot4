param(
    [string]$SourceRoot = (Join-Path $PSScriptRoot '..'),
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$GodotBinary = 'E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe',
    [string]$EvidenceDirectory,
    [string]$DebugTemplatePath = 'C:\Users\18421\AppData\Roaming\Godot\export_templates\4.7.1.stable\windows_debug_x86_64.exe'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\', '/')
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\', '/')
$allowedRoot = Join-Path $SourceRoot 'dist/playtests'
if (Test-Path -LiteralPath $OutputDirectory) { throw "Output already exists: $OutputDirectory" }
if (-not $OutputDirectory.StartsWith($allowedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Output must be under source dist/playtests.'
}
# Reject links/junctions in destination ancestry; lexical containment alone is insufficient.
$ancestor = $OutputDirectory
while ($ancestor.Length -gt $SourceRoot.Length) {
    if ((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Output ancestry contains a reparse point: $ancestor"
    }
    $ancestor = Split-Path -Parent $ancestor
}
if (-not $EvidenceDirectory) { $EvidenceDirectory = Join-Path $SourceRoot 'reports/playtest-feedback-v1/task4a' }
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
$buildRoot = Join-Path $EvidenceDirectory ('build-' + [guid]::NewGuid().ToString('N'))
$stage = Join-Path $buildRoot 'staging'
$utf8 = [Text.UTF8Encoding]::new($false)
function Write-Utf8([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, $utf8) }
function Assert-NoReparse([string]$Path) {
    $cursor=[IO.Path]::GetFullPath($Path)
    while($cursor){
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Reparse traversal rejected: $cursor"}
        $parent=Split-Path -Parent $cursor;if($parent -eq $cursor){break};$cursor=$parent
    }
}
function Canonical([string]$Path){return [IO.Path]::GetFullPath($Path).TrimEnd('\','/').Replace('\','/')}
$lifecyclePath=Join-Path $PSScriptRoot 'playtest_packaging/owned_process_lifecycle.ps1'
Assert-NoReparse $lifecyclePath
$lifecycleHash=(Get-FileHash -LiteralPath $lifecyclePath).Hash
$builderHash=(Get-FileHash -LiteralPath $PSCommandPath).Hash
. $lifecyclePath
function Assert-GuardDiagnostics($Record,[string]$Phase,[string]$Assurance,[int]$ExpectedPid,$Child,[string]$ActualUser,[string[]]$Arguments,[bool]$ExpectedUserMismatch){
    # Also imported by the pinned probe as this one AST definition. Never trust
    # a reported check/reason without recomputing it from closed typed fields.
    function Guard-Keys($Value,[string[]]$Keys){
        if($Value -isnot [pscustomobject]){throw 'Guard diagnostic: expected JSON object.'}
        $actual=@($Value.PSObject.Properties.Name)
        if($actual.Count -ne $Keys.Count -or @($actual|Where-Object {$Keys -cnotcontains $_}).Count){throw 'Guard diagnostic: unknown or missing field.'}
    }
    function Guard-Integer($Value){return $Value -is [int] -or $Value -is [long]}
    function Guard-Path([string]$Value){if(-not $Value){return ''};if(-not [IO.Path]::IsPathRooted($Value)){throw 'Guard diagnostic: nonabsolute path.'};return [IO.Path]::GetFullPath($Value).TrimEnd('\','/').Replace('\','/')}
    Guard-Keys $Record @('schema_version','termination_contract','platform','phase','assurance_stage','pid','appdata','localappdata','user_data','expected_appdata','expected_localappdata','expected_user_data','engine_arguments','user_arguments','editor_hint','version','checks','failures')
    foreach($key in @('termination_contract','platform','phase','assurance_stage','appdata','localappdata','user_data','expected_appdata','expected_localappdata','expected_user_data')){if($Record.$key -isnot [string]){throw 'Guard diagnostic: expected string field.'}}
    if(-not(Guard-Integer $Record.schema_version) -or $Record.schema_version -ne 2 -or -not(Guard-Integer $Record.pid) -or $Record.pid -ne $ExpectedPid -or $Record.editor_hint -isnot [bool]){throw 'Guard diagnostic: schema/PID/type mismatch.'}
    if($Record.termination_contract -cne 'godot-4.7.1-windows-self-kill-v1' -or $Record.phase -cne $Phase -or $Record.assurance_stage -cne $Assurance){throw 'Guard diagnostic: contract/phase/assurance mismatch.'}
    foreach($key in @('engine_arguments','user_arguments','failures')){if($Record.$key -isnot [array] -or @($Record.$key|Where-Object {$_ -isnot [string]}).Count){throw 'Guard diagnostic: expected string array.'}}
    $v=$Record.version;Guard-Keys $v @('major','minor','patch','status','build','hash','hex','string','timestamp')
    foreach($key in @('major','minor','patch','hex','timestamp')){if(-not(Guard-Integer $v.$key)){throw 'Guard diagnostic: version integer type.'}}
    foreach($key in @('status','build','hash','string')){if($v.$key -isnot [string]){throw 'Guard diagnostic: version string type.'}}
    $checkKeys=@('phase','version','platform','expected_nonempty','appdata','localappdata','user_data');Guard-Keys $Record.checks $checkKeys
    foreach($key in $checkKeys){if($Record.checks.$key -isnot [bool]){throw 'Guard diagnostic: check must be boolean.'}}
    # The actual launch array is separate evidence: import was consumed by
    # Main::setup and is not independently proved by OS.get_cmdline_args().
    $count=if($Phase -ceq 'version-info'){8}else{9}
    if($Arguments.Count -ne $count -or @($Arguments|Where-Object {[string]::IsNullOrWhiteSpace($_)}).Count){throw 'Guard diagnostic: actual argv shape.'}
    switch -CaseSensitive ($Phase){
        'version-info'{$shape=@('--headless','--path',$Arguments[2],'--script',$Arguments[4],'--','--guard-phase','version-info');$pathSlots=@(2,4)}
        'import'{$shape=@('--headless','--editor','--path',$Arguments[3],'--import','--quit','--','--guard-phase','import');$pathSlots=@(3)}
        'export'{$shape=@('--headless','--path',$Arguments[2],'--export-debug','Windows Desktop',$Arguments[5],'--','--guard-phase','export');$pathSlots=@(2,5)}
        default{throw 'Guard diagnostic: actual argv unknown phase.'}
    }
    for($i=0;$i -lt $shape.Count;$i++){if($Arguments[$i] -cne $shape[$i]){throw 'Guard diagnostic: actual argv differs from the frozen phase layout.'}}
    foreach($i in $pathSlots){if(-not [IO.Path]::IsPathRooted($Arguments[$i])){throw 'Guard diagnostic: actual argv requires absolute paths.'}}
    foreach($pair in @(@('appdata',$Child.APPDATA),@('localappdata',$Child.LOCALAPPDATA),@('user_data',$ActualUser),@('expected_appdata',$Child.GOGOBRO_TEST_EXPECTED_APPDATA),@('expected_localappdata',$Child.GOGOBRO_TEST_EXPECTED_LOCALAPPDATA),@('expected_user_data',$Child.GOGOBRO_TEST_EXPECTED_USER_DATA_DIR))){if((Guard-Path $Record.($pair[0])) -cne (Guard-Path $pair[1])){throw 'Guard diagnostic: actual/expected path binding mismatch.'}}
    $debug=@($Record.engine_arguments|Where-Object {$_ -ceq '--export-debug'}).Count
    $scripts=@($Record.engine_arguments|Where-Object {$_ -cin @('--script','-s')}).Count
    $conflicts=@($Record.engine_arguments|Where-Object {$_ -ceq '--import' -or ($_.StartsWith('--export',[StringComparison]::Ordinal) -and $_ -cne '--export-debug')}).Count
    $phaseOk=$Record.user_arguments.Count -eq 2 -and $Record.user_arguments[0] -ceq '--guard-phase' -and $Record.user_arguments[1] -ceq $Phase -and $conflicts -eq 0
    if($Phase -ceq 'version-info'){$phaseOk=$phaseOk -and -not $Record.editor_hint -and $debug -eq 0 -and $scripts -le 1}
    else{$phaseOk=$phaseOk -and $Record.editor_hint -and $scripts -eq 0 -and $debug -eq $(if($Phase -ceq 'export'){1}else{0})}
    $checks=[ordered]@{
        phase=[bool]$phaseOk
        version=($v.major -eq 4 -and $v.minor -eq 7 -and $v.patch -eq 1 -and $v.status -ceq 'stable' -and $v.build -ceq 'official' -and $v.hash -ceq 'a13da4feb8d8aefc283c3763d33a2f170a18d541' -and $v.hex -eq 263937 -and $v.string -ceq '4.7.1-stable (official)' -and $v.timestamp -eq 0)
        platform=($Record.platform -ceq 'Windows')
        expected_nonempty=($Record.expected_appdata.Length -gt 0 -and $Record.expected_localappdata.Length -gt 0 -and $Record.expected_user_data.Length -gt 0)
        appdata=((Guard-Path $Record.appdata) -ceq (Guard-Path $Record.expected_appdata))
        localappdata=((Guard-Path $Record.localappdata) -ceq (Guard-Path $Record.expected_localappdata))
        user_data=((Guard-Path $Record.user_data) -ceq (Guard-Path $Record.expected_user_data))
    }
    foreach($key in $checkKeys){if($Record.checks.$key -ne $checks[$key]){throw 'Guard diagnostic: reported check differs from recomputation.'}}
    $failures=@($checkKeys|Where-Object {-not $checks[$_]})
    if($Record.failures.Count -ne $failures.Count -or ($Record.failures -join ',') -cne ($failures -join ',')){throw 'Guard diagnostic: failure reasons differ from recomputation.'}
    $expectedFailures=@(if($ExpectedUserMismatch){'user_data'})
    if($failures.Count -ne $expectedFailures.Count -or ($failures -join ',') -cne ($expectedFailures -join ',')){throw 'Guard diagnostic: unexpected failure set.'}
}
foreach($path in @($SourceRoot,$OutputDirectory,$buildRoot,$GodotBinary,$DebugTemplatePath)){Assert-NoReparse $path}
function Assert-ProjectSectionSyntax([string]$Text,[switch]$ReturnSections){
    # Closed lexical layout, not a Variant evaluator: one top-level assignment
    # or standalone tag per line; balanced value containers may span lines.
    # After a value ends, no second token (including an inline tag) is allowed.
    $sections=[Collections.Generic.List[object]]::new()
    $closers=[Collections.Generic.Stack[char]]::new()
    $quoted=$false;$escaped=$false;$state='statement'
    foreach($physical in [regex]::Matches($Text,'[^\n]*(?:\n|\z)')){
        if(-not $physical.Length){continue}
        $line=$physical.Value
        if($line.EndsWith("`n")){$line=$line.Substring(0,$line.Length-1)}
        if($line.EndsWith("`r")){$line=$line.Substring(0,$line.Length-1)}
        if($line.Contains("`r")){throw 'Noncanonical project layout: unsupported line ending.'}
        $i=0
        if($state -ceq 'statement'){
            if($line -match '^[ \t]*(;.*)?$'){continue}
            if($line.TrimStart(' ',"`t").StartsWith('[',[StringComparison]::Ordinal)){
                $header=[regex]::Match($line,'\A[ \t]*\[(?<name>[a-z0-9_./-]+)\][ \t]*\z')
                if(-not $header.Success){throw 'Noncanonical project section header; aliases and malformed boundaries are refused.'}
                $name=$header.Groups['name'].Value
                if($name -ceq 'autoload'){throw 'Unapproved autoload project section.'}
                if($sections.Count){$sections[$sections.Count-1].body_end=$physical.Index}
                $sections.Add([pscustomobject]@{name=$name;body_start=$physical.Index+$physical.Length;body_end=$Text.Length})
                continue
            }
            $assignment=[regex]::Match($line,'\A[ \t]*[A-Za-z0-9_./-]+[ \t]*=[ \t]*')
            if(-not $assignment.Success){throw 'Noncanonical project layout: expected one assignment or standalone section.'}
            $i=$assignment.Length;$state='value'
        }
        while($i -lt $line.Length){
            $ch=$line[$i]
            if($quoted){
                if($escaped){$escaped=$false}
                elseif($ch -ceq '\'){$escaped=$true}
                elseif($ch -ceq '"'){$quoted=$false;if(-not $closers.Count){$state='after'}}
                $i++;continue
            }
            if($ch -ceq ' ' -or $ch -ceq "`t"){$i++;continue}
            if($ch -ceq ';'){break}
            if($state -ceq 'after'){throw 'Noncanonical project layout: extra token after value; inline sections are refused.'}
            if($ch -ceq '"'){$quoted=$true;$i++;continue}
            if($ch -ceq '[' -or $ch -ceq '{' -or $ch -ceq '('){
                $close=switch($ch){'['{']'} '{'{'}'} '(' {')'}}
                $closers.Push([char]$close);$state='container';$i++;continue
            }
            if($state -ceq 'value'){
                $rest=$line.Substring($i)
                $constructor=[regex]::Match($rest,'\A[A-Za-z_][A-Za-z0-9_]*[ \t]*\(')
                if($constructor.Success){$closers.Push([char]')');$state='container';$i+=$constructor.Length;continue}
                $scalar=[regex]::Match($rest,'\A(?:true|false|null|[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)(?=[ \t;]|\z)')
                if(-not $scalar.Success){throw 'Noncanonical project layout: unsupported top-level value.'}
                $i+=$scalar.Length;$state='after';continue
            }
            if($ch -ceq ']' -or $ch -ceq '}' -or $ch -ceq ')'){
                if(-not $closers.Count -or $closers.Pop() -cne $ch){throw 'Noncanonical project layout: mismatched value container.'}
                if(-not $closers.Count){$state='after'}
            }
            $i++
        }
        if($quoted){throw 'Noncanonical project layout: multiline or unterminated string is unsupported.'}
        if($state -ceq 'value'){throw 'Noncanonical project layout: missing assignment value.'}
        if(-not $closers.Count){$state='statement'}
    }
    if($closers.Count){throw 'Noncanonical project layout: unterminated value container.'}
    if($ReturnSections){$sections.ToArray()}
}
function Assert-ProjectEntrypoints {
    $text=Get-Content -LiteralPath (Join-Path $SourceRoot 'project.godot') -Raw
    $sections=@(Assert-ProjectSectionSyntax $text -ReturnSections|Where-Object {$_.name -ceq 'editor_plugins'})
    if($sections.Count -ne 1){throw 'Unapproved editor plugin section set.'}
    $bodyStart=$sections[0].body_start
    $body=$text.Substring($bodyStart,$sections[0].body_end-$bodyStart)
    $lines=@($body -split '\r?\n'|Where-Object {$_ -notmatch '^[ \t]*(;.*)?$'})
    $approved='^[ \t]*enabled[ \t]*=[ \t]*PackedStringArray\([ \t]*"res://addons/gdUnit4/plugin\.cfg"[ \t]*\)[ \t]*(;[^\r\n]*)?$'
    if($lines.Count -ne 1 -or $lines[0] -cnotmatch $approved){throw 'Unapproved editor plugin enabled set; only the existing gdUnit4 development plugin is approved.'}
    # Examine project-root entries and the runtime/editor source roots before
    # allowlist filtering. Never traverse dist/reports or existing user profiles.
    if(@(Get-ChildItem -LiteralPath $SourceRoot -File -Force -Filter '*.gdextension').Count){throw 'Unapproved GDExtension entry at project root.'}
    $pending=[Collections.Generic.Stack[string]]::new()
    foreach($name in @('game','addons')){$directory=Join-Path $SourceRoot $name;if(Test-Path -LiteralPath $directory -PathType Container){$pending.Push($directory)}}
    while($pending.Count){
        $directory=$pending.Pop();Assert-NoReparse $directory
        foreach($entry in Get-ChildItem -LiteralPath $directory -Force){
            if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Source entry reparse rejected: $($entry.FullName)"}
            if($entry.PSIsContainer){$pending.Push($entry.FullName)}
            elseif($entry.Extension -ieq '.gdextension'){throw "Unapproved GDExtension entry: $($entry.FullName)"}
            elseif($entry.Extension -ieq '.gd' -and $entry.FullName.StartsWith((Join-Path $SourceRoot 'game')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
                $relative=$entry.FullName.Substring($SourceRoot.Length+1).Replace('\','/')
                if($relative -notmatch '^game/(assets/top20/|content/packs/items/top20/)' -and (Get-Content -LiteralPath $entry.FullName -Raw) -match '(?m)^\s*@tool\b|^\s*(static\s+)?func\s+_static_init\s*\('){throw "Unapproved early runtime script: $relative"}
            }
        }
    }
    $offset=$bodyStart+$body.IndexOf($lines[0],[StringComparison]::Ordinal)
    return @{source_text=$text;staged_text=$text.Remove($offset,$lines[0].Length).Insert($offset,'enabled=PackedStringArray("res://addons/playtest_raw_export/plugin.cfg")')}
}
$projectAdmission=Assert-ProjectEntrypoints
$engineCommand=[IO.Path]::GetFullPath($GodotBinary)
$engineCommandHash=(Get-FileHash -LiteralPath $engineCommand).Hash
$engineExecutable=$engineCommand
# The small console launcher owns a different PID. Run the same installation's
# full binary directly so each phase's guard PID is the owned process PID.
if($engineExecutable.EndsWith('_console.exe',[StringComparison]::OrdinalIgnoreCase)){
    $peer=$engineExecutable -replace '_console\.exe$','.exe'
    if(-not(Test-Path -LiteralPath $peer -PathType Leaf)){throw 'Missing full engine peer.'}
    Assert-NoReparse $peer;$engineExecutable=$peer
}
$engineHash=(Get-FileHash -LiteralPath $engineExecutable).Hash
function Assert-EngineStable([string]$Phase) {
    foreach($inputRecord in @(@{role='command';path=$engineCommand;sha256=$engineCommandHash},@{role='runtime';path=$engineExecutable;sha256=$engineHash})){
        Assert-NoReparse $inputRecord.path
        if(-not(Test-Path -LiteralPath $inputRecord.path -PathType Leaf) -or (Get-FileHash -LiteralPath $inputRecord.path).Hash -cne $inputRecord.sha256){throw "Engine input changed ($($inputRecord.role)) $Phase."}
    }
}
$null = New-Item -ItemType Directory -Path $stage -Force
$templatePreHash=(Get-FileHash -LiteralPath $DebugTemplatePath).Hash
$tempBase=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Temp'
Assert-NoReparse $tempBase
if((Canonical $tempBase).StartsWith((Canonical $SourceRoot)+'/',[StringComparison]::OrdinalIgnoreCase)){throw 'External TEMP must not be inside source.'}
$templateRoot=Join-Path $tempBase ('gogobro-export-template-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $templateRoot
$templateCopy=Join-Path $templateRoot 'windows_debug_x86_64.exe'
Copy-Item -LiteralPath $DebugTemplatePath -Destination $templateCopy
if((Get-FileHash -LiteralPath $templateCopy).Hash -cne $templatePreHash){throw 'Template copy mismatch.'}
$generated=Join-Path $buildRoot 'generated';$null=New-Item -ItemType Directory -Path $generated
$builderAtRun=Join-Path $buildRoot 'build_experimental_playtest.at-run.ps1'
$lifecycleAtRun=Join-Path $buildRoot 'owned_process_lifecycle.at-run.ps1'
Copy-Item -LiteralPath $PSCommandPath -Destination $builderAtRun
Copy-Item -LiteralPath $lifecyclePath -Destination $lifecycleAtRun
if((Get-FileHash -LiteralPath $builderAtRun).Hash -cne $builderHash -or (Get-FileHash -LiteralPath $lifecycleAtRun).Hash -cne $lifecycleHash){throw 'Build runner source copy mismatch.'}
$buildGuard=Join-Path $generated 'build_guard.gd'
Write-Utf8 $buildGuard @'
@tool
extends SceneTree

var _phase := ""

func _init() -> void:
    var report: Dictionary = _guard_report("version-info-early")
    _phase = report.phase
    if not report.failures.is_empty():
        print("BUILD_GUARD_FAIL " + JSON.stringify(report))
        OS.kill(OS.get_process_id())
        # Never continue the standalone version process after a self-kill failure.
        # The owning PowerShell process has a 30-second watchdog.
        while true:
            OS.delay_msec(50)
    print("BUILD_GUARD_OK " + JSON.stringify(report))

func _initialize() -> void:
    if _phase == "version-info":
        quit(0)

func _guard_report(assurance: String) -> Dictionary:
    var user_arguments: PackedStringArray = OS.get_cmdline_user_args()
    var engine_arguments: PackedStringArray = OS.get_cmdline_args()
    var editor_hint: bool = Engine.is_editor_hint()
    var phase: String = ""
    var phase_ok: bool = user_arguments.size() == 2 and user_arguments[0] == "--guard-phase"
    if phase_ok:
        phase = user_arguments[1]
    var debug_count: int = engine_arguments.count("--export-debug")
    var script_count: int = engine_arguments.count("--script") + engine_arguments.count("-s")
    var conflicts: bool = "--import" in engine_arguments
    for argument in engine_arguments:
        if argument.begins_with("--export") and argument != "--export-debug":
            conflicts = true
    # --import is consumed by Main::setup. The pinned outer argv proves import;
    # this API only supplies editor/phase consistency and visible conflicts.
    if assurance == "version-info-early":
        phase_ok = phase_ok and phase == "version-info" and not editor_hint \
            and not conflicts and debug_count == 0 and script_count <= 1
    else:
        phase_ok = phase_ok and editor_hint and not conflicts and script_count == 0 \
            and ((phase == "import" and debug_count == 0) or (phase == "export" and debug_count == 1))
    var version: Dictionary = Engine.get_version_info()
    var report: Dictionary = {"schema_version": 2,
        "termination_contract": "godot-4.7.1-windows-self-kill-v1",
        "platform": OS.get_name(), "phase": phase, "assurance_stage": assurance,
        "pid": OS.get_process_id(), "engine_arguments": engine_arguments,
        "user_arguments": user_arguments, "editor_hint": editor_hint,
        "appdata": OS.get_environment("APPDATA"), "localappdata": OS.get_environment("LOCALAPPDATA"),
        "user_data": OS.get_user_data_dir(),
        "expected_appdata": OS.get_environment("GOGOBRO_TEST_EXPECTED_APPDATA"),
        "expected_localappdata": OS.get_environment("GOGOBRO_TEST_EXPECTED_LOCALAPPDATA"),
        "expected_user_data": OS.get_environment("GOGOBRO_TEST_EXPECTED_USER_DATA_DIR"), "version": version}
    var version_ok: bool = version.major == 4 and version.minor == 7 and version.patch == 1 \
        and version.status == "stable" and version.build == "official" \
        and version.hash == "a13da4feb8d8aefc283c3763d33a2f170a18d541" and version.hex == 263937 \
        and version.string == "4.7.1-stable (official)" and version.timestamp == 0
    var checks: Dictionary = {"phase": phase_ok, "version": version_ok, "platform": report.platform == "Windows",
        "expected_nonempty": not report.expected_appdata.is_empty() and not report.expected_localappdata.is_empty() and not report.expected_user_data.is_empty(),
        "appdata": _canonical(report.appdata) == _canonical(report.expected_appdata),
        "localappdata": _canonical(report.localappdata) == _canonical(report.expected_localappdata),
        "user_data": _canonical(report.user_data) == _canonical(report.expected_user_data)}
    var failures: Array[String] = []
    for key in checks:
        if not checks[key]:
            failures.append(key)
    report["checks"] = checks
    report["failures"] = failures
    return report

func _canonical(value: String) -> String:
    return value.replace("\\", "/").simplify_path()
'@
$guardHash=(Get-FileHash -LiteralPath $buildGuard).Hash
$phaseEvidence=[Collections.Generic.List[object]]::new()
function Invoke-Engine([string]$Step, [string[]]$Arguments) {
    $phaseRoot=Join-Path $tempBase ('gogobro-build-'+$Step+'-'+[guid]::NewGuid().ToString('N'))
    Assert-NoReparse $phaseRoot
    $null=New-Item -ItemType Directory -Path $phaseRoot
    $child=[ordered]@{TEMP=(Join-Path $phaseRoot 'Temp');TMP=(Join-Path $phaseRoot 'Temp');APPDATA=(Join-Path $phaseRoot 'AppData');LOCALAPPDATA=(Join-Path $phaseRoot 'LocalAppData')}
    foreach($path in @($child.TEMP,$child.APPDATA,$child.LOCALAPPDATA)){$null=New-Item -ItemType Directory -Path $path}
    $child.GOGOBRO_TEST_EXPECTED_APPDATA=$child.APPDATA
    $child.GOGOBRO_TEST_EXPECTED_LOCALAPPDATA=$child.LOCALAPPDATA
    $child.GOGOBRO_TEST_EXPECTED_USER_DATA_DIR=Join-Path $child.APPDATA 'GOGOBRO'
    foreach($name in @('profile.json','profile.tmp','profile.backup')){if(Test-Path -LiteralPath (Join-Path $child.GOGOBRO_TEST_EXPECTED_USER_DATA_DIR ('GOGOBRO/'+$name))){throw 'Fresh synthetic profile unexpectedly exists.'}}
    foreach($path in @($buildGuard,$templateCopy)){Assert-NoReparse $path}
    if((Get-FileHash -LiteralPath $buildGuard).Hash -cne $guardHash -or (Get-FileHash -LiteralPath $templateCopy).Hash -cne $templatePreHash){throw 'Build tool input changed.'}
    Assert-EngineStable "before $Step"
    Assert-StagedBuildInputs "before $Step"
    $stdout=Join-Path $buildRoot ($Step+'.stdout.log');$stderr=Join-Path $buildRoot ($Step+'.stderr.log')
    $psi=[Diagnostics.ProcessStartInfo]::new($engineExecutable)
    $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.WorkingDirectory=$phaseRoot
    $psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
    if([IO.Path]::GetExtension($engineExecutable) -in @('.cmd','.bat')){
        $parts=@($engineExecutable)+$Arguments
        if(@($parts|Where-Object {$_ -match '["%&|<>^!\r\n]'}).Count){throw 'Unsafe command-fixture argument.'}
        $psi.FileName=$env:ComSpec;$psi.Arguments='/d /s /c "'+(($parts|ForEach-Object {'"'+$_+'"'}) -join ' ')+'"'
    }else{foreach($argument in $Arguments){$psi.ArgumentList.Add($argument)}}
    $parentEnv=[ordered]@{}
    foreach($key in $child.Keys){$parentEnv[$key]=@{present=(Test-Path "Env:$key");value=[Environment]::GetEnvironmentVariable($key,'Process')};$psi.Environment[$key]=$child[$key]}
    $assurance=if($Step -ceq 'version-info'){'version-info-early'}else{'plugin-entry'}
    $record=[ordered]@{phase=$Step;assurance_stage=$assurance;engine_command=$engineCommand;engine_command_sha256=$engineCommandHash;executable=$engineExecutable;engine_sha256=$engineHash;arguments=$Arguments;working_directory=$phaseRoot;environment=$child;parent_environment=$parentEnv;started=$false;owned=$false;pid=$null;exit_code=$null;timed_out=$false;guard_ok=$false;disposed=$false;exception=$null;stdout=$stdout;stderr=$stderr;parent_environment_unchanged=$false;cleanup_errors=@();source_unchanged=$false;tools_unchanged=$false;engine_unchanged=$false;staged_inputs_unchanged=$false;builder_sha256=$builderHash;lifecycle_sha256=$lifecycleHash;builder_at_run=$builderAtRun;lifecycle_at_run=$lifecycleAtRun}
    try{
        foreach($key in $child.Keys){if($psi.Environment[$key] -cne $child[$key]){throw "Child environment mismatch: $key"}}
        Write-Utf8 (Join-Path $buildRoot ($Step+'.invocation.json')) ($record|ConvertTo-Json -Depth 7)
        $process=[Diagnostics.Process]::new();$process.StartInfo=$psi
        $output=Invoke-OwnedProcess $process $record $stdout $stderr (Join-Path $buildRoot ($Step+'.process-start.json'))
        if($record.exception){throw $record.exception}
        if($record.cleanup_errors.Count -or -not $record.has_exited -or -not $record.stdout_complete -or -not $record.stderr_complete){throw "$Step process finalization incomplete."}
        $out=$output.out;$err=$output.err
        if($record.timed_out -or $record.exit_code -ne 0){throw "$Step failed with exit code $($record.exit_code)"}
        if($err.Length -gt 0 -or $out -match '(?m)^ERROR:|SCRIPT ERROR:|BUILD_GUARD_FAIL'){throw "$Step logged errors"}
        $lines=@($out -split '\r?\n'|Where-Object {$_ -match '^BUILD_GUARD_OK '})
        if($lines.Count -ne 1){throw "$Step needs exactly one actual guard marker"}
        $guard=$lines[0].Substring('BUILD_GUARD_OK '.Length)|ConvertFrom-Json
        Assert-GuardDiagnostics $guard $Step $assurance $record.pid $child $child.GOGOBRO_TEST_EXPECTED_USER_DATA_DIR $Arguments $false
        $record.guard_ok=$true;$record.guard=$guard
    }catch{if(-not $record.exception){$record.exception=$_.Exception.Message}}finally{
        # Invoke-OwnedProcess has already independently finalized owned handles.
        # All remaining provenance and receipt actions are independent as well.
        Invoke-OwnedFinalizer $record 'source-inventory' {$null=Assert-SourceInventory $records "finally $Step";$record.source_unchanged=$true}
        Invoke-OwnedFinalizer $record 'staged-inputs' {Assert-StagedBuildInputs "finally $Step";$record.staged_inputs_unchanged=$true}
        Invoke-OwnedFinalizer $record 'engine-inputs' {Assert-EngineStable "finally $Step";$record.engine_unchanged=$true}
        Invoke-OwnedFinalizer $record 'tool-inputs' {
            foreach($pin in @(@($buildGuard,$guardHash),@($templateCopy,$templatePreHash),@($DebugTemplatePath,$templatePreHash),@($PSCommandPath,$builderHash),@($builderAtRun,$builderHash),@($lifecyclePath,$lifecycleHash),@($lifecycleAtRun,$lifecycleHash))){
                Assert-NoReparse $pin[0]
                if((Get-FileHash -LiteralPath $pin[0]).Hash -cne $pin[1]){throw "Build tool changed: $($pin[0])"}
            }
            $record.tools_unchanged=$true
        }
        Invoke-OwnedFinalizer $record 'parent-environment' {$record.parent_environment_unchanged=Test-OwnedParentEnvironment $parentEnv;if(-not $record.parent_environment_unchanged){throw 'Parent environment changed.'}}
        Invoke-OwnedFinalizer $record 'phase-evidence' {$phaseEvidence.Add($record)}
        Write-OwnedCompletion $record (Join-Path $buildRoot ($Step+'.completion.json'))
    }
    if($record.exception -or $record.cleanup_errors.Count){throw "$Step failed: $($record.exception) Cleanup: $($record.cleanup_errors|ConvertTo-Json -Compress)"}
}
$version='4.7.1.stable.official.a13da4feb'
$project = Join-Path $SourceRoot 'project.godot'
$preset = Join-Path $SourceRoot 'export_presets.cfg'
foreach ($required in @($project, $preset, (Join-Path $SourceRoot 'game/app/app_root.tscn'))) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing source dependency: $required" }
}
function Get-SourceInventory {
    $sourceFiles = @()
    foreach ($rootConfig in @($project, $preset)) {
        if (Test-Path -LiteralPath $rootConfig -PathType Leaf) { $sourceFiles += Get-Item -LiteralPath $rootConfig }
    }
    foreach ($optional in @('default_bus_layout.tres', 'icon.svg', 'icon.svg.import')) {
        if (Test-Path -LiteralPath (Join-Path $SourceRoot $optional)) { $sourceFiles += Get-Item -LiteralPath (Join-Path $SourceRoot $optional) }
    }
    # Runtime-owned roots only. Top20 candidates are deliberately absent, not activated or promoted.
    $sourceFiles += Get-ChildItem -LiteralPath (Join-Path $SourceRoot 'game') -File -Recurse | Where-Object {
        $relative = $_.FullName.Substring($SourceRoot.Length + 1).Replace('\', '/')
        $relative -notmatch '^game/(assets/top20/|content/packs/items/top20/)' -and
        $_.Extension -in @('.gd', '.uid', '.tscn', '.tres', '.png', '.import', '.wav', '.json', '.txt', '.gdshader')
    }
    return @($sourceFiles | Sort-Object FullName | ForEach-Object {
        if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Source link not allowed: $($_.FullName)" }
        $relative = $_.FullName.Substring($SourceRoot.Length + 1).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        [ordered]@{path=$relative; bytes=$_.Length; sha256=$hash; source_pre_sha256=$hash; stage_sha256=$null; source_post_sha256=$null}
    })
}
function Assert-SourceInventory([object[]]$Expected, [string]$Phase) {
    $actual = @(Get-SourceInventory)
    $expectedByPath = @{}
    $actualByPath = @{}
    foreach ($record in $Expected) { $expectedByPath[$record.path] = $record }
    foreach ($record in $actual) { $actualByPath[$record.path] = $record }
    $missing = @($expectedByPath.Keys | Where-Object { -not $actualByPath.ContainsKey($_) } | Sort-Object)
    $added = @($actualByPath.Keys | Where-Object { -not $expectedByPath.ContainsKey($_) } | Sort-Object)
    $changed = @($expectedByPath.Keys | Where-Object {
        $actualByPath.ContainsKey($_) -and ($expectedByPath[$_].bytes -ne $actualByPath[$_].bytes -or $expectedByPath[$_].sha256 -ne $actualByPath[$_].sha256)
    } | Sort-Object)
    if ($missing.Count -or $added.Count -or $changed.Count) {
        $details = @()
        if ($missing.Count) { $details += 'missing ' + ($missing -join ', ') }
        if ($added.Count) { $details += 'added ' + ($added -join ', ') }
        if ($changed.Count) { $details += 'changed ' + ($changed -join ', ') }
        throw "Source changed during staging after ${Phase}: $($details -join '; ')"
    }
    $null=Assert-ProjectEntrypoints
    return $actual
}
function Get-PinnedSourceHead([string]$Phase) {
    $value = (& git -C $SourceRoot rev-parse --verify HEAD 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $value -cnotmatch '^[a-f0-9]{40}$') {
        throw "Cannot pin the source HEAD $Phase."
    }
    return $value
}
$headPre = Get-PinnedSourceHead 'before source inventory'
$records = @(Get-SourceInventory)
Assert-ProjectSectionSyntax (Get-Content -LiteralPath $project -Raw)
foreach($record in $records|Where-Object {$_.path.EndsWith('.gd')}){
    if((Get-Content -LiteralPath (Join-Path $SourceRoot $record.path) -Raw) -match '(?m)^\s*@tool\b|^\s*(static\s+)?func\s+_static_init\s*\('){throw "Unapproved early runtime script: $($record.path)"}
}
foreach ($record in $records) {
    $target = Join-Path $stage $record.path
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force
    Copy-Item -LiteralPath (Join-Path $SourceRoot $record.path) -Destination $target
    $record.stage_sha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    if ($record.stage_sha256 -ne $record.source_pre_sha256) { throw "Staged copy hash mismatch: $($record.path)" }
}
$fingerprintText = ($records | ForEach-Object { $_.path + "`t" + $_.sha256 }) -join "`n"
$fingerprint = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($fingerprintText)))
$rawExporterSource = Join-Path $PSScriptRoot 'playtest_packaging/raw_export_plugin.gd'
if (-not (Test-Path -LiteralPath $rawExporterSource -PathType Leaf)) { throw "Missing raw exporter dependency: $rawExporterSource" }
$rawExporterPreHash = (Get-FileHash -LiteralPath $rawExporterSource -Algorithm SHA256).Hash
$pluginDir = Join-Path $stage 'addons/playtest_raw_export'
$null = New-Item -ItemType Directory -Path $pluginDir -Force
$stagedRawExporter = Join-Path $pluginDir 'plugin.gd'
Copy-Item -LiteralPath $rawExporterSource -Destination $stagedRawExporter
$rawExporterStageHash = (Get-FileHash -LiteralPath $stagedRawExporter -Algorithm SHA256).Hash
if ($rawExporterStageHash -ne $rawExporterPreHash) { throw 'Staged raw exporter hash mismatch.' }
function Assert-RawExporterStable([string]$Phase) {
    $hash = (Get-FileHash -LiteralPath $rawExporterSource -Algorithm SHA256).Hash
    if ($hash -ne $rawExporterPreHash) { throw "Raw exporter changed during staging after ${Phase}: tools/playtest_packaging/raw_export_plugin.gd" }
    return $hash
}
$null = Assert-SourceInventory $records 'copy'
$rawExporterPostHash = Assert-RawExporterStable 'copy'
$stagedProject = Join-Path $stage 'project.godot'
$stagedPreset = Join-Path $stage 'export_presets.cfg'
if((Get-Content -LiteralPath $stagedProject -Raw) -cne $projectAdmission.source_text){throw 'Project changed since entrypoint preflight.'}
Assert-ProjectSectionSyntax $projectAdmission.staged_text
Write-Utf8 $stagedProject $projectAdmission.staged_text
# Runtime validates raw image bytes and parses JSON via FileAccess, not just ResourceLoader.
Write-Utf8 $stagedPreset ((Get-Content -LiteralPath $stagedPreset -Raw) -replace 'include_filter=""', 'include_filter="*.json,*.png"')
# Only Windows preset. The explicit debug template remains outside game/PCK.
$stagedPresetText=Get-Content -LiteralPath $stagedPreset -Raw
$windowsTemplatePattern='(?ms)(\[preset\.0\.options\]\s*.*?custom_template/debug=)"[^"\r\n]*"'
if($stagedPresetText -notmatch $windowsTemplatePattern){throw 'Missing Windows debug template option.'}
$templateValue=$templateCopy.Replace('\','/')
Write-Utf8 $stagedPreset ([regex]::Replace($stagedPresetText,$windowsTemplatePattern,{param($match) $match.Groups[1].Value+'"'+$templateValue+'"'},1))
Write-Utf8 (Join-Path $pluginDir 'plugin.cfg') "[plugin]`nname=`"Experimental raw PNG export`"`ndescription=`"Package byte-exact runtime dependencies`"`nauthor=`"GOGOBRO`"`nversion=`"1.0`"`nscript=`"plugin.gd`"`n"
$stagedInputs=@{}
foreach($record in $records|Where-Object {$_.path -match '\.(gd|tscn|tres|gdshader)$'}){$stagedInputs[$record.path]=$record.stage_sha256}
foreach($relative in @('project.godot','export_presets.cfg','addons/playtest_raw_export/plugin.cfg','addons/playtest_raw_export/plugin.gd')){$stagedInputs[$relative]=(Get-FileHash -LiteralPath (Join-Path $stage $relative)).Hash}
function Assert-StagedBuildInputs([string]$Phase){
    foreach($relative in $stagedInputs.Keys){
        $path=Join-Path $stage $relative;Assert-NoReparse $path
        if(-not(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path).Hash -cne $stagedInputs[$relative]){throw "Staged executable input changed $Phase`: $relative"}
    }
    Assert-ProjectSectionSyntax (Get-Content -LiteralPath $stagedProject -Raw)
    $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($stage)
    while($pending.Count){
        foreach($entry in Get-ChildItem -LiteralPath $pending.Pop() -Force){
            $relative=$entry.FullName.Substring($stage.Length+1).Replace('\','/')
            if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Staged reparse rejected: $relative"}
            if($relative -ceq 'addons/playtest_raw_export/plugin.gd.uid'){
                # Only this known script's generated metadata, never arbitrary
                # addon files or executable entries. Godot emits base-34 IDs.
                if($entry.PSIsContainer -or $entry.LinkType -or $entry.Length -gt 21){throw 'Staged plugin UID is not a small ordinary file.'}
                $uid=[regex]::Match([IO.File]::ReadAllText($entry.FullName),'\Auid://(a|[b-y0-8][a-y0-8]{0,12})(?:\r?\n)?\z')
                if(-not $uid.Success){throw 'Staged plugin UID is not one canonical UID line.'}
                $value=[Numerics.BigInteger]::Zero
                foreach($character in $uid.Groups[1].Value.ToCharArray()){$value=$value*34+'abcdefghijklmnopqrstuvwxy012345678'.IndexOf($character)}
                if($value -gt [long]::MaxValue){throw 'Staged plugin UID exceeds the Godot ID range.'}
                continue
            }
            if($entry.PSIsContainer){if($relative -cne '.godot'){$pending.Push($entry.FullName)}}
            elseif($entry.Extension -ieq '.gdextension' -or (($entry.Extension -in @('.gd','.tscn','.tres','.gdshader') -or $relative.StartsWith('addons/')) -and -not $stagedInputs.ContainsKey($relative))){throw "Staged unapproved executable input: $relative"}
        }
    }
    $null=Assert-RawExporterStable $Phase
}
Invoke-Engine 'version-info' @('--headless','--path',$stage,'--script',$buildGuard,'--','--guard-phase','version-info')
Invoke-Engine 'import' @('--headless', '--editor', '--path', $stage, '--import', '--quit','--','--guard-phase','import')
$null = Assert-SourceInventory $records 'import'
$rawExporterPostHash = Assert-RawExporterStable 'import'
# Atomically reserve a fresh directory. No cleanup/overwrite of earlier packages, even on failure.
$null = New-Item -ItemType Directory -Path $OutputDirectory
$exe = Join-Path $OutputDirectory 'GOGOBRO.exe'
Invoke-Engine 'export' @('--headless', '--path', $stage, '--export-debug', 'Windows Desktop', $exe,'--','--guard-phase','export')
Assert-EngineStable 'after export'
foreach ($artifact in @($exe, (Join-Path $OutputDirectory 'GOGOBRO.pck'))) {
    if (-not (Test-Path -LiteralPath $artifact) -or (Get-Item -LiteralPath $artifact).Length -eq 0) { throw "Missing exported artifact: $artifact" }
}
$sourcePostInventory = @(Assert-SourceInventory $records 'export')
$rawExporterPostHash = Assert-RawExporterStable 'export'
$templatePostHash=(Get-FileHash -LiteralPath $DebugTemplatePath).Hash
if($templatePostHash -cne $templatePreHash -or (Get-FileHash -LiteralPath $templateCopy).Hash -cne $templatePreHash){throw 'Template changed during build.'}
if((Get-FileHash -LiteralPath $buildGuard).Hash -cne $guardHash){throw 'Build guard changed during build.'}
$sourcePostByPath = @{}
foreach ($record in $sourcePostInventory) { $sourcePostByPath[$record.path] = $record }
foreach ($record in $records) { $record.source_post_sha256 = $sourcePostByPath[$record.path].sha256 }
Write-Utf8 (Join-Path $buildRoot 'source-files.json') ($records | ConvertTo-Json -Depth 4)
# Publish launcher last: failed exports cannot be mistaken for a playable package.
$launcher = @'
@echo off
setlocal
set "APPDATA=%~dp0profile\AppData"
set "LOCALAPPDATA=%~dp0profile\LocalAppData"
if not exist "%APPDATA%" mkdir "%APPDATA%"
if not exist "%LOCALAPPDATA%" mkdir "%LOCALAPPDATA%"
pushd "%~dp0"
"%~dp0GOGOBRO.exe" %*
set "PLAYTEST_EXIT=%ERRORLEVEL%"
popd
exit /b %PLAYTEST_EXIT%
'@
Assert-EngineStable 'before launcher publication'
Assert-StagedBuildInputs 'before launcher publication'
Write-Utf8 (Join-Path $OutputDirectory 'Launch-Experimental.cmd') ($launcher -replace "`r?`n", "`r`n")
Write-Utf8 (Join-Path $OutputDirectory 'PLAYTEST.md') @'
# GOGOBRO 实验试玩快照（20 波）

双击 `Launch-Experimental.cmd` 开始。请保持整个目录完整；不要直接启动 EXE。
包含当前菜单、共享角色/武器设置、商店和战斗；角色仅 NiKo，12 把武器，当前 20 波，并保留第 21 波后的无尽流程。
WASD 移动，Esc 暂停；战斗自动攻击。此版本使用开发预览素材。
存档与设置仅保存在本包的 `profile`，与主项目、工作树和其他试玩包独立。
这是实验 debug 快照，不是正式成品；原生晚波/无尽平衡尚未签收。当前 20 波内容不等于完整游戏完成声明。
未启用 Top20 候选道具包；早期武器保底已包含在当前实验范围内。
包含逐把武器 I–IV 品质、同内容同品质二合一、按实例出售与品质伤害；运行中 checkpoint 使用 schema3，外层 profile 仍为 schema1。
本包的计划验证范围为：配置完整引擎加载此 PCK 的资源、路线及品质/存档连接；实际结果以独立验证证据为准。品质组合为受控库存/金币 fixture，不代表自然购入、整局通关或平衡验收。
导出 EXE/启动器本轮仅做静态产物与来源校验，未实际启动验收。
无窗口启动/资源/路由/短战斗检查不代表人工画面验收、20 波或无尽整局通关验收。
OS自动点击未验，整体手感待试玩。
反馈时请附 `SNAPSHOT.json` 的 source_fingerprint、当前波次和复现步骤。
'@
Write-Utf8 (Join-Path $OutputDirectory 'THIRD_PARTY.md') @'
# Runtime notice

This experimental snapshot uses Godot Engine 4.7.1, distributed under the MIT license.
Godot license text and bundled third-party component notices: https://godotengine.org/license/

Godot's documentation accepts a link to this license page in accompanying documentation.
Game art/audio are the existing project assets identified by SNAPSHOT.json; this package makes
no new ownership or public-release approval claim. Unapproved Top20 assets are excluded.
Development-only GdUnit4 and MCP addons are not included. This snapshot does not ship the
legacy assets/font/ directory and makes no claim that the old font stack is used.
'@
$headPost = Get-PinnedSourceHead 'before manifest publication'
if ($headPost -cne $headPre) { throw 'Source HEAD changed during package construction.' }
$manifest = [ordered]@{
    kind='experimental-twenty-wave-debug-snapshot'; created_utc=[DateTime]::UtcNow.ToString('o'); engine=$version
    engine_sha256=$engineCommandHash; source_head=$headPre; source_fingerprint=$fingerprint
    engine_command=$engineCommand; engine_runtime=$engineExecutable; engine_runtime_sha256=$engineHash
    engine_consistency=[ordered]@{verified=$true;window='Captured command and runtime before staging; both rehashed before every phase, after export, and immediately before launcher publication.';command_pre_sha256=$engineCommandHash;command_post_sha256=$engineCommandHash;runtime_pre_sha256=$engineHash;runtime_post_sha256=$engineHash}
    source_files=$records
    source_consistency_verified=$true
    source_consistency=[ordered]@{
        window='Captured before staging; rehashed after copy, after import, and after export before package publication.'
        source_pre_fingerprint=$fingerprint
        source_post_fingerprint=$fingerprint
    }
    raw_exporter=[ordered]@{
        source_path='tools/playtest_packaging/raw_export_plugin.gd'
        source_pre_sha256=$rawExporterPreHash
        stage_sha256=$rawExporterStageHash
        source_post_sha256=$rawExporterPostHash
    }
    build_guard=[ordered]@{path=$buildGuard;sha256=$guardHash;version_info_assurance='version-info-early';import_export_assurance='plugin-entry';assurance_limits='Plugin entry is not before EditorNode or arbitrary project code.';plugin_sha256=$rawExporterPreHash;real_toy_status='unverified until separately authorized two-stage toy probe';phases=$phaseEvidence.ToArray()}
    debug_template=[ordered]@{source_path=$DebugTemplatePath;source_pre_sha256=$templatePreHash;copy_path=$templateCopy;copy_sha256=(Get-FileHash -LiteralPath $templateCopy).Hash;source_post_sha256=$templatePostHash}
    scope=@('NiKo', '12 weapons', '20 waves', '21+ endless flow', 'early weapon guarantee', 'menu/shop/combat', 'experimental debug/development preview','per-instance weapon quality I-IV','same-content same-quality merge','per-instance sale and damage','run checkpoint schema3 with validated profile wire')
    acceptance_limits=@('OS automation unverified', 'overall feel pending playtest','exported EXE startup unverified','PCK smoke uses controlled quality fixture')
    exclusions=@('Top20 candidates', 'native late-wave/endless balance not signed', 'reports', 'test caches', 'raw generation', 'private ledgers')
    launch_command='Launch-Experimental.cmd'; profile='profile/AppData/GOGOBRO'; build_logs=$buildRoot
    staging_overrides=@('disable development test plugin; enable packaging-only raw PNG exporter from staged project config', 'include runtime JSON and raw PNG from staged export preset; preserve imported textures')
    build_config_files=@('project.godot', 'export_presets.cfg', 'addons/playtest_raw_export/plugin.cfg', 'addons/playtest_raw_export/plugin.gd') | ForEach-Object {
        [ordered]@{path=$_; sha256=(Get-FileHash -LiteralPath (Join-Path $stage $_)).Hash}
    }
    files=@(Get-ChildItem -LiteralPath $OutputDirectory -File | Sort-Object Name | ForEach-Object {
        [ordered]@{path=$_.Name; bytes=$_.Length; sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}
    })
}
Write-Utf8 (Join-Path $OutputDirectory 'SNAPSHOT.json') ($manifest | ConvertTo-Json -Depth 6)
Write-Output "PACKAGE $OutputDirectory"
Write-Output "SOURCE_FINGERPRINT $fingerprint"
Write-Output "BUILD_LOGS $buildRoot"
