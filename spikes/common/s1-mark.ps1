# spikes/common/s1-mark.ps1 — S1(c)(d) 용 표식. PowerShell 5.1 / 7 pane 에서 실행한다.
#   사용: .\spikes\common\s1-mark.ps1 before|after [-Label x]
param([string]$Phase = 'before', [string]$Label = '')
. "$PSScriptRoot\common.ps1"
Initialize-SpikeDirs
$kind = 'ps' + $PSVersionTable.PSVersion.Major
$row = [ordered]@{
    ts = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'); phase = $Phase; label = $Label; shell = $kind; distro = ''
    cwd = (Get-Location).ProviderPath; WT_SESSION = [string]$env:WT_SESSION; WT_PROFILE_ID = [string]$env:WT_PROFILE_ID; pid = $PID }
Add-Jsonl (Join-Path $script:LogDir 's1-panes.jsonl') $row
Write-Host ("[s1-mark] phase={0} shell={1} cwd={2} WT_SESSION={3} WT_PROFILE_ID={4}" -f $Phase, $kind, $row.cwd, $env:WT_SESSION, $env:WT_PROFILE_ID)
