<#
.SYNOPSIS
  S4(b) 제목(attach) 스파이크 — attach 상태에서 훅 sessionTitle 로 정한 이름과 아이콘이 WT 탭에 보이는가. Windows PowerShell 5.1.

.DESCRIPTION
  S3-bg-attach.ps1 -Step setup 이 깔아 둔 임시 훅(_cce_spike)이 C:\cce-spike\c\_title.txt 가 있으면
  SessionStart / UserPromptSubmit 에서 그 내용을 sessionTitle 로 낸다. 이 스크립트는 그 파일을 계획 4.6 형식으로 쓰고,
  새 bg 세션을 띄운 뒤, 사람이 attach 해서 본 탭 제목을 record 로 받는다.
  형식: <별칭> [<계정>] · <부제>   (아이콘은 Claude Code 가 그린다. 부제가 없으면 `<별칭> [<계정>]`)
  합격: 아이콘을 뺀 텍스트가 정한 이름과 같다.

.EXAMPLE
  .\S4b-title-attach.ps1 -Phase prepare -Alias claude_env -Account 개인 -Subtitle '로그인 버그 수정'
  .\S4b-title-attach.ps1 -Phase record -Stage sessionstart -Observed '✳ claude_env [개인] · 로그인 버그 수정' -Screenshot S4b-1-sessionstart.png
  .\S4b-title-attach.ps1 -Phase collect
  .\S4b-title-attach.ps1 -Phase analyze
  .\S4b-title-attach.ps1 -Phase cleanup
#>
[CmdletBinding()]
param(
    [ValidateSet('prepare', 'collect', 'analyze', 'record', 'osc', 'cleanup')]
    [string]$Phase = 'prepare',

    [string]$Alias = 'claude_env',
    [string]$Account = '개인',
    [string]$Subtitle = '',

    # 기존 세션에 붙여 볼 때(새 세션을 띄우지 않음)
    [string]$Id = '',
    [string]$SessionId = '',

    # record 용
    [ValidateSet('sessionstart', 'userprompt', 'busy', 'idle', 'waiting', 'osc')]
    [string]$Stage = 'sessionstart',
    [string]$Observed = '',
    [string]$Screenshot = '',
    [ValidateSet('pass', 'fail', 'record')][string]$Result = 'record',
    [string]$Note = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common\c-lib.ps1')
$P = Get-CPaths
$Utf8 = Get-CUtf8NoBom

function Get-ExpectedTitle {
    param([string]$A, [string]$Acc, [string]$Sub)
    if ($Sub -and $Sub.Trim().Length -gt 0) { return ('{0} [{1}] · {2}' -f $A, $Acc, $Sub.Trim()) }
    return ('{0} [{1}]' -f $A, $Acc)
}

function Remove-LeadingIcon {
    # 앞쪽의 글자·숫자·'[' 가 아닌 글리프(상태 아이콘, 변형 선택자, 공백)를 걷어낸다. 코드포인트 수도 돌려준다.
    param([string]$Text)
    $m = [regex]::Match($Text, '^(?<icon>[^\p{L}\p{N}\[]+?)\s*(?<rest>[\p{L}\p{N}\[].*)$')
    if ($m.Success) {
        $icon = $m.Groups['icon'].Value.TrimEnd()
        $cps = 0
        $i = 0
        while ($i -lt $icon.Length) { if ([char]::IsSurrogatePair($icon, $i)) { $i += 2 } else { $i += 1 }; $cps++ }
        $hex = ($icon.ToCharArray() | ForEach-Object { ('{0:X4}' -f [int]$_) }) -join ' '
        return [pscustomobject]@{ icon = $icon; iconCodepoints = $cps; iconUtf16Hex = $hex; text = $m.Groups['rest'].Value.Trim() }
    }
    return [pscustomobject]@{ icon = ''; iconCodepoints = 0; iconUtf16Hex = ''; text = $Text.Trim() }
}

function Get-S4bInfo {
    $s = Get-CState
    if ($s.ContainsKey('S4b')) { return $s['S4b'] }
    return $null
}

function Save-S4bInfo {
    param([hashtable]$Info)
    $s = Get-CState
    $cur = @{}
    if ($s.ContainsKey('S4b') -and $s['S4b']) { foreach ($pp in $s['S4b'].PSObject.Properties) { $cur[$pp.Name] = $pp.Value } }
    foreach ($k in $Info.Keys) { $cur[$k] = $Info[$k] }
    $s['S4b'] = [pscustomobject]$cur
    Set-CState -State $s
}

switch ($Phase) {
    'prepare' {
        Show-CBanner '[S4b] prepare — 제목 파일 쓰기 + 새 bg 세션'
        if (-not (Test-Path (Join-Path $P.Scratch '.claude\settings.json'))) { throw 'S3-bg-attach.ps1 -Step setup 을 먼저 실행한다.' }
        $title = Get-ExpectedTitle $Alias $Account $Subtitle
        [System.IO.File]::WriteAllText($P.TitleFile, $title, $Utf8)
        Write-Host "  제목 파일: $($P.TitleFile) ← '$title'"
        $sid = $SessionId; $short = $Id
        if (-not $sid -and -not $short) {
            $sid = [guid]::NewGuid().ToString()
            $r = Start-CBgSession -ClaudeArgs @('--session-id', $sid, '--settings', $P.SettingsNone) -Cwd $P.Scratch -Log $P.S4bLog -Step 'S4b'
            Write-Host ("  exit={0}`n  출력: {1}" -f $r.Exit, $r.Output)
            $a = Resolve-CBgSession -SessionId $sid -Cwd $P.Scratch -SinceEpochMs $r.LaunchedAt -TimeoutSec 60
            if ($a) { $short = $a.id; $sid = $a.sessionId } elseif ($r.ShortId) { $short = $r.ShortId } else { $short = Get-CShortId $sid }
            Add-CSpikeSession -Step 'S4b' -ShortId $short -SessionId $sid
        } elseif ($short -and -not $sid) {
            $a = Get-ClaudeAgents -All | Where-Object { $_.id -eq $short } | Select-Object -First 1
            if ($a) { $sid = $a.sessionId }
        } elseif ($sid -and -not $short) { $short = Get-CShortId $sid }
        Save-S4bInfo @{ id = $short; sessionId = $sid; expected = $title; alias = $Alias; account = $Account; subtitle = $Subtitle; preparedAt = (Get-Date).ToUniversalTime().ToString('o') }
        Write-CLog -Path $P.S4bLog -Record @{ kind = 'prepare'; id = $short; sessionId = $sid; expected = $title }
        Write-Host ''
        Write-Host "수동 1: WT 새 탭에서  cd $($P.Scratch); claude attach $short"
        Write-Host '  → 탭 제목을 그대로 적어 두고(아이콘 포함) 스크린샷: spikes\_evidence\S4b-1-sessionstart.png'
        Write-Host "     .\S4b-title-attach.ps1 -Phase record -Stage sessionstart -Observed '<탭 제목 그대로>' -Screenshot S4b-1-sessionstart.png"
        Write-Host "수동 2: 세션에 '안녕, 한 줄로만 답해' 를 보낸다. 응답 중(busy)·응답 뒤(idle) 제목을 각각 기록: S4b-2-busy.png, S4b-3-idle.png"
        Write-Host "     .\S4b-title-attach.ps1 -Phase record -Stage busy -Observed '<...>' -Screenshot S4b-2-busy.png"
        Write-Host "     .\S4b-title-attach.ps1 -Phase record -Stage idle -Observed '<...>' -Screenshot S4b-3-idle.png"
        Write-Host "수동 3(선택): 권한이 필요한 요청(예: Bash 로 git status)을 보내 waiting 아이콘도 기록: S4b-4-waiting.png"
        Write-Host "그다음:  .\S4b-title-attach.ps1 -Phase collect;  .\S4b-title-attach.ps1 -Phase analyze"
    }
    'record' {
        $info = Get-S4bInfo
        if (-not $info) { throw 'prepare 를 먼저 실행한다.' }
        $parsed = Remove-LeadingIcon $Observed
        $match = ($parsed.text -eq $info.expected)
        # 첫 프롬프트 전 변형 접미어(계획 T-7 (1)) 허용: 기대 이름으로 시작하면 접미어를 기록만 한다
        $prefixMatch = (-not $match -and $parsed.text.StartsWith($info.expected))
        $verdict = $(if ($match) { 'pass' } elseif ($Result -ne 'record') { $Result } else { 'fail' })
        $shot = $(if ($Screenshot) { Join-Path $P.EvidenceDir $Screenshot } else { '' })
        $rec = @{ kind = 'observe'; stage = $Stage; observed = $Observed; icon = $parsed.icon; iconCodepoints = $parsed.iconCodepoints; iconUtf16Hex = $parsed.iconUtf16Hex; textWithoutIcon = $parsed.text; expected = $info.expected; match = $match; suffixVariant = $prefixMatch; verdict = $verdict; screenshot = $shot; screenshotExists = $(if ($shot) { Test-Path $shot } else { $false }); note = $Note }
        Write-CLog -Path $P.S4bLog -Record $rec
        Write-Host ("  [{0}] 아이콘='{1}'({2} cp, {3}) 텍스트='{4}' 기대='{5}' 일치={6} 접미어변형={7} 스크린샷존재={8}" -f $Stage, $parsed.icon, $parsed.iconCodepoints, $parsed.iconUtf16Hex, $parsed.text, $info.expected, $match, $prefixMatch, $rec.screenshotExists)
    }
    'collect' {
        Show-CBanner '[S4b] collect — 훅 기록과 agents --json 의 name'
        $info = Get-S4bInfo
        if (-not $info) { throw 'prepare 를 먼저 실행한다.' }
        $all = @(Read-CLog $P.NotifyLog | Where-Object { ($_.PSObject.Properties['payload'] -and $_.payload -and (Get-CProp $_.payload 'session_id') -eq $info.sessionId) -or ($_.PSObject.Properties['emitted']) })
        $emits = @(Read-CLog $P.NotifyLog | Where-Object { $_.PSObject.Properties['emitted'] -and $_.ts -ge $info.preparedAt })
        $starts = @($all | Where-Object { $_.event -eq 'SessionStart' })
        $prompts = @($all | Where-Object { $_.event -eq 'UserPromptSubmit' })
        $a = Find-CAgent -SessionId $info.sessionId -All
        $name = Get-CProp $a 'name'
        $nameMatch = ($name -eq $info.expected)
        $sessionTitleEcho = @($starts | ForEach-Object { Get-CProp $_.payload 'session_title' } | Where-Object { $_ })
        Write-Host ("  SessionStart 기록 {0}건, UserPromptSubmit 기록 {1}건, sessionTitle 출력 {2}건" -f $starts.Count, $prompts.Count, $emits.Count)
        Write-Host ("  agents --json name='{0}' 기대='{1}' 일치={2}" -f $name, $info.expected, $nameMatch)
        Write-Host ("  이후 SessionStart 의 session_title 값: {0}" -f ($sessionTitleEcho -join ' | '))
        $job = Get-CJobState $info.id
        Write-Host ('  job state(내부): ' + ($job | ConvertTo-Json -Compress))
        Save-S4bInfo @{ agentsName = $name; agentsNameMatch = $nameMatch; sessionStartCount = $starts.Count; userPromptCount = $prompts.Count; emitCount = $emits.Count; sessionTitleEcho = $sessionTitleEcho }
        Write-CLog -Path $P.S4bLog -Record @{ kind = 'collect'; agentsName = $name; nameMatch = $nameMatch; sessionStartCount = $starts.Count; userPromptCount = $prompts.Count; emitCount = $emits.Count; sessionTitleEcho = $sessionTitleEcho; job = $job }
    }
    'analyze' {
        Show-CBanner '[S4b] analyze'
        $info = Get-S4bInfo
        if (-not $info) { Write-CVerdict -Step 'S4b' -Result 'pending' -Evidence 'prepare 미실행'; return }
        $obs = @(Read-CLog $P.S4bLog | Where-Object { $_.kind -eq 'observe' })
        if ($obs.Count -eq 0) { Write-CVerdict -Step 'S4b' -Result 'pending' -Evidence '관찰 record 없음'; return }
        $byStage = @{}
        foreach ($o in $obs) { $byStage[$o.stage] = $o }
        $lines = @()
        $allOk = $true
        foreach ($st in $byStage.Keys) {
            $o = $byStage[$st]
            $ok = ($o.match -or ($o.suffixVariant -and $st -eq 'sessionstart'))
            if (-not $ok) { $allOk = $false }
            $lines += ("{0}: icon='{1}'({2}cp) text='{3}' ok={4}" -f $st, $o.icon, $o.iconCodepoints, $o.textWithoutIcon, $ok)
        }
        $ev = ($lines -join ' / ') + " / agentsName=" + (Get-CProp $info 'agentsName' '(collect 미실행)')
        if ($allOk) { Write-CVerdict -Step 'S4b' -Result 'pass' -Evidence $ev -Note '아이콘을 뺀 텍스트가 4.6 형식과 같음' }
        else { Write-CVerdict -Step 'S4b' -Result 'fail' -Evidence $ev -Note '대체: cce 가 attach 직전 OSC 0 출력(-Phase osc 로 시험) → 덮어써지면 C 프로젝트에 한해 --title 고정(아이콘 포기)' }
    }
    'osc' {
        # 대체 경로 시험: attach 직전에 OSC 0 으로 제목을 직접 찍고 붙는다. WT 탭에서 직접 실행한다.
        $info = Get-S4bInfo
        if (-not $info) { throw 'prepare 를 먼저 실행한다.' }
        $title = $info.expected
        $esc = [char]27; $bel = [char]7
        [Console]::Write("$esc]0;$title$bel")
        Write-CLog -Path $P.S4bLog -Record @{ kind = 'osc'; title = $title; id = $info.id }
        Write-Host "  OSC 0 로 '$title' 출력 후 attach. 탭 제목이 유지되는지/덮어써지는지 본다 → record -Stage osc"
        $exe = Get-ClaudeExe
        & $exe attach $info.id
    }
    'cleanup' {
        if (Test-Path $P.TitleFile) { Remove-Item $P.TitleFile -Force; Write-Host "  삭제: $($P.TitleFile)" }
        Write-Host '  세션 정리는 S3-bg-attach.ps1 -Step cleanup 이 함께 한다.'
    }
}
