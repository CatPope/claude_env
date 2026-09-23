<#
.SYNOPSIS
  backup.ps1 이 만든 백업을 원래 위치로 되돌리고 SHA-256 으로 검증한다.
.PARAMETER Timestamp
  spikes/_backup/ 아래 폴더 이름. 생략하면 가장 최근 폴더.
.PARAMETER Only
  일부 키만 복원(예: -Only wt-settings,claude-settings). 키는 manifest.json 의 key.
.PARAMETER RemoveCreated
  백업 시점에 없었는데 지금은 있는 파일을 삭제한다(기본은 경고만).
.PARAMETER WhatIf
  실제로 쓰지 않고 무엇을 되돌릴지만 출력한다.
.NOTES
  Windows Terminal 이 실행 중이면 state.json 은 WT 가 곧 덮어쓰므로 WT 를 완전히 닫고 실행하라(경고를 띄운다).
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Timestamp = '',
    [string[]]$Only = @(),
    [switch]$RemoveCreated
)

. "$PSScriptRoot\common.ps1"
$Only = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })

if ($Timestamp -eq '') {
    $latest = Get-ChildItem -Path $script:BackupRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'manifest.json') } |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($null -eq $latest) { throw "백업 폴더가 없다: $($script:BackupRoot)" }
    $Timestamp = $latest.Name
}
$dir = Join-Path $script:BackupRoot $Timestamp
$manifestPath = Join-Path $dir 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "manifest.json 이 없다: $manifestPath" }
$manifest = Read-Json $manifestPath
Write-Step 'restore' ("백업 {0} (만든 시각 {1})" -f $Timestamp, $manifest.createdAt)

if (@(Get-WtProcesses).Count -gt 0) {
    Write-Warning 'WindowsTerminal.exe 가 실행 중이다. WT 설정·state.json 은 WT 가 다시 덮어쓸 수 있다. WT 를 모두 닫은 뒤 실행하는 편이 안전하다.'
}

$results = @()
foreach ($m in $manifest.entries) {
    if ($Only.Count -gt 0 -and ($Only -notcontains $m.key)) { continue }
    $r = [pscustomobject]@{ key = $m.key; path = $m.source; action = ''; ok = $null }
    if ($m.exists) {
        $from = Join-Path $dir $m.backupFile
        if (-not (Test-Path -LiteralPath $from)) { $r.action = 'MISSING-BACKUP'; $r.ok = $false; $results += $r; continue }
        $backupHash = Get-FileSha256 $from
        if ($backupHash -ne $m.sha256) { $r.action = 'BACKUP-CORRUPT'; $r.ok = $false; $results += $r; continue }
        $current = Get-FileSha256 $m.source
        if ($current -eq $m.sha256) { $r.action = 'UNCHANGED'; $r.ok = $true; $results += $r; continue }
        if ($PSCmdlet.ShouldProcess($m.source, "백업 $($m.backupFile) 으로 되돌리기")) {
            $parent = Split-Path -Parent $m.source
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
            Copy-Item -LiteralPath $from -Destination $m.source -Force
            $after = Get-FileSha256 $m.source
            $r.ok = ($after -eq $m.sha256)
            $r.action = $(if ($r.ok) { 'RESTORED' } else { 'HASH-MISMATCH' })
            Write-Touched 'WRITE' ("{0}  [{1}]" -f $m.source, $r.action)
        } else { $r.action = 'WOULD-RESTORE'; $r.ok = $true }
    } else {
        if (Test-Path -LiteralPath $m.source) {
            if ($RemoveCreated) {
                if ($PSCmdlet.ShouldProcess($m.source, '백업 시점에 없던 파일 삭제')) {
                    Remove-Item -LiteralPath $m.source -Force
                    Write-Touched 'DELETE' $m.source
                    $r.action = 'DELETED'; $r.ok = $true
                } else { $r.action = 'WOULD-DELETE'; $r.ok = $true }
            } else {
                $r.action = 'NEW-FILE-KEPT(-RemoveCreated 로 삭제 가능)'; $r.ok = $true
            }
        } else { $r.action = 'ABSENT-AS-BEFORE'; $r.ok = $true }
    }
    $results += $r
}

Write-Host ''
$results | Format-Table key, action, ok, path -AutoSize | Out-String | Write-Host
$bad = @($results | Where-Object { $_.ok -eq $false })
if ($bad.Count -gt 0) { Write-Step 'restore' ("실패 {0}건. 위 표를 확인하라." -f $bad.Count); exit 1 }
Write-Step 'restore' '모든 항목이 백업 해시와 일치한다.'
