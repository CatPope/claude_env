<#
.SYNOPSIS
  S4 — 탭 제목 스파이크, interactive (계획 §5 Step 0, S4(a)(c)(d)(e)(f); S4(b) attach 는 다른 레인).
.DESCRIPTION
  단계(-Step):
    prepare -Mode <SessionStart|UserPromptSubmit|both|none|osc> [-Base '<별칭> [<계정>]']
              백업 → 표식 훅(exec-bash, 5 이벤트) 설치, 제목 모드 파일 기록. 기존 statusline(OMC HUD)은 건드리지 않는다.
              훅은 CCE_PANE_KEY 가 있는 세션(= cce-stub 으로 띄운 세션)에만 sessionTitle 을 낸다.
                SessionStart      : S4(d-1) — SessionStart 에서 이름을 정한다
                UserPromptSubmit  : S4(d-2) — 첫 UserPromptSubmit 에서만 이름을 정한다
                both              : 계획 4.6절 기본(시작 시 <별칭> [<계정>], 첫 프롬프트 뒤 · <부제>)
                none              : 이름을 정하지 않는다(Claude 기본 제목 관찰용)
                osc               : S4(a) 불합격 시 대체 경로 — terminalSequence 로 OSC 0 을 직접 낸다
    collect -Label <x> [-Seconds 60]
              WT 창 제목(GetWindowText)과 UIA 탭 이름을 0.5초마다 모아 _log/s4-titles.jsonl 에 코드포인트와 함께 남긴다.
              사람이 그 사이에 busy/idle/waiting 상태를 만든다.
    snapshot -Label <x>
              ~/.claude/sessions/*.json 사본, `claude agents --json`, stub 세션 transcript 의 줄 수를 저장한다(S4(d)(e) 비교 기준).
    analyze   (a) 아이콘 글리프·코드포인트, 텍스트 일치  (c) 변형 접미어  (d) 자동 제목 출처(transcript ai-title / sessions json / agents --json)
              (e) /rename 감지 수단  (f) 첫 프롬프트 제목 반영 지연
    cleanup   표식 훅 제거, 제목 모드 none.
#>
param(
    [Parameter(Mandatory)][ValidateSet('prepare','collect','snapshot','analyze','cleanup')][string]$Step,
    [ValidateSet('SessionStart','UserPromptSubmit','both','none','osc')][string]$Mode = 'both',
    [string]$Base = 'claude_env [개인]',
    [string]$Label = 'run',
    [int]$Seconds = 60
)
. "$PSScriptRoot\common\common.ps1"
Initialize-SpikeDirs
$Tag = 'S4'
$events = @('SessionStart','UserPromptSubmit','Notification','Stop','SessionEnd')
$titlesLog = Join-Path $script:LogDir 's4-titles.jsonl'
$runsLog   = Join-Path $script:LogDir 's4-runs.jsonl'
$snapLog   = Join-Path $script:LogDir 's4-snapshots.jsonl'

function Get-StubSessionIds {
    return @(Read-Jsonl $script:RegistryLog | Where-Object { $_.state -eq 'active' } | ForEach-Object { $_.uuid } | Select-Object -Unique)
}
function Split-IconPrefix([string]$Title) {
    # 제목의 맨 앞에서 첫 공백까지를 아이콘 후보로 본다(ASCII 가 아닌 글리프일 때만).
    $sp = $Title.IndexOf(' ')
    if ($sp -gt 0) {
        $head = $Title.Substring(0, $sp)
        $nonAscii = $false
        foreach ($ch in $head.ToCharArray()) { if ([int]$ch -gt 127) { $nonAscii = $true } }
        if ($nonAscii) { return @{ icon = $head; text = $Title.Substring($sp + 1) } }
    }
    return @{ icon = ''; text = $Title }
}
function Read-TranscriptTitles([string]$Path) {
    $rows = @(); $types = @{}; $n = 0
    if (-not (Test-Path -LiteralPath $Path)) { return @{ aiTitles = @(); types = $types; lines = 0; titleLike = @() } }
    $titleLike = @()
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        $n++
        if ($line -match '"type"\s*:\s*"([^"]+)"') { $t = $Matches[1]; if ($types.ContainsKey($t)) { $types[$t]++ } else { $types[$t] = 1 } }
        if ($line -match '"type"\s*:\s*"ai-title"') {
            try { $o = $line | ConvertFrom-Json; $rows += [pscustomobject]@{ line = $n; aiTitle = $o.aiTitle } } catch { }
        } elseif ($line.Length -lt 2000 -and $line -match '(?i)"(custom-?title|title|session_?name|name)"\s*:' -and $line -notmatch '"type"\s*:\s*"(user|assistant|attachment|progress|file-history-snapshot|system)"') {
            $titleLike += ("L{0}: {1}" -f $n, $line.Substring(0, [math]::Min(200, $line.Length)))
        }
    }
    return @{ aiTitles = $rows; types = $types; lines = $n; titleLike = $titleLike }
}

switch ($Step) {
  'prepare' {
    & "$PSScriptRoot\common\backup.ps1" -Label 'before-S4'
    Set-TitleMode -Mode $Mode -Base $Base
    if (@(Get-SpikeHooksInSettings).Count -eq 0) {
        $entries = @(); foreach ($ev in $events) { $entries += @{ Event = $ev; Group = (New-HookEntry -Event $ev -Form exec-bash) } }
        Install-SpikeHooks -Entries $entries -Tag $Tag
    } else { Write-Step $Tag '표식 훅이 이미 있다(S5/S2 에서 설치). 그대로 쓴다.' }
    Add-Jsonl $runsLog ([ordered]@{ ts = [DateTime]::UtcNow.ToString('o'); mode = $Mode; base = $Base })
    $repo = $script:RepoRoot
    Write-Step $Tag ("제목 모드={0}, 기본 이름='{1}'. statusline 은 그대로다: {2}" -f $Mode, $Base, ((Read-Json $script:ClaudeSettingsPath).statusLine.command))
    Write-Manual @(
        "-Step snapshot -Label before  (기준 스냅샷)",
        "WT 의 PowerShell pane 에서:  & '$repo\spikes\common\cce-stub.ps1' -Scenario s4-$Mode   → Claude 가 뜬다. 탭 제목을 본다(첫 프롬프트 전).",
        "다른 콘솔에서:  -Step collect -Label $Mode -Seconds 90   를 켜 둔 채로 아래를 진행한다.",
        "프롬프트를 보낸다(예: '로그인 버그를 고쳐줘. 먼저 계획만 말해'). busy 동안, 끝난 뒤(idle), 그리고 권한 요청이 뜨도록('C:\Temp\s4.txt 만들어줘') 각각 5초 이상 기다린다(waiting).",
        "(c) 같은 폴더에서 두 번째 WT 탭을 열고 같은 명령으로 두 번째 세션을 띄워 같은 프롬프트를 보낸다 → 접미어 형식 관찰.",
        "(e) 첫 세션에서 /rename 내이름 을 실행하고 5초 뒤 -Step snapshot -Label after-rename. 그다음 /exit 하고 같은 pane 에서 -Resume 으로 다시 띄운다(SessionStart(resume) 의 session_title 관찰).",
        "-Step snapshot -Label after  →  -Step analyze.",
        "d-1 과 d-2 를 각각 보려면 -Mode SessionStart 와 -Mode UserPromptSubmit 로 prepare 를 다시 하고 2~7 을 반복한다.",
        "끝나면 -Step cleanup."
    )
  }
  'collect' {
    Write-Step $Tag ("{0}초 동안 0.5초 간격으로 WT 창 제목과 탭 이름을 모은다 → {1}" -f $Seconds, $titlesLog)
    $end = (Get-Date).AddSeconds($Seconds)
    $lastSig = ''
    while ((Get-Date) -lt $end) {
        $now = [DateTime]::UtcNow.ToString('o')
        $rows = @()
        foreach ($w in Get-WtWindows) { $rows += [ordered]@{ ts = $now; label = $Label; source = 'window'; hwnd = $w.hwnd; title = $w.title } }
        foreach ($t in Get-WtTabNames) { $rows += [ordered]@{ ts = $now; label = $Label; source = 'tab'; hwnd = $t.hwnd; title = $t.name } }
        $sig = ($rows | ForEach-Object { $_.source + '|' + $_.hwnd + '|' + $_.title }) -join "`n"
        if ($sig -ne $lastSig) {
            # 바뀐 순간만 기록한다(같은 상태 반복 기록은 줄이되, 첫 관측은 남긴다).
            foreach ($r in $rows) { $r.codepoints = ((Get-CodePoints $r.title) -join ' '); Add-Jsonl $titlesLog $r }
            Write-Host ("  {0}  {1}" -f $now.Substring(11, 12), (($rows | Where-Object { $_.source -eq 'tab' } | ForEach-Object { "[$($_.title)]" }) -join ' '))
            $lastSig = $sig
        }
        Start-Sleep -Milliseconds 500
    }
  }
  'snapshot' {
    $dir = Join-Path $script:LogDir ("s4-sessions-{0}-{1}" -f $Label, (Get-Date -Format 'HHmmss'))
    New-Item -ItemType Directory -Path $dir | Out-Null
    Copy-Item -Path (Join-Path $script:ClaudeDir 'sessions\*.json') -Destination $dir -ErrorAction SilentlyContinue
    Write-Touched 'COPY' ("~/.claude/sessions/*.json -> {0}" -f $dir)
    $agents = Get-ClaudeAgentsJson
    Write-JsonAtomic (Join-Path $dir 'agents.json') $agents
    $tx = @()
    foreach ($sid in @(Get-StubSessionIds)) {
        $p = Find-TranscriptPath $sid
        if ($p) { $tx += [ordered]@{ sessionId = $sid; path = $p; lines = @([System.IO.File]::ReadLines($p)).Count } }
    }
    Add-Jsonl $snapLog ([ordered]@{ ts = [DateTime]::UtcNow.ToString('o'); label = $Label; dir = $dir; agents = @($agents | ForEach-Object { [ordered]@{ sessionId = (Get-Prop $_ 'sessionId'); name = (Get-Prop $_ 'name'); kind = (Get-Prop $_ 'kind'); status = (Get-Prop $_ 'status') } }); transcripts = $tx })
    Write-Step $Tag ("스냅샷 '{0}': sessions {1}개, agents {2}개, stub transcript {3}개" -f $Label, @(Get-ChildItem $dir -Filter '*.json').Count, @($agents).Count, $tx.Count)
  }
  'analyze' {
    $hooks = @(Read-Jsonl $script:HooksLog)
    $titles = @(Read-Jsonl $titlesLog)
    $stubSids = @(Get-StubSessionIds)   # 빈 배열을 return 하면 $null 이 되므로 다시 감싼다
    $runs = @(Read-Jsonl $runsLog)
    Write-Host ("훅 로그 {0}건, 제목 표본 {1}건, stub 세션 {2}개, prepare 실행 {3}회" -f $hooks.Count, $titles.Count, $stubSids.Count, $runs.Count)
    $emitted = @($hooks | Where-Object { $_.title_emitted -ne '' } | ForEach-Object { $_.title_emitted } | Select-Object -Unique)
    Write-Host ("훅이 낸 이름: {0}" -f ($emitted -join ' | '))

    Write-Host ''
    Write-Host '=== (a) WT 탭에 <아이콘> <이름> 으로 보이는가 / 글리프와 코드포인트 ==='
    $glyphs = @{}
    foreach ($lab in ($titles | ForEach-Object { $_.label } | Select-Object -Unique)) {
        Write-Host ("  [label={0}]" -f $lab)
        $distinct = $titles | Where-Object { $_.label -eq $lab -and $_.source -eq 'tab' } | Select-Object -ExpandProperty title -Unique
        foreach ($t in $distinct) {
            $sp = Split-IconPrefix $t
            $match = ($emitted -contains $sp.text)
            $prefixOf = @($emitted | Where-Object { $sp.text.StartsWith($_) }).Count -gt 0
            if ($sp.icon -ne '') { $glyphs[$sp.icon] = ((Get-CodePoints $sp.icon) -join ' ') }
            Write-Host ("    '{0}'  icon='{1}' [{2}]  text='{3}'  이름과 같음={4} 접두 일치={5}" -f $t, $sp.icon, $(if ($sp.icon) { (Get-CodePoints $sp.icon) -join ' ' } else { '없음' }), $sp.text, $match, $prefixOf)
        }
    }
    Write-Host '  관측한 아이콘 글리프 집합(T-7 <ICON> 후보):'
    foreach ($k in $glyphs.Keys) { Write-Host ("    '{0}' = {1}  ({2} 코드포인트)" -f $k, $glyphs[$k], @($glyphs[$k] -split ' ').Count) }
    Write-Host '  판정: busy·idle·waiting 세 상태에서 아이콘을 뺀 텍스트가 정한 이름과 같으면 합격. idle 에서 아이콘이 없으면 "없음"으로 기록한다.'

    Write-Host ''
    Write-Host '=== (c) 같은 이름 둘일 때 변형 접미어 ==='
    foreach ($t in ($titles | Where-Object { $_.source -eq 'tab' } | Select-Object -ExpandProperty title -Unique)) {
        $sp = Split-IconPrefix $t
        foreach ($e in $emitted) {
            if ($sp.text.Length -gt $e.Length -and $sp.text.StartsWith($e)) { Write-Host ("    '{0}' → 접미어 '{1}'" -f $sp.text, $sp.text.Substring($e.Length)) }
        }
    }
    Write-Host '  (문서: 살아 있는 세션과 이름이 겹치면 두 단어 접미어 예: -graceful-unicorn. 관측 형식을 T-7 첫 프롬프트 전 정규식에 넣는다)'

    Write-Host ''
    Write-Host '=== (d) Claude 자동 생성 제목을 어디서 얻을 수 있는가 ==='
    $sessFiles = @(Get-ClaudeSessionFiles)
    $agents = @(Get-ClaudeAgentsJson)
    foreach ($sid in $stubSids) {
        $reg = @(Read-Jsonl $script:RegistryLog | Where-Object { $_.uuid -eq $sid -and $_.state -eq 'active' } | Select-Object -Last 1)
        $started = $(if ($reg.Count -gt 0) { [datetime]$reg[0].ts } else { [datetime]::MinValue })
        $modeAtStart = '?'
        foreach ($r in $runs) { if ([datetime]$r.ts -le $started) { $modeAtStart = $r.mode } }
        $tp = Find-TranscriptPath $sid
        $tt = Read-TranscriptTitles $tp
        $sf = $sessFiles | Where-Object { (Get-Prop $_ 'sessionId') -eq $sid } | Select-Object -First 1
        $ag = $agents | Where-Object { (Get-Prop $_ 'sessionId') -eq $sid } | Select-Object -First 1
        $titleSet = @($hooks | Where-Object { $_.session_id -eq $sid -and $_.title_emitted -ne '' })
        Write-Host ("  세션 {0}  (시작 {1}, 제목 모드 {2}, 훅이 이름을 정한 횟수 {3})" -f $sid.Substring(0, 8), $started.ToString('HH:mm:ss'), $modeAtStart, $titleSet.Count)
        Write-Host ("    transcript ai-title 레코드: {0}개  최근='{1}'" -f $tt.aiTitles.Count, $(if ($tt.aiTitles.Count -gt 0) { $tt.aiTitles[-1].aiTitle } else { '' }))
        Write-Host ("    sessions/<pid>.json: name='{0}' nameSource='{1}'" -f $(if ($sf) { Get-Prop $sf 'name' } else { '(없음)' }), $(if ($sf) { Get-Prop $sf 'nameSource' } else { '' }))
        Write-Host ("    agents --json: name='{0}'" -f $(if ($ag) { Get-Prop $ag 'name' } else { '(없음)' }))
        if ($tt.titleLike.Count -gt 0) { Write-Host '    제목 비슷한 다른 레코드:'; $tt.titleLike | Select-Object -First 5 | ForEach-Object { Write-Host "      $_" } }
        $got = ($tt.aiTitles.Count -gt 0) -or ($sf -and (Get-Prop $sf 'nameSource') -eq 'auto') -or ($ag -and (Get-Prop $ag 'name') -and -not (($emitted -contains (Get-Prop $ag 'name'))))
        Write-Host ("    → 이름을 정한 뒤에도 자동 제목을 얻을 수 있음: {0}   ({1})" -f $got, $(if ($modeAtStart -eq 'SessionStart') { 'd-1' } elseif ($modeAtStart -eq 'UserPromptSubmit') { 'd-2' } else { $modeAtStart }))
    }
    Write-Host '  합격 기준: d-1 또는 d-2 가운데 하나라도 자동 제목을 얻을 수 있으면 합격 → 4.6절 출처 2 를 켠다.'
    Write-Host '  주의: transcript ai-title 과 sessions/<pid>.json 은 문서화되지 않은 계약(로컬 관찰). statusline session_name 은 기존 OMC HUD 를 쓰므로 이 스파이크에서는 쓰지 않는다.'

    Write-Host ''
    Write-Host '=== (e) /rename 감지 수단 ==='
    $ss = @($hooks | Where-Object { $_.event -eq 'SessionStart' -and $_.session_title -ne '' })
    Write-Host ("  SessionStart 입력 session_title 이 있던 건: {0}" -f $ss.Count)
    foreach ($r in $ss) { Write-Host ("    {0} source={1} sid={2} session_title='{3}'" -f $r.ts, $r.source, $r.session_id.Substring(0, 8), $r.session_title) }
    $snaps = @(Read-Jsonl $snapLog)
    if ($snaps.Count -ge 2) {
        Write-Host '  스냅샷 간 sessions/<pid>.json name 변화:'
        $prev = $null
        foreach ($s in $snaps) {
            if ($null -ne $prev) {
                $a = @(Get-ChildItem $prev.dir -Filter '*.json' | Where-Object { $_.Name -ne 'agents.json' } | ForEach-Object { Read-Json $_.FullName })
                $b = @(Get-ChildItem $s.dir -Filter '*.json' | Where-Object { $_.Name -ne 'agents.json' } | ForEach-Object { Read-Json $_.FullName })
                foreach ($x in $b) {
                    $y = $a | Where-Object { (Get-Prop $_ 'sessionId') -eq (Get-Prop $x 'sessionId') } | Select-Object -First 1
                    if ($y -and ((Get-Prop $y 'name') -ne (Get-Prop $x 'name') -or (Get-Prop $y 'nameSource') -ne (Get-Prop $x 'nameSource'))) {
                        Write-Host ("    [{0}→{1}] sid={2}: '{3}'({4}) → '{5}'({6})" -f $prev.label, $s.label, ([string](Get-Prop $x 'sessionId')).Substring(0, 8), (Get-Prop $y 'name'), (Get-Prop $y 'nameSource'), (Get-Prop $x 'name'), (Get-Prop $x 'nameSource'))
                    }
                }
                foreach ($t in @($s.transcripts)) {
                    $t0 = @($prev.transcripts | Where-Object { $_.sessionId -eq $t.sessionId })
                    if ($t0.Count -gt 0 -and $t.lines -gt $t0[0].lines) {
                        $new = [System.IO.File]::ReadLines($t.path) | Select-Object -Skip $t0[0].lines
                        $types = @($new | ForEach-Object { if ($_ -match '"type"\s*:\s*"([^"]+)"') { $Matches[1] } } | Group-Object | ForEach-Object { "$($_.Name)=$($_.Count)" })
                        Write-Host ("    [{0}→{1}] transcript {2} 새 레코드 유형: {3}" -f $prev.label, $s.label, $t.sessionId.Substring(0, 8), ($types -join ' '))
                    }
                }
            }
            $prev = $s
        }
    } else { Write-Host '  스냅샷이 2개 미만이다(-Step snapshot 을 before/after-rename 으로 남겨라).' }
    Write-Host '  피드백 루프 방지 규칙: 감지한 이름이 도구 형식(T-7 정규식 + 부제=레지스트리 subtitle)이면 /rename 으로 세지 않는다.'

    Write-Host ''
    Write-Host '=== (f) UserPromptSubmit 의 sessionTitle 이 첫 프롬프트에서 바로 탭에 반영되는가 ==='
    foreach ($sid in $stubSids) {
        $ups = @($hooks | Where-Object { $_.session_id -eq $sid -and $_.event -eq 'UserPromptSubmit' -and $_.title_emitted -ne '' } | Select-Object -First 1)
        if ($ups.Count -eq 0) { continue }
        $t0 = [datetime]::Parse($ups[0].ts).ToUniversalTime()
        $want = $ups[0].title_emitted
        $hit = $titles | Where-Object { $_.source -eq 'tab' -and $_.title.EndsWith($want) -and ([datetime]::Parse($_.ts).ToUniversalTime() -ge $t0) } | Select-Object -First 1
        if ($hit) { Write-Host ("  세션 {0}: 훅 {1} → 탭 관측 {2}  지연 {3:0.0}s  '{4}'" -f $sid.Substring(0, 8), $t0.ToString('HH:mm:ss.fff'), ([datetime]::Parse($hit.ts).ToUniversalTime()).ToString('HH:mm:ss.fff'), ([datetime]::Parse($hit.ts).ToUniversalTime() - $t0).TotalSeconds, $hit.title) }
        else { Write-Host ("  세션 {0}: 훅이 '{1}' 을 냈지만 탭에서 관측하지 못했다(collect 가 꺼져 있었거나 반영 안 됨)" -f $sid.Substring(0, 8), $want) }
    }
  }
  'cleanup' { Remove-SpikeHooks -Tag $Tag; Set-TitleMode -Mode none }
}
