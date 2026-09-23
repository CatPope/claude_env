<#
.SYNOPSIS
  S2 — 창 닫기 신호 스파이크 (계획 §5 Step 0, S2(a)~(e); A 방식의 AC-1·AC-2).
.DESCRIPTION
  cce 대역(common\cce-stub.ps1)이 SetConsoleCtrlHandler 로 CTRL_CLOSE_EVENT 를 받아 _log/registry.jsonl 에
  interrupted / windowClosed 를 쓰고, 자식 종료 경로는 300ms 뒤 closing 플래그를 보고 closed 를 쓴다.
  단계(-Step):
    prepare            백업 → 표식 훅(exec-bash, 5 이벤트) 설치, 제목 모드 both.
    run -Scenario X    WT pane 안에서 실행. cce-stub 으로 Claude 를 띄운다. 시나리오:
                         busy        응답(스트리밍) 중에 창을 X 로 닫는다             → 기대 interrupted (S2(a)(b)(c), 10회)
                         waiting     권한 요청에서 멈췄을 때 창을 X 로 닫는다         → 기대 interrupted + 플래그 (S2(d), 10회)
                         idle_prompt 턴이 끝나고 60초 유휴 알림이 온 뒤 창을 닫는다   → 기대 windowClosed (S2(d-2), 10회)
                         race-exit   /exit 로 자식이 끝난 직후(3초 안) 창을 닫는다      → 기대 windowClosed 가 closed 를 이김, interrupted 아님 (S2(e), 20회)
                         close-only  프롬프트 없이(또는 idle 에서) 창만 닫는다          → 기대 windowClosed (S2(e), 20회)
    resume -Scenario X 같은 시나리오의 마지막 중단 세션을 --resume 으로 다시 띄운다(복원 시 ⏸중단 표시 확인).
    collect            stub 세션들의 transcript 를 _log/s2-transcripts/ 로 복사한다.
    analyze            시나리오별로 최종 상태(우선순위 windowClosed/interrupted > closed), 처리기 쓰기 시간, SessionEnd 발생,
                       transcript 의 마지막 사용자 메시지·완료 턴, 복원 시 ⏸중단 표시를 집계해 합격 기준과 비교한다.
    cleanup            표식 훅 제거.
#>
param(
    [Parameter(Mandatory)][ValidateSet('prepare','run','resume','collect','analyze','cleanup')][string]$Step,
    [ValidateSet('busy','waiting','idle_prompt','race-exit','close-only','default')][string]$Scenario = 'default',
    [string[]]$ClaudeArgs = @()
)
. "$PSScriptRoot\common\common.ps1"
Initialize-SpikeDirs
$Tag = 'S2'
$ClaudeArgs = @($ClaudeArgs | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
$events = @('SessionStart','UserPromptSubmit','Notification','Stop','SessionEnd')
$txDir = Join-Path $script:LogDir 's2-transcripts'
$priority = @{ interrupted = 3; windowClosed = 3; closed = 1; detached = 1; active = 0 }

function Get-FinalState([object[]]$Rows) {
    $best = $null
    foreach ($r in $Rows) {
        if ($r.state -eq 'active') { continue }
        if ($null -eq $best -or $priority[$r.state] -gt $priority[$best.state]) { $best = $r }
    }
    return $best
}
function Read-TranscriptSummary([string]$Path, [string]$PromptHead) {
    $res = [ordered]@{ exists = $false; lines = 0; lastTypes = @(); lastUserFound = $false; assistantAfterUser = 0; lastAssistantStopReason = $null; lastAssistantHasText = $false }
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $res }
    $res.exists = $true
    $lastUserLine = -1; $n = 0; $types = New-Object System.Collections.ArrayList
    $head = $PromptHead
    if ($head.Length -gt 20) { $head = $head.Substring(0, 20) }
    $lastAssistant = $null
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        $n++
        $t = ''; if ($line -match '"type"\s*:\s*"([^"]+)"') { $t = $Matches[1] }
        [void]$types.Add($t)
        if ($t -eq 'user' -and $head -ne '' -and $line.Contains($head) -and $line -notmatch '"tool_result"') { $lastUserLine = $n; $res.lastUserFound = $true; $res.assistantAfterUser = 0 }
        if ($t -eq 'assistant') {
            if ($lastUserLine -gt 0) { $res.assistantAfterUser++ }
            $lastAssistant = $line
        }
    }
    $res.lines = $n
    $res.lastTypes = @($types | Select-Object -Last 6)
    if ($lastAssistant) {
        try {
            $o = $lastAssistant | ConvertFrom-Json
            $res.lastAssistantStopReason = Get-Prop $o.message 'stop_reason' $null
            $res.lastAssistantHasText = (($o.message.content | ConvertTo-Json -Compress -Depth 8) -match '"text"')
        } catch { }
    }
    return $res
}

switch ($Step) {
  'prepare' {
    & "$PSScriptRoot\common\backup.ps1" -Label 'before-S2'
    Set-TitleMode -Mode both -Base 'claude_env [개인]'
    if (@(Get-SpikeHooksInSettings).Count -eq 0) {
        $entries = @(); foreach ($ev in $events) { $entries += @{ Event = $ev; Group = (New-HookEntry -Event $ev -Form exec-bash) } }
        Install-SpikeHooks -Entries $entries -Tag $Tag
    } else { Write-Step $Tag '표식 훅이 이미 있다. 그대로 쓴다.' }
    $repo = $script:RepoRoot
    Write-Manual @(
        "각 회차는 WT 의 PowerShell pane 에서:  & '$repo\spikes\S2-close-signal.ps1' -Step run -Scenario <busy|waiting|idle_prompt|race-exit|close-only>",
        "busy(10회): '1부터 200까지 한 줄에 하나씩 쓴 out.txt 를 만들어 줘' 를 보내고, 응답이 흐르는 중에 창(또는 탭)을 X 로 닫는다.",
        "waiting(10회): 'C:\Temp\s2.txt 를 만들어 줘' 처럼 권한 요청이 뜨는 프롬프트를 보내고, 권한 대화상자가 떠 있을 때 X 로 닫는다.",
        "idle_prompt(10회): 짧은 프롬프트('1+1은?')를 보내고 응답이 끝난 뒤 60초 이상 기다려 idle 알림이 온 다음 X 로 닫는다.",
        "race-exit(20회): 프롬프트 하나를 보내고 끝난 뒤 /exit 를 치자마자(3초 안에) X 로 닫는다.",
        "close-only(20회): Claude 가 뜨면 프롬프트 없이 바로(또는 idle 에서) X 로 닫는다.",
        "복원 확인(busy·waiting·idle_prompt 각 회차 뒤): 새 pane 에서  -Step resume -Scenario <같은 시나리오>  → 탭 제목에 '⏸중단' 이 있는지 보고, 프롬프트 하나를 보내 표시가 사라지는지 본다. 그리고 /exit.",
        "모두 끝나면 -Step collect → -Step analyze → -Step cleanup."
    )
  }
  'run' {
    if ($Scenario -eq 'default') { throw '-Scenario 를 지정하라.' }
    & "$PSScriptRoot\common\cce-stub.ps1" -Scenario $Scenario -ClaudeArgs $ClaudeArgs -Tag $Tag
  }
  'resume' {
    if ($Scenario -eq 'default') { throw '-Scenario 를 지정하라.' }
    & "$PSScriptRoot\common\cce-stub.ps1" -Scenario $Scenario -Resume -ClaudeArgs $ClaudeArgs -Tag $Tag
  }
  'collect' {
    if (-not (Test-Path -LiteralPath $txDir)) { New-Item -ItemType Directory -Path $txDir | Out-Null }
    $n = 0
    foreach ($sid in (Read-Jsonl $script:RegistryLog | Where-Object { $_.state -eq 'active' } | ForEach-Object { $_.uuid } | Select-Object -Unique)) {
        $p = Find-TranscriptPath $sid
        if ($p) { Copy-Item -LiteralPath $p -Destination (Join-Path $txDir "$sid.jsonl") -Force; $n++ }
    }
    Write-Touched 'COPY' ("transcript {0}개 -> {1}" -f $n, $txDir)
  }
  'analyze' {
    $reg = @(Read-Jsonl $script:RegistryLog)
    $hooks = @(Read-Jsonl $script:HooksLog)
    $runs = @($reg | Where-Object { $_.state -eq 'active' -and $_.resume -ne $true })
    Write-Host ("레지스트리 {0}행, 실행(run) {1}회" -f $reg.Count, $runs.Count)
    $rows = @()
    foreach ($r in $runs) {
        $mine = @($reg | Where-Object { $_.runId -eq $r.runId })
        $final = Get-FinalState $mine
        $handler = @($mine | Where-Object { $_.state -eq 'interrupted' -or $_.state -eq 'windowClosed' } | Select-Object -First 1)
        $closedRow = @($mine | Where-Object { $_.state -eq 'closed' } | Select-Object -First 1)
        $closeTs = $(if ($handler.Count -gt 0) { [datetime]$handler[0].ts } elseif ($closedRow.Count -gt 0) { [datetime]$closedRow[0].ts } else { [datetime]::MaxValue })
        $sessionEnd = @($hooks | Where-Object { $_.session_id -eq $r.uuid -and $_.event -eq 'SessionEnd' })
        $lastPrompt = @($hooks | Where-Object { $_.session_id -eq $r.uuid -and $_.event -eq 'UserPromptSubmit' -and ([datetime]::Parse($_.ts).ToUniversalTime() -le $closeTs.ToUniversalTime()) } | Select-Object -Last 1)
        $promptHead = $(if ($lastPrompt.Count -gt 0) { $lastPrompt[0].prompt_head } else { '' })
        $tp = Join-Path $txDir "$($r.uuid).jsonl"
        if (-not (Test-Path -LiteralPath $tp)) { $tp = Find-TranscriptPath $r.uuid }
        $tx = Read-TranscriptSummary $tp $promptHead
        # 복원 회차: 같은 uuid 의 resume 실행 뒤 SessionStart(resume) 에서 낸 제목
        $resumeTitle = @($hooks | Where-Object { $_.session_id -eq $r.uuid -and $_.event -eq 'SessionStart' -and $_.source -eq 'resume' -and ([datetime]::Parse($_.ts).ToUniversalTime() -gt $closeTs.ToUniversalTime()) } | Select-Object -First 1)
        $afterResumePrompt = @($hooks | Where-Object { $_.session_id -eq $r.uuid -and $_.event -eq 'UserPromptSubmit' -and $resumeTitle.Count -gt 0 -and ([datetime]::Parse($_.ts).ToUniversalTime() -gt [datetime]::Parse($resumeTitle[0].ts).ToUniversalTime()) } | Select-Object -First 1)
        $rows += [pscustomobject]@{
            runId = $r.runId; scenario = $r.scenario; uuid = $r.uuid.Substring(0, 8)
            final = $(if ($final) { $final.state } else { '(없음)' })
            lastStatus = $(if ($handler.Count -gt 0) { $handler[0].lastStatus } else { '' })
            flag = $(if ($handler.Count -gt 0) { [bool]$handler[0].interruptedFlag } else { $false })
            handlerMs = $(if ($handler.Count -gt 0) { [int]$handler[0].handlerWriteMs } else { $null })
            closedAlso = ($closedRow.Count -gt 0)
            sessionEnd = ($sessionEnd.Count -gt 0)
            txUser = $tx.lastUserFound; txAsst = $tx.assistantAfterUser; txStop = $tx.lastAssistantStopReason; txLast = ($tx.lastTypes -join ',')
            resumeTitle = $(if ($resumeTitle.Count -gt 0) { $resumeTitle[0].title_emitted } else { '' })
            resumeMark = $(if ($resumeTitle.Count -gt 0) { $resumeTitle[0].title_emitted.Contains('⏸중단') } else { $null })
            clearedAfterPrompt = $(if ($afterResumePrompt.Count -gt 0) { -not $afterResumePrompt[0].title_emitted.Contains('⏸중단') } else { $null })
        }
    }
    $rows | Format-Table runId, scenario, final, lastStatus, flag, handlerMs, closedAlso, sessionEnd, txUser, txAsst, txStop, resumeMark, clearedAfterPrompt -AutoSize | Out-String -Width 220 | Write-Host
    Write-JsonAtomic (Join-Path $script:LogDir 's2-analysis.json') $rows
    Write-Touched 'WRITE' (Join-Path $script:LogDir 's2-analysis.json')

    Write-Host '=== 시나리오별 집계 (합격 기준은 계획 Step 0 표) ==='
    $closes = @($rows | Where-Object { $_.handlerMs -ne $null })
    $fast = @($closes | Where-Object { $_.handlerMs -lt 1000 })
    Write-Host ("  (a) 처리기가 1초 안에 레지스트리를 씀: {0}/{1}  (기준 20/20)" -f $fast.Count, $closes.Count)
    $txOk = @($rows | Where-Object { $_.scenario -in @('busy','waiting','idle_prompt','race-exit') -and $_.txUser })
    $txAll = @($rows | Where-Object { $_.scenario -in @('busy','waiting','idle_prompt','race-exit') })
    Write-Host ("  (b) jsonl 에 마지막 사용자 메시지 있음: {0}/{1}  (기준 20/20). 스트리밍 중 응답의 흔적은 txStop(stop_reason 비어 있으면 잘림)·txAsst 로 본다" -f $txOk.Count, $txAll.Count)
    $se = @($rows | Where-Object { $_.handlerMs -ne $null -and $_.sessionEnd })
    Write-Host ("  (c) 창 닫기 뒤 SessionEnd 훅 발생: {0}/{1}  (기록용. 1.5초 예산 안에 훅이 돌았는지)" -f $se.Count, $closes.Count)
    foreach ($sc in @('busy','waiting')) {
        $s = @($rows | Where-Object { $_.scenario -eq $sc })
        $ok = @($s | Where-Object { $_.final -eq 'interrupted' -and $_.flag })
        $mark = @($s | Where-Object { $_.resumeMark -eq $true })
        Write-Host ("  (d) {0}: interrupted+플래그 {1}/{2}, 복원 시 ⏸중단 {3}/{2}  (기준 10/10, 10/10)" -f $sc, $ok.Count, $s.Count, $mark.Count)
    }
    $s = @($rows | Where-Object { $_.scenario -eq 'idle_prompt' })
    $ok = @($s | Where-Object { $_.final -eq 'windowClosed' -and -not $_.flag })
    $mark = @($s | Where-Object { $_.resumeMark -eq $true })
    Write-Host ("  (d-2) idle_prompt: windowClosed {0}/{1}, 복원 시 ⏸중단 {2}/{1}  (기준 10/10, 0/10)" -f $ok.Count, $s.Count, $mark.Count)
    $s = @($rows | Where-Object { $_.scenario -eq 'race-exit' })
    $mis = @($s | Where-Object { $_.final -eq 'interrupted' -or ($_.handlerMs -ne $null -and $_.final -ne 'windowClosed') })
    Write-Host ("  (e) race-exit: {0}회, 오분류 {1}  (interrupted 가 나오거나 처리기가 돌았는데 windowClosed 가 아니면 오분류)" -f $s.Count, $mis.Count)
    $s2 = @($rows | Where-Object { $_.scenario -eq 'close-only' })
    $mis2 = @($s2 | Where-Object { $_.final -ne 'windowClosed' })
    Write-Host ("  (e) close-only: {0}회, 오분류 {1}  (windowClosed 가 아니면 오분류). 합계 {2}회 중 오분류 {3} (기준 40회 중 0)" -f $s2.Count, $mis2.Count, ($s.Count + $s2.Count), ($mis.Count + $mis2.Count))
  }
  'cleanup' { Remove-SpikeHooks -Tag $Tag }
}
