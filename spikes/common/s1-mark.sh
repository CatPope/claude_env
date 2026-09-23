#!/usr/bin/env bash
# spikes/common/s1-mark.sh — S1(c)(d) 용 표식. Git Bash / WSL pane 에서 실행한다.
#   사용: s1-mark.sh before|after [label]
# 현재 셸 종류, 작업 폴더(Windows 경로), WT_SESSION, WT_PROFILE_ID 를 _log/s1-panes.jsonl 에 남긴다.
PHASE="${1:-before}"; LABEL="${2:-}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$DIR/../_log"; mkdir -p "$LOG"
if grep -qi microsoft /proc/version 2>/dev/null; then
  SHELL_KIND="wsl"; WINPWD="$(wslpath -w "$PWD" 2>/dev/null || printf '%s' "$PWD")"
  DISTRO="${WSL_DISTRO_NAME:-}"
else
  SHELL_KIND="gitbash"; WINPWD="$(cygpath -w "$PWD" 2>/dev/null || printf '%s' "$PWD")"; DISTRO=""
fi
esc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
printf '{"ts":"%s","phase":"%s","label":"%s","shell":"%s","distro":"%s","cwd":"%s","WT_SESSION":"%s","WT_PROFILE_ID":"%s","pid":%s}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PHASE" "$(esc "$LABEL")" "$SHELL_KIND" "$(esc "$DISTRO")" "$(esc "$WINPWD")" \
  "$(esc "${WT_SESSION:-}")" "$(esc "${WT_PROFILE_ID:-}")" "$$" >> "$LOG/s1-panes.jsonl"
echo "[s1-mark] phase=$PHASE shell=$SHELL_KIND cwd=$WINPWD WT_SESSION=${WT_SESSION:-<없음>} WT_PROFILE_ID=${WT_PROFILE_ID:-<없음>}"
