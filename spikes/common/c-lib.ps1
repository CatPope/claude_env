# c-lib.ps1 — C 경로 스파이크(S3, S4(b)) 공용 함수. Windows PowerShell 5.1 호환.
# 사용: . "$PSScriptRoot\common\c-lib.ps1"
# 이 파일은 실행 시 부작용이 없다(함수 정의만). 다른 스파이크(S1/S2/S4/S5)의 backup.ps1/restore.ps1 과는 별개다.

Set-StrictMode -Version 2.0

function Get-CPaths {
    # 저장소 루트 = spikes/common 의 두 단계 위
    $repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $logDir = Join-Path $repo 'spikes\_log'
    $evDir = Join-Path $repo 'spikes\_evidence'
    $assets = Join-Path $repo 'spikes\c-assets'
    $scratchRoot = 'C:\cce-spike'
    $scratch = Join-Path $scratchRoot 'c'
    $tmp = Join-Path $scratchRoot 'tmp'
    return @{
        Repo        = $repo
        LogDir      = $logDir
        EvidenceDir = $evDir
        Assets      = $assets
        ScratchRoot = $scratchRoot
        Scratch     = $scratch
        Tmp         = $tmp
        StateFile   = Join-Path $logDir 's3-state.json'
        S3Log       = Join-Path $logDir 's3-bg-attach.jsonl'
        NotifyLog   = Join-Path $logDir 's3-notify.jsonl'
        AttachLog   = Join-Path $logDir 's3-4-attach.jsonl'
        ProtocolLog = Join-Path $logDir 's3-8-protocol.jsonl'
        VerdictLog  = Join-Path $logDir 'verdicts-c.jsonl'
        S4bLog      = Join-Path $logDir 's4b-title.jsonl'
        ClaudeHome  = Join-Path $env:USERPROFILE '.claude'
        UserSettings = Join-Path $env:USERPROFILE '.claude\settings.json'
        SettingsNone = Join-Path $tmp 'settings-none.json'
        SettingsWorktree = Join-Path $tmp 'settings-worktree.json'
        TitleFile   = Join-Path $scratch '_title.txt'
        ProtocolAttachFlag = Join-Path $scratch '_protocol-attach.enabled'
    }
}

function Get-CUtf8NoBom { return (New-Object System.Text.UTF8Encoding $false) }

function Write-CLog {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Record)
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    if ($Record -is [hashtable] -and -not $Record.ContainsKey('ts')) { $Record['ts'] = (Get-Date).ToUniversalTime().ToString('o') }
    $line = ($Record | ConvertTo-Json -Compress -Depth 8)
    [System.IO.File]::AppendAllText($Path, $line + [Environment]::NewLine, (Get-CUtf8NoBom))
}

function Read-CLog {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { return @() }
    $out = @()
    foreach ($line in [System.IO.File]::ReadAllLines($Path, (Get-CUtf8NoBom))) {
        if ($line.Trim().Length -eq 0) { continue }
        try { $out += ($line | ConvertFrom-Json) } catch { }
    }
    return ,$out
}

function Get-CState {
    $p = (Get-CPaths).StateFile
    if (-not (Test-Path $p)) { return @{} }
    $obj = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
    $h = @{}
    foreach ($prop in $obj.PSObject.Properties) { $h[$prop.Name] = $prop.Value }
    return $h
}

function Set-CState {
    param([Parameter(Mandatory)][hashtable]$State)
    $p = (Get-CPaths).StateFile
    $dir = Split-Path $p -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    [System.IO.File]::WriteAllText($p, ($State | ConvertTo-Json -Depth 8), (Get-CUtf8NoBom))
}

function Set-CStateValue {
    param([Parameter(Mandatory)][string]$Key, $Value)
    $s = Get-CState
    $s[$Key] = $Value
    Set-CState -State $s
}

function Add-CSpikeSession {
    # 이 스파이크가 만든 bg 세션을 기록해 두고 cleanup 에서 한꺼번에 rm 한다.
    param([string]$Step, [string]$ShortId, [string]$SessionId)
    $s = Get-CState
    $list = @()
    if ($s.ContainsKey('sessions') -and $s['sessions']) { $list = @($s['sessions']) }
    $list += [pscustomobject]@{ step = $Step; id = $ShortId; sessionId = $SessionId; at = (Get-Date).ToUniversalTime().ToString('o') }
    $s['sessions'] = $list
    Set-CState -State $s
}

function Write-CVerdict {
    param([Parameter(Mandatory)][string]$Step, [Parameter(Mandatory)][ValidateSet('pass','fail','record','pending')][string]$Result, [string]$Evidence = '', [string]$Note = '')
    $p = (Get-CPaths).VerdictLog
    Write-CLog -Path $p -Record @{ step = $Step; result = $Result; evidence = $Evidence; note = $Note }
    $label = switch ($Result) { 'pass' { '합격' } 'fail' { '불합격' } 'record' { '기록' } default { '보류' } }
    Write-Host ("[{0}] {1} — {2} {3}" -f $Step, $label, $Evidence, $Note)
}

function Get-ClaudeExe {
    $c = Get-Command claude.exe -ErrorAction SilentlyContinue
    if (-not $c) { $c = Get-Command claude -ErrorAction SilentlyContinue }
    if (-not $c) { throw 'claude 실행 파일을 찾을 수 없다.' }
    return $c.Source
}

function Get-WtExe {
    $c = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
    if (Test-Path $alias) { return $alias }
    throw 'wt.exe 를 찾을 수 없다.'
}

function Get-ClaudeAgents {
    # claude agents --json [--all] 을 파싱해 배열로 돌려준다.
    param([switch]$All)
    $exe = Get-ClaudeExe
    $args = @('agents', '--json')
    if ($All) { $args += '--all' }
    $raw = & $exe @args 2>$null | Out-String
    if (-not $raw -or $raw.Trim().Length -eq 0) { return @() }
    try { $arr = $raw | ConvertFrom-Json } catch { return @() }
    if ($null -eq $arr) { return @() }
    return ,@($arr)
}

function Get-CProp {
    # StrictMode 아래에서 없는 속성을 안전하게 읽는다.
    param($Object, [Parameter(Mandatory)][string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $Default
}

function Select-CAgentFields {
    # 계획 R3e 의 관심 필드만 뽑는다. 없는 필드는 $null.
    param($Agent)
    if ($null -eq $Agent) { return $null }
    $names = 'kind','id','state','status','pid','sessionId','name','cwd','startedAt','waitingFor'
    $h = [ordered]@{}
    foreach ($n in $names) {
        if ($Agent.PSObject.Properties[$n]) { $h[$n] = $Agent.$n } else { $h[$n] = $null }
    }
    return [pscustomobject]$h
}

function Find-CAgent {
    # sessionId(정확) 또는 cwd + startedAt(launchedAt 이후)로 찾는다.
    param([string]$SessionId, [string]$Cwd, [long]$SinceEpochMs = 0, [switch]$All, [string]$Kind = 'background')
    $agents = Get-ClaudeAgents -All:$All
    foreach ($a in $agents) {
        if ($Kind -and $a.PSObject.Properties['kind'] -and $a.kind -ne $Kind) { continue }
        if ($SessionId) {
            if ($a.PSObject.Properties['sessionId'] -and $a.sessionId -eq $SessionId) { return $a }
            continue
        }
        if ($Cwd) {
            if (-not $a.PSObject.Properties['cwd']) { continue }
            if ($a.cwd.TrimEnd('\').ToLower() -ne $Cwd.TrimEnd('\').ToLower()) { continue }
            if ($SinceEpochMs -gt 0 -and $a.PSObject.Properties['startedAt'] -and [long]$a.startedAt -lt $SinceEpochMs) { continue }
            return $a
        }
    }
    return $null
}

function Get-CEpochMs { return [long]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) }

function Wait-CAgentState {
    # 세션이 $States 중 하나가 될 때까지 폴링. 상태 변화를 $Log 에 남긴다. 최종 agent 객체(없으면 $null)를 돌려준다.
    param([Parameter(Mandatory)][string]$SessionId, [string[]]$States = @('done','failed','stopped','blocked'), [int]$TimeoutSec = 180, [int]$IntervalSec = 3, [string]$Log, [string]$Step = '')
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $last = ''
    $agent = $null
    while ((Get-Date) -lt $deadline) {
        $agent = Find-CAgent -SessionId $SessionId -All
        $cur = if ($agent) { "$($agent.state)/$($agent.status)" } else { '(없음)' }
        if ($cur -ne $last) {
            Write-Host ("  {0} state={1}" -f (Get-Date).ToString('HH:mm:ss'), $cur)
            if ($Log) { Write-CLog -Path $Log -Record @{ kind = 'poll'; step = $Step; sessionId = $SessionId; agent = (Select-CAgentFields $agent) } }
            $last = $cur
        }
        if ($agent -and $agent.PSObject.Properties['state'] -and ($States -contains $agent.state)) { return $agent }
        Start-Sleep -Seconds $IntervalSec
    }
    return $agent
}

function Start-CBgSession {
    # claude --bg 를 $Cwd 에서 실행하고 출력에서 짧은 id 를 뽑는다. 출력 전체도 돌려준다.
    param([string[]]$ClaudeArgs = @(), [Parameter(Mandatory)][string]$Cwd, [string]$Log, [string]$Step = '')
    $exe = Get-ClaudeExe
    $launchedAt = Get-CEpochMs
    Push-Location $Cwd
    try {
        $full = @('--bg') + $ClaudeArgs
        Write-Host ("  실행: claude {0}" -f ($full -join ' '))
        $lines = & $exe @full 2>&1 | ForEach-Object { "$_" }
        $exit = $LASTEXITCODE
    } finally { Pop-Location }
    $text = ($lines -join "`n")
    $short = $null
    $m = [regex]::Match($text, '(?<![0-9a-f])([0-9a-f]{8})(?![0-9a-f-])')
    if ($m.Success) { $short = $m.Groups[1].Value }
    $rec = @{ kind = 'launch'; step = $Step; args = $full; exit = $exit; output = $text; shortId = $short; launchedAt = $launchedAt }
    if ($Log) { Write-CLog -Path $Log -Record $rec }
    return [pscustomobject]@{ ShortId = $short; Output = $text; Exit = $exit; LaunchedAt = $launchedAt }
}

function Resolve-CBgSession {
    # 실행 직후 agents --json 에서 세션을 찾는다(계획 4.1 §3 의 대체 경로: startedAt + cwd).
    param([string]$SessionId, [Parameter(Mandatory)][string]$Cwd, [long]$SinceEpochMs, [int]$TimeoutSec = 60)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $a = $null
        if ($SessionId) { $a = Find-CAgent -SessionId $SessionId -All }
        if (-not $a) { $a = Find-CAgent -Cwd $Cwd -SinceEpochMs ($SinceEpochMs - 5000) -All }
        if ($a) { return $a }
        Start-Sleep -Seconds 2
    }
    return $null
}

function Get-CProjectKey {
    # ~/.claude/projects/<인코딩 cwd> 규칙: 영숫자 이외를 '-' 로 바꾼다(로컬 관찰: C:\Users\qwer\... → C--Users-qwer-...).
    param([Parameter(Mandatory)][string]$Cwd)
    return ([regex]::Replace($Cwd, '[^A-Za-z0-9]', '-'))
}

function Get-CTranscriptPath {
    param([Parameter(Mandatory)][string]$Cwd, [Parameter(Mandatory)][string]$SessionId)
    $p = Get-CPaths
    $dir = Join-Path $p.ClaudeHome ('projects\' + (Get-CProjectKey $Cwd))
    $f = Join-Path $dir ($SessionId + '.jsonl')
    if (Test-Path $f) { return $f }
    # worktree 격리 등으로 cwd 가 달라졌을 수 있으므로 전체 검색으로 대체
    $hit = Get-ChildItem (Join-Path $p.ClaudeHome 'projects') -Recurse -Filter ($SessionId + '.jsonl') -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($hit) { return $hit.FullName }
    return $null
}

function Get-CTranscriptSummary {
    # jsonl 을 훑어 사용자/assistant 메시지 수, 마지막 레코드 종류, 마지막 assistant 텍스트 길이를 돌려준다.
    param([Parameter(Mandatory)][string]$Path)
    $lines = [System.IO.File]::ReadAllLines($Path, (Get-CUtf8NoBom))
    $user = 0; $asst = 0; $lastType = ''; $lastAsstLen = 0; $lastAsstStop = ''; $bad = 0
    foreach ($l in $lines) {
        if ($l.Trim().Length -eq 0) { continue }
        try { $o = $l | ConvertFrom-Json } catch { $bad++; continue }
        if (-not $o.PSObject.Properties['type']) { continue }
        $lastType = $o.type
        if ($o.type -eq 'user') { $user++ }
        if ($o.type -eq 'assistant') {
            $asst++
            $len = 0
            try {
                if ($o.message.content -is [string]) { $len = $o.message.content.Length }
                else { foreach ($c in $o.message.content) { if ($c.PSObject.Properties['text']) { $len += $c.text.Length } } }
                if ($o.message.PSObject.Properties['stop_reason']) { $lastAsstStop = "$($o.message.stop_reason)" }
            } catch { }
            $lastAsstLen = $len
        }
    }
    return [pscustomobject]@{ path = $Path; lines = $lines.Count; userMsgs = $user; assistantMsgs = $asst; lastType = $lastType; lastAssistantTextLen = $lastAsstLen; lastAssistantStopReason = $lastAsstStop; unparsableLines = $bad }
}

function Get-CRosterWorker {
    # 문서화되지 않은 내부 파일(~/.claude/daemon/roster.json)을 읽기 전용으로 본다. 증거 보강용이며 설계는 여기에 기대지 않는다.
    param([Parameter(Mandatory)][string]$ShortId)
    $p = Join-Path (Get-CPaths).ClaudeHome 'daemon\roster.json'
    if (-not (Test-Path $p)) { return $null }
    try {
        $r = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($r.workers.PSObject.Properties[$ShortId]) {
            $w = $r.workers.$ShortId
            return [pscustomobject]@{ pid = $w.pid; procStart = $w.procStart; sessionId = $w.sessionId; cwd = $w.cwd; isolation = $w.dispatch.isolation; envIsolation = $w.dispatch.env.CLAUDE_BG_ISOLATION; cliVersion = $w.cliVersion }
        }
    } catch { }
    return $null
}

function Get-CJobState {
    # ~/.claude/jobs/<short>/state.json (문서화되지 않음, 읽기 전용).
    param([Parameter(Mandatory)][string]$ShortId)
    $p = Join-Path (Get-CPaths).ClaudeHome ('jobs\' + $ShortId + '\state.json')
    if (-not (Test-Path $p)) { return $null }
    try {
        $s = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
        $h = [ordered]@{}
        foreach ($n in 'state','tempo','bgIsolation','sessionId','resumeSessionId','daemonShort','cliVersion','cwd','name','nameSource','backend') {
            if ($s.PSObject.Properties[$n]) { $h[$n] = $s.$n }
        }
        return [pscustomobject]$h
    } catch { return $null }
}

function Get-CFileHash256 {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { return '(없음)' }
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash
}

function Get-CShortId {
    param([Parameter(Mandatory)][string]$SessionId)
    return $SessionId.Substring(0, 8)
}

function Test-CPs51Parse {
    # 스크립트가 PS 5.1 파서를 통과하는지 확인한다(구문 오류 목록을 돌려준다).
    param([Parameter(Mandatory)][string]$Path)
    $tokens = $null; $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors) | Out-Null
    return ,@($errors)
}

function Show-CBanner {
    param([string]$Text)
    Write-Host ''
    Write-Host ('=' * 72)
    Write-Host $Text
    Write-Host ('=' * 72)
}
