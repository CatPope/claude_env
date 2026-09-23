#!/usr/bin/env bash
# spikes/common/cce-spike-hook.sh — 스파이크용 Claude Code 훅 (cce hook 의 대역).
# 사용: cce-spike-hook.sh <Event> [variant] [logDir]
#   Event   : SessionStart | UserPromptSubmit | Notification | Stop | SessionEnd
#   variant : 설치 형식 표식(exec-bash, shell-bash, path-space ...). 로그에만 남는다.
#   logDir  : spikes/_log 의 경로(슬래시 형식). 생략하면 이 파일 기준 ../_log
# 하는 일:
#   1. stdin 의 JSON 페이로드와 환경(WT_SESSION, CCE_PANE_KEY, TERM_PROGRAM ...)을 _log/hooks.jsonl 에 한 줄로 남긴다.
#   2. CCE_PANE_KEY 가 있을 때만(=cce-stub 이 띄운 세션) 상태 파일 _log/status/<session_id>.status 를 갱신한다.
#      UserPromptSubmit→busy, Stop→idle, Notification(permission_prompt|elicitation_*|agent_needs_input)→waiting,
#      Notification(idle_prompt)→idle(계획 rev 5 승인 조건). SessionStart 는 lineage 에 추가.
#   3. CCE_PANE_KEY 가 있고 _log/title-mode.txt 가 허용하면 sessionTitle 을 내보낸다(계획 4.6절의 축소판).
#      _log/title-base.txt = "<별칭> [<계정>]", _log/status/<sid>.subtitle = 부제, <sid>.interrupted = 중단 플래그.
# 항상 exit 0. 외부 프로세스를 거의 띄우지 않는다(bash 내장만 사용: 훅 p95 100ms 목표를 스크립트가 잡아먹지 않도록).
export LC_ALL=C.UTF-8
shopt -s extglob
T0=$EPOCHREALTIME
EVENT="${1:-unknown}"
VARIANT="${2:-exec-bash}"
DIR="${BASH_SOURCE[0]%/*}"
if [ -n "${3:-}" ]; then LOG="$3"; else LOG="$DIR/../_log"; fi
[ -d "$LOG/status" ] || mkdir -p "$LOG/status" 2>/dev/null

PAYLOAD="$(cat)"
PAYLOAD="${PAYLOAD#$'\xEF\xBB\xBF'}"                          # 앞의 UTF-8 BOM 제거(PowerShell 로 파이프하면 붙을 수 있다)
PAYLOAD="${PAYLOAD//$'\r'/}"; PAYLOAD="${PAYLOAD//$'\n'/}"   # jsonl 한 줄에 넣기 위해 토큰 사이 개행 제거

# JSON 문자열 필드 추출(내장 정규식). 결과는 JSON 이스케이프를 푼 값(\" → ", \\ → \, \n → 개행).
jget() {
  local re="\"$1\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\""
  if [[ $PAYLOAD =~ $re ]]; then
    local v="${BASH_REMATCH[1]}"
    v="${v//\\\"/\"}"; v="${v//\\n/$'\n'}"; v="${v//\\t/$'\t'}"; v="${v//\\\\/\\}"
    printf '%s' "$v"
  fi
}
jesc() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"; printf '%s' "$s"; }
readfile() { local v=""; if [ -f "$1" ]; then IFS= read -r v < "$1" || true; fi; printf '%s' "${v%$'\r'}"; }

SID="$(jget session_id)"
SRC="$(jget source)"
NTYPE="$(jget notification_type)"
REASON="$(jget reason)"
STITLE="$(jget session_title)"
PROMPT="$(jget prompt)"
PROMPT_HEAD="${PROMPT:0:60}"
CWD="$(jget cwd)"

STATUS_WRITTEN=""
TITLE_EMITTED=""
SKIPPED="false"
if [ -z "${CCE_PANE_KEY:-}" ]; then
  # cce 와 같은 규칙: pane key 가 없으면(VS Code 등) 아무것도 기록하지 않는다(S5(e)).
  SKIPPED="true"
else
  SF="$LOG/status/$SID.status"
  case "$EVENT" in
    SessionStart)
      TZ=UTC printf '%(%Y-%m-%dT%H:%M:%SZ)T %s %s\n' -1 "$SID" "$SRC" >> "$LOG/status/$CCE_PANE_KEY.lineage"
      ;;
    UserPromptSubmit)
      printf 'busy' > "$SF"; STATUS_WRITTEN="busy"
      [ -f "$LOG/status/$SID.interrupted" ] && rm -f "$LOG/status/$SID.interrupted"
      ;;
    Stop)
      printf 'idle' > "$SF"; STATUS_WRITTEN="idle" ;;
    Notification)
      case "$NTYPE" in
        permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input)
          printf 'waiting' > "$SF"; STATUS_WRITTEN="waiting" ;;
        idle_prompt)
          printf 'idle' > "$SF"; STATUS_WRITTEN="idle" ;;
      esac ;;
  esac

  # ---- 제목 ----
  MODE="$(readfile "$LOG/title-mode.txt")"; [ -z "$MODE" ] && MODE="none"
  BASE="$(readfile "$LOG/title-base.txt")"
  SUBF="$LOG/status/$SID.subtitle"
  SUB="$(readfile "$SUBF")"
  EMIT="no"
  case "$EVENT:$MODE" in
    SessionStart:SessionStart|SessionStart:both|SessionStart:osc) EMIT="yes" ;;
    UserPromptSubmit:UserPromptSubmit|UserPromptSubmit:both|UserPromptSubmit:osc) EMIT="yes" ;;
  esac
  if [ "$EMIT" = "yes" ] && [ -n "$BASE" ]; then
    if [ "$EVENT" = "UserPromptSubmit" ]; then
      # 첫 프롬프트: 부제가 없을 때만 로컬 요약(앞 24자)을 저장한다(4.6절 선택 3).
      if [ -z "$SUB" ] && [ -n "$PROMPT" ]; then
        SUB="${PROMPT//+([[:space:]])/ }"; SUB="${SUB# }"; SUB="${SUB% }"; SUB="${SUB:0:24}"
        printf '%s' "$SUB" > "$SUBF"
      fi
      TITLE="$BASE"; [ -n "$SUB" ] && TITLE="$BASE · $SUB"
    else
      TITLE="$BASE"
      if [ -f "$LOG/status/$SID.interrupted" ]; then TITLE="$BASE · ⏸중단 $SUB"
      elif [ -n "$SUB" ]; then TITLE="$BASE · $SUB"; fi
    fi
    TITLE_EMITTED="$TITLE"
    if [ "$MODE" = "osc" ]; then
      # S4(a) 불합격 시 대체 경로 시험: terminalSequence 로 OSC 0 을 직접 내보낸다.
      printf '{"hookSpecificOutput":{"hookEventName":"%s","terminalSequence":"\\u001b]0;%s\\u0007"}}\n' "$EVENT" "$(jesc "$TITLE")"
    else
      printf '{"hookSpecificOutput":{"hookEventName":"%s","sessionTitle":"%s"}}\n' "$EVENT" "$(jesc "$TITLE")"
    fi
  fi
fi

T1=$EPOCHREALTIME
# EPOCHREALTIME 은 "초.마이크로초". ms 정수로 바꾼다(외부 명령 없이).
ms_of() { local s="${1%.*}" f="${1#*.}"; printf '%s' "$(( s * 1000 + 10#${f:0:3} ))"; }
T0MS=$(ms_of "$T0"); T1MS=$(ms_of "$T1")
TZ=UTC printf -v TS '%(%Y-%m-%dT%H:%M:%S)T' -1
TS="$TS.$(printf '%03d' $((T1MS % 1000)))Z"
{
  printf '{"ts":"%s","t_ms":%s,"event":"%s","variant":"%s","shell":"bash","pid":%s,"ppid":%s,' \
    "$TS" "$T1MS" "$EVENT" "$VARIANT" "$$" "$PPID"
  printf '"WT_SESSION":"%s","CCE_PANE_KEY":"%s","WT_PROFILE_ID":"%s","TERM_PROGRAM":"%s","script":"%s",' \
    "$(jesc "${WT_SESSION:-}")" "$(jesc "${CCE_PANE_KEY:-}")" "$(jesc "${WT_PROFILE_ID:-}")" "$(jesc "${TERM_PROGRAM:-}")" "$(jesc "${BASH_SOURCE[0]}")"
  printf '"session_id":"%s","source":"%s","notification_type":"%s","reason":"%s","session_title":"%s","prompt_head":"%s","cwd":"%s",' \
    "$(jesc "$SID")" "$(jesc "$SRC")" "$(jesc "$NTYPE")" "$(jesc "$REASON")" "$(jesc "$STITLE")" "$(jesc "$PROMPT_HEAD")" "$(jesc "$CWD")"
  printf '"skipped":%s,"status_written":"%s","title_emitted":"%s","dur_ms":%s,"payload":%s}\n' \
    "$SKIPPED" "$(jesc "$STATUS_WRITTEN")" "$(jesc "$TITLE_EMITTED")" "$((T1MS - T0MS))" "${PAYLOAD:-null}"
} >> "$LOG/hooks.jsonl"
exit 0
