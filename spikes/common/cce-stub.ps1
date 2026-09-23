<#
.SYNOPSIS
  cce claude 실행기의 대역(스파이크용). WT pane 안에서 실행한다.
.DESCRIPTION
  계획 4.1절을 최소한으로 흉내 낸다:
    - 세션 ID(UUID)를 미리 만들어 claude --session-id <uuid> 로 넘긴다(-ResumeId 면 --resume <id>).
    - 자식에 CCE_PANE_KEY(=WT_SESSION)를 넘긴다.
    - SetConsoleCtrlHandler 를 등록한다(C#, PowerShell 스레드와 무관하게 동작).
        CTRL_C / CTRL_BREAK → TRUE 를 돌려 무시.
        CTRL_CLOSE_EVENT   → 원자적 closing 플래그 → 상태 파일(_log/status/<uuid>.status)을 읽어
                             busy|waiting 이면 state=interrupted + <uuid>.interrupted 플래그, 그 밖이면 windowClosed 를
                             _log/registry.jsonl 에 추가(쓰기까지 걸린 ms 기록).
    - 자식이 끝나면 300ms 기다린 뒤 closing 플래그가 없을 때만 closed 를 기록하고, -LingerSeconds 만큼 더 살아 있는다
      (S2(e) 경쟁 시험: 자식 종료 직후 창을 닫으면 windowClosed 가 closed 를 이겨야 한다).
  레지스트리는 append-only 이며, 분석기가 우선순위(windowClosed/interrupted > closed)로 최종 상태를 정한다.
.EXAMPLE
  .\spikes\common\cce-stub.ps1 -Scenario busy
  .\spikes\common\cce-stub.ps1 -Scenario busy -Resume            # 같은 시나리오의 마지막 중단 세션을 --resume
  .\spikes\common\cce-stub.ps1 -Scenario s4 -ClaudeArgs @('--model','sonnet')
#>
param(
    [string]$Scenario = 'default',
    [switch]$Resume,
    [string]$ResumeId = '',
    [string[]]$ClaudeArgs = @(),
    [int]$LingerSeconds = 3,
    [string]$Tag = 'stub'
)
. "$PSScriptRoot\common.ps1"
Initialize-SpikeDirs
$ClaudeArgs = @($ClaudeArgs | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })

if (-not $env:WT_SESSION) {
    Write-Warning 'WT_SESSION 이 없다(Windows Terminal 이 아닌 곳). cce 는 이때 기록 없이 claude 를 그대로 실행한다. 여기서도 CCE_PANE_KEY 를 넣지 않는다.'
}

if (-not ([System.Management.Automation.PSTypeName]'CceSpike.CtrlStub').Type) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Runtime.InteropServices;
namespace CceSpike {
  public static class CtrlStub {
    public delegate bool HandlerRoutine(uint ctrlType);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetConsoleCtrlHandler(HandlerRoutine handler, bool add);
    static HandlerRoutine _keep; static int _closing; static string _registry, _runId, _uuid, _statusFile, _flagFile, _closeFile;
    public static bool Closing { get { return Volatile.Read(ref _closing) == 1; } }
    public static void Install(string registry, string runId, string uuid, string statusFile, string flagFile, string closeFile) {
      _registry = registry; _runId = runId; _uuid = uuid; _statusFile = statusFile; _flagFile = flagFile; _closeFile = closeFile;
      _keep = new HandlerRoutine(Handler);
      if (!SetConsoleCtrlHandler(_keep, true)) throw new Exception("SetConsoleCtrlHandler failed: " + Marshal.GetLastWin32Error());
    }
    static string Esc(string s) { return (s ?? "").Replace("\\", "\\\\").Replace("\"", "\\\""); }
    public static void Append(string state, string extraJson) {
      string line = "{\"ts\":\"" + DateTime.UtcNow.ToString("o") + "\",\"runId\":\"" + Esc(_runId) + "\",\"uuid\":\"" + Esc(_uuid) +
        "\",\"state\":\"" + state + "\"" + (string.IsNullOrEmpty(extraJson) ? "" : "," + extraJson) + "}\n";
      File.AppendAllText(_registry, line, new UTF8Encoding(false));
    }
    static bool Handler(uint t) {
      if (t == 0 || t == 1) return true;                 // CTRL_C_EVENT, CTRL_BREAK_EVENT: 무시(자식이 처리)
      if (t == 2 || t == 5 || t == 6) {                  // CLOSE, LOGOFF, SHUTDOWN
        var sw = System.Diagnostics.Stopwatch.StartNew();
        Interlocked.Exchange(ref _closing, 1);
        string last = "";
        try { if (File.Exists(_statusFile)) last = File.ReadAllText(_statusFile).Trim(); } catch { }
        bool interrupted = (last == "busy" || last == "waiting");
        string state = interrupted ? "interrupted" : "windowClosed";
        try { if (interrupted) File.WriteAllText(_flagFile, DateTime.UtcNow.ToString("o")); } catch { }
        try { Append(state, "\"ctrlType\":" + t + ",\"lastStatus\":\"" + Esc(last) + "\",\"interruptedFlag\":" + (interrupted ? "true" : "false") + ",\"handlerWriteMs\":" + sw.ElapsedMilliseconds); } catch { }
        try { File.WriteAllText(_closeFile, "{\"state\":\"" + state + "\",\"handlerWriteMs\":" + sw.ElapsedMilliseconds + "}"); } catch { }
        return false;                                     // 기본 처리(종료)로 넘긴다
      }
      return false;
    }
  }
}
'@
}

$runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $Scenario
if ($ResumeId -ne '') {
    $uuid = $ResumeId
} elseif ($Resume) {
    # 같은 시나리오의 마지막 interrupted/windowClosed 기록을 찾는다.
    $rows = Read-Jsonl $script:RegistryLog
    $cand = @($rows | Where-Object { $_.scenario -eq $Scenario -and $_.state -eq 'active' } | Select-Object -ExpandProperty uuid -Unique)
    $pick = $null
    foreach ($u in ($cand | Select-Object -Last 20)) {
        $st = @($rows | Where-Object { $_.uuid -eq $u -and ($_.state -eq 'interrupted' -or $_.state -eq 'windowClosed') })
        if ($st.Count -gt 0) { $pick = $u }
    }
    if ($null -eq $pick) { throw "시나리오 '$Scenario' 에서 복원할 세션(interrupted/windowClosed)이 없다." }
    $uuid = $pick
} else {
    $uuid = [guid]::NewGuid().ToString()
}

$statusFile = Join-Path $script:StatusDir "$uuid.status"
$flagFile   = Join-Path $script:StatusDir "$uuid.interrupted"
$closeFile  = Join-Path $script:LogDir "close-$runId.json"
if ($env:WT_SESSION) { $env:CCE_PANE_KEY = $env:WT_SESSION } else { Remove-Item Env:CCE_PANE_KEY -ErrorAction SilentlyContinue }

[CceSpike.CtrlStub]::Install($script:RegistryLog, $runId, $uuid, $statusFile, $flagFile, $closeFile)

$exe = Get-ClaudeExe
if ($null -eq $exe) { throw 'claude 실행 파일을 찾지 못했다.' }
if ($Resume -or $ResumeId -ne '') { $argv = @('--resume', $uuid) + $ClaudeArgs }
else { $argv = @('--session-id', $uuid) + $ClaudeArgs }

Add-Jsonl $script:RegistryLog ([ordered]@{
    ts = [DateTime]::UtcNow.ToString('o'); runId = $runId; uuid = $uuid; state = 'active'; scenario = $Scenario
    wtSession = [string]$env:WT_SESSION; paneKey = [string]$env:CCE_PANE_KEY; cwd = (Get-Location).Path
    resume = [bool]($Resume -or $ResumeId -ne ''); interruptedFlagBefore = (Test-Path -LiteralPath $flagFile)
    stubPid = $PID; argv = ($argv -join ' ') })
Write-Step $Tag ("runId={0} uuid={1} scenario={2}" -f $runId, $uuid, $Scenario)
Write-Step $Tag ("실행: claude {0}" -f ($argv -join ' '))

$p = Start-Process -FilePath $exe -ArgumentList $argv -NoNewWindow -PassThru -Wait
$code = $p.ExitCode
Start-Sleep -Milliseconds 300
if ([CceSpike.CtrlStub]::Closing) {
    Write-Step $Tag 'closing 플래그가 서 있어 closed 를 쓰지 않는다.'
} else {
    [CceSpike.CtrlStub]::Append('closed', ('"exitCode":' + $code + ',"childPid":' + $p.Id))
    Write-Step $Tag ("자식 종료(exit {0}). closed 기록. {1}초 더 대기(경쟁 시험용)..." -f $code, $LingerSeconds)
    Start-Sleep -Seconds $LingerSeconds
    if ([CceSpike.CtrlStub]::Closing) { Write-Step $Tag 'linger 중 CTRL_CLOSE 를 받았다.' }
}
