# spikes/common/osc99.ps1 — S1(d) 용. 프로필을 고치지 않고, 현재 PowerShell(5.1/7) 세션의 prompt 를 감싸
# 프롬프트마다 OSC 9;9 로 현재 폴더를 Windows Terminal 에 보고한다.
#   사용:  . C:\...\spikes\common\osc99.ps1
# 참고: https://learn.microsoft.com/en-us/windows/terminal/tutorials/new-tab-same-directory
if (-not (Get-Variable -Name __cce_orig_prompt -Scope Global -ErrorAction SilentlyContinue)) {
    $global:__cce_orig_prompt = $function:prompt
}
function global:prompt {
    $out = & $global:__cce_orig_prompt
    $loc = $ExecutionContext.SessionState.Path.CurrentLocation
    if ($loc.Provider.Name -eq 'FileSystem') {
        $Host.UI.Write("$([char]27)]9;9;`"$($loc.ProviderPath)`"$([char]7)")
    }
    return $out
}
Write-Host ("[osc99] prompt 를 감쌌다. 이 pane 은 이제 폴더를 WT 에 보고한다. (PS {0}, WT_SESSION={1})" -f $PSVersionTable.PSVersion, $env:WT_SESSION)
