# spikes/common/cce-spike-hook.ps1 — S5(b) 용 PowerShell 훅 변형. 로그만 남긴다(상태·제목은 bash 판이 담당).
# 설치 형식: shell:"powershell" 의 command 문자열, 또는 powershell.exe -File 의 exec 형식.
param(
    [string]$Event = 'unknown',
    [string]$Variant = 'shell-ps',
    [string]$LogDir = ''
)
$t0 = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
if ($LogDir -eq '') { $LogDir = Join-Path (Split-Path -Parent $PSScriptRoot) '_log' }
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
$payload = [Console]::In.ReadToEnd()
$sid = ''
if ($payload -match '"session_id"\s*:\s*"([^"]*)"') { $sid = $Matches[1] }
$t1 = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$row = [ordered]@{
    ts = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ'); t_ms = $t1; event = $Event; variant = $Variant; shell = 'powershell'
    pid = $PID; ppid = 0
    WT_SESSION = [string]$env:WT_SESSION; CCE_PANE_KEY = [string]$env:CCE_PANE_KEY
    WT_PROFILE_ID = [string]$env:WT_PROFILE_ID; TERM_PROGRAM = [string]$env:TERM_PROGRAM
    script = $PSCommandPath; session_id = $sid; source = ''; notification_type = ''; reason = ''; session_title = ''
    prompt_head = ''; cwd = ''; skipped = $true; status_written = ''; title_emitted = ''
    dur_ms = ($t1 - $t0); payload = 'see-bash-variant'
}
$line = ($row | ConvertTo-Json -Compress -Depth 4) + "`n"
[System.IO.File]::AppendAllText((Join-Path $LogDir 'hooks.jsonl'), $line, (New-Object System.Text.UTF8Encoding($false)))
exit 0
