# _hook-logger.ps1 — 스파이크용 임시 훅 로거 (_cce_spike). Windows PowerShell 5.1.
# Claude Code 가 exec 형식(args)으로 실행한다. stdin 의 훅 JSON 과 환경 변수, 프로세스 조상 체인을 jsonl 에 남긴다.
# SessionStart / UserPromptSubmit 에서 -TitleFile 이 존재하면 그 내용을 sessionTitle 로 출력한다(S4(b)).
# 항상 exit 0. Claude 를 막지 않는다.
param(
    [string]$Event = '',
    [string]$Tag = '_cce_spike',
    [string]$Log = '',
    [string]$TitleFile = ''
)

$ErrorActionPreference = 'Continue'
$utf8 = New-Object System.Text.UTF8Encoding $false

# stdin 을 UTF-8 로 읽는다(콘솔 코드 페이지와 무관하게).
$raw = ''
try {
    $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), $utf8)
    $raw = $reader.ReadToEnd()
} catch { $raw = '' }

$payload = $null
try { if ($raw.Trim().Length -gt 0) { $payload = $raw | ConvertFrom-Json } } catch { $payload = $null }

# 환경: 계획 S3-9 가 보는 키 + CLAUDE*/CCE* 전부
$envRec = [ordered]@{}
foreach ($k in 'WT_SESSION','WT_PROFILE_ID','CCE_PANE_KEY','CCE_SPIKE_MARK','TERM_PROGRAM','SESSIONNAME') {
    $v = [Environment]::GetEnvironmentVariable($k)
    $envRec[$k] = $v
}
foreach ($item in (Get-ChildItem Env: | Where-Object { $_.Name -like 'CLAUDE*' -or $_.Name -like 'CCE*' })) {
    if (-not $envRec.Contains($item.Name)) { $envRec[$item.Name] = $item.Value }
}

# 프로세스 조상 체인(최대 6단계): 훅이 supervisor 워커에서 떴는지, WT 탭 아래인지 본다.
$chain = @()
try {
    $pidCur = $PID
    for ($i = 0; $i -lt 6; $i++) {
        $p = Get-CimInstance Win32_Process -Filter "ProcessId=$pidCur" -ErrorAction Stop
        if (-not $p) { break }
        $chain += [pscustomobject]@{ pid = $p.ProcessId; name = $p.Name; ppid = $p.ParentProcessId }
        if (-not $p.ParentProcessId -or $p.ParentProcessId -eq 0) { break }
        $pidCur = $p.ParentProcessId
    }
} catch { }

$rec = [ordered]@{
    ts        = (Get-Date).ToUniversalTime().ToString('o')
    tag       = $Tag
    event     = $Event
    hookPid   = $PID
    payload   = $payload
    rawLength = $raw.Length
    env       = $envRec
    ancestry  = $chain
}

if ($Log) {
    try {
        $dir = Split-Path $Log -Parent
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
        $line = ($rec | ConvertTo-Json -Compress -Depth 8)
        [System.IO.File]::AppendAllText($Log, $line + [Environment]::NewLine, $utf8)
    } catch { }
}

# S4(b): 제목 파일이 있으면 sessionTitle 을 낸다.
if ($TitleFile -and (Test-Path $TitleFile) -and ($Event -eq 'SessionStart' -or $Event -eq 'UserPromptSubmit')) {
    try {
        $title = ([System.IO.File]::ReadAllText($TitleFile, $utf8)).Trim()
        if ($title.Length -gt 0) {
            $out = @{ hookSpecificOutput = @{ hookEventName = $Event; sessionTitle = $title } } | ConvertTo-Json -Compress -Depth 4
            $stdout = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), $utf8)
            $stdout.Write($out)
            $stdout.Flush()
            if ($Log) {
                [System.IO.File]::AppendAllText($Log, ((@{ ts = (Get-Date).ToUniversalTime().ToString('o'); tag = $Tag; event = $Event; emitted = $out } | ConvertTo-Json -Compress) + [Environment]::NewLine), $utf8)
            }
        }
    } catch { }
}

exit 0
