<#
.SYNOPSIS
  S1 — Windows Terminal 레이아웃 복원 스파이크 (계획 §5 Step 0, S1(a)~(f)).
.DESCRIPTION
  단계(-Step):
    prepare   백업 → WT settings.json 에 "firstWindowPreference": "persistedWindowLayout" 을 표식 주석과 함께 넣는다(수술적 삽입).
              사람이 할 일(pane 4종 열기, osc99 헬퍼 source, 표식 남기기)을 번호로 출력한다.
    watch     숨김 백그라운드 프로세스로 state.json 을 1초마다 감시해 변경마다 사본을 저장하고
              WT 프로세스 수·창 수를 함께 기록한다(S1(e) 저장 시점·간격, S1(a) 키 구조 원본 확보).
    layout    현재 state.json 의 persistedWindowLayouts 를 보기 좋게 출력하고 키 구조를 _log/s1-state-keys.txt 에 남긴다(S1(a)(b)).
    count     지금 열린 WT 창 수와 창 제목을 출력한다(S1(f) 복원 확인).
    rewrite   WT 가 완전히 꺼진 상태에서, 감시 중 저장한 사본(창 수가 가장 많은 것, 또는 -From) 을 state.json 에 되쓴다(S1(f)).
    analyze   _log/s1-panes.jsonl(before/after 쌍), 감시 로그, 키 구조를 합쳐 (a)~(f) 판정 자료를 출력한다.
    cleanup   settings.json 의 표식 줄을 제거(원래 값이 있었으면 되돌림)한다. 마지막에는 restore.ps1 로 전체를 되돌린다.
  PowerShell 5.1 에서 실행한다. pwsh 7 이 있으면 감지해 안내한다.
#>
param(
    [Parameter(Mandatory)][ValidateSet('prepare','watch','watch-run','layout','count','rewrite','analyze','cleanup')][string]$Step,
    [int]$Seconds = 900,
    [string]$From = ''
)
. "$PSScriptRoot\common\common.ps1"
Initialize-SpikeDirs
$Tag = 'S1'
$MarkerComment = '// cce-spike:S1'
$watchLog = Join-Path $script:LogDir 's1-state-watch.jsonl'
$snapDir  = Join-Path $script:LogDir 's1-state-snapshots'
$panesLog = Join-Path $script:LogDir 's1-panes.jsonl'

function Get-KeyPaths($Object, [string]$Prefix = '') {
    # JSON 객체의 키 경로를 모두 나열한다(배열은 [] 로 표시).
    $out = @()
    if ($null -eq $Object) { return $out }
    if ($Object -is [System.Array]) {
        foreach ($e in $Object) { $out += Get-KeyPaths $e ($Prefix + '[]') }
        return ($out | Select-Object -Unique)
    }
    if ($Object -is [pscustomobject]) {
        foreach ($p in $Object.PSObject.Properties) {
            $path = $(if ($Prefix -eq '') { $p.Name } else { "$Prefix.$($p.Name)" })
            $out += $path
            $out += Get-KeyPaths $p.Value $path
        }
        return ($out | Select-Object -Unique)
    }
    return $out
}

switch ($Step) {
  'prepare' {
    & "$PSScriptRoot\common\backup.ps1" -Label 'before-S1'
    $text = Read-TextFile $script:WtSettingsPath
    if ($text -match [regex]::Escape($MarkerComment)) {
        Write-Step $Tag '이미 표식이 있다. prepare 를 건너뛴다.'
    } elseif ($text -match '(?m)^(\s*)"firstWindowPreference"\s*:\s*"([^"]*)"\s*,?') {
        $orig = $Matches[2]
        $indent = $Matches[1]
        $new = $text -replace '(?m)^(\s*)"firstWindowPreference"\s*:\s*"[^"]*"(\s*,?)', ('$1"firstWindowPreference": "persistedWindowLayout"$2 ' + $MarkerComment + ' original=' + $orig)
        Write-TextFileAtomic $script:WtSettingsPath $new -Bom:($text.StartsWith([char]0xFEFF))
        Write-Touched 'EDIT' ("{0}  (firstWindowPreference: '{1}' -> 'persistedWindowLayout', 표식 기록)" -f $script:WtSettingsPath, $orig)
    } else {
        # 첫 "{" 바로 다음 줄에 넣는다. WT settings.json 은 JSONC 라 줄 끝 주석을 허용한다.
        $idx = $text.IndexOf('{')
        if ($idx -lt 0) { throw 'settings.json 에서 여는 중괄호를 찾지 못했다.' }
        $nl = "`r`n"; if (-not $text.Contains("`r`n")) { $nl = "`n" }
        $line = $nl + '    "firstWindowPreference": "persistedWindowLayout", ' + $MarkerComment
        $new = $text.Substring(0, $idx + 1) + $line + $text.Substring($idx + 1)
        Write-TextFileAtomic $script:WtSettingsPath $new -Bom:($text.StartsWith([char]0xFEFF))
        Write-Touched 'EDIT' ("{0}  (firstWindowPreference 줄 삽입, 표식 '{1}')" -f $script:WtSettingsPath, $MarkerComment)
    }
    $pwsh = Get-Pwsh7Path
    $distros = Get-WslDistros
    Write-Step $Tag ("pwsh 7: {0}" -f $(if ($pwsh) { $pwsh } else { '없음(설치 중이면 나중에 pane 을 추가)' }))
    Write-Step $Tag ("WSL 배포판: {0}" -f ($distros -join ', '))
    Write-Step $Tag ("state.json 현재 persistedWindowLayouts 수: {0}" -f @((Read-Json $script:WtStatePath).persistedWindowLayouts).Count)
    $repo = $script:RepoRoot
    $repoBash = ConvertTo-BashPath $repo
    $repoWsl = '/mnt' + $repoBash
    Write-Manual @(
        "감시를 먼저 켠다(아무 콘솔에서나, WT 밖이어도 됨):  powershell -NoProfile -ExecutionPolicy Bypass -File $repo\spikes\S1-wt-layout.ps1 -Step watch -Seconds 1200",
        "WT 창 1 을 열고 탭/분할로 pane 4개를 만든다: [PS 5.1] [pwsh 7(있으면)] [Git Bash] [WSL Ubuntu]. 각 pane 에서 서로 다른 폴더로 cd 한다(예: C:\Windows, C:\Users, C:\Temp, ~).",
        "각 pane 에서 OSC 9;9 헬퍼를 source 한다:  PS: . $repo\spikes\common\osc99.ps1   /  Git Bash: source $repoBash/spikes/common/osc99.sh   /  WSL: source $repoWsl/spikes/common/osc99.sh",
        "각 pane 에서 표식(before)을 남긴다:  PS: & '$repo\spikes\common\s1-mark.ps1' before   /  Git Bash: $repoBash/spikes/common/s1-mark.sh before   /  WSL: $repoWsl/spikes/common/s1-mark.sh before",
        "WT 창 2 를 하나 더 열고(예: PS 5.1 탭 1개, cd C:\Program Files) 같은 방식으로 표식(before, 라벨 win2)을 남긴다. (S1(e): 창 2개)",
        "창 2 를 X 로 닫고 10초를 센 뒤 창 1 을 X 로 닫는다. 감시 로그가 저장 시점을 초 단위로 기록한다.",
        "시작 메뉴에서 WT 를 다시 연다. 복원된 각 pane 에서 pwd 를 확인하고 표식(after)을 같은 명령으로 남긴다(PS 는 -Phase after / bash 는 after).",
        "  -Step layout 으로 state.json 구조를 보고, -Step count 로 창 수를 확인한 뒤, -Step analyze 를 실행한다.",
        "S1(f): WT 를 모두 닫고 -Step rewrite 를 실행한 뒤 WT 를 다시 열어 -Step count 로 창 2개가 복원되는지 본다.",
        "끝나면 -Step cleanup, 그리고 restore.ps1 로 원래 파일을 되돌린다."
    )
  }
  'watch' {
    $ps = (Get-Process -Id $PID).Path
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $PSCommandPath, '-Step', 'watch-run', '-Seconds', $Seconds)
    $p = Start-Process -FilePath $ps -ArgumentList $args -WindowStyle Hidden -PassThru
    Write-Step $Tag ("숨김 감시 프로세스 pid={0}, {1}초 동안 {2} 에 기록. 중단: Stop-Process -Id {0}" -f $p.Id, $Seconds, $watchLog)
  }
  'watch-run' {
    if (-not (Test-Path -LiteralPath $snapDir)) { New-Item -ItemType Directory -Path $snapDir | Out-Null }
    $lastHash = ''
    $end = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $end) {
        $h = Get-FileSha256 $script:WtStatePath
        $wtCount = @(Get-WtProcesses).Count
        $winCount = 0; try { $winCount = Get-WtWindowCount } catch { }
        if ($h -ne $lastHash) {
            $lastHash = $h
            $fi = Get-Item -LiteralPath $script:WtStatePath
            $layouts = 0; $tabs = @()
            try {
                $o = Read-Json $script:WtStatePath
                $layouts = @($o.persistedWindowLayouts).Count
                foreach ($L in @($o.persistedWindowLayouts)) { $tabs += @(Get-Prop $L 'tabLayout' @()).Count }
            } catch { }
            $snap = Join-Path $snapDir ("state-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
            Copy-Item -LiteralPath $script:WtStatePath -Destination $snap
            Add-Jsonl $watchLog ([ordered]@{ ts = [DateTime]::UtcNow.ToString('o'); change = $true; sha256 = $h; size = $fi.Length
                lastWrite = $fi.LastWriteTimeUtc.ToString('o'); persistedWindowLayouts = $layouts; tabLayoutActions = ($tabs -join '/')
                wtProcesses = $wtCount; wtWindows = $winCount; snapshot = $snap })
        } else {
            Add-Jsonl $watchLog ([ordered]@{ ts = [DateTime]::UtcNow.ToString('o'); change = $false; wtProcesses = $wtCount; wtWindows = $winCount })
        }
        Start-Sleep -Seconds 1
    }
  }
  'layout' {
    $o = Read-Json $script:WtStatePath
    Write-Step $Tag ("state.json 최상위 키: {0}" -f ((Get-PropNames $o) -join ', '))
    $layouts = @(Get-Prop $o 'persistedWindowLayouts' @())
    Write-Step $Tag ("persistedWindowLayouts: {0}개" -f $layouts.Count)
    $keys = Get-KeyPaths $layouts 'persistedWindowLayouts'
    $keysPath = Join-Path $script:LogDir 's1-state-keys.txt'
    Write-TextFileAtomic $keysPath ($keys -join "`r`n")
    Write-Touched 'WRITE' $keysPath
    $pretty = $layouts | ConvertTo-Json -Depth 32
    $prettyPath = Join-Path $script:LogDir 's1-layouts-pretty.json'
    Write-TextFileAtomic $prettyPath $pretty
    Write-Touched 'WRITE' $prettyPath
    Write-Host $pretty
    Write-Host ''
    Write-Host '키 구조:'; $keys | ForEach-Object { Write-Host "  $_" }
    $raw = Read-TextFile $script:WtStatePath
    Write-Step $Tag ("(b) 'commandline' 문자열 포함 여부: {0}   'cwd/startingDirectory' 포함 여부: {1}" -f ($raw -match 'commandline'), ($raw -match 'startingDirectory|"cwd"|directory'))
  }
  'count' {
    $wins = @(Get-WtWindows)
    Write-Step $Tag ("WT 프로세스 {0}개, 최상위 창 {1}개" -f @(Get-WtProcesses).Count, $wins.Count)
    foreach ($w in $wins) { Write-Host ("  hwnd={0} pid={1} title='{2}'" -f $w.hwnd, $w.pid, $w.title) }
    $tabs = @(Get-WtTabNames)
    if ($tabs.Count -gt 0) { Write-Host '  UIA 탭:'; foreach ($t in $tabs) { Write-Host ("    [{0}] {1}" -f $t.hwnd, $t.name) } }
    Add-Jsonl (Join-Path $script:LogDir 's1-count.jsonl') ([ordered]@{ ts = [DateTime]::UtcNow.ToString('o'); wtProcesses = @(Get-WtProcesses).Count; windows = $wins.Count; titles = @($wins | ForEach-Object { $_.title }); tabs = @($tabs | ForEach-Object { $_.name }) })
  }
  'rewrite' {
    if (@(Get-WtProcesses).Count -gt 0) { throw 'WindowsTerminal.exe 가 아직 실행 중이다. 모두 닫은 뒤(allowHeadless 주의) 다시 실행하라.' }
    if ($From -eq '') {
        $best = $null; $bestN = -1
        foreach ($r in (Read-Jsonl $watchLog | Where-Object { $_.change -eq $true })) {
            if ([int]$r.persistedWindowLayouts -gt $bestN) { $bestN = [int]$r.persistedWindowLayouts; $best = $r.snapshot }
        }
        if ($null -eq $best) { throw '감시 사본이 없다. -From <state 사본 경로> 를 지정하라.' }
        $From = $best
        Write-Step $Tag ("창 수가 가장 많은 사본({0}개)을 고른다: {1}" -f $bestN, $From)
    }
    $bak = Join-Path $script:BackupRoot ("state.before-rewrite.{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Copy-Item -LiteralPath $script:WtStatePath -Destination $bak
    Write-Touched 'COPY' ("{0} -> {1}" -f $script:WtStatePath, $bak)
    $tmp = "$($script:WtStatePath).cce-tmp"
    Copy-Item -LiteralPath $From -Destination $tmp
    if (@(Get-WtProcesses).Count -gt 0) { Remove-Item $tmp; throw '교체 직전에 WT 가 다시 떴다. 중단.' }
    Move-Item -LiteralPath $tmp -Destination $script:WtStatePath -Force
    Write-Touched 'WRITE' ("{0}  (<- {1})" -f $script:WtStatePath, $From)
    Add-Jsonl (Join-Path $script:LogDir 's1-rewrite.jsonl') ([ordered]@{ ts = [DateTime]::UtcNow.ToString('o'); from = $From; backup = $bak; sha256 = (Get-FileSha256 $script:WtStatePath) })
    Write-Manual @('시작 메뉴에서 WT 를 연다.', "열린 창 수를 -Step count 로 확인한다. 되쓴 파일의 창 수와 같으면 S1(f) 합격.")
  }
  'analyze' {
    Write-Host '=== S1(c)(d) pane 표식 before/after 비교 ==='
    $marks = @(Read-Jsonl $panesLog)
    $before = @($marks | Where-Object { $_.phase -eq 'before' })
    $after  = @($marks | Where-Object { $_.phase -eq 'after' })
    $pass = 0; $total = 0
    foreach ($b in $before) {
        $total++
        $a = $after | Where-Object { $_.shell -eq $b.shell -and $_.label -eq $b.label } | Select-Object -Last 1
        if ($null -eq $a) { Write-Host ("  [{0}] after 없음 (before cwd={1})" -f $b.shell, $b.cwd); continue }
        $cwdSame = ($a.cwd -eq $b.cwd)
        $wtSame  = ($a.WT_SESSION -eq $b.WT_SESSION) -and ($b.WT_SESSION -ne '')
        if ($cwdSame) { $pass++ }
        Write-Host ("  [{0}{5}] cwd 같음={1}  ({2} -> {3})   WT_SESSION 유지={4}" -f $b.shell, $cwdSame, $b.cwd, $a.cwd, $wtSame, $(if ($b.label) { ':' + $b.label } else { '' }))
    }
    Write-Host ("  (d) 폴더 복원 {0}/{1}  — 합격 기준: 4/4 (pwsh 5.1·pwsh 7·Git Bash·WSL)" -f $pass, $total)
    Write-Host ''
    Write-Host '=== S1(e) state.json 저장 시점 (감시 로그의 변경 이벤트) ==='
    $changes = @(Read-Jsonl $watchLog | Where-Object { $_.change -eq $true })
    $prev = $null
    foreach ($c in $changes) {
        $gap = ''
        if ($null -ne $prev) { $gap = ('+{0:0.0}s' -f ([datetime]$c.ts - [datetime]$prev.ts).TotalSeconds) }
        Write-Host ("  {0}  layouts={1} tabActions={2} wtProc={3} wtWin={4} {5}" -f $c.ts, $c.persistedWindowLayouts, $c.tabLayoutActions, $c.wtProcesses, $c.wtWindows, $gap)
        $prev = $c
    }
    if ($changes.Count -eq 0) { Write-Host '  변경 기록 없음(감시를 켜지 않았거나 WT 가 저장하지 않았다).' }
    Write-Host ''
    Write-Host '=== S1(a)(b) 키 구조 ==='
    $keysPath = Join-Path $script:LogDir 's1-state-keys.txt'
    if (Test-Path -LiteralPath $keysPath) { Get-Content -LiteralPath $keysPath | ForEach-Object { Write-Host "  $_" } } else { Write-Host '  -Step layout 을 먼저 실행하라.' }
    Write-Host ''
    Write-Host '=== S1(f) 되쓰기 후 창 수 ==='
    $rw = @(Read-Jsonl (Join-Path $script:LogDir 's1-rewrite.jsonl'))
    $cnt = @(Read-Jsonl (Join-Path $script:LogDir 's1-count.jsonl'))
    if ($rw.Count -gt 0) {
        $last = $rw[-1]
        $expected = @((Read-Json $last.from).persistedWindowLayouts).Count
        $afterCount = @($cnt | Where-Object { [datetime]$_.ts -gt [datetime]$last.ts }) | Select-Object -Last 1
        Write-Host ("  되쓴 파일의 창 수={0}, 되쓰기 후 관측한 창 수={1}" -f $expected, $(if ($afterCount) { $afterCount.windows } else { '(count 미실행)' }))
    } else { Write-Host '  rewrite 미실행.' }
  }
  'cleanup' {
    $text = Read-TextFile $script:WtSettingsPath
    if ($text -match ('(?m)^\s*"firstWindowPreference"\s*:\s*"persistedWindowLayout"(\s*,?)\s*' + [regex]::Escape($MarkerComment) + ' original=([^\r\n]*)\r?$')) {
        $orig = $Matches[2].Trim()
        $new = $text -replace ('(?m)^(\s*)"firstWindowPreference"\s*:\s*"persistedWindowLayout"(\s*,?)\s*' + [regex]::Escape($MarkerComment) + ' original=[^\r\n]*'), ('$1"firstWindowPreference": "' + $orig + '"$2')
        Write-TextFileAtomic $script:WtSettingsPath $new -Bom:($text.StartsWith([char]0xFEFF))
        Write-Touched 'EDIT' ("{0}  (firstWindowPreference 를 '{1}' 로 되돌림)" -f $script:WtSettingsPath, $orig)
    } elseif ($text -match [regex]::Escape($MarkerComment)) {
        $new = $text -replace ('(?m)^[^\r\n]*' + [regex]::Escape($MarkerComment) + '[^\r\n]*\r?\n?'), ''
        Write-TextFileAtomic $script:WtSettingsPath $new -Bom:($text.StartsWith([char]0xFEFF))
        Write-Touched 'EDIT' ("{0}  (표식 줄 삭제)" -f $script:WtSettingsPath)
    } else { Write-Step $Tag '표식이 없다. 할 일이 없다.' }
    Write-Step $Tag '전체 원복은 spikes\common\restore.ps1 로 한다(WT 를 모두 닫은 뒤).'
  }
}
