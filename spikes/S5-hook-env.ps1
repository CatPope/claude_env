<#
.SYNOPSIS
  S5 — 훅 환경 스파이크 (계획 §5 Step 0, S5(a)~(e)).
.DESCRIPTION
  단계(-Step):
    prepare   백업 → ~/.claude/settings.json 에 표식 훅을 4가지 형식으로 설치한다(기존 항목은 그대로 두고 덧붙임).
                exec-bash : bash.exe + args(exec 형식, 셸 없음)                  ← 계획의 기본 형식
                shell-bash: 기본 셸(Git Bash) command 문자열, 공백·한글 경로를 작은따옴표로 인용
                shell-ps  : shell:"powershell" command 문자열
                exec-ps   : powershell.exe -NoProfile -ExecutionPolicy Bypass -File ... (exec 형식)
              shell-bash / shell-ps 는 공백과 한글이 든 폴더(_log\경로 테스트 dir\)에 복사한 스크립트를 가리킨다(S5(b)).
              이벤트: SessionStart, UserPromptSubmit, Notification, Stop, SessionEnd.
    bench     각 형식의 훅 명령을 PowerShell 에서 N회 직접 실행해 벽시계 시간(p50/p95)을 잰다(S5(c) 훅 시간).
    auth      `claude auth status` 지연을 잰다: 웜(연속 N회) + 콜드(N회, 각 실행 사이 -ColdGapSeconds 대기)(S5(c)).
    policy    실행 정책 재현(S5(d)): 사용자 정책은 바꾸지 않고, 자식 프로세스에 -ExecutionPolicy Restricted 를 줘서
              프로필·스크립트가 막히는 것을 재현하고, RemoteSigned/Bypass 로 풀리는 것을 확인한다.
    analyze   hooks.jsonl 을 읽어 (a) CCE_PANE_KEY/WT_SESSION 가시성, (b) 형식별 실행 여부, (c) dur_ms p95,
              (e) VS Code(TERM_PROGRAM=vscode) 세션에서 상태 파일이 바뀌지 않았는지 판정한다.
    cleanup   표식 훅만 제거한다(다른 훅·statusline 은 건드리지 않음).
#>
param(
    [Parameter(Mandatory)][ValidateSet('prepare','bench','auth','policy','analyze','cleanup')][string]$Step,
    [int]$N = 10,
    [int]$ColdGapSeconds = 20,
    [string[]]$Variants = @('exec-bash','shell-bash','shell-ps','exec-ps')
)
. "$PSScriptRoot\common\common.ps1"
Initialize-SpikeDirs
$Tag = 'S5'
# powershell -File 로 넘기면 "a,b" 가 한 문자열로 오므로 쉼표를 나눈다.
$Variants = @($Variants | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
$events = @('SessionStart','UserPromptSubmit','Notification','Stop','SessionEnd')
$pathDir = Join-Path $script:LogDir '경로 테스트 dir'          # 공백 + 한글 (S5(b))
$pathSh  = Join-Path $pathDir 'cce-spike-hook.sh'
$pathPs1 = Join-Path $pathDir 'cce-spike-hook.ps1'
$samplePayload = '{"session_id":"bench-0000","transcript_path":"C:\\Users\\x\\t.jsonl","cwd":"C:\\Users\\x","hook_event_name":"Stop","last_assistant_message":"ok"}'

function Get-CommandLineForVariant([string]$Variant, [string]$Event) {
    # 설치한 것과 같은 실행 방식으로 벤치마크용 커맨드라인을 만든다.
    switch ($Variant) {
        'exec-bash'  { return @{ file = $script:GitBashExe; args = @((ConvertTo-ForwardSlash $script:HookSh), $Event, 'bench-exec-bash', (ConvertTo-ForwardSlash $script:LogDir)) } }
        'shell-bash' { return @{ file = $script:GitBashExe; args = @('-c', ("'{0}' {1} bench-shell-bash '{2}'" -f (ConvertTo-ForwardSlash $pathSh), $Event, (ConvertTo-ForwardSlash $script:LogDir))) } }
        'shell-ps'   { return @{ file = 'powershell.exe'; args = @('-NoProfile','-Command', ("& '{0}' -Event {1} -Variant bench-shell-ps -LogDir '{2}'" -f $pathPs1, $Event, $script:LogDir)) } }
        'exec-ps'    { return @{ file = 'powershell.exe'; args = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $script:HookPs1, '-Event', $Event, '-Variant', 'bench-exec-ps', '-LogDir', $script:LogDir) } }
    }
}
function Invoke-Timed([string]$File, [string[]]$ArgList, [string]$Stdin) {
    # 매개변수 이름을 $Args 로 하면 자동 변수 $args 와 겹쳐 빈 값이 되므로 ArgList 로 둔다.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    $psi.Arguments = ($ArgList | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"','\"') + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Console]::OutputEncoding; $psi.StandardErrorEncoding = [Console]::OutputEncoding
    $psi.CreateNoWindow = $true
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $p = [System.Diagnostics.Process]::Start($psi)
    # StandardInput 의 기본 인코더는 BOM 을 붙이므로 바이트로 직접 쓴다(Claude Code 가 주는 페이로드에는 BOM 이 없다).
    $bytes = $script:Utf8NoBom.GetBytes($Stdin)
    $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length); $p.StandardInput.BaseStream.Flush(); $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEnd(); $err = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    $sw.Stop()
    return [pscustomobject]@{ ms = [math]::Round($sw.Elapsed.TotalMilliseconds, 1); exit = $p.ExitCode; stdout = $out.Trim(); stderr = $err.Trim() }
}

switch ($Step) {
  'prepare' {
    & "$PSScriptRoot\common\backup.ps1" -Label 'before-S5'
    if (-not (Test-Path -LiteralPath $pathDir)) { New-Item -ItemType Directory -Path $pathDir | Out-Null; Write-Touched 'MKDIR' $pathDir }
    Copy-Item -LiteralPath $script:HookSh -Destination $pathSh -Force;  Write-Touched 'COPY' $pathSh
    Copy-Item -LiteralPath $script:HookPs1 -Destination $pathPs1 -Force; Write-Touched 'COPY' $pathPs1
    Set-TitleMode -Mode none
    $entries = @()
    foreach ($ev in $events) {
        foreach ($v in $Variants) {
            switch ($v) {
                'exec-bash'  { $g = New-HookEntry -Event $ev -Form exec-bash }
                'shell-bash' { $g = New-HookEntry -Event $ev -Form shell-bash -ScriptSh $pathSh -Variant 'shell-bash-path' }
                'shell-ps'   { $g = New-HookEntry -Event $ev -Form shell-ps -ScriptPs1 $pathPs1 -Variant 'shell-ps-path' }
                'exec-ps'    { $g = New-HookEntry -Event $ev -Form exec-ps }
            }
            $entries += @{ Event = $ev; Group = $g }
        }
    }
    Install-SpikeHooks -Entries $entries -Tag $Tag
    Write-Host ''
    Write-Host '설치한 항목(요약):'
    foreach ($r in Get-SpikeHooksInSettings) {
        $h = $r.group.hooks[0]
        $desc = $(if (Test-JsonHasProperty $h 'args') { "$($h.command) " + (($h.args | Select-Object -First 3) -join ' ') + ' ...' } else { "[shell=$(Get-Prop $h 'shell' 'bash')] $($h.command)" })
        Write-Host ("  {0,-17} {1}" -f $r.event, $desc)
    }
    $repo = $script:RepoRoot
    Write-Manual @(
        "WT 의 PowerShell pane 에서 cce 대역으로 Claude 를 띄운다:  & '$repo\spikes\common\cce-stub.ps1' -Scenario s5",
        "프롬프트를 하나 보내고(예: '1+1은?'), 권한 요청이 나오게 하는 프롬프트도 하나 보낸 뒤(예: 'C:\Temp 에 a.txt 만들어줘'), /exit 로 끝낸다.",
        "(e) VS Code 통합 터미널에서 같은 폴더로 이동해 그냥 `claude` 를 띄우고 프롬프트 하나를 보낸 뒤 /exit. (CCE_PANE_KEY·WT_SESSION 이 없어야 함)",
        "  -Step bench -N 20 으로 훅 시간, -Step auth -N 10 으로 auth 지연, -Step policy 로 실행 정책을 확인한 뒤 -Step analyze.",
        "끝나면 -Step cleanup."
    )
  }
  'bench' {
    $rows = @()
    foreach ($v in $Variants) {
        $cl = Get-CommandLineForVariant $v 'Stop'
        $times = @()
        for ($i = 0; $i -lt $N; $i++) {
            $r = Invoke-Timed $cl.file $cl.args $samplePayload
            $times += [double]$r.ms
            if ($r.exit -ne 0 -or $r.stderr) { Write-Host ("  [{0}] run {1}: exit={2} stderr={3}" -f $v, $i, $r.exit, $r.stderr) }
        }
        $row = [pscustomobject]@{ variant = $v; n = $N; p50_ms = (Get-Percentile $times 50); p95_ms = (Get-Percentile $times 95); min_ms = ($times | Measure-Object -Minimum).Minimum; max_ms = ($times | Measure-Object -Maximum).Maximum }
        $rows += $row
        Write-Step $Tag ("{0,-11} p50={1}ms p95={2}ms min={3} max={4}  (합격 기준 p95 <= 100ms)" -f $v, $row.p50_ms, $row.p95_ms, $row.min_ms, $row.max_ms)
    }
    $out = Join-Path $script:LogDir 's5-bench.json'
    Write-JsonAtomic $out ([pscustomobject]@{ ts = [DateTime]::UtcNow.ToString('o'); note = '훅 명령을 PowerShell 에서 직접 실행한 벽시계 시간(프로세스 생성 포함). Claude Code 내부 오버헤드는 포함하지 않는다.'; rows = $rows })
    Write-Touched 'WRITE' $out
  }
  'auth' {
    $exe = Get-ClaudeExe
    if ($null -eq $exe) { throw 'claude 를 찾지 못했다.' }
    $warm = @(); $cold = @()
    Write-Step $Tag ("웜: `claude auth status` 를 연속 {0}회" -f $N)
    for ($i = 0; $i -lt $N; $i++) { $r = Invoke-Timed $exe @('auth','status') ''; $warm += [double]$r.ms; Write-Host ("  warm[{0}] {1} ms exit={2}" -f $i, $r.ms, $r.exit) }
    Write-Step $Tag ("콜드: {0}회, 실행 사이 {1}초 대기(프로세스 캐시가 식도록)" -f $N, $ColdGapSeconds)
    for ($i = 0; $i -lt $N; $i++) { Start-Sleep -Seconds $ColdGapSeconds; $r = Invoke-Timed $exe @('auth','status') ''; $cold += [double]$r.ms; Write-Host ("  cold[{0}] {1} ms exit={2}" -f $i, $r.ms, $r.exit) }
    $res = [pscustomobject]@{ ts = [DateTime]::UtcNow.ToString('o'); n = $N; coldGapSeconds = $ColdGapSeconds
        warm = [pscustomobject]@{ p50 = (Get-Percentile $warm 50); p95 = (Get-Percentile $warm 95); values = $warm }
        cold = [pscustomobject]@{ p50 = (Get-Percentile $cold 50); p95 = (Get-Percentile $cold 95); values = $cold }
        sampleOutput = (Invoke-Timed $exe @('auth','status') '').stdout }
    $out = Join-Path $script:LogDir 's5-auth-latency.json'
    Write-JsonAtomic $out $res; Write-Touched 'WRITE' $out
    Write-Step $Tag ("warm p50={0} p95={1} / cold p50={2} p95={3} ms  (p95 > 1000ms 이면 rev 5 에서 실행 간 캐시 검토)" -f $res.warm.p50, $res.warm.p95, $res.cold.p50, $res.cold.p95)
  }
  'policy' {
    $probe = Join-Path $script:LogDir 's5-policy-probe.ps1'
    Write-TextFileAtomic $probe "Write-Output ('probe-ran ' + (Get-ExecutionPolicy))" -Bom
    Write-Touched 'WRITE' $probe
    $list = Get-ExecutionPolicy -List | ForEach-Object { [pscustomobject]@{ scope = [string]$_.Scope; policy = [string]$_.ExecutionPolicy } }
    Write-Step $Tag '현재 실행 정책(변경하지 않음):'
    $list | ForEach-Object { Write-Host ("  {0,-14} {1}" -f $_.scope, $_.policy) }
    $cases = @()
    foreach ($pol in @('Restricted','AllSigned','RemoteSigned','Bypass')) {
        $r = Invoke-Timed 'powershell.exe' @('-NoProfile','-ExecutionPolicy',$pol,'-File',$probe) ''
        $ok = ($r.stdout -like 'probe-ran*')
        $cases += [pscustomobject]@{ childPolicy = $pol; scriptRan = $ok; stdout = $r.stdout; stderr = ($r.stderr -split "`n" | Select-Object -First 1) }
        Write-Host ("  -ExecutionPolicy {0,-12} -File 스크립트 실행됨={1}  {2}" -f $pol, $ok, $(if (-not $ok) { '(' + (($r.stderr -split "`n")[0]) + ')' } else { '' }))
    }
    # exec 형식 훅(exec-ps)이 쓰는 -ExecutionPolicy Bypass 는 사용자 정책과 무관하게 동작해야 한다.
    $hookRun = Invoke-Timed 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',$script:HookPs1,'-Event','Stop','-Variant','policy-probe','-LogDir',$script:LogDir) $samplePayload
    $res = [pscustomobject]@{ ts = [DateTime]::UtcNow.ToString('o'); current = $list; childProcessCases = $cases
        hookExecFormUnderBypass = [pscustomobject]@{ exit = $hookRun.exit; stderr = $hookRun.stderr }
        note = 'Restricted 는 프로필($PROFILE)과 .ps1 실행을 모두 막는다. 계획 4.5절: Restricted/AllSigned 면 동의 후 CurrentUser 를 RemoteSigned 로 바꾼다. 여기서는 사용자 정책을 바꾸지 않고 자식 프로세스 -ExecutionPolicy 로 재현했다.' }
    $out = Join-Path $script:LogDir 's5-policy.json'
    Write-JsonAtomic $out $res; Write-Touched 'WRITE' $out
    Write-Step $Tag ("exec 형식 훅(-ExecutionPolicy Bypass) exit={0}. 합격 조건: Restricted 에서 스크립트 차단 재현 + RemoteSigned 에서 실행 + Bypass 훅 exit 0" -f $hookRun.exit)
  }
  'analyze' {
    $log = @(Read-Jsonl $script:HooksLog)
    Write-Host ("훅 로그 {0}건" -f $log.Count)
    Write-Host ''
    Write-Host '=== (a) interactive 훅에 CCE_PANE_KEY·WT_SESSION 이 보이는가 (cce-stub 으로 띄운 세션) ==='
    $reg = @(Read-Jsonl $script:RegistryLog | Where-Object { $_.state -eq 'active' })
    $stubSids = @($reg | ForEach-Object { $_.uuid } | Select-Object -Unique)
    $fromStub = @($log | Where-Object { $stubSids -contains $_.session_id })
    $seen = @($fromStub | Where-Object { $_.CCE_PANE_KEY -ne '' -and $_.WT_SESSION -ne '' })
    Write-Host ("  stub 세션 {0}개, 그 훅 로그 {1}건, 둘 다 보인 건 {2}건 → {3}" -f $stubSids.Count, $fromStub.Count, $seen.Count, $(if ($fromStub.Count -gt 0 -and $seen.Count -eq $fromStub.Count) { '합격' } elseif ($fromStub.Count -eq 0) { '자료 없음' } else { '불합격(session_id 역조회 대체 경로 검토)' }))
    foreach ($ev in $events) {
        $n = @($fromStub | Where-Object { $_.event -eq $ev }).Count
        Write-Host ("    {0,-17} {1}건" -f $ev, $n)
    }
    Write-Host ''
    Write-Host '=== (b) 형식별 실행 여부 (공백·한글 경로 포함) ==='
    $log | Group-Object variant | Sort-Object Name | ForEach-Object {
        $evs = ($_.Group | Group-Object event | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ' '
        $shells = ($_.Group | Select-Object -ExpandProperty shell -Unique) -join '/'
        Write-Host ("  {0,-18} shell={1,-10} {2}" -f $_.Name, $shells, $evs)
    }
    $expected = @('exec-bash','shell-bash-path','shell-ps-path','exec-ps')
    $missing = @($expected | Where-Object { $v = $_; @($log | Where-Object { $_.variant -eq $v }).Count -eq 0 })
    Write-Host ("  기대 형식 4종 중 실행 기록 없음: {0} → {1}" -f $(if ($missing.Count -eq 0) { '없음' } else { $missing -join ', ' }), $(if ($missing.Count -eq 0) { '합격' } else { '불합격' }))
    Write-Host ''
    Write-Host '=== (c) 훅 시간 ==='
    $log | Group-Object variant | Sort-Object Name | ForEach-Object {
        $d = @($_.Group | ForEach-Object { [double]$_.dur_ms })
        Write-Host ("  {0,-18} 스크립트 자체 시간 p50={1}ms p95={2}ms (n={3})" -f $_.Name, (Get-Percentile $d 50), (Get-Percentile $d 95), $d.Count)
    }
    $benchPath = Join-Path $script:LogDir 's5-bench.json'
    if (Test-Path -LiteralPath $benchPath) {
        $b = Read-Json $benchPath
        foreach ($r in $b.rows) { Write-Host ("  [bench] {0,-11} 프로세스 포함 벽시계 p50={1}ms p95={2}ms → {3}" -f $r.variant, $r.p50_ms, $r.p95_ms, $(if ($r.p95_ms -le 100) { '합격' } else { '불합격(>100ms)' })) }
    } else { Write-Host '  -Step bench 미실행.' }
    $authPath = Join-Path $script:LogDir 's5-auth-latency.json'
    if (Test-Path -LiteralPath $authPath) {
        $a = Read-Json $authPath
        Write-Host ("  [auth status] warm p50={0} p95={1} / cold p50={2} p95={3} ms  (p95 > 1000ms → 캐시 검토)" -f $a.warm.p50, $a.warm.p95, $a.cold.p50, $a.cold.p95)
    } else { Write-Host '  -Step auth 미실행.' }
    Write-Host ''
    Write-Host '=== (d) 실행 정책 ==='
    $polPath = Join-Path $script:LogDir 's5-policy.json'
    if (Test-Path -LiteralPath $polPath) {
        $p = Read-Json $polPath
        foreach ($c in $p.childProcessCases) { Write-Host ("  {0,-12} scriptRan={1}" -f $c.childPolicy, $c.scriptRan) }
        $restricted = ($p.childProcessCases | Where-Object { $_.childPolicy -eq 'Restricted' }).scriptRan
        $remote = ($p.childProcessCases | Where-Object { $_.childPolicy -eq 'RemoteSigned' }).scriptRan
        Write-Host ("  판정: Restricted 차단 재현={0}, RemoteSigned 실행={1}, Bypass 훅 exit={2} → {3}" -f (-not $restricted), $remote, $p.hookExecFormUnderBypass.exit, $(if ((-not $restricted) -and $remote -and $p.hookExecFormUnderBypass.exit -eq 0) { '합격' } else { '불합격' }))
    } else { Write-Host '  -Step policy 미실행.' }
    Write-Host ''
    Write-Host '=== (e) VS Code 터미널: 레지스트리(상태 파일) 변경 0 ==='
    $vs = @($log | Where-Object { $_.TERM_PROGRAM -eq 'vscode' })
    $vsWrote = @($vs | Where-Object { $_.skipped -ne $true -or $_.status_written -ne '' -or $_.title_emitted -ne '' })
    Write-Host ("  vscode 훅 로그 {0}건, 그중 상태·제목을 쓴 건 {1}건 → {2}" -f $vs.Count, $vsWrote.Count, $(if ($vs.Count -eq 0) { '자료 없음' } elseif ($vsWrote.Count -eq 0) { '합격' } else { '불합격' }))
    if ($vs.Count -gt 0) { Write-Host ("  vscode 항목의 WT_SESSION 비어 있음={0}, CCE_PANE_KEY 비어 있음={1}" -f (@($vs | Where-Object { $_.WT_SESSION -eq '' }).Count -eq $vs.Count), (@($vs | Where-Object { $_.CCE_PANE_KEY -eq '' }).Count -eq $vs.Count)) }
  }
  'cleanup' { Remove-SpikeHooks -Tag $Tag }
}
