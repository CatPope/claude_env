# spikes/common/osc99.sh — S1(d) 용. Git Bash 또는 WSL 에서 source 하면 프롬프트마다 OSC 9;9 로 현재 폴더(Windows 경로)를 보고한다.
#   Git Bash:  source /c/Users/<me>/Documents/GitHub/claude_env/spikes/common/osc99.sh
#   WSL:       source /mnt/c/Users/<me>/Documents/GitHub/claude_env/spikes/common/osc99.sh
# 프로필(.bashrc)은 고치지 않는다.
__cce_winpath() {
  if command -v wslpath >/dev/null 2>&1; then wslpath -w "$PWD" 2>/dev/null
  elif command -v cygpath >/dev/null 2>&1; then cygpath -w "$PWD"
  else printf '%s' "$PWD"; fi
}
__cce_osc99() { printf '\033]9;9;"%s"\033\\' "$(__cce_winpath)"; }
case ";$PROMPT_COMMAND;" in
  *";__cce_osc99;"*) ;;
  *) PROMPT_COMMAND="__cce_osc99${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
esac
echo "[osc99] PROMPT_COMMAND 에 OSC 9;9 를 넣었다. (shell=$(uname -s), WT_SESSION=${WT_SESSION:-<없음>})"
