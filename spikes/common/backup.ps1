<#
.SYNOPSIS
  스파이크가 건드릴 수 있는 사용자 설정 파일을 spikes/_backup/<타임스탬프>/ 아래에 바이트 그대로 복사한다.
.DESCRIPTION
  대상:
    - Windows Terminal settings.json, state.json (LocalState of Microsoft.WindowsTerminal_8wekyb3d8bbwe)
    - %USERPROFILE%\.claude\settings.json
    - PowerShell 5.1 $PROFILE (CurrentUserCurrentHost)  = <내 문서>\WindowsPowerShell\Microsoft.PowerShell_profile.ps1
    - PowerShell 7 프로필                                  = <내 문서>\PowerShell\Microsoft.PowerShell_profile.ps1
    - %USERPROFILE%\.bashrc, .bash_profile
  없는 파일은 manifest 에 exists=false 로 기록만 한다(복원 때 "원래 없었음"을 알기 위해).
  복사 뒤 SHA-256 을 다시 계산해 원본과 같은지 확인한다.
.PARAMETER WhatIf
  실제로 복사하지 않고 무엇을 복사할지(대상 경로, 존재 여부, 크기, 해시)만 출력한다.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File spikes\common\backup.ps1 -WhatIf
  powershell -NoProfile -ExecutionPolicy Bypass -File spikes\common\backup.ps1 -Label before-S1
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param([string]$Label = '')

. "$PSScriptRoot\common.ps1"
Initialize-SpikeDirs

$docs = [Environment]::GetFolderPath('MyDocuments')
$targets = @(
    [pscustomobject]@{ key = 'wt-settings';   path = $script:WtSettingsPath },
    [pscustomobject]@{ key = 'wt-state';      path = $script:WtStatePath },
    [pscustomobject]@{ key = 'claude-settings'; path = $script:ClaudeSettingsPath },
    [pscustomobject]@{ key = 'ps51-profile';  path = (Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1') },
    [pscustomobject]@{ key = 'ps7-profile';   path = (Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1') },
    [pscustomobject]@{ key = 'bashrc';        path = (Join-Path $env:USERPROFILE '.bashrc') },
    [pscustomobject]@{ key = 'bash_profile';  path = (Join-Path $env:USERPROFILE '.bash_profile') }
)

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if ($Label -ne '') { $stamp = "$stamp-$Label" }
$dest = Join-Path $script:BackupRoot $stamp

Write-Step 'backup' ("대상 폴더: {0}" -f $dest)
$manifest = @()
$i = 0
foreach ($t in $targets) {
    $i++
    $exists = Test-Path -LiteralPath $t.path -PathType Leaf
    $entry = [pscustomobject]@{
        key = $t.key; source = $t.path; exists = $exists
        size = $null; sha256 = $null; backupFile = $null; verified = $null
    }
    if ($exists) {
        $fi = Get-Item -LiteralPath $t.path
        $entry.size = $fi.Length
        $entry.sha256 = Get-FileSha256 $t.path
        $entry.backupFile = ('{0:00}-{1}{2}' -f $i, $t.key, $fi.Extension)
    }
    $manifest += $entry
    if ($exists) {
        Write-Host ("  [{0}] {1}  ({2} bytes, sha256 {3}...)" -f '있음', $t.path, $entry.size, $entry.sha256.Substring(0, 12))
    } else {
        Write-Host ("  [{0}] {1}" -f '없음', $t.path)
    }
}

if ($WhatIfPreference) {
    Write-Step 'backup' 'WhatIf: 위 파일들을 복사할 예정이다. 실제로 복사하지 않았다.'
    return
}

if ($PSCmdlet.ShouldProcess($dest, '백업 폴더 생성 및 복사')) {
    New-Item -ItemType Directory -Path $dest | Out-Null
    Write-Touched 'MKDIR' $dest
    foreach ($m in $manifest) {
        if (-not $m.exists) { continue }
        $to = Join-Path $dest $m.backupFile
        Copy-Item -LiteralPath $m.source -Destination $to
        $after = Get-FileSha256 $to
        $m.verified = ($after -eq $m.sha256)
        Write-Touched 'COPY' ("{0} -> {1}  [{2}]" -f $m.source, $to, $(if ($m.verified) { 'hash OK' } else { 'HASH MISMATCH' }))
        if (-not $m.verified) { throw "복사 검증 실패: $($m.source)" }
    }
    $manifestPath = Join-Path $dest 'manifest.json'
    Write-JsonAtomic $manifestPath ([pscustomobject]@{
        createdAt = (Get-Date).ToString('o'); label = $Label; host = $env:COMPUTERNAME
        psVersion = $PSVersionTable.PSVersion.ToString(); entries = $manifest })
    Write-Touched 'WRITE' $manifestPath
    Write-Step 'backup' ("완료. 복원: powershell -NoProfile -ExecutionPolicy Bypass -File spikes\common\restore.ps1 -Timestamp {0}" -f $stamp)
}
