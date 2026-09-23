# _protocol-handler.ps1 — S3-8 사전 점검용 프로토콜 처리기. `cce-spike://...` URI 클릭 활성화가 도착하면 기록한다.
# 레지스트리 HKCU\Software\Classes\cce-spike 가 이 스크립트를 가리킨다(S3-bg-attach.ps1 -Step S3-8 -Phase prepare 가 등록, cleanup 이 제거).
# `_protocol-attach.enabled` 파일이 있으면 2단계(wt -w 0 new-tab ... claude attach <id>)까지 실행한다.
param(
    [string]$Uri = '',
    [string]$Log = ''
)
$ErrorActionPreference = 'Continue'
$utf8 = New-Object System.Text.UTF8Encoding $false
if (-not $Log) { $Log = Join-Path $PSScriptRoot '_protocol-handler.jsonl' }

$id = ''
$m = [regex]::Match($Uri, 'cce-spike://attach/([0-9a-f]{8})')
if ($m.Success) { $id = $m.Groups[1].Value }

$stage2 = $false
$stage2Cmd = ''
$stage2Error = ''
$enableFlag = Join-Path $PSScriptRoot '_protocol-attach.enabled'
if ($id -and (Test-Path $enableFlag)) {
    try {
        $wt = (Get-Command wt.exe -ErrorAction SilentlyContinue)
        if ($wt) { $wtPath = $wt.Source } else { $wtPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe' }
        # 계획 4.2 대체 순서 1 의 두 번째 단계와 같은 형태. 제품에서는 `cce claude --attach-session <id>` 가 이 자리다.
        $stage2Cmd = "$wtPath -w 0 new-tab -d C:\cce-spike\c powershell -NoProfile -NoExit -Command claude attach $id"
        Start-Process -FilePath $wtPath -ArgumentList @('-w', '0', 'new-tab', '-d', 'C:\cce-spike\c', 'powershell', '-NoProfile', '-NoExit', '-Command', "claude attach $id")
        $stage2 = $true
    } catch { $stage2Error = "$_" }
}

$rec = [ordered]@{
    ts          = (Get-Date).ToUniversalTime().ToString('o')
    kind        = 'protocol-activation'
    uri         = $Uri
    id          = $id
    handlerPid  = $PID
    stage2      = $stage2
    stage2Cmd   = $stage2Cmd
    stage2Error = $stage2Error
}
try { [System.IO.File]::AppendAllText($Log, (($rec | ConvertTo-Json -Compress -Depth 4) + [Environment]::NewLine), $utf8) } catch { }
exit 0
