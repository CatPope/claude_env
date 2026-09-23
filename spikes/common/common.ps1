# spikes/common/common.ps1
# 스파이크 스크립트가 공통으로 dot-source 하는 도우미.  Windows PowerShell 5.1 기준(&&, 삼항, ?? 사용 금지).
#   . "$PSScriptRoot\common\common.ps1"     (S*.ps1 에서)
#   . "$PSScriptRoot\common.ps1"            (common\*.ps1 에서)
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

# ---------- 경로 ----------
$script:CommonDir  = $PSScriptRoot
$script:SpikeRoot  = Split-Path -Parent $script:CommonDir
$script:RepoRoot   = Split-Path -Parent $script:SpikeRoot
$script:LogDir     = Join-Path $script:SpikeRoot '_log'
$script:StatusDir  = Join-Path $script:LogDir 'status'
$script:BackupRoot = Join-Path $script:SpikeRoot '_backup'

$script:WtLocalState   = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
$script:WtSettingsPath = Join-Path $script:WtLocalState 'settings.json'
$script:WtStatePath    = Join-Path $script:WtLocalState 'state.json'
$script:ClaudeDir      = Join-Path $env:USERPROFILE '.claude'
$script:ClaudeSettingsPath = Join-Path $script:ClaudeDir 'settings.json'
$script:GitBashExe     = 'C:\Program Files\Git\bin\bash.exe'
$script:HookSh         = Join-Path $script:CommonDir 'cce-spike-hook.sh'
$script:HookPs1        = Join-Path $script:CommonDir 'cce-spike-hook.ps1'
$script:HooksLog       = Join-Path $script:LogDir 'hooks.jsonl'
$script:HooksInstalled = Join-Path $script:LogDir 'hooks-installed.json'
$script:RegistryLog    = Join-Path $script:LogDir 'registry.jsonl'   # cce-stub 이 쓰는 pane/세션 레지스트리(append-only)
$script:Marker         = 'cce-spike'   # 설치한 훅을 식별하는 표식(스크립트 파일 이름과 경로에 들어 있다)

# PS 5.1 의 -Encoding UTF8 은 BOM 을 붙이므로, BOM 없는 UTF-8 로 쓸 때는 이 인코더를 쓴다.
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Initialize-SpikeDirs {
    foreach ($d in @($script:LogDir, $script:StatusDir, $script:BackupRoot)) {
        # -WhatIf:$false: backup.ps1 -WhatIf 가 여기까지 전파되어 폴더 생성을 건너뛰지 않게 한다(로그 폴더는 항상 만든다).
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -WhatIf:$false | Out-Null }
    }
}

# ---------- 출력 ----------
function Write-Step([string]$Tag, [string]$Message) {
    Write-Host ("[{0}] {1}" -f $Tag, $Message)
}
function Write-Touched([string]$Action, [string]$Path) {
    # 스크립트가 실제로 건드린 파일은 반드시 이 함수로 한 줄씩 남긴다.
    Write-Host ("  TOUCH {0,-8} {1}" -f $Action, $Path)
}
function Write-Manual([string[]]$Lines) {
    Write-Host ''
    Write-Host '  ---- 사람이 할 일 ----'
    $i = 1
    foreach ($l in $Lines) { Write-Host ("  {0}. {1}" -f $i, $l); $i++ }
    Write-Host ''
}

# ---------- 파일·JSON ----------
function Get-FileSha256([string]$Path) {
    # Get-FileHash 는 -WhatIf 전파에 영향을 받으므로 .NET 으로 직접 계산한다.
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try { $hash = $sha.ComputeHash($fs) } finally { $fs.Dispose(); $sha.Dispose() }
    return (($hash | ForEach-Object { $_.ToString('X2') }) -join '')
}
function Read-TextFile([string]$Path) {
    return [System.IO.File]::ReadAllText($Path)   # BOM 자동 감지
}
function Write-TextFileAtomic([string]$Path, [string]$Content, [switch]$Bom) {
    $tmp = "$Path.tmp-$PID"
    if ($Bom) { $enc = New-Object System.Text.UTF8Encoding($true) } else { $enc = $script:Utf8NoBom }
    [System.IO.File]::WriteAllText($tmp, $Content, $enc)
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}
function Read-Json([string]$Path) {
    return (Read-TextFile $Path | ConvertFrom-Json)
}
function Write-JsonAtomic([string]$Path, $Object) {
    Write-TextFileAtomic -Path $Path -Content ($Object | ConvertTo-Json -Depth 64)
}
function Add-Jsonl([string]$Path, $Object) {
    $line = ($Object | ConvertTo-Json -Depth 32 -Compress) + "`n"
    [System.IO.File]::AppendAllText($Path, $line, $script:Utf8NoBom)
}
function Read-Jsonl([string]$Path) {
    $out = @()
    if (-not (Test-Path -LiteralPath $Path)) { return $out }
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line.Trim().Length -eq 0) { continue }
        try { $out += ($line | ConvertFrom-Json) } catch { }
    }
    return $out
}
function Get-PropNames($Object) {
    # 빈 객체에서 .PSObject.Properties.Name 은 StrictMode 에서 오류가 나므로 항상 이 함수로 키 목록을 얻는다.
    $names = @()
    if ($null -eq $Object) { return $names }
    foreach ($p in $Object.PSObject.Properties) { $names += $p.Name }
    return $names
}
function Test-JsonHasProperty($Object, [string]$Name) {
    return ((Get-PropNames $Object) -contains $Name)
}
function Get-Prop($Object, [string]$Name, $Default = $null) {
    if (Test-JsonHasProperty $Object $Name) { return $Object.$Name }
    return $Default
}

# ---------- 경로 변환 ----------
function ConvertTo-BashPath([string]$WinPath) {
    # C:\a b\c  ->  /c/a b/c   (Git Bash)
    $p = $WinPath -replace '\\', '/'
    if ($p -match '^([A-Za-z]):(.*)$') { return ('/' + $Matches[1].ToLower() + $Matches[2]) }
    return $p
}
function ConvertTo-ForwardSlash([string]$WinPath) { return ($WinPath -replace '\\', '/') }

# ---------- 환경 탐지 ----------
function Get-Pwsh7Path {
    $c = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -ne $c) { return $c.Source }
    $candidate = 'C:\Program Files\PowerShell\7\pwsh.exe'
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    return $null
}
function Get-ClaudeExe {
    $c = Get-Command claude -ErrorAction SilentlyContinue
    if ($null -ne $c) { return $c.Source }
    return $null
}
function Get-WslDistros {
    try {
        $raw = & wsl.exe -l -q 2>$null
        # wsl.exe 는 UTF-16 을 내보내 NUL 이 섞여 나온다.
        $txt = ($raw -join "`n") -replace "`0", ''
        return @($txt -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
    } catch { return @() }
}
function Get-WtProcesses { return @(Get-Process -Name 'WindowsTerminal' -ErrorAction SilentlyContinue) }

# 최상위 WT 창 열거(EnumWindows). 창 클래스 CASCADIA_HOSTING_WINDOW_CLASS 를 센다.
function Initialize-WinApi {
    if (-not ([System.Management.Automation.PSTypeName]'CceSpike.WinApi').Type) {
        Add-Type -Namespace CceSpike -Name WinApi -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder text, int count);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
public static System.Collections.Generic.List<object[]> ListWindows() {
    var list = new System.Collections.Generic.List<object[]>();
    EnumWindows((h, l) => {
        var cls = new System.Text.StringBuilder(256); GetClassName(h, cls, 256);
        var txt = new System.Text.StringBuilder(1024); GetWindowText(h, txt, 1024);
        uint pid; GetWindowThreadProcessId(h, out pid);
        list.Add(new object[] { (long)h, cls.ToString(), txt.ToString(), (int)pid, IsWindowVisible(h) });
        return true; }, IntPtr.Zero);
    return list;
}
'@
    }
}
function Get-WtWindows {
    Initialize-WinApi
    $rows = @()
    foreach ($w in [CceSpike.WinApi]::ListWindows()) {
        if ($w[1] -eq 'CASCADIA_HOSTING_WINDOW_CLASS' -and $w[4]) {
            $rows += [pscustomobject]@{ hwnd = $w[0]; title = $w[2]; pid = $w[3] }
        }
    }
    return $rows
}
function Get-WtWindowCount { return @(Get-WtWindows).Count }

# UI Automation 으로 WT 창의 탭 이름을 모은다(베스트 에포트).
function Get-WtTabNames {
    $out = @()
    try {
        Add-Type -AssemblyName UIAutomationClient
        Add-Type -AssemblyName UIAutomationTypes
        foreach ($w in Get-WtWindows) {
            $root = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$w.hwnd)
            $cond = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::TabItem)
            $tabs = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
            foreach ($t in $tabs) { $out += [pscustomobject]@{ hwnd = $w.hwnd; name = $t.Current.Name } }
        }
    } catch { }
    return $out
}

function Get-CodePoints([string]$Text) {
    $cps = @()
    $i = 0
    while ($i -lt $Text.Length) {
        $cp = [char]::ConvertToUtf32($Text, $i)
        $cps += ('U+{0:X4}' -f $cp)
        if ($cp -gt 0xFFFF) { $i += 2 } else { $i += 1 }
    }
    return $cps
}

function Get-Percentile([double[]]$Values, [double]$P) {
    if ($null -eq $Values -or $Values.Count -eq 0) { return $null }
    $sorted = @($Values | Sort-Object)   # 값이 하나면 스칼라가 되어 .Count 가 없으므로 배열로 감싼다
    $idx = [math]::Ceiling($P / 100.0 * $sorted.Count) - 1
    if ($idx -lt 0) { $idx = 0 }
    if ($idx -ge $sorted.Count) { $idx = $sorted.Count - 1 }
    return [math]::Round($sorted[$idx], 1)
}

# ---------- Claude Code 훅 설치·제거 (표식 기반, 기존 항목 보존) ----------
# 항목 형식은 훅 문서( https://code.claude.com/docs/en/hooks )의 command 훅:
#   hooks.<Event>[] = { matcher?, hooks: [ { type:"command", command, args?, shell?, timeout? } ] }
# 표식: command 또는 args 문자열 어딘가에 'cce-spike' 가 들어 있으면 우리가 넣은 항목이다.
function New-HookEntry {
    param(
        [Parameter(Mandatory)][string]$Event,
        [ValidateSet('exec-bash','shell-bash','shell-ps','exec-ps')][string]$Form = 'exec-bash',
        [string]$ScriptSh = $script:HookSh,
        [string]$ScriptPs1 = $script:HookPs1,
        [string]$Variant = '',
        [int]$Timeout = 10
    )
    if ($Variant -eq '') { $Variant = $Form }
    $logBash = ConvertTo-ForwardSlash $script:LogDir
    switch ($Form) {
        'exec-bash' {
            # exec 형식: 셸을 거치지 않으므로 공백·한글 경로를 인용할 필요가 없다.
            $h = @{ type = 'command'; command = $script:GitBashExe;
                    args = @((ConvertTo-ForwardSlash $ScriptSh), $Event, $Variant, $logBash); timeout = $Timeout }
        }
        'shell-bash' {
            # 기본 셸(Git Bash) 형식: 경로는 슬래시 + 작은따옴표(statusline 문서의 Windows 안내와 같다).
            $h = @{ type = 'command';
                    command = ("'{0}' {1} {2} '{3}'" -f (ConvertTo-ForwardSlash $ScriptSh), $Event, $Variant, $logBash);
                    timeout = $Timeout }
        }
        'shell-ps' {
            $h = @{ type = 'command'; shell = 'powershell';
                    command = ("& '{0}' -Event {1} -Variant {2} -LogDir '{3}'" -f $ScriptPs1, $Event, $Variant, $script:LogDir);
                    timeout = $Timeout }
        }
        'exec-ps' {
            $h = @{ type = 'command'; command = 'powershell.exe';
                    args = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $ScriptPs1, '-Event', $Event, '-Variant', $Variant, '-LogDir', $script:LogDir);
                    timeout = $Timeout }
        }
    }
    return @{ hooks = @($h) }
}

function Test-SpikeHookGroup($Group) {
    if (-not (Test-JsonHasProperty $Group 'hooks')) { return $false }
    foreach ($h in @($Group.hooks)) {
        $cmd = [string](Get-Prop $h 'command' '')
        if ($cmd -like "*$($script:Marker)*") { return $true }
        foreach ($a in @(Get-Prop $h 'args' @())) { if ([string]$a -like "*$($script:Marker)*") { return $true } }
    }
    return $false
}

function Install-SpikeHooks {
    # -Entries: @{ Event='SessionStart'; Group=<New-HookEntry 결과> } 의 배열
    param([Parameter(Mandatory)][hashtable[]]$Entries, [string]$Tag = 'hooks')
    Initialize-SpikeDirs
    $settings = Read-Json $script:ClaudeSettingsPath
    $hadHooksKey = Test-JsonHasProperty $settings 'hooks'
    if (-not $hadHooksKey) {
        $settings | Add-Member -MemberType NoteProperty -Name hooks -Value ([pscustomobject]@{})
    }
    $installed = @()
    foreach ($e in $Entries) {
        $ev = $e.Event
        if (-not (Test-JsonHasProperty $settings.hooks $ev)) {
            $settings.hooks | Add-Member -MemberType NoteProperty -Name $ev -Value @()
        }
        $groupObj = ($e.Group | ConvertTo-Json -Depth 16 | ConvertFrom-Json)
        $settings.hooks.$ev = @($settings.hooks.$ev) + @($groupObj)
        $installed += [pscustomobject]@{ event = $ev; group = $groupObj }
    }
    Write-JsonAtomic $script:ClaudeSettingsPath $settings
    Write-Touched 'EDIT' $script:ClaudeSettingsPath
    $record = [pscustomobject]@{ installedAt = (Get-Date).ToString('o'); tag = $Tag; hooksKeyExisted = $hadHooksKey; entries = $installed }
    Write-JsonAtomic $script:HooksInstalled $record
    Write-Touched 'WRITE' $script:HooksInstalled
    Write-Step $Tag ("훅 {0}개를 {1} 에 추가했다(표식 '{2}'). 실행 중인 Claude 세션은 다음 시작부터 반영된다." -f $installed.Count, $script:ClaudeSettingsPath, $script:Marker)
}

function Remove-SpikeHooks([string]$Tag = 'hooks') {
    if (-not (Test-Path -LiteralPath $script:ClaudeSettingsPath)) { return }
    $settings = Read-Json $script:ClaudeSettingsPath
    if (-not (Test-JsonHasProperty $settings 'hooks')) { Write-Step $Tag 'hooks 키가 없다. 제거할 것이 없다.'; return }
    $removed = 0
    $events = @(Get-PropNames $settings.hooks)
    foreach ($ev in $events) {
        $keep = @()
        foreach ($g in @($settings.hooks.$ev)) {
            if (Test-SpikeHookGroup $g) { $removed++ } else { $keep += $g }
        }
        if ($keep.Count -eq 0) { $settings.hooks.PSObject.Properties.Remove($ev) }
        else { $settings.hooks.$ev = $keep }
    }
    $hooksKeyExisted = $true
    if (Test-Path -LiteralPath $script:HooksInstalled) {
        $rec = Read-Json $script:HooksInstalled
        $hooksKeyExisted = [bool](Get-Prop $rec 'hooksKeyExisted' $true)
    }
    if ((@(Get-PropNames $settings.hooks).Count -eq 0) -and (-not $hooksKeyExisted)) {
        $settings.PSObject.Properties.Remove('hooks')
    }
    Write-JsonAtomic $script:ClaudeSettingsPath $settings
    Write-Touched 'EDIT' $script:ClaudeSettingsPath
    if (Test-Path -LiteralPath $script:HooksInstalled) { Remove-Item -LiteralPath $script:HooksInstalled; Write-Touched 'DELETE' $script:HooksInstalled }
    Write-Step $Tag ("표식 '{0}' 훅 {1}개를 제거했다. 다른 항목은 그대로 두었다." -f $script:Marker, $removed)
}

function Get-SpikeHooksInSettings {
    $settings = Read-Json $script:ClaudeSettingsPath
    $rows = @()
    if (-not (Test-JsonHasProperty $settings 'hooks')) { return $rows }
    foreach ($ev in @(Get-PropNames $settings.hooks)) {
        foreach ($g in @($settings.hooks.$ev)) {
            if (Test-SpikeHookGroup $g) { $rows += [pscustomobject]@{ event = $ev; group = $g } }
        }
    }
    return $rows
}

# ---------- 훅 로그 ----------
function Get-HookLog {
    param([datetime]$Since, [string]$SessionId, [string]$Event, [string]$Variant)
    $rows = Read-Jsonl $script:HooksLog
    if ($PSBoundParameters.ContainsKey('Since')) { $rows = $rows | Where-Object { [datetime]::Parse($_.ts) -ge $Since.ToUniversalTime() } }
    if ($SessionId) { $rows = $rows | Where-Object { $_.session_id -eq $SessionId } }
    if ($Event)     { $rows = $rows | Where-Object { $_.event -eq $Event } }
    if ($Variant)   { $rows = $rows | Where-Object { $_.variant -eq $Variant } }
    return @($rows)
}

# ---------- 제목 모드(훅이 읽는 파일) ----------
function Set-TitleMode {
    param([ValidateSet('none','SessionStart','UserPromptSubmit','both','osc')][string]$Mode, [string]$Base)
    Initialize-SpikeDirs
    Write-TextFileAtomic (Join-Path $script:LogDir 'title-mode.txt') $Mode
    Write-Touched 'WRITE' (Join-Path $script:LogDir 'title-mode.txt')
    if ($PSBoundParameters.ContainsKey('Base')) {
        Write-TextFileAtomic (Join-Path $script:LogDir 'title-base.txt') $Base
        Write-Touched 'WRITE' (Join-Path $script:LogDir 'title-base.txt')
    }
}

# ---------- Claude 세션 파일 ----------
function Find-TranscriptPath([string]$SessionId) {
    $projects = Join-Path $script:ClaudeDir 'projects'
    $hit = Get-ChildItem -Path $projects -Recurse -Filter "$SessionId.jsonl" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $hit) { return $hit.FullName }
    return $null
}
function Get-ClaudeSessionFiles {
    # ~/.claude/sessions/<pid>.json (로컬 관찰: name / nameSource 필드가 있다. 문서화된 계약은 아니다)
    $dir = Join-Path $script:ClaudeDir 'sessions'
    $rows = @()
    foreach ($f in Get-ChildItem -Path $dir -Filter '*.json' -ErrorAction SilentlyContinue) {
        try { $o = Read-Json $f.FullName; $rows += $o } catch { }
    }
    return $rows
}
function Get-ClaudeAgentsJson {
    $exe = Get-ClaudeExe
    if ($null -eq $exe) { return @() }
    try {
        $raw = & $exe agents --json 2>$null
        return @(($raw -join "`n") | ConvertFrom-Json)
    } catch { return @() }
}
