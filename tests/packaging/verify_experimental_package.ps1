param(
    [Parameter(Mandatory)][string]$PackageDirectory,
    [string]$GodotBinary = 'E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe',
    [string]$EvidenceDirectory = (Join-Path $PSScriptRoot '../../reports/playtest-feedback-v1/task4a'),
    [ValidateSet('PckOnlyExperimental')][string]$AcceptanceMode,
    [switch]$RenderedPck
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($AcceptanceMode -cne 'PckOnlyExperimental'){throw 'Explicit AcceptanceMode PckOnlyExperimental is required; exported EXE startup will not be tested.'}
function Assert-NoReparse([string]$Path){
    $cursor=[IO.Path]::GetFullPath($Path)
    while($cursor){
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Reparse traversal rejected: $cursor"}
        $parent=Split-Path -Parent $cursor;if($parent -eq $cursor){break};$cursor=$parent
    }
}
function Canonical([string]$Path){return [IO.Path]::GetFullPath($Path).TrimEnd('\','/').Replace('\','/')}
function Get-PckArguments([string]$Package,[string]$Fixture,[bool]$Rendered){
    $display=if($Rendered){@('--windowed','--resolution','1280x720')}else{@('--headless')}
    return @($display)+@('--verbose','--max-fps','60','--quit-after','1200','--main-pack',($Package.TrimEnd('/','\')+'/GOGOBRO.pck'),'--script',$Fixture,'--',$Package)
}
function Assert-ViewportReceipts([string[]]$Lines,[string]$Directory,[bool]$Rendered){
    $records=@($Lines|Where-Object {$_ -match '^PACKAGE_VIEWPORT(?:\s|$)'})
    if(-not $Rendered){if($records.Count){throw 'Headless PCK unexpectedly emitted viewport evidence.'};return}
    $names=@('character-only','weapon-choice','difficulty-ready','combat-after5s','shop-after-merge')
    if($records.Count -ne 5){throw 'Rendered PCK requires exactly five viewport receipts.'}
    Add-Type -AssemblyName System.Drawing
    for($i=0;$i -lt 5;$i++){
        $record=$records[$i].Substring('PACKAGE_VIEWPORT '.Length)|ConvertFrom-Json
        $fields=@('name','path','sha256','bytes','width','height')
        if($record -isnot [pscustomobject] -or @($record.PSObject.Properties.Name).Count -ne $fields.Count -or @($record.PSObject.Properties.Name|Where-Object {$_ -cnotin $fields}).Count){throw 'Viewport receipt schema mismatch.'}
        if($record.name -cne $names[$i] -or $record.path -isnot [string] -or -not [IO.Path]::IsPathRooted($record.path) -or (Canonical $record.path) -cne (Canonical (Join-Path $Directory ($names[$i]+'.png')))){throw 'Viewport name/order/path mismatch.'}
        foreach($key in @('width','height','bytes')){if($record.$key -isnot [int] -and $record.$key -isnot [long]){throw 'Viewport integer type mismatch.'}}
        if($record.width -ne 1280 -or $record.height -ne 720 -or $record.bytes -le 0 -or $record.bytes -gt 33554432 -or $record.sha256 -isnot [string] -or $record.sha256 -cnotmatch '^[A-F0-9]{64}$'){throw 'Viewport size/hash receipt mismatch.'}
        Assert-NoReparse $record.path
        if(-not(Test-Path -LiteralPath $record.path -PathType Leaf) -or (Get-Item -LiteralPath $record.path).Length -ne $record.bytes -or (Get-FileHash -LiteralPath $record.path).Hash -cne $record.sha256){throw 'Viewport artifact changed or missing.'}
        $bytes=[IO.File]::ReadAllBytes($record.path)
        if($bytes.Length -lt 24 -or [Convert]::ToHexString($bytes[0..7]) -cne '89504E470D0A1A0A'){throw 'Viewport artifact is not PNG.'}
        $memory=[IO.MemoryStream]::new($bytes,$false);$png=$null
        try{
            $png=[Drawing.Image]::FromStream($memory,$false,$true)
            if($png.Width -ne 1280 -or $png.Height -ne 720 -or $png.RawFormat.Guid -ne [Drawing.Imaging.ImageFormat]::Png.Guid){throw 'Actual viewport PNG dimensions/format mismatch.'}
        }finally{try{if($null -ne $png){$png.Dispose()}}finally{$memory.Dispose()}}
        $record
    }
}
$lifecyclePath=Join-Path $PSScriptRoot '../../tools/playtest_packaging/owned_process_lifecycle.ps1'
Assert-NoReparse $lifecyclePath
$lifecycleHash=(Get-FileHash -LiteralPath $lifecyclePath).Hash
. $lifecyclePath
Assert-NoReparse $PackageDirectory
$PackageDirectory=(Resolve-Path -LiteralPath $PackageDirectory).Path
$profileRoot=Join-Path $PackageDirectory 'profile'
if(Test-Path -LiteralPath $profileRoot){
    Assert-NoReparse $profileRoot
    $existing=@(Get-ChildItem -LiteralPath $profileRoot -Recurse -Force)
    if(@($existing|Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}).Count){throw 'Profile reparse points cannot be verified safely.'}
    if(@($existing|Where-Object {-not $_.PSIsContainer}).Count){throw 'Profile is not empty; verification will not touch existing player data.'}
}
$active=@(Get-CimInstance Win32_Process|Where-Object {$_.Name -match '^(Godot.*|GOGOBRO|cmd)\.exe$' -and $_.CommandLine -and $_.CommandLine.Replace('/','\').IndexOf($PackageDirectory,[StringComparison]::OrdinalIgnoreCase) -ge 0})
if($active.Count){throw 'Package is in use; refusing verification.'}
function Package-Inventory {
    return @(Get-ChildItem -LiteralPath $PackageDirectory -Recurse -Force|Sort-Object FullName|ForEach-Object {
        Assert-NoReparse $_.FullName
        if($_.PSIsContainer){[ordered]@{path=$_.FullName.Substring($PackageDirectory.Length+1);kind='directory';sha256=$null;bytes=0}}
        else{[ordered]@{path=$_.FullName.Substring($PackageDirectory.Length+1);kind='file';sha256=(Get-FileHash -LiteralPath $_.FullName).Hash;bytes=$_.Length}}
    })
}
$before=@(Package-Inventory)
$manifest=Get-Content -LiteralPath (Join-Path $PackageDirectory 'SNAPSHOT.json') -Raw|ConvertFrom-Json
foreach($name in @('GOGOBRO.exe','GOGOBRO.pck','Launch-Experimental.cmd')){
    $record=@($manifest.files|Where-Object {$_.path -ceq $name})
    if($record.Count -ne 1){throw "Missing/duplicate manifest artifact: $name"}
}
foreach($entry in $manifest.files){
    if($entry.path -notmatch '^[^/\\:]+$' -or $entry.path -in @('.','..')){throw 'Unsafe manifest artifact path.'}
    $path=Join-Path $PackageDirectory $entry.path
    Assert-NoReparse $path
    if(-not(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0 -or (Get-FileHash -LiteralPath $path).Hash -cne $entry.sha256){throw "Package modified: $($entry.path)"}
}
# Static PE inspection only; never execute the exported template/launcher.
$stream=[IO.File]::OpenRead((Join-Path $PackageDirectory 'GOGOBRO.exe'))
$reader=[IO.BinaryReader]::new($stream)
try{
    if($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5a4d){throw 'EXE is not PE.'}
    $stream.Position=60;$peOffset=$reader.ReadInt32()
    if($peOffset -lt 64 -or $peOffset -gt $stream.Length-6){throw 'Invalid PE header offset.'}
    $stream.Position=$peOffset
    if($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664){throw 'EXE is not x64 PE.'}
}finally{$reader.Dispose();$stream.Dispose()}
Assert-NoReparse $EvidenceDirectory
$validation=Join-Path ([IO.Path]::GetFullPath($EvidenceDirectory)) ('validation-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $validation
$tempBase=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Temp'
Assert-NoReparse $tempBase
$fresh=Join-Path $tempBase ('gogobro-pck-validation-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $fresh
$working=Join-Path $fresh 'working';$null=New-Item -ItemType Directory -Path $working
$child=[ordered]@{TEMP=(Join-Path $fresh 'Temp');TMP=(Join-Path $fresh 'Temp');APPDATA=(Join-Path $fresh 'AppData');LOCALAPPDATA=(Join-Path $fresh 'LocalAppData')}
foreach($path in @($child.TEMP,$child.APPDATA,$child.LOCALAPPDATA)){$null=New-Item -ItemType Directory -Path $path}
$child.GOGOBRO_TEST_EXPECTED_APPDATA=$child.APPDATA;$child.GOGOBRO_TEST_EXPECTED_LOCALAPPDATA=$child.LOCALAPPDATA
$child.GOGOBRO_TEST_EXPECTED_USER_DATA_DIR=Join-Path $child.APPDATA 'GOGOBRO'
foreach($name in @('profile.json','profile.tmp','profile.backup')){if(Test-Path -LiteralPath (Join-Path $child.GOGOBRO_TEST_EXPECTED_USER_DATA_DIR ('GOGOBRO/'+$name))){throw 'Fresh synthetic profile unexpectedly exists.'}}
$smokeSource=Join-Path $PSScriptRoot '../../tools/playtest_packaging/package_smoke.gd'
Assert-NoReparse $smokeSource
$fixture=Join-Path $fresh 'package_smoke.gd';Copy-Item -LiteralPath $smokeSource -Destination $fixture
$fixtureHash=(Get-FileHash -LiteralPath $fixture).Hash
if($fixtureHash -cne (Get-FileHash -LiteralPath $smokeSource).Hash){throw 'External fixture copy mismatch.'}
$fixtureAtRun=Join-Path $validation 'package_smoke.at-run.gd'
Copy-Item -LiteralPath $fixture -Destination $fixtureAtRun
$verifierAtRun=Join-Path $validation 'verify_experimental_package.at-run.ps1'
Copy-Item -LiteralPath $PSCommandPath -Destination $verifierAtRun
$verifierHash=(Get-FileHash -LiteralPath $PSCommandPath).Hash
$lifecycleAtRun=Join-Path $validation 'owned_process_lifecycle.at-run.ps1'
Copy-Item -LiteralPath $lifecyclePath -Destination $lifecycleAtRun
if((Get-FileHash -LiteralPath $lifecycleAtRun).Hash -cne $lifecycleHash){throw 'Lifecycle source copy mismatch.'}
$engineExecutable=[IO.Path]::GetFullPath($GodotBinary)
if($engineExecutable.EndsWith('_console.exe',[StringComparison]::OrdinalIgnoreCase)){$engineExecutable=$engineExecutable -replace '_console\.exe$','.exe'}
Assert-NoReparse $engineExecutable
$engineHash=(Get-FileHash -LiteralPath $engineExecutable).Hash
$arguments=@(Get-PckArguments $PackageDirectory $fixture $RenderedPck.IsPresent)
$psi=[Diagnostics.ProcessStartInfo]::new($engineExecutable)
$psi.UseShellExecute=$false;$psi.CreateNoWindow=-not $RenderedPck.IsPresent;$psi.WorkingDirectory=$working;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
if([IO.Path]::GetExtension($engineExecutable) -in @('.cmd','.bat')){
    $parts=@($engineExecutable)+$arguments
    if(@($parts|Where-Object {$_ -match '["%&|<>^!\r\n]'}).Count){throw 'Unsafe command-fixture argument.'}
    $psi.FileName=$env:ComSpec;$psi.Arguments='/d /s /c "'+(($parts|ForEach-Object {'"'+$_+'"'}) -join ' ')+'"'
}else{foreach($argument in $arguments){$psi.ArgumentList.Add($argument)}}
$parentEnv=[ordered]@{}
foreach($key in $child.Keys){$parentEnv[$key]=@{present=(Test-Path "Env:$key");value=[Environment]::GetEnvironmentVariable($key,'Process')};$psi.Environment[$key]=$child[$key]}
$result=[ordered]@{acceptance_mode=$AcceptanceMode;exported_exe_startup='not_run';pck_smoke_passed=$false;static_pe_x64=$true;package=$PackageDirectory;
    execution_mode=$(if($RenderedPck){'rendered-pck'}else{'headless-pck'});viewport_directory=(Join-Path $child.TEMP 'package-viewports');viewports=@();viewport_kind='native-rendered-viewport-not-desktop';os_input='not_run';
    executable=$engineExecutable;engine_sha256=$engineHash;arguments=$arguments;working_directory=$working;environment=$child;parent_environment=$parentEnv;
    fixture_source=$smokeSource;fixture=$fixture;fixture_sha256=$fixtureHash;fixture_at_run=$fixtureAtRun;verifier_at_run=$verifierAtRun;verifier_sha256=$verifierHash;
    started=$false;owned=$false;pid=$null;start_time_utc=$null;start_receipt=$null;end_pid=$null;has_exited=$null;exit_code=$null;timed_out=$false;disposed=$false;streams_disposed=$false;
    guard_ok=$false;exception=$null;cleanup_errors=@();package_unchanged=$false;parent_environment_unchanged=$false;inputs_unchanged=$false;profile_artifact=$null;profile_presence=$null;profile_files=@();lifecycle_sha256=$lifecycleHash;lifecycle_at_run=$lifecycleAtRun}
$utf8=[Text.UTF8Encoding]::new($false)
$stdout=Join-Path $validation 'package-only-smoke.stdout.log';$stderr=Join-Path $validation 'package-only-smoke.stderr.log'
[IO.File]::WriteAllText((Join-Path $validation 'invocation.json'),($result|ConvertTo-Json -Depth 7),$utf8)
[IO.File]::WriteAllText((Join-Path $validation 'package-before.json'),($before|ConvertTo-Json -Depth 4),$utf8)
$after=@()
function Preserve-SyntheticProfile {
    $presence=[ordered]@{}
    foreach($entry in @(@('profile','profile.json'),@('temporary','profile.tmp'),@('backup','profile.backup'))){
        $path=Join-Path $child.GOGOBRO_TEST_EXPECTED_USER_DATA_DIR ('GOGOBRO/'+$entry[1])
        Assert-NoReparse $path
        $presence[$entry[0]]=Test-Path -LiteralPath $path -PathType Leaf
        if($presence[$entry[0]]){
            $copy=Join-Path $validation ('synthetic-'+$entry[1])
            if(-not(Test-Path -LiteralPath $copy)){Copy-Item -LiteralPath $path -Destination $copy}
            $record=[ordered]@{path=$path;copy=$copy;sha256=(Get-FileHash -LiteralPath $path).Hash;bytes=(Get-Item -LiteralPath $path).Length}
            if((Get-FileHash -LiteralPath $copy).Hash -cne $record.sha256){throw 'Synthetic profile evidence changed.'}
            $result.profile_files+=@($record)
            if($entry[0] -ceq 'profile'){$result.profile_artifact=$record}
        }
    }
    $result.profile_presence=$presence
}
try{
    foreach($key in $child.Keys){if($psi.Environment[$key] -cne $child[$key]){throw "Child environment mismatch: $key"}}
    $process=[Diagnostics.Process]::new();$process.StartInfo=$psi
    $output=Invoke-OwnedProcess $process $result $stdout $stderr (Join-Path $validation 'process-start.json')
    if($result.exception){throw $result.exception}
    if($result.cleanup_errors.Count -or -not $result.has_exited -or -not $result.stdout_complete -or -not $result.stderr_complete){throw 'PCK process finalization incomplete.'}
    $out=$output.out;$err=$output.err
    if($result.timed_out -or $result.exit_code -ne 0){throw "PCK smoke exit $($result.exit_code)"}
    if($err.Length -gt 0 -or $out -match 'SCRIPT ERROR:|(?m)^ERROR:|PACKAGE_ISOLATION_FAIL|PACKAGE_SMOKE_FAILED'){throw 'PCK smoke logged errors.'}
    $guards=@($out -split '\r?\n'|Where-Object {$_ -match '^PACKAGE_ISOLATION_OK '})
    if($guards.Count -ne 1){throw 'PCK needs exactly one actual-user guard.'}
    $guard=$guards[0].Substring('PACKAGE_ISOLATION_OK '.Length)|ConvertFrom-Json
    if($guard.pid -ne $result.pid -or (Canonical $guard.appdata) -cne (Canonical $child.APPDATA) -or (Canonical $guard.localappdata) -cne (Canonical $child.LOCALAPPDATA) -or (Canonical $guard.user_data) -cne (Canonical $child.GOGOBRO_TEST_EXPECTED_USER_DATA_DIR)){throw 'PCK guard identity/path mismatch.'}
    if($guard.schema_version -ne 1 -or $guard.phase -cne 'before-manifest-app-profile' -or $guard.pid -isnot [long] -and $guard.pid -isnot [int]){throw 'PCK guard schema/phase/PID mismatch.'}
    foreach($pair in @(@('temp','TEMP'),@('tmp','TMP'),@('expected_appdata','GOGOBRO_TEST_EXPECTED_APPDATA'),@('expected_localappdata','GOGOBRO_TEST_EXPECTED_LOCALAPPDATA'),@('expected_user_data','GOGOBRO_TEST_EXPECTED_USER_DATA_DIR'))){
        if($guard.($pair[0]) -isnot [string] -or (Canonical $guard.($pair[0])) -cne (Canonical $child[$pair[1]])){throw "PCK guard environment mismatch: $($pair[0])"}
    }
    foreach($field in @('profile','temporary','backup')){if($guard.profile_before.$field -isnot [bool] -or $guard.profile_before.$field){throw 'PCK profile must be absent at the pre-App guard.'}}
    $result.guard_ok=$true;$result.guard=$guard
    $lines=@($out -split '\r?\n');$lastIndex=-1
    foreach($marker in @('PACKAGE_ISOLATION_OK','PACKAGE_RESOURCES_OK','PACKAGE_ROUTE_OK','PACKAGE_B_PURCHASE_OK','PACKAGE_SHOP_OK','PACKAGE_B_QUALITY_OK','PACKAGE_PROFILE_WIRE_OK','PACKAGE_SMOKE_RESULT')){
        $matches=@(for($i=0;$i -lt $lines.Count;$i++){if($lines[$i] -match ('^'+[regex]::Escape($marker)+'(?:\s|$)')){$i}})
        if($matches.Count -ne 1 -or $matches[0] -le $lastIndex){throw "Missing/duplicate/out-of-order PCK completion marker: $marker"}
        $lastIndex=$matches[0]
    }
    if($lines[$lastIndex] -cne 'PACKAGE_SMOKE_RESULT failures=0'){throw 'PCK final result is not exactly failures=0.'}
    $wireLine=@($lines|Where-Object {$_ -match '^PACKAGE_PROFILE_WIRE_OK '})
    if($wireLine.Count -ne 1){throw 'PCK wire receipt is missing.'}
    $wire=$wireLine[0].Substring('PACKAGE_PROFILE_WIRE_OK '.Length)|ConvertFrom-Json
    Preserve-SyntheticProfile
    if(-not $result.profile_artifact -or $wire.profile_sha256 -cne $result.profile_artifact.sha256 -or $wire.pre_wire_sha256 -notmatch '^[A-F0-9]{64}$' -or $wire.run_seed_exact -cne '9007199254740993'){throw 'PCK wire profile/hash/int64 receipt mismatch.'}
    foreach($field in @('profile','temporary','backup')){if($wire.profile_presence.$field -isnot [bool] -or $wire.profile_presence.$field -ne $result.profile_presence[$field]){throw 'PCK wire three-file presence mismatch.'}}
    $result.profile_wire=$wire
    $progressMarkers=@('PACKAGE_CHARACTER_GRID_OK','PACKAGE_PROGRESS_20_OK','PACKAGE_ENDLESS_21_22_OK','PACKAGE_PROFILE_READBACK_OK')
    $progressIndexes=[ordered]@{}
    foreach($marker in $progressMarkers){
        $matches=@(for($i=0;$i -lt $lines.Count;$i++){if($lines[$i] -match ('^'+[regex]::Escape($marker)+'(?:\s|$)')){$i}})
        if($matches.Count -ne 1){throw "Missing/duplicate PCK progression marker: $marker"}
        $progressIndexes[$marker]=$matches[0]
    }
    $resourceIndex=[array]::IndexOf($lines,@($lines|Where-Object {$_ -match '^PACKAGE_RESOURCES_OK(?:\s|$)'})[0])
    $routeIndex=[array]::IndexOf($lines,@($lines|Where-Object {$_ -match '^PACKAGE_ROUTE_OK(?:\s|$)'})[0])
    $qualityIndex=[array]::IndexOf($lines,@($lines|Where-Object {$_ -match '^PACKAGE_B_QUALITY_OK(?:\s|$)'})[0])
    $wireIndex=[array]::IndexOf($lines,$wireLine[0])
    if(-not($resourceIndex -lt $progressIndexes.PACKAGE_CHARACTER_GRID_OK -and $progressIndexes.PACKAGE_CHARACTER_GRID_OK -lt $routeIndex -and
        $qualityIndex -lt $progressIndexes.PACKAGE_PROGRESS_20_OK -and $progressIndexes.PACKAGE_PROGRESS_20_OK -lt $progressIndexes.PACKAGE_ENDLESS_21_22_OK -and
        $progressIndexes.PACKAGE_ENDLESS_21_22_OK -lt $progressIndexes.PACKAGE_PROFILE_READBACK_OK -and $progressIndexes.PACKAGE_PROFILE_READBACK_OK -lt $wireIndex)){
        throw 'PCK progression marker order mismatch.'
    }
    if($lines[$progressIndexes.PACKAGE_CHARACTER_GRID_OK] -cne 'PACKAGE_CHARACTER_GRID_OK columns=6 rows=4 live=1 placeholders=23'){
        throw 'PCK character grid receipt mismatch.'
    }
    $progress=$lines[$progressIndexes.PACKAGE_PROGRESS_20_OK].Substring('PACKAGE_PROGRESS_20_OK '.Length)|ConvertFrom-Json
    if($progress.controlled -ne $true -or $progress.full_survival_pilot -ne $false -or $progress.first -ne 1 -or $progress.last -ne 20 -or $progress.count -ne 20 -or $progress.final_shop -ne $true){
        throw 'PCK controlled W1-W20 receipt mismatch.'
    }
    $endless=$lines[$progressIndexes.PACKAGE_ENDLESS_21_22_OK].Substring('PACKAGE_ENDLESS_21_22_OK '.Length)|ConvertFrom-Json
    if($endless.controlled -ne $true -or $endless.full_survival_pilot -ne $false -or $endless.endless_button -ne 21 -or $endless.continue_button -ne 22 -or $endless.live_world -ne 22){
        throw 'PCK endless W21-W22 receipt mismatch.'
    }
    $readback=$lines[$progressIndexes.PACKAGE_PROFILE_READBACK_OK].Substring('PACKAGE_PROFILE_READBACK_OK '.Length)|ConvertFrom-Json
    if($readback.resume_claim -ne $false -or @($readback.waves).Count -ne 2 -or $readback.waves[0] -ne 21 -or $readback.waves[1] -ne 22 -or $readback.profile_sha256 -cnotmatch '^[A-F0-9]{64}$'){
        throw 'PCK checkpoint readback receipt mismatch.'
    }
    $result.progression=[ordered]@{character_grid=$lines[$progressIndexes.PACKAGE_CHARACTER_GRID_OK];waves=$progress;endless=$endless;profile_readback=$readback}
    $result.viewports=@(Assert-ViewportReceipts $lines $result.viewport_directory $RenderedPck.IsPresent)
    $result.pck_smoke_passed=$true
}catch{if(-not $result.exception){$result.exception=$_.Exception.Message};$result.pck_smoke_passed=$false}finally{
    Invoke-OwnedFinalizer $result 'synthetic-profile' {if($null -eq $result.profile_presence){Preserve-SyntheticProfile}}
    Invoke-OwnedFinalizer $result 'package-inventory' {
        $script:after=@(Package-Inventory)
        $result.package_unchanged=($before|ConvertTo-Json -Compress -Depth 4) -ceq ($after|ConvertTo-Json -Compress -Depth 4)
        if(-not $result.package_unchanged){throw 'Package changed during verification.'}
    }
    $pinErrors=$result.cleanup_errors.Count
    foreach($pin in @(@($fixture,$fixtureHash),@($fixtureAtRun,$fixtureHash),@($smokeSource,$fixtureHash),@($PSCommandPath,$verifierHash),@($verifierAtRun,$verifierHash),@($engineExecutable,$engineHash),@($lifecyclePath,$lifecycleHash),@($lifecycleAtRun,$lifecycleHash))){
        Invoke-OwnedFinalizer $result ('input:'+ $pin[0]) {Assert-NoReparse $pin[0];if((Get-FileHash -LiteralPath $pin[0]).Hash -cne $pin[1]){throw 'PCK verification input changed.'}}
    }
    $result.inputs_unchanged=$result.cleanup_errors.Count -eq $pinErrors
    Invoke-OwnedFinalizer $result 'parent-environment' {$result.parent_environment_unchanged=Test-OwnedParentEnvironment $parentEnv;if(-not $result.parent_environment_unchanged){throw 'Parent environment changed.'}}
    Invoke-OwnedFinalizer $result 'package-after-receipt' {[IO.File]::WriteAllText((Join-Path $validation 'package-after.json'),($after|ConvertTo-Json -Depth 4),$utf8)}
    if($result.exception -or $result.cleanup_errors.Count -or -not $result.package_unchanged -or -not $result.inputs_unchanged -or -not $result.parent_environment_unchanged){$result.pck_smoke_passed=$false}
    Write-OwnedCompletion $result (Join-Path $validation 'completion.json')
}
if($result.exception -or $result.cleanup_errors.Count){throw "PCK failed: $($result.exception) Cleanup: $($result.cleanup_errors|ConvertTo-Json -Compress)"}
if(-not $result.pck_smoke_passed){throw 'PCK verification provenance changed.'}
Write-Output 'EXPORTED_EXE_STARTUP=not_run'
Write-Output 'PCK_SMOKE_PASSED=True'
Write-Output "VALIDATED_PCK_ONLY $PackageDirectory"
Write-Output "LOGS $validation"
Write-Output "EXTERNAL_SYNTHETIC_USER $($child.GOGOBRO_TEST_EXPECTED_USER_DATA_DIR)"
