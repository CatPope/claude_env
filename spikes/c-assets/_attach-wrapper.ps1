# _attach-wrapper.ps1 — S3-4 용. `claude attach <id>` 를 자식으로 띄우고, 계획 4.1 §6 의 구분 논리를 흉내낸다.
#   - SetConsoleCtrlHandler(P/Invoke) 로 CTRL_CLOSE_EVENT 를 받으면 즉시 플래그 + 로그(windowClosed)
#   - CTRL_C / CTRL_BREAK 는 TRUE 를 돌려 무시(자식 claude 가 자기 처리기로 받는다)
#   - 자식이 끝나면 300ms 기다린 뒤 플래그를 보고 detached / windowClosed 를 기록
# WT 탭에서 직접 실행한다:
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\cce-spike\c\_attach-wrapper.ps1 -Id <short> -Run 1 -Expected detach
# 주의: Windows PowerShell 5.1 에서만 검증. PS 7 은 대상이 아니다.
param(
    [Parameter(Mandatory = $true)][string]$Id,
    [int]$Run = 0,
    [ValidateSet('detach', 'close', 'exit-then-close')][string]$Expected = 'detach',
    [string]$Log = '',
    [string]$FlagDir = ''
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
if (-not $Log) { $Log = Join-Path $PSScriptRoot '_attach-wrapper.jsonl' }
if (-not $FlagDir) { $FlagDir = $PSScriptRoot }
$flag = Join-Path $FlagDir ("closing-{0}.flag" -f $Run)
if (Test-Path $flag) { Remove-Item $flag -Force }

function Write-Line {
    param([hashtable]$Rec)
    if (-not $Rec.ContainsKey('ts')) { $Rec['ts'] = (Get-Date).ToUniversalTime().ToString('o') }
    [System.IO.File]::AppendAllText($Log, (($Rec | ConvertTo-Json -Compress -Depth 6) + [Environment]::NewLine), $utf8)
}

# --- 콘솔 컨트롤 처리기 (C#, Add-Type) ---
$csharp = @'
using System;
using System.IO;
using System.Runtime.InteropServices;
public static class CceCtrl {
    public delegate bool HandlerRoutine(int ctrlType);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetConsoleCtrlHandler(HandlerRoutine handler, bool add);
    static HandlerRoutine _keep;            // GC 방지
    public static string FlagPath;
    public static string LogPath;
    public static int Run;
    public static volatile bool Closing;
    public static bool Handler(int t) {
        // 0=CTRL_C 1=CTRL_BREAK 2=CTRL_CLOSE 5=CTRL_LOGOFF 6=CTRL_SHUTDOWN
        if (t == 2 || t == 5 || t == 6) {
            Closing = true;
            try {
                string line = "{\"ts\":\"" + DateTime.UtcNow.ToString("o") + "\",\"kind\":\"ctrl\",\"run\":" + Run +
                              ",\"ctrlType\":" + t + ",\"outcome\":\"windowClosed\"}";
                File.AppendAllText(LogPath, line + Environment.NewLine);
                File.WriteAllText(FlagPath, "1");
            } catch { }
            return true;   // OS 는 처리기가 돌아온 뒤(또는 5초 뒤) 어차피 프로세스를 끝낸다
        }
        if (t == 0 || t == 1) { return true; }   // CTRL_C / CTRL_BREAK 무시
        return false;
    }
    public static bool Install() {
        _keep = new HandlerRoutine(Handler);
        return SetConsoleCtrlHandler(_keep, true);
    }
}
'@
$handlerInstalled = $false
$handlerError = ''
try {
    if (-not ('CceCtrl' -as [type])) { Add-Type -TypeDefinition $csharp -Language CSharp }
    [CceCtrl]::FlagPath = $flag
    [CceCtrl]::LogPath = $Log
    [CceCtrl]::Run = $Run
    $handlerInstalled = [CceCtrl]::Install()
} catch { $handlerError = "$_" }

$claude = (Get-Command claude.exe -ErrorAction SilentlyContinue)
if (-not $claude) { $claude = Get-Command claude }

Write-Line @{ kind = 'start'; run = $Run; expected = $Expected; id = $Id; wrapperPid = $PID; wtSession = $env:WT_SESSION; handlerInstalled = $handlerInstalled; handlerError = $handlerError; psVersion = $PSVersionTable.PSVersion.ToString() }

Write-Host ("[S3-4] run={0} expected={1} handler={2}" -f $Run, $Expected, $handlerInstalled)
Write-Host "[S3-4] claude attach $Id 시작. detach 는 /exit 또는 ←, 닫기는 탭의 X."

$p = Start-Process -FilePath $claude.Source -ArgumentList @('attach', $Id) -NoNewWindow -PassThru
$childStart = $null
try { $childStart = $p.StartTime.ToUniversalTime().ToString('o') } catch { }
Write-Line @{ kind = 'child'; run = $Run; childPid = $p.Id; childStart = $childStart }

$p.WaitForExit()
$exitCode = $null
try { $exitCode = $p.ExitCode } catch { }

Start-Sleep -Milliseconds 300
if ([CceCtrl]::Closing -or (Test-Path $flag)) {
    # 처리기가 이미 windowClosed 를 썼다. 낮은 상태로 덮어쓰지 않는다(우선순위 강제).
    Write-Line @{ kind = 'end'; run = $Run; outcome = 'windowClosed'; via = 'flag-after-child-exit'; childExit = $exitCode }
} else {
    Write-Line @{ kind = 'end'; run = $Run; outcome = 'detached'; childExit = $exitCode }
    Write-Host ("[S3-4] run={0} → detached (exit={1})" -f $Run, $exitCode)
}
