# Shared only by the canonical builder/verifier. No engine admission or acceptance
# is performed here: callers must retain their own guard and provenance checks.
function Invoke-OwnedFinalizer($Record,[string]$Name,[scriptblock]$Action){
    try{& $Action | Out-Null}
    catch{$Record.cleanup_errors+=@([ordered]@{stage=$Name;error=$_.Exception.Message})}
}

function Test-OwnedParentEnvironment($Snapshot){
    $unchanged=$true
    foreach($key in $Snapshot.Keys){
        if((Test-Path "Env:$key") -ne $Snapshot[$key].present -or [Environment]::GetEnvironmentVariable($key,'Process') -cne $Snapshot[$key].value){$unchanged=$false}
    }
    return $unchanged
}

function Write-OwnedCompletion($Record,[string]$Path){
    Invoke-OwnedFinalizer $Record 'final-receipt' {
        $Record.final_receipt=$Path
        $Record.final_receipt_written=$true
        try{[IO.File]::WriteAllText($Path,($Record|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))}
        catch{$Record.final_receipt_written=$false;throw}
    }
}

function Invoke-OwnedProcess($Process,$Record,[string]$StdoutPath,[string]$StderrPath,[string]$StartReceipt){
    $defaults=[ordered]@{started=$false;owned=$false;pid=$null;start_time_utc=$null;start_receipt=$null;start_receipt_written=$false;
        end_pid=$null;has_exited=$null;exit_code=$null;timed_out=$false;kill_requested=$false;kill_succeeded=$false;terminal_wait_completed=$null;
        stdout_complete=$false;stderr_complete=$false;stdout_written=$false;stderr_written=$false;
        stdout_dispose_attempted=$false;stderr_dispose_attempted=$false;stdout_disposed=$false;stderr_disposed=$false;
        process_dispose_attempted=$false;disposed=$false;streams_disposed=$false;exception=$null;cleanup_errors=@();
        final_receipt=$null;final_receipt_written=$false}
    foreach($key in $defaults.Keys){$Record[$key]=$defaults[$key]}
    $io=@{stdout=$null;stderr=$null;outTask=$null;errTask=$null;out='';err=''}
    $encoding=[Text.UTF8Encoding]::new($false)
    try{
        if(-not $Process.Start()){throw 'Owned process did not start.'}
        $Record.started=$true
        $Record.pid=$Process.Id
        if($Record.pid -isnot [int] -or $Record.pid -le 0){throw 'Start succeeded but a positive owned PID could not be captured.'}
        $Record.owned=$true
        # PID and Start success are persisted before any further Process property
        # or stream access can fail. This is a real receipt, not reconstructed.
        $Record.start_receipt=$StartReceipt
        $Record.start_receipt_written=$true
        try{[IO.File]::WriteAllText($StartReceipt,($Record|ConvertTo-Json -Depth 12),$encoding)}
        catch{$Record.start_receipt_written=$false;throw}
        $Record.start_time_utc=$Process.StartTime.ToUniversalTime().ToString('o')
        $io.stdout=$Process.StandardOutput
        $io.stderr=$Process.StandardError
        $io.outTask=$io.stdout.ReadToEndAsync()
        $io.errTask=$io.stderr.ReadToEndAsync()
        if(-not $Process.WaitForExit(30000)){$Record.timed_out=$true}
    }catch{$Record.exception=$_.Exception.Message}
    finally{
        # Each action is independent: failed Kill does not skip the bounded wait,
        # and failed drain/write/status/disposal does not skip another resource.
        Invoke-OwnedFinalizer $Record 'owned-status-stop' {
            if($Record.owned){
                $exited=$Process.HasExited
                if($exited -isnot [bool]){throw 'Owned child status unavailable; termination is not authorized by an unknown status.'}
                if(-not $exited){
                    $Record.kill_requested=$true
                    $Process.Kill()
                    $Record.kill_succeeded=$true
                }
            }
        }
        Invoke-OwnedFinalizer $Record 'terminal-wait' {
            if($Record.kill_requested){
                $Record.terminal_wait_completed=$Process.WaitForExit(2000)
                if(-not $Record.terminal_wait_completed){throw 'Owned child did not exit within terminal budget.'}
            }
        }
        foreach($streamName in @('stdout','stderr')){
            $taskKey=if($streamName -ceq 'stdout'){'outTask'}else{'errTask'}
            $textKey=if($streamName -ceq 'stdout'){'out'}else{'err'}
            $path=if($streamName -ceq 'stdout'){$StdoutPath}else{$StderrPath}
            Invoke-OwnedFinalizer $Record ($streamName+'-drain') {
                $task=$io[$taskKey]
                if($null -eq $task){throw 'Stream read task was not established; output is incomplete.'}
                if(-not $task.Wait(2000) -or -not $task.IsCompleted){throw 'Stream drain did not complete within 2000ms.'}
                # A faulted Wait throws above. Never request a blocking result.
                $io[$textKey]=$task.GetAwaiter().GetResult()
                $Record[$streamName+'_complete']=$true
            }
            Invoke-OwnedFinalizer $Record ($streamName+'-write') {
                # Empty on an incomplete read is only an artifact placeholder;
                # *_complete=false and cleanup_errors explicitly preserve that fact.
                [IO.File]::WriteAllText($path,$io[$textKey],$encoding)
                $Record[$streamName+'_written']=$true
            }
        }
        Invoke-OwnedFinalizer $Record 'final-pid' {
            if($Record.owned){$Record.end_pid=$Process.Id;if($Record.end_pid -isnot [int] -or $Record.end_pid -ne $Record.pid){throw 'Final owned PID unavailable or changed.'}}
        }
        Invoke-OwnedFinalizer $Record 'final-has-exited' {
            if($Record.owned){$Record.has_exited=$Process.HasExited;if($Record.has_exited -isnot [bool]){throw 'Final child status unavailable.'}}
        }
        Invoke-OwnedFinalizer $Record 'final-exit-code' {
            if($Record.owned -and $Record.has_exited){$Record.exit_code=$Process.ExitCode;if($Record.exit_code -isnot [int]){throw 'Final child exit code unavailable.'}}
        }
        foreach($streamName in @('stdout','stderr')){
            Invoke-OwnedFinalizer $Record ($streamName+'-dispose') {
                # Stream retrieval itself may have failed after Start; make one
                # independent final attempt to acquire each owned stream handle.
                if($null -eq $io[$streamName] -and $Record.owned){
                    $io[$streamName]=if($streamName -ceq 'stdout'){$Process.StandardOutput}else{$Process.StandardError}
                }
                if($null -ne $io[$streamName]){
                    $Record[$streamName+'_dispose_attempted']=$true
                    $io[$streamName].Dispose()
                    $Record[$streamName+'_disposed']=$true
                }
            }
        }
        Invoke-OwnedFinalizer $Record 'process-dispose' {
            $Record.process_dispose_attempted=$true
            $Process.Dispose()
            $Record.disposed=$true
        }
        $Record.streams_disposed=$Record.stdout_disposed -and $Record.stderr_disposed
    }
    return [pscustomobject]@{out=$io.out;err=$io.err}
}
