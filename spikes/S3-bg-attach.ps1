<#
.SYNOPSIS
  S3 bg-attach 스파이크 (계획 plan-ralplan.md §5 Step 0, S3-1 … S3-9). Windows PowerShell 5.1.

.DESCRIPTION
  하위 확인마다 -Step 을 주고, -Phase 로 prepare / collect / analyze / record 를 나눠 실행한다.
  사람이 하는 조작(attach, 창 닫기, 알림 클릭)은 prepare 와 collect 사이에 한다. Read-Host 는 쓰지 않는다.
  절차와 합격 기준은 docs/spikes/runbook-c.md 를 따른다.

  건드리는 위치: 이 저장소의 spikes/_log, spikes/_evidence 와 스크래치 C:\cce-spike\ 뿐이다.
  예외 1: S3-8 prepare 는 HKCU\Software\Classes\cce-spike (프로토콜 처리기)를 등록한다. cleanup 이 지운다.
  예외 2: cleanup 은 이 스크립트가 만든 bg 세션을 claude stop / claude rm 한다.
  사용자 ~/.claude/settings.json, WT settings, 셸 프로필은 읽기만 한다.

.EXAMPLE
  .\S3-bg-attach.ps1 -Step setup
  .\S3-bg-attach.ps1 -Step S3-2 -Phase prepare
  .\S3-bg-attach.ps1 -Step S3-2 -Phase collect
  .\S3-bg-attach.ps1 -Step S3-4 -Phase analyze
  .\S3-bg-attach.ps1 -Step cleanup
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('setup', 'status', 'S3-1', 'S3-2', 'S3-3', 'S3-4', 'S3-5', 'S3-6', 'S3-7', 'S3-8', 'S3-9', 'cleanup')]
    [string]$Step,

    [ValidateSet('prepare', 'collect', 'analyze', 'record')]
    [string]$Phase = 'prepare',

    # bg 짧은 id(8자) 또는 세션 UUID. 생략하면 상태 파일(spikes/_log/s3-state.json)에서 찾는다.
    [string]$Id = '',
    [string]$SessionId = '',

    # S3-3
    [ValidateSet('none', 'worktree')][string]$Isolation = 'none',

    # S3-4 / S3-5 반복 번호
    [int]$Run = 0,

    # S3-6 대기 유지 관찰 시간(분)
    [int]$Minutes = 5,

    # S3-8 토스트 활성화 방식
    [ValidateSet('protocol', 'foreground')][string]$Variant = 'protocol',

    # setup: 훅 형식(exec = args 배열, shell = bash 한 줄)
    [ValidateSet('exec', 'shell')][string]$HookForm = 'exec',

    # record: 수동 관찰 결과
    [ValidateSet('pass', 'fail', 'record')][string]$Result = 'record',
    [string]$Note = '',

    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common\c-lib.ps1')
$P = Get-CPaths
$Utf8 = Get-CUtf8NoBom
$PsExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

# ---------------------------------------------------------------------------
# 공용 도우미
# ---------------------------------------------------------------------------
function Get-StepKey { param([string]$S) return ($S -replace '-', '_') }

function Get-StepSession {
    # -SessionId / -Id 인자 → 상태 파일의 해당 단계 → S3-2 → S3-1 순서로 세션을 정한다.
    param([string]$StepName)
    $s = Get-CState
    if ($SessionId) { return @{ sessionId = $SessionId; id = (Get-CShortId $SessionId) } }
    if ($Id) {
        if ($Id.Length -ge 36) { return @{ sessionId = $Id; id = (Get-CShortId $Id) } }
        $a = Get-ClaudeAgents -All | Where-Object { $_.PSObject.Properties['id'] -and $_.id -eq $Id } | Select-Object -First 1
        if ($a) { return @{ sessionId = $a.sessionId; id = $Id } }
        return @{ sessionId = ''; id = $Id }
    }
    foreach ($k in @((Get-StepKey $StepName), 'S3_2', 'S3_1')) {
        if ($s.ContainsKey($k) -and $s[$k] -and $s[$k].PSObject.Properties['sessionId'] -and $s[$k].sessionId) {
            return @{ sessionId = $s[$k].sessionId; id = $s[$k].id }
        }
    }
    throw "세션을 정할 수 없다. -Id <short> 또는 -SessionId <uuid> 를 주거나 S3-1/S3-2 prepare 를 먼저 실행한다."
}

function Save-StepInfo {
    param([string]$StepName, [hashtable]$Info)
    $s = Get-CState
    $key = Get-StepKey $StepName
    $cur = @{}
    if ($s.ContainsKey($key) -and $s[$key]) { foreach ($pp in $s[$key].PSObject.Properties) { $cur[$pp.Name] = $pp.Value } }
    foreach ($k in $Info.Keys) { $cur[$k] = $Info[$k] }
    $s[$key] = [pscustomobject]$cur
    Set-CState -State $s
}

function Get-StepInfo {
    param([string]$StepName)
    $s = Get-CState
    $key = Get-StepKey $StepName
    if ($s.ContainsKey($key)) { return $s[$key] }
    return $null
}

function Invoke-ClaudeText {
    # claude <args> 를 실행하고 출력 문자열과 종료 코드를 돌려준다(2>&1 포함).
    param([string[]]$CliArgs, [string]$Cwd = $P.Scratch)
    $exe = Get-ClaudeExe
    Push-Location $Cwd
    try {
        $lines = & $exe @CliArgs 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
    } finally { Pop-Location }
    return [pscustomobject]@{ Output = ($lines -join "`n"); Exit = $code }
}

function New-HookEntry {
    param([string]$Event)
    $logger = Join-Path $P.Scratch '_hook-logger.ps1'
    if ($HookForm -eq 'exec') {
        return @{
            type    = 'command'
            command = $PsExe
            args    = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $logger, '-Event', $Event, '-Tag', '_cce_spike', '-Log', $P.NotifyLog, '-TitleFile', $P.TitleFile)
            timeout = 20
        }
    }
    $q = { param($s) return "'" + ($s -replace '\\', '/') + "'" }
    $cmd = "{0} -NoProfile -ExecutionPolicy Bypass -File {1} -Event {2} -Tag _cce_spike -Log {3} -TitleFile {4}" -f (& $q $PsExe), (& $q $logger), $Event, (& $q $P.NotifyLog), (& $q $P.TitleFile)
    return @{ type = 'command'; command = $cmd; timeout = 20 }
}

function Write-ProjectSpikeSettings {
    # C:\cce-spike\c\.claude\settings.json — 이 파일 전체가 스파이크 소유다. 최상위 "_cce_spike": true 표식(스키마가 최상위 추가 키를 허용함).
    $hooks = [ordered]@{}
    foreach ($ev in 'SessionStart', 'UserPromptSubmit', 'Notification', 'PermissionRequest', 'Stop', 'SessionEnd') {
        $hooks[$ev] = @(@{ hooks = @((New-HookEntry $ev)) })
    }
    $settings = [ordered]@{ '_cce_spike' = $true; hooks = $hooks }
    $dir = Join-Path $P.Scratch '.claude'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    $path = Join-Path $dir 'settings.json'
    [System.IO.File]::WriteAllText($path, ($settings | ConvertTo-Json -Depth 8), $Utf8)
    return $path
}

function Get-NotifyRecords {
    param([string]$ForSessionId = '', [string]$Event = '')
    $all = Read-CLog -Path $P.NotifyLog
    $out = @()
    foreach ($r in $all) {
        if ($Event -and (-not $r.PSObject.Properties['event'] -or $r.event -ne $Event)) { continue }
        if ($ForSessionId) {
            if (-not $r.PSObject.Properties['payload'] -or $null -eq $r.payload) { continue }
            if (-not $r.payload.PSObject.Properties['session_id'] -or $r.payload.session_id -ne $ForSessionId) { continue }
        }
        $out += $r
    }
    return ,$out
}

function Show-AgentRow {
    param($Agent, [string]$Prefix = '  ')
    if (-not $Agent) { Write-Host ($Prefix + '(agents --json 에 없음)'); return }
    $f = Select-CAgentFields $Agent
    Write-Host ($Prefix + (($f | ConvertTo-Json -Compress)))
}

# ---------------------------------------------------------------------------
# setup / status / cleanup
# ---------------------------------------------------------------------------
function Step-Setup {
    Show-BannerStep 'setup — 스크래치 프로젝트, 임시 훅, --settings 파일 준비'
    foreach ($d in $P.ScratchRoot, $P.Scratch, $P.Tmp, $P.LogDir, $P.EvidenceDir) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force $d | Out-Null }
    }
    # git 저장소(bgIsolation 관찰용)
    if (-not (Test-Path (Join-Path $P.Scratch '.git'))) {
        Push-Location $P.Scratch
        try {
            git init -q
            git config user.email 'cce-spike@example.invalid'
            git config user.name 'cce-spike'
            [System.IO.File]::WriteAllText((Join-Path $P.Scratch 'README.md'), "cce spike scratch (C path)`n", $Utf8)
            git add README.md
            git commit -q -m 'init'
        } finally { Pop-Location }
        Write-Host "  git init: $($P.Scratch)"
    } else { Write-Host "  git 저장소 있음: $($P.Scratch)" }

    # 자산 복사
    foreach ($f in '_hook-logger.ps1', '_attach-wrapper.ps1', '_protocol-handler.ps1') {
        Copy-Item (Join-Path $P.Assets $f) (Join-Path $P.Scratch $f) -Force
    }
    Write-Host '  자산 복사: _hook-logger.ps1, _attach-wrapper.ps1, _protocol-handler.ps1'

    # 프로젝트 훅(스파이크 표식) — worktree 에도 실리도록 커밋한다
    $sp = Write-ProjectSpikeSettings
    Push-Location $P.Scratch
    try {
        git add -f .claude/settings.json
        git commit -q -m 'spike hooks' 2>$null
    } finally { Pop-Location }
    Write-Host "  훅 설정: $sp (형식: $HookForm)"

    # --settings 파일 (계획 4.1 §3: 인라인 JSON 이 아니라 파일 경로)
    [System.IO.File]::WriteAllText($P.SettingsNone, '{"worktree":{"bgIsolation":"none"}}', $Utf8)
    [System.IO.File]::WriteAllText($P.SettingsWorktree, '{"worktree":{"bgIsolation":"worktree"}}', $Utf8)
    Write-Host "  --settings 파일: $($P.SettingsNone), $($P.SettingsWorktree)"

    # 제목 파일이 남아 있으면 S3 결과가 흔들리므로 지운다
    if (Test-Path $P.TitleFile) { Remove-Item $P.TitleFile -Force }

    $h = Get-CFileHash256 $P.UserSettings
    Save-StepInfo 'setup' @{ userSettingsHash = $h; hookForm = $HookForm; at = (Get-Date).ToUniversalTime().ToString('o'); claudeVersion = ((Invoke-ClaudeText @('--version')).Output.Trim()) }
    Write-CLog -Path $P.S3Log -Record @{ kind = 'setup'; hookForm = $HookForm; userSettingsHash = $h }

    Write-Host ''
    Write-Host '다음(수동): WT 새 탭에서'
    Write-Host "  cd $($P.Scratch); claude"
    Write-Host '  → 신뢰(trust) 대화상자를 승인하고, /hooks 로 _cce_spike 훅 6종이 보이는지 확인한 뒤 /exit'
    Write-Host '그다음:  .\S3-bg-attach.ps1 -Step setup -Phase collect   (SessionStart 기록이 남았는지 확인)'
}

function Step-SetupCollect {
    $recs = Get-NotifyRecords -Event 'SessionStart'
    $mine = @($recs | Where-Object { $_.payload -and $_.payload.PSObject.Properties['cwd'] -and ($_.payload.cwd -replace '/', '\').TrimEnd('\').ToLower() -eq $P.Scratch.ToLower() })
    Write-Host ("  SessionStart 기록(스크래치 cwd): {0}건" -f $mine.Count)
    if ($mine.Count -gt 0) {
        $last = $mine[-1]
        Write-Host ("  마지막: source={0} session_id={1} WT_SESSION={2}" -f (Get-CProp $last.payload 'source'), (Get-CProp $last.payload 'session_id'), (Get-CProp (Get-CProp $last 'env') 'WT_SESSION'))
        Write-CVerdict -Step 'setup' -Result 'pass' -Evidence "SessionStart 훅 기록 $($mine.Count)건" -Note "hookForm=$HookForm"
    } else {
        Write-Host '  훅이 기록되지 않았다. 신뢰 대화상자를 승인했는지, /hooks 에 항목이 보이는지 확인. 안 보이면 -HookForm shell 로 setup 재실행.'
        Write-CVerdict -Step 'setup' -Result 'fail' -Evidence 'SessionStart 기록 없음' -Note "hookForm=$HookForm"
    }
}

function Step-Status {
    Show-BannerStep 'status'
    $s = Get-CState
    Write-Host ($s | ConvertTo-Json -Depth 6)
    Write-Host ''
    Write-Host '현재 agents --json --all (스크래치 cwd 만):'
    foreach ($a in (Get-ClaudeAgents -All)) {
        if ($a.PSObject.Properties['cwd'] -and $a.cwd -like ($P.Scratch + '*')) { Show-AgentRow $a }
    }
}

function Step-Cleanup {
    Show-BannerStep 'cleanup — 스파이크가 만든 bg 세션 stop/rm, 프로토콜 키 제거'
    $s = Get-CState
    if ($s.ContainsKey('sessions') -and $s['sessions']) {
        foreach ($sess in @($s['sessions'])) {
            if (-not $sess.id) { continue }
            Write-Host ("  claude stop {0}" -f $sess.id)
            try { Invoke-ClaudeText @('stop', $sess.id) | Out-Null } catch { }
            Write-Host ("  claude rm {0}" -f $sess.id)
            try { $r = Invoke-ClaudeText @('rm', $sess.id); Write-Host ('    ' + $r.Output) } catch { Write-Host "    실패: $_" }
        }
    }
    $key = 'HKCU:\Software\Classes\cce-spike'
    if (Test-Path $key) { Remove-Item $key -Recurse -Force; Write-Host "  제거: $key" }
    foreach ($f in $P.TitleFile, $P.ProtocolAttachFlag) { if (Test-Path $f) { Remove-Item $f -Force } }
    if ($Force) {
        if (Test-Path $P.ScratchRoot) { Remove-Item $P.ScratchRoot -Recurse -Force; Write-Host "  삭제: $($P.ScratchRoot)" }
    } else {
        Write-Host "  스크래치 $($P.ScratchRoot) 는 남겨 둔다(-Force 로 삭제)."
    }
    Write-Host "  로그(spikes/_log)는 증거이므로 지우지 않는다."
}

function Show-BannerStep { param([string]$T) Show-CBanner ("[S3] " + $T) }

# ---------------------------------------------------------------------------
# S3-1  claude --bg (프롬프트 없이) → attach
# ---------------------------------------------------------------------------
function Step-S31 {
    switch ($Phase) {
        'prepare' {
            Show-BannerStep 'S3-1 prepare — claude --bg (프롬프트 없음, --settings none)'
            $r = Start-CBgSession -ClaudeArgs @('--settings', $P.SettingsNone) -Cwd $P.Scratch -Log $P.S3Log -Step 'S3-1'
            Write-Host ("  exit={0}`n  출력: {1}" -f $r.Exit, $r.Output)
            $a = Resolve-CBgSession -Cwd $P.Scratch -SinceEpochMs $r.LaunchedAt -TimeoutSec 60
            Show-AgentRow $a
            $sid = ''; $short = $r.ShortId
            if ($a) { $sid = $a.sessionId; $short = $a.id }
            Save-StepInfo 'S3-1' @{ id = $short; sessionId = $sid; launchExit = $r.Exit; launchOutput = $r.Output; launchedAt = $r.LaunchedAt }
            if ($short) { Add-CSpikeSession -Step 'S3-1' -ShortId $short -SessionId $sid }
            Write-Host ''
            Write-Host "다음(수동): WT 새 탭에서  cd $($P.Scratch); claude attach $short"
            Write-Host '  → fullscreen 으로 붙는지, 프롬프트가 보이는지 확인. /exit 로 detach 한 뒤 세션이 agents 에 남는지 본다.'
            Write-Host "그다음:  .\S3-bg-attach.ps1 -Step S3-1 -Phase collect"
        }
        'collect' {
            Show-BannerStep 'S3-1 collect — agents --json 필드 기록'
            $info = Get-StepSession 'S3-1'
            $a = $null
            if ($info.sessionId) { $a = Find-CAgent -SessionId $info.sessionId -All } else { $a = Get-ClaudeAgents -All | Where-Object { $_.id -eq $info.id } | Select-Object -First 1 }
            Show-AgentRow $a
            $roster = $null; $job = $null
            if ($info.id) { $roster = Get-CRosterWorker $info.id; $job = Get-CJobState $info.id }
            Write-Host ('  roster(내부): ' + ($roster | ConvertTo-Json -Compress))
            Write-Host ('  job state(내부): ' + ($job | ConvertTo-Json -Compress))
            Write-CLog -Path $P.S3Log -Record @{ kind = 'collect'; step = 'S3-1'; agent = (Select-CAgentFields $a); roster = $roster; job = $job }
            Write-Host "다음:  .\S3-bg-attach.ps1 -Step S3-1 -Phase record -Result pass|fail -Note '<attach 관찰>'"
        }
        'record' {
            Write-CLog -Path $P.S3Log -Record @{ kind = 'manual'; step = 'S3-1'; result = $Result; note = $Note }
            Write-Host "  기록됨."
        }
        'analyze' {
            Show-BannerStep 'S3-1 analyze'
            $info = Get-StepInfo 'S3-1'
            $manual = @(Read-CLog $P.S3Log | Where-Object { $_.kind -eq 'manual' -and $_.step -eq 'S3-1' })
            $launchOk = ($info -and $info.launchExit -eq 0 -and $info.sessionId)
            $manualOk = ($manual.Count -gt 0 -and $manual[-1].result -eq 'pass')
            Write-Host ("  실행 성공={0}, agents 등록={1}, 수동 attach 판정={2}" -f ($info.launchExit -eq 0), [bool]$info.sessionId, ($(if ($manual.Count -gt 0) { $manual[-1].result } else { '없음' })))
            if ($launchOk -and $manualOk) { Write-CVerdict -Step 'S3-1' -Result 'pass' -Evidence "id=$($info.id) sessionId=$($info.sessionId)" -Note $manual[-1].note }
            elseif (-not $launchOk) { Write-CVerdict -Step 'S3-1' -Result 'fail' -Evidence "launchExit=$($info.launchExit) output=$($info.launchOutput)" }
            else { Write-CVerdict -Step 'S3-1' -Result 'pending' -Evidence '수동 record 필요' }
        }
    }
}

# ---------------------------------------------------------------------------
# S3-2  --session-id + --bg
# ---------------------------------------------------------------------------
function Step-S32 {
    switch ($Phase) {
        'prepare' {
            Show-BannerStep 'S3-2 prepare — claude --bg --session-id <uuid>'
            $uuid = [guid]::NewGuid().ToString()
            $r = Start-CBgSession -ClaudeArgs @('--session-id', $uuid, '--settings', $P.SettingsNone) -Cwd $P.Scratch -Log $P.S3Log -Step 'S3-2'
            Write-Host ("  요청 uuid={0}`n  exit={1}`n  출력: {2}" -f $uuid, $r.Exit, $r.Output)
            Save-StepInfo 'S3-2' @{ requested = $uuid; launchExit = $r.Exit; launchOutput = $r.Output; launchedAt = $r.LaunchedAt; printedId = $r.ShortId }
            Write-Host "다음:  .\S3-bg-attach.ps1 -Step S3-2 -Phase collect   (몇 초 뒤)"
        }
        'collect' {
            Show-BannerStep 'S3-2 collect'
            $info = Get-StepInfo 'S3-2'
            $a = Resolve-CBgSession -SessionId $info.requested -Cwd $P.Scratch -SinceEpochMs $info.launchedAt -TimeoutSec 60
            Show-AgentRow $a
            $same = ($a -and $a.sessionId -eq $info.requested)
            $shortMatch = ($a -and $a.id -eq (Get-CShortId $info.requested))
            if ($a) { Save-StepInfo 'S3-2' @{ id = $a.id; sessionId = $a.sessionId; sameId = $same; shortIsPrefix = $shortMatch }; Add-CSpikeSession -Step 'S3-2' -ShortId $a.id -SessionId $a.sessionId }
            Write-CLog -Path $P.S3Log -Record @{ kind = 'collect'; step = 'S3-2'; requested = $info.requested; agent = (Select-CAgentFields $a); sameId = $same; shortIsPrefix = $shortMatch }
            Write-Host ("  sessionId 일치={0}, 짧은 id 가 uuid 앞 8자={1}" -f $same, $shortMatch)
            Write-Host "다음:  .\S3-bg-attach.ps1 -Step S3-2 -Phase analyze"
        }
        'analyze' {
            Show-BannerStep 'S3-2 analyze'
            $info = Get-StepInfo 'S3-2'
            if ($info -and $info.PSObject.Properties['sameId'] -and $info.sameId) {
                Write-CVerdict -Step 'S3-2' -Result 'pass' -Evidence "requested=$($info.requested) agents.sessionId 동일, id=$($info.id)" -Note '계획 4.1 §3: --session-id 사전 할당 경로 사용 가능'
            } elseif ($info -and $info.launchExit -ne 0) {
                Write-CVerdict -Step 'S3-2' -Result 'fail' -Evidence "launchExit=$($info.launchExit) output=$($info.launchOutput)" -Note '대체: 실행 직전 시각 이후 startedAt + cwd 로 agents --json 탐색(계획 4.1 §3)'
            } else {
                Write-CVerdict -Step 'S3-2' -Result 'fail' -Evidence ("agents.sessionId=" + $(if ($info.PSObject.Properties['sessionId']) { $info.sessionId } else { '(없음)' })) -Note '대체: startedAt + cwd 탐색'
            }
        }
        'record' { Write-CLog -Path $P.S3Log -Record @{ kind = 'manual'; step = 'S3-2'; result = $Result; note = $Note } }
    }
}

# ---------------------------------------------------------------------------
# S3-3  --settings 의 bgIsolation (none / worktree)
# ---------------------------------------------------------------------------
function Step-S33 {
    $stepKey = "S3-3-$Isolation"
    $probe = "probe-$Isolation.txt"
    $settingsFile = $(if ($Isolation -eq 'none') { $P.SettingsNone } else { $P.SettingsWorktree })
    switch ($Phase) {
        'prepare' {
            Show-BannerStep "S3-3 prepare — bgIsolation=$Isolation ( --settings $settingsFile )"
            $orig = Join-Path $P.Scratch $probe
            if (Test-Path $orig) { Remove-Item $orig -Force }
            $wtDir = Join-Path $P.Scratch '.claude\worktrees'
            if (Test-Path $wtDir) { Get-ChildItem $wtDir -Recurse -Filter $probe -ErrorAction SilentlyContinue | Remove-Item -Force }
            $hashBefore = Get-CFileHash256 $P.UserSettings
            $projHashBefore = Get-CFileHash256 (Join-Path $P.Scratch '.claude\settings.json')
            $uuid = [guid]::NewGuid().ToString()
            $prompt = "현재 작업 폴더에 $probe 파일을 만들고 내용으로 'hello $Isolation' 한 줄만 써라. 다른 파일은 만들거나 고치지 마라. 끝나면 '완료'라고만 답해라."
            $r = Start-CBgSession -ClaudeArgs @('--session-id', $uuid, '--settings', $settingsFile, '--permission-mode', 'acceptEdits', $prompt) -Cwd $P.Scratch -Log $P.S3Log -Step $stepKey
            Write-Host ("  exit={0}`n  출력: {1}" -f $r.Exit, $r.Output)
            $a = Resolve-CBgSession -SessionId $uuid -Cwd $P.Scratch -SinceEpochMs $r.LaunchedAt -TimeoutSec 60
            Show-AgentRow $a
            $short = $(if ($a) { $a.id } else { $r.ShortId })
            $sid = $(if ($a) { $a.sessionId } else { $uuid })
            Save-StepInfo $stepKey @{ id = $short; sessionId = $sid; launchExit = $r.Exit; launchOutput = $r.Output; launchedAt = $r.LaunchedAt; userSettingsHashBefore = $hashBefore; projectSettingsHashBefore = $projHashBefore; settingsFile = $settingsFile }
            if ($short) { Add-CSpikeSession -Step $stepKey -ShortId $short -SessionId $sid }
            Write-Host "다음:  .\S3-bg-attach.ps1 -Step S3-3 -Isolation $Isolation -Phase collect   (done 까지 최대 4분 폴링)"
            Write-Host "  blocked 로 멈추면(신뢰 대화상자·권한): claude attach $short 로 처리한 뒤 collect 재실행"
        }
        'collect' {
            Show-BannerStep "S3-3 collect — bgIsolation=$Isolation"
            $info = Get-StepInfo $stepKey
            $a = Wait-CAgentState -SessionId $info.sessionId -States @('done', 'failed', 'stopped', 'blocked') -TimeoutSec 240 -IntervalSec 5 -Log $P.S3Log -Step $stepKey
            Show-AgentRow $a
            $orig = Join-Path $P.Scratch $probe
            $origExists = Test-Path $orig
            $wtHits = @()
            $wtDir = Join-Path $P.Scratch '.claude\worktrees'
            if (Test-Path $wtDir) { $wtHits = @(Get-ChildItem $wtDir -Recurse -Filter $probe -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) }
            Push-Location $P.Scratch
            try { $wtList = (git worktree list --porcelain 2>&1 | Out-String) } finally { Pop-Location }
            $hashAfter = Get-CFileHash256 $P.UserSettings
            $projHashAfter = Get-CFileHash256 (Join-Path $P.Scratch '.claude\settings.json')
            $roster = Get-CRosterWorker $info.id
            $job = Get-CJobState $info.id
            $rec = @{ kind = 'collect'; step = $stepKey; agent = (Select-CAgentFields $a); originalExists = $origExists; worktreeHits = $wtHits; gitWorktreeList = $wtList; userSettingsUnchanged = ($hashAfter -eq $info.userSettingsHashBefore); projectSettingsUnchanged = ($projHashAfter -eq $info.projectSettingsHashBefore); rosterIsolation = $(if ($roster) { $roster.isolation } else { $null }); jobBgIsolation = $(if ($job) { $job.bgIsolation } else { $null }) }
            Write-CLog -Path $P.S3Log -Record $rec
            Write-Host ("  원래 폴더 {0}: {1}" -f $probe, $origExists)
            Write-Host ("  worktree 아래: {0}" -f ($(if ($wtHits.Count) { $wtHits -join '; ' } else { '(없음)' })))
            Write-Host ("  ~/.claude/settings.json 변경 없음={0}, 프로젝트 settings 변경 없음={1}" -f $rec.userSettingsUnchanged, $rec.projectSettingsUnchanged)
            Write-Host ("  내부 기록 isolation: roster={0}, job={1}" -f $rec.rosterIsolation, $rec.jobBgIsolation)
            Save-StepInfo $stepKey @{ originalExists = $origExists; worktreeHits = $wtHits; finalState = $(if ($a) { $a.state } else { '' }); userSettingsUnchanged = $rec.userSettingsUnchanged }
            if ($a -and $a.state -eq 'blocked') { Write-Host "  → blocked. claude attach $($info.id) 로 대화상자를 처리하고 collect 를 다시 실행." }
            Write-Host "다음:  .\S3-bg-attach.ps1 -Step S3-3 -Isolation $Isolation -Phase analyze"
        }
        'analyze' {
            Show-BannerStep "S3-3 analyze — bgIsolation=$Isolation"
            $info = Get-StepInfo $stepKey
            if (-not $info -or -not $info.PSObject.Properties['finalState']) { Write-CVerdict -Step $stepKey -Result 'pending' -Evidence 'collect 미실행'; return }
            $hits = @(); if ($info.PSObject.Properties['worktreeHits'] -and $info.worktreeHits) { $hits = @($info.worktreeHits) }
            $ok = $false
            if ($Isolation -eq 'none') { $ok = ($info.originalExists -and $hits.Count -eq 0 -and $info.userSettingsUnchanged) }
            else { $ok = ((-not $info.originalExists) -and $hits.Count -gt 0 -and $info.userSettingsUnchanged) }
            $ev = "state=$($info.finalState) original=$($info.originalExists) worktreeHits=$($hits.Count) userSettingsUnchanged=$($info.userSettingsUnchanged)"
            if ($ok) { Write-CVerdict -Step $stepKey -Result 'pass' -Evidence $ev }
            else { Write-CVerdict -Step $stepKey -Result 'fail' -Evidence $ev -Note '대체: 프로젝트 .claude/settings.json 에 worktree.bgIsolation 을 쓰는 방식(전역 아님)을 검토' }
        }
        'record' { Write-CLog -Path $P.S3Log -Record @{ kind = 'manual'; step = $stepKey; result = $Result; note = $Note } }
    }
}

# ---------------------------------------------------------------------------
# S3-4  attach 자식 pid 추적, X 닫기 vs /exit detach 구분, 20회 반복
# ---------------------------------------------------------------------------
function Step-S34 {
    switch ($Phase) {
        'prepare' {
            Show-BannerStep 'S3-4 prepare — 래퍼 안내'
            $info = Get-StepSession 'S3-4'
            Save-StepInfo 'S3-4' @{ id = $info.id; sessionId = $info.sessionId }
            Copy-Item (Join-Path $P.Assets '_attach-wrapper.ps1') (Join-Path $P.Scratch '_attach-wrapper.ps1') -Force
            $w = Join-Path $P.Scratch '_attach-wrapper.ps1'
            Write-Host "  대상 세션: id=$($info.id) sessionId=$($info.sessionId)"
            Write-Host "  로그: $($P.AttachLog)"
            Write-Host ''
            Write-Host '각 회차마다 WT 새 탭에서 아래 한 줄을 실행한다(run 번호와 expected 를 바꿔 가며 20회):'
            Write-Host ("  powershell -NoProfile -ExecutionPolicy Bypass -File `"{0}`" -Id {1} -Log `"{2}`" -FlagDir `"{3}`" -Run <N> -Expected <detach|close|exit-then-close>" -f $w, $info.id, $P.AttachLog, $P.Scratch)
            Write-Host '  권장 배분: 1~7 detach (/exit 또는 ←), 8~14 close (붙은 상태에서 탭 X), 15~20 exit-then-close (/exit 직후 곧바로 X)'
            Write-Host "그다음:  .\S3-bg-attach.ps1 -Step S3-4 -Phase collect"
        }
        'collect' {
            Show-BannerStep 'S3-4 collect — 회차별 기록'
            $rows = Get-S34Rows
            foreach ($r in $rows) { Write-Host ('  ' + ($r | ConvertTo-Json -Compress)) }
            Write-Host ("  회차 수: {0}" -f $rows.Count)
            Write-Host "다음:  .\S3-bg-attach.ps1 -Step S3-4 -Phase analyze"
        }
        'analyze' {
            Show-BannerStep 'S3-4 analyze — 오분류 집계'
            $rows = Get-S34Rows
            $mis = 0; $missing = 0; $noHandler = 0
            foreach ($r in $rows) {
                if ($r.handlerInstalled -eq $false) { $noHandler++ }
                if ($r.classification -eq 'missing') { $missing++ }
                elseif ($r.classification -eq 'misclassified') { $mis++ }
            }
            $ev = "runs=$($rows.Count) misclassified=$mis missing=$missing handlerNotInstalled=$noHandler"
            Write-Host "  $ev"
            if ($noHandler -gt 0 -or ($missing -gt 0 -and $rows.Count -gt 0)) {
                Write-CVerdict -Step 'S3-4' -Result 'record' -Evidence $ev -Note 'PS 5.1 처리기가 CTRL_CLOSE 를 받지 못했다 → Step 1 프로토타입(Rust SetConsoleCtrlHandler) 필요. 자식 pid/시작 시각 추적 자체는 기록됨.'
            } elseif ($rows.Count -ge 20 -and $mis -eq 0) {
                Write-CVerdict -Step 'S3-4' -Result 'pass' -Evidence $ev
            } elseif ($rows.Count -lt 20) {
                Write-CVerdict -Step 'S3-4' -Result 'pending' -Evidence $ev -Note '20회 미만'
            } else {
                Write-CVerdict -Step 'S3-4' -Result 'fail' -Evidence $ev -Note '대체: 트레이가 attach 자식 pid 소멸 + 창 존재 여부로 판단'
            }
        }
        'record' { Write-CLog -Path $P.S3Log -Record @{ kind = 'manual'; step = 'S3-4'; result = $Result; note = $Note } }
    }
}

function Get-S34Rows {
    $recs = Read-CLog $P.AttachLog
    $byRun = @{}
    foreach ($r in $recs) {
        if (-not $r.PSObject.Properties['run']) { continue }
        $k = [int]$r.run
        if (-not $byRun.ContainsKey($k)) { $byRun[$k] = @{ run = $k; expected = ''; handlerInstalled = $null; childPid = $null; childStart = $null; ctrl = $false; endOutcome = '' } }
        $e = $byRun[$k]
        switch ($r.kind) {
            'start' { $e.expected = $r.expected; $e.handlerInstalled = $r.handlerInstalled }
            'child' { $e.childPid = $r.childPid; $e.childStart = $r.childStart }
            'ctrl'  { $e.ctrl = $true }
            'end'   { $e.endOutcome = $r.outcome }
        }
    }
    $rows = @()
    foreach ($k in ($byRun.Keys | Sort-Object)) {
        $e = $byRun[$k]
        $cls = ''
        $hasDetach = ($e.endOutcome -eq 'detached')
        $hasClose = ($e.ctrl -or $e.endOutcome -eq 'windowClosed')
        if (-not $hasDetach -and -not $hasClose) { $cls = 'missing' }
        elseif ($hasDetach -and $hasClose) { $cls = 'misclassified' }
        else {
            switch ($e.expected) {
                'detach' { $cls = $(if ($hasDetach) { 'ok' } else { 'misclassified' }) }
                'close' { $cls = $(if ($hasClose) { 'ok' } else { 'misclassified' }) }
                'exit-then-close' { $cls = 'ok' }   # 어느 한쪽이면 정상(4.1 §6: 300ms 안이면 windowClosed, 밖이면 detached)
                default { $cls = 'unknown-expected' }
            }
        }
        $rows += [pscustomobject]@{ run = $k; expected = $e.expected; handlerInstalled = $e.handlerInstalled; childPid = $e.childPid; childStart = $e.childStart; ctrlFired = $e.ctrl; endOutcome = $e.endOutcome; classification = $cls }
    }
    return ,$rows
}

# ---------------------------------------------------------------------------
# S3-5  응답 중 창 닫기 → 턴·파일 수정 완료, jsonl 완전 (10회)
# ---------------------------------------------------------------------------
function Step-S35 {
    $stepKey = "S3-5-r$Run"
    switch ($Phase) {
        'prepare' {
            if ($Run -lt 1) { throw '-Run <1..10> 이 필요하다.' }
            Show-BannerStep "S3-5 prepare — run $Run"
            $out = Join-Path $P.Scratch 'out.txt'
            if (Test-Path $out) { Remove-Item $out -Force }
            $uuid = [guid]::NewGuid().ToString()
            $prompt = "현재 작업 폴더에 out.txt 를 만들어라. 내용은 1부터 200까지 정수를 한 줄에 하나씩(마지막 줄 200, 빈 줄 없음). Write 도구로 직접 써라(셸 명령 금지). 파일을 쓴 뒤 그 200줄을 응답 본문에도 그대로 다시 출력하고, 맨 끝에 '완료'라고 써라."
            $r = Start-CBgSession -ClaudeArgs @('--session-id', $uuid, '--settings', $P.SettingsNone, '--permission-mode', 'acceptEdits', $prompt) -Cwd $P.Scratch -Log $P.S3Log -Step $stepKey
            Write-Host ("  exit={0}`n  출력: {1}" -f $r.Exit, $r.Output)
            $short = $(if ($r.ShortId) { $r.ShortId } else { Get-CShortId $uuid })
            Save-StepInfo $stepKey @{ id = $short; sessionId = $uuid; launchExit = $r.Exit; launchedAt = $r.LaunchedAt }
            Add-CSpikeSession -Step $stepKey -ShortId $short -SessionId $uuid
            Write-Host ''
            Write-Host "지금 바로(수동): WT 새 탭에서  cd $($P.Scratch); claude attach $short"
            Write-Host '  → 응답이 흘러나오는 동안 탭의 X 로 닫는다(창 전체를 닫아도 된다).'
            Write-Host "그다음:  .\S3-bg-attach.ps1 -Step S3-5 -Run $Run -Phase collect"
        }
        'collect' {
            if ($Run -lt 1) { throw '-Run 이 필요하다.' }
            Show-BannerStep "S3-5 collect — run $Run"
            $info = Get-StepInfo $stepKey
            $a = Wait-CAgentState -SessionId $info.sessionId -States @('done', 'failed', 'stopped') -TimeoutSec 240 -IntervalSec 5 -Log $P.S3Log -Step $stepKey
            Show-AgentRow $a
            $out = Join-Path $P.Scratch 'out.txt'
            $lines = -1
            if (Test-Path $out) { $lines = @([System.IO.File]::ReadAllLines($out) | Where-Object { $_.Trim().Length -gt 0 }).Count }
            $tp = Get-CTranscriptPath -Cwd $P.Scratch -SessionId $info.sessionId
            $ts = $null
            if ($tp) { $ts = Get-CTranscriptSummary $tp }
            $state = $(if ($a) { $a.state } else { '' })
            $pass = ($state -eq 'done' -and $lines -eq 200 -and $ts -and $ts.assistantMsgs -gt 0 -and $ts.unparsableLines -eq 0)
            Write-CLog -Path $P.S3Log -Record @{ kind = 'collect'; step = $stepKey; run = $Run; agent = (Select-CAgentFields $a); outLines = $lines; transcript = $ts; pass = $pass }
            Save-StepInfo $stepKey @{ finalState = $state; outLines = $lines; transcript = $ts; pass = $pass }
            Write-Host ("  state={0} out.txt 줄 수={1} transcript: {2}" -f $state, $lines, ($ts | ConvertTo-Json -Compress))
            Write-Host ("  run {0}: {1}" -f $Run, $(if ($pass) { '합격' } else { '불합격' }))
        }
        'analyze' {
            Show-BannerStep 'S3-5 analyze — 10회 집계'
            $s = Get-CState
            $runs = @($s.Keys | Where-Object { $_ -like 'S3_5_r*' } | Sort-Object { [int]($_ -replace 'S3_5_r', '') })
            $ok = 0; $n = 0
            foreach ($k in $runs) {
                $v = $s[$k]
                if (-not $v.PSObject.Properties['pass']) { continue }
                $n++
                if ($v.pass) { $ok++ }
                Write-Host ("  {0}: state={1} lines={2} pass={3}" -f $k, $v.finalState, $v.outLines, $v.pass)
            }
            $ev = "$ok/$n"
            if ($n -ge 10 -and $ok -eq $n) { Write-CVerdict -Step 'S3-5' -Result 'pass' -Evidence $ev }
            elseif ($n -lt 10) { Write-CVerdict -Step 'S3-5' -Result 'pending' -Evidence $ev -Note '10회 미만' }
            else { Write-CVerdict -Step 'S3-5' -Result 'fail' -Evidence $ev -Note 'C 제공 불가 → A 만 출시(계획 §5 S3 불합격 시 대체)' }
        }
        'record' { Write-CLog -Path $P.S3Log -Record @{ kind = 'manual'; step = $stepKey; result = $Result; note = $Note } }
    }
}

# ---------------------------------------------------------------------------
# S3-6  blocked(권한 대기) 턴에서 창을 닫은 뒤 대기 유지   (+ S3-9 의 데이터 원천)
# ---------------------------------------------------------------------------
function Step-S36 {
    switch ($Phase) {
        'prepare' {
            Show-BannerStep 'S3-6 prepare — 권한 요청으로 blocked 되는 bg 세션 (CCE_PANE_KEY 상속 관찰 포함)'
            $uuid = [guid]::NewGuid().ToString()
            $paneKey = $env:WT_SESSION
            if (-not $paneKey) { $paneKey = 'no-wt-session' }
            $env:CCE_PANE_KEY = $paneKey
            $env:CCE_SPIKE_MARK = 's3-6'
            $prompt = "Bash 도구로 'git log --oneline -3' 을 실행하고 결과를 한 줄로 요약해라. 권한을 물으면 승인될 때까지 기다려라."
            $r = Start-CBgSession -ClaudeArgs @('--session-id', $uuid, '--settings', $P.SettingsNone, '--permission-mode', 'manual', $prompt) -Cwd $P.Scratch -Log $P.S3Log -Step 'S3-6'
            Write-Host ("  exit={0}`n  출력: {1}" -f $r.Exit, $r.Output)
            $a = Resolve-CBgSession -SessionId $uuid -Cwd $P.Scratch -SinceEpochMs $r.LaunchedAt -TimeoutSec 60
            Show-AgentRow $a
            $short = $(if ($a) { $a.id } else { Get-CShortId $uuid })
            Save-StepInfo 'S3-6' @{ id = $short; sessionId = $uuid; launchExit = $r.Exit; launchedAt = $r.LaunchedAt; paneKey = $paneKey }
            Add-CSpikeSession -Step 'S3-6' -ShortId $short -SessionId $uuid
            Write-Host ''
            Write-Host "수동: WT 새 탭에서  cd $($P.Scratch); claude attach $short  → 권한 프롬프트가 뜬 것을 확인하고, 승인하지 말고 탭 X 로 닫는다."
            Write-Host "  닫은 직후:  .\S3-bg-attach.ps1 -Step S3-6 -Phase record -Result record -Note closed"
            Write-Host "그다음:  .\S3-bg-attach.ps1 -Step S3-6 -Phase collect -Minutes 5   (15초 간격 폴링)"
        }
        'record' {
            $rec = @{ kind = 'manual'; step = 'S3-6'; result = $Result; note = $Note }
            Write-CLog -Path $P.S3Log -Record $rec
            if ($Note -eq 'closed') { Save-StepInfo 'S3-6' @{ closedAt = (Get-Date).ToUniversalTime().ToString('o') } }
            Write-Host '  기록됨.'
        }
        'collect' {
            Show-BannerStep "S3-6 collect — $Minutes 분 동안 15초 간격으로 상태 관찰"
            $info = Get-StepInfo 'S3-6'
            $deadline = (Get-Date).AddMinutes($Minutes)
            $series = @()
            while ((Get-Date) -lt $deadline) {
                $a = Find-CAgent -SessionId $info.sessionId -All
                $roster = Get-CRosterWorker $info.id
                $st = $(if ($a) { $a.state } else { '(없음)' })
                $series += [pscustomobject]@{ t = (Get-Date).ToUniversalTime().ToString('o'); state = $st; rosterPid = $(if ($roster) { $roster.pid } else { $null }) }
                Write-Host ("  {0} state={1} rosterPid={2}" -f (Get-Date).ToString('HH:mm:ss'), $st, $(if ($roster) { $roster.pid } else { '-' }))
                Start-Sleep -Seconds 15
            }
            $states = @($series | ForEach-Object { $_.state } | Select-Object -Unique)
            $notes = @(Get-NotifyRecords -ForSessionId $info.sessionId -Event 'Notification')
            Write-CLog -Path $P.S3Log -Record @{ kind = 'collect'; step = 'S3-6'; series = $series; distinctStates = $states; notificationHookCount = $notes.Count }
            Save-StepInfo 'S3-6' @{ distinctStates = $states; samples = $series.Count; notificationHookCount = $notes.Count }
            Write-Host ("  관찰된 상태: {0} / Notification 훅 기록 {1}건(S3-9 에서 분석)" -f ($states -join ','), $notes.Count)
            Write-Host "이제(수동): claude attach $($info.id) 로 다시 붙어 권한 프롬프트가 그대로 있는지 보고 승인 → done 확인."
            Write-Host "  .\S3-bg-attach.ps1 -Step S3-6 -Phase record -Result pass|fail -Note '<재접속 관찰>'"
            Write-Host "그다음:  .\S3-bg-attach.ps1 -Step S3-6 -Phase analyze"
        }
        'analyze' {
            Show-BannerStep 'S3-6 analyze'
            $info = Get-StepInfo 'S3-6'
            $manual = @(Read-CLog $P.S3Log | Where-Object { $_.kind -eq 'manual' -and $_.step -eq 'S3-6' -and $_.result -ne 'record' })
            $states = @(); if ($info.PSObject.Properties['distinctStates']) { $states = @($info.distinctStates) }
            $stayed = ($states.Count -eq 1 -and $states[0] -eq 'blocked')
            $manualOk = ($manual.Count -gt 0 -and $manual[-1].result -eq 'pass')
            $ev = "states=$($states -join ',') samples=$($info.samples) reattach=$(if ($manual.Count) { $manual[-1].result } else { '없음' })"
            if ($stayed -and $manualOk) { Write-CVerdict -Step 'S3-6' -Result 'pass' -Evidence $ev }
            elseif (-not $manual.Count) { Write-CVerdict -Step 'S3-6' -Result 'pending' -Evidence $ev -Note '재접속 record 필요' }
            else { Write-CVerdict -Step 'S3-6' -Result 'fail' -Evidence $ev -Note 'C 제공 불가 → A 만 출시' }
        }
    }
}

# ---------------------------------------------------------------------------
# S3-7  respawn 과 --resume --bg 의 ID 유지
# ---------------------------------------------------------------------------
function Step-S37 {
    switch ($Phase) {
        'prepare' {
            Show-BannerStep 'S3-7 prepare — stop → respawn → stop → --bg --resume → (실행 중) --bg --resume'
            $info = Get-StepSession 'S3-7'
            $sid = $info.sessionId; $short = $info.id
            if (-not $sid) { throw '세션 UUID 가 필요하다(-SessionId).' }
            $log = @()

            Write-Host "  1) claude stop $short"
            $r1 = Invoke-ClaudeText @('stop', $short)
            $log += @{ op = 'stop'; output = $r1.Output; exit = $r1.Exit }
            $a1 = Wait-CAgentState -SessionId $sid -States @('stopped', 'done', 'failed') -TimeoutSec 60 -IntervalSec 3 -Log $P.S3Log -Step 'S3-7'
            Show-AgentRow $a1

            Write-Host "  2) claude respawn $short"
            $r2 = Invoke-ClaudeText @('respawn', $short)
            $log += @{ op = 'respawn'; output = $r2.Output; exit = $r2.Exit }
            Start-Sleep -Seconds 5
            $a2 = Find-CAgent -SessionId $sid -All
            Show-AgentRow $a2
            $respawnSame = ($a2 -ne $null -and $a2.sessionId -eq $sid)
            # --settings 는 --resume/respawn 에 복원되지 않는다(문서). respawn 뒤 bgIsolation 이 기본값(worktree)으로 돌아가는지 내부 기록으로 본다.
            $jobAfterRespawn = Get-CJobState $short
            $isoAfterRespawn = $(if ($jobAfterRespawn) { Get-CProp $jobAfterRespawn 'bgIsolation' } else { $null })
            Write-Host ("  respawn 뒤 job.bgIsolation={0}" -f $isoAfterRespawn)
            $afterRespawnNew = @(Get-ClaudeAgents -All | Where-Object { $_.PSObject.Properties['cwd'] -and $_.cwd -like ($P.Scratch + '*') -and $_.PSObject.Properties['startedAt'] -and [long]$_.startedAt -gt ((Get-CEpochMs) - 30000) } | ForEach-Object { Select-CAgentFields $_ })

            Write-Host "  3) claude stop $short  →  claude --bg --resume $sid"
            $r3 = Invoke-ClaudeText @('stop', $short)
            $log += @{ op = 'stop2'; output = $r3.Output; exit = $r3.Exit }
            Wait-CAgentState -SessionId $sid -States @('stopped', 'done', 'failed') -TimeoutSec 60 -IntervalSec 3 -Log $P.S3Log -Step 'S3-7' | Out-Null
            $r4 = Start-CBgSession -ClaudeArgs @('--resume', $sid, '--settings', $P.SettingsNone) -Cwd $P.Scratch -Log $P.S3Log -Step 'S3-7'
            $log += @{ op = 'bg-resume-stopped'; output = $r4.Output; exit = $r4.Exit; printedId = $r4.ShortId }
            Start-Sleep -Seconds 5
            $a4 = Find-CAgent -SessionId $sid -All
            Show-AgentRow $a4
            $resumeSame = ($a4 -ne $null -and $a4.sessionId -eq $sid -and $a4.state -ne 'stopped')
            if ($r4.ShortId -and $r4.ShortId -ne $short) { Add-CSpikeSession -Step 'S3-7' -ShortId $r4.ShortId -SessionId '' }

            Write-Host "  4) (실행 중) claude --bg --resume $sid  → 복사본이 생기는지"
            $r5 = Start-CBgSession -ClaudeArgs @('--resume', $sid, '--settings', $P.SettingsNone) -Cwd $P.Scratch -Log $P.S3Log -Step 'S3-7'
            $log += @{ op = 'bg-resume-running'; output = $r5.Output; exit = $r5.Exit; printedId = $r5.ShortId }
            Start-Sleep -Seconds 5
            $copies = @(Get-ClaudeAgents -All | Where-Object { $_.PSObject.Properties['cwd'] -and $_.cwd -like ($P.Scratch + '*') -and $_.PSObject.Properties['startedAt'] -and [long]$_.startedAt -gt ($r5.LaunchedAt - 5000) } | ForEach-Object { Select-CAgentFields $_ })
            foreach ($c in $copies) { if ($c.id -and $c.id -ne $short) { Add-CSpikeSession -Step 'S3-7-copy' -ShortId $c.id -SessionId $c.sessionId } }

            $rec = @{ kind = 'collect'; step = 'S3-7'; sessionId = $sid; ops = $log; respawnSameId = $respawnSame; resumeBgSameId = $resumeSame; copiesAfterRunningResume = $copies; agentsAfterRespawn = $afterRespawnNew; bgIsolationAfterRespawn = $isoAfterRespawn }
            Write-CLog -Path $P.S3Log -Record $rec
            Save-StepInfo 'S3-7' @{ id = $short; sessionId = $sid; respawnSameId = $respawnSame; resumeBgSameId = $resumeSame; copies = $copies; ops = $log; bgIsolationAfterRespawn = $isoAfterRespawn }
            Write-Host ("  respawn 후 같은 sessionId={0}, stopped 에서 --bg --resume 후 같은 sessionId={1}, 실행 중 --bg --resume 복사본={2}" -f $respawnSame, $resumeSame, $copies.Count)
            Write-Host "다음:  .\S3-bg-attach.ps1 -Step S3-7 -Phase analyze"
        }
        'collect' { Write-Host '  S3-7 은 prepare 에서 수집까지 끝난다. analyze 를 실행한다.' }
        'analyze' {
            Show-BannerStep 'S3-7 analyze'
            $info = Get-StepInfo 'S3-7'
            if (-not $info) { Write-CVerdict -Step 'S3-7' -Result 'pending' -Evidence 'prepare 미실행'; return }
            $ev = "respawnSameId=$($info.respawnSameId) resumeBgSameId=$($info.resumeBgSameId) copies=$(@($info.copies).Count) bgIsolationAfterRespawn=$(Get-CProp $info 'bgIsolationAfterRespawn' '(내부 기록 없음)')"
            $note = $(if ($info.respawnSameId -and $info.resumeBgSameId) { 'ID 유지 → sessionLineage 는 단일 항목으로 충분' } else { 'ID 변경 → sessionLineage 에 새 ID 추가(계획 4.3 §3)' })
            if ((Get-CProp $info 'bgIsolationAfterRespawn') -eq 'worktree') { $note += '. respawn 뒤 bgIsolation 이 worktree 로 되돌아감 → 복원 경로(4.3 §3)는 respawn 대신 stop 후 --bg --resume --settings 를 검토' }
            Write-CVerdict -Step 'S3-7' -Result 'record' -Evidence $ev -Note $note
        }
        'record' { Write-CLog -Path $P.S3Log -Record @{ kind = 'manual'; step = 'S3-7'; result = $Result; note = $Note } }
    }
}

# ---------------------------------------------------------------------------
# S3-8  Windows 토스트 클릭 활성화 — OS 수준 사전 점검(프로토콜 활성화). Tauri 본시험은 runbook.
# ---------------------------------------------------------------------------
function Step-S38 {
    $key = 'HKCU:\Software\Classes\cce-spike'
    switch ($Phase) {
        'prepare' {
            Show-BannerStep 'S3-8 prepare — cce-spike:// 프로토콜 처리기 등록(HKCU, cleanup 이 제거)'
            Copy-Item (Join-Path $P.Assets '_protocol-handler.ps1') (Join-Path $P.Scratch '_protocol-handler.ps1') -Force
            $handler = Join-Path $P.Scratch '_protocol-handler.ps1'
            $cmd = ('"{0}" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}" -Uri "%1" -Log "{2}"' -f $PsExe, $handler, $P.ProtocolLog)
            New-Item -Path $key -Force | Out-Null
            Set-ItemProperty -Path $key -Name '(default)' -Value 'URL:cce spike protocol'
            Set-ItemProperty -Path $key -Name 'URL Protocol' -Value ''
            New-Item -Path (Join-Path $key 'shell\open\command') -Force | Out-Null
            Set-ItemProperty -Path (Join-Path $key 'shell\open\command') -Name '(default)' -Value $cmd
            if (Test-Path $P.ProtocolAttachFlag) { Remove-Item $P.ProtocolAttachFlag -Force }
            Write-CLog -Path $P.S3Log -Record @{ kind = 'prepare'; step = 'S3-8'; registry = $key; command = $cmd }
            Write-Host "  등록: $key → $cmd"
            Write-Host "다음:  .\S3-bg-attach.ps1 -Step S3-8 -Phase collect [-Id <short>]         (1단계: 클릭 → 처리기 기록만)"
            Write-Host "       .\S3-bg-attach.ps1 -Step S3-8 -Phase collect -Id <short> -Force   (2단계: 클릭 → wt -w 0 new-tab … claude attach)"
            Write-Host "       .\S3-bg-attach.ps1 -Step S3-8 -Phase collect -Variant foreground  (참고: foreground 활성화는 COM 활성화기 없이는 무반응 예상)"
        }
        'collect' {
            Show-BannerStep "S3-8 collect — 토스트 발송 (variant=$Variant, stage2=$($Force.IsPresent))"
            $short = $Id
            if (-not $short) { try { $short = (Get-StepSession 'S3-8').id } catch { $short = 'deadbeef' } }
            if ($Force) { [System.IO.File]::WriteAllText($P.ProtocolAttachFlag, 'on', $Utf8) } elseif (Test-Path $P.ProtocolAttachFlag) { Remove-Item $P.ProtocolAttachFlag -Force }
            $launch = "cce-spike://attach/$short"
            if ($Variant -eq 'protocol') {
                $xml = @"
<toast activationType="protocol" launch="$launch">
  <visual><binding template="ToastGeneric">
    <text>cce spike S3-8</text>
    <text>claude_env [개인] · 권한 요청을 기다립니다 — 본문을 클릭</text>
  </binding></visual>
  <actions>
    <action content="세션에 붙기" activationType="protocol" arguments="$launch/button" />
  </actions>
</toast>
"@
            } else {
                $xml = @"
<toast activationType="foreground" launch="$launch">
  <visual><binding template="ToastGeneric">
    <text>cce spike S3-8 (foreground)</text>
    <text>클릭해도 COM 활성화기가 없으면 아무 일도 없어야 한다</text>
  </binding></visual>
</toast>
"@
            }
            [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
            [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
            $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
            $doc.LoadXml($xml)
            $toast = New-Object Windows.UI.Notifications.ToastNotification $doc
            $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
            [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
            $sentAt = (Get-Date).ToUniversalTime().ToString('o')
            Write-CLog -Path $P.S3Log -Record @{ kind = 'toast'; step = 'S3-8'; variant = $Variant; stage2 = $Force.IsPresent; launch = $launch; sentAt = $sentAt; appId = $appId }
            Save-StepInfo 'S3-8' @{ lastToastAt = $sentAt; lastVariant = $Variant; lastStage2 = $Force.IsPresent; id = $short }
            Write-Host "  토스트 발송됨($sentAt). 알림을 클릭한다(본문 또는 '세션에 붙기' 버튼). 알림 센터에 들어간 뒤 클릭해도 된다."
            Write-Host "그다음:  .\S3-bg-attach.ps1 -Step S3-8 -Phase analyze"
        }
        'analyze' {
            Show-BannerStep 'S3-8 analyze — 프로토콜 활성화 기록'
            $info = Get-StepInfo 'S3-8'
            $recs = @(Read-CLog $P.ProtocolLog)
            $after = @()
            if ($info -and $info.PSObject.Properties['lastToastAt']) { $after = @($recs | Where-Object { $_.ts -ge $info.lastToastAt }) } else { $after = $recs }
            foreach ($r in $after) { Write-Host ('  ' + ($r | ConvertTo-Json -Compress)) }
            $ev = "activations=$($after.Count) variant=$($info.lastVariant) stage2=$($info.lastStage2)"
            if ($after.Count -gt 0) {
                $s2 = @($after | Where-Object { $_.stage2 }).Count
                Write-CVerdict -Step 'S3-8-pre' -Result 'record' -Evidence $ev -Note "OS 수준 클릭 활성화(프로토콜) 동작. 2단계(wt new-tab attach) 실행=$s2. Tauri 플러그인 본시험은 runbook §S3-8 참조"
            } else {
                Write-CVerdict -Step 'S3-8-pre' -Result 'record' -Evidence $ev -Note '활성화 기록 없음(아직 클릭 안 했거나 프로토콜 미동작). 클릭 후 analyze 재실행'
            }
        }
        'record' { Write-CLog -Path $P.S3Log -Record @{ kind = 'manual'; step = 'S3-8'; result = $Result; note = $Note } }
    }
}

# ---------------------------------------------------------------------------
# S3-9  붙어 있지 않은 bg 세션에서 Notification 훅이 발생하는가 + pane 역조회 가능성
# ---------------------------------------------------------------------------
function Step-S39 {
    switch ($Phase) {
        'prepare' {
            Show-BannerStep 'S3-9 prepare'
            Write-Host '  S3-9 는 S3-6 세션의 훅 로그를 쓴다. S3-6 prepare/record(closed)/collect 를 먼저 끝낸다.'
            Write-Host "  로그: $($P.NotifyLog)"
        }
        'collect' {
            Show-BannerStep 'S3-9 collect — Notification 훅 기록'
            $info = Get-StepInfo 'S3-6'
            if (-not $info) { throw 'S3-6 정보가 없다.' }
            $all = @(Get-NotifyRecords -ForSessionId $info.sessionId)
            $notes = @($all | Where-Object { $_.event -eq 'Notification' })
            $perm = @($all | Where-Object { $_.event -eq 'PermissionRequest' })
            $closedAt = $(if ($info.PSObject.Properties['closedAt']) { $info.closedAt } else { '' })
            Write-Host ("  세션 {0}: 훅 기록 전체 {1}건, Notification {2}건, PermissionRequest {3}건, 창 닫은 시각={4}" -f $info.sessionId, $all.Count, $notes.Count, $perm.Count, $closedAt)
            foreach ($n in $notes) {
                $unattached = $(if ($closedAt -and $n.ts -gt $closedAt) { $true } else { $false })
                $anc = @(); if ($n.PSObject.Properties['ancestry']) { $anc = @($n.ancestry | ForEach-Object { Get-CProp $_ 'name' }) }
                $envRec = Get-CProp $n 'env'
                Write-Host ("  {0} type={1} unattached={2} CCE_PANE_KEY={3} WT_SESSION={4} ancestry={5}" -f $n.ts, (Get-CProp $n.payload 'notification_type'), $unattached, (Get-CProp $envRec 'CCE_PANE_KEY'), (Get-CProp $envRec 'WT_SESSION'), ($anc -join '>'))
            }
            $unattachedNotes = @($notes | Where-Object { $closedAt -and $_.ts -gt $closedAt })
            $paneKeySeen = @($notes | Where-Object { Get-CProp (Get-CProp $_ 'env') 'CCE_PANE_KEY' }).Count
            Save-StepInfo 'S3-9' @{ notificationCount = $notes.Count; unattachedCount = $unattachedNotes.Count; paneKeySeen = $paneKeySeen; permissionRequestCount = $perm.Count; sessionIdInPayload = (@($notes | Where-Object { Get-CProp $_.payload 'session_id' }).Count) }
            Write-CLog -Path $P.S3Log -Record @{ kind = 'collect'; step = 'S3-9'; notificationCount = $notes.Count; unattachedCount = $unattachedNotes.Count; paneKeySeen = $paneKeySeen; closedAt = $closedAt }
            Write-Host "다음:  .\S3-bg-attach.ps1 -Step S3-9 -Phase analyze"
        }
        'analyze' {
            Show-BannerStep 'S3-9 analyze'
            $i = Get-StepInfo 'S3-9'
            if (-not $i) { Write-CVerdict -Step 'S3-9' -Result 'pending' -Evidence 'collect 미실행'; return }
            $ev = "Notification=$($i.notificationCount) unattached=$($i.unattachedCount) CCE_PANE_KEY보임=$($i.paneKeySeen) session_id있음=$($i.sessionIdInPayload) PermissionRequest=$($i.permissionRequestCount)"
            if ($i.unattachedCount -gt 0) {
                $lookup = $(if ($i.paneKeySeen -gt 0) { 'CCE_PANE_KEY 상속됨 → 직접 조회' } else { 'CCE_PANE_KEY 없음 → session_id 역조회 필요(계획 4.1 훅 절)' })
                Write-CVerdict -Step 'S3-9' -Result 'pass' -Evidence $ev -Note "훅 경로를 알림의 빠른 경로로 추가 가능. pane 찾기: $lookup"
            } else {
                Write-CVerdict -Step 'S3-9' -Result 'fail' -Evidence $ev -Note '붙어 있지 않은 동안 Notification 훅 없음 → 폴링 15초만(계획 4.2)'
            }
        }
        'record' { Write-CLog -Path $P.S3Log -Record @{ kind = 'manual'; step = 'S3-9'; result = $Result; note = $Note } }
    }
}

# ---------------------------------------------------------------------------
# 진입
# ---------------------------------------------------------------------------
switch ($Step) {
    'setup'   { if ($Phase -eq 'collect') { Step-SetupCollect } else { Step-Setup } }
    'status'  { Step-Status }
    'cleanup' { Step-Cleanup }
    'S3-1'    { Step-S31 }
    'S3-2'    { Step-S32 }
    'S3-3'    { Step-S33 }
    'S3-4'    { Step-S34 }
    'S3-5'    { Step-S35 }
    'S3-6'    { Step-S36 }
    'S3-7'    { Step-S37 }
    'S3-8'    { Step-S38 }
    'S3-9'    { Step-S39 }
}
