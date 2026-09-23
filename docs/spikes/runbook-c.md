# 런북 C — S3 bg-attach, S4(b) 제목(attach)

- 대상 계획: `docs/planning/plan-ralplan.md` §5 Step 0, 스파이크 표의 **S3** 행과 **S4(b)** 행. 합격 기준은 그 표의 원문을 각 절에 그대로 옮겼다.
- 스크립트: `spikes/S3-bg-attach.ps1`, `spikes/S4b-title-attach.ps1` (공용 `spikes/common/c-lib.ps1`, 자산 `spikes/c-assets/`)
- 결과 기록: `docs/spikes/results-c.md` (또는 `docs/spikes/results.md` 가 있으면 그 파일의 S3/S4(b) 행)
- 실행 환경(확인함): Windows 11 Home 10.0.26200, Windows Terminal 1.24.11911.0, Claude Code 2.1.280 (`C:\Users\qwer\.local\bin\claude.exe`, 네이티브), Windows PowerShell 5.1.26100. `pwsh`, `cargo`, `rustc` 는 없다(Rust 설치 중). `wt.exe` 는 `%LOCALAPPDATA%\Microsoft\WindowsApps\wt.exe`.
- 모든 명령은 **Windows PowerShell 5.1**(`powershell.exe`) 탭에서 실행한다. `pwsh` 가 아니다(S3-8 의 WinRT 형식 로드 구문은 5.1 전용).

## 0. 읽기 전에

### 0.1 이 런북이 건드리는 것
| 위치 | 무엇 | 되돌리기 |
|---|---|---|
| `C:\cce-spike\c` | 스크래치 git 저장소, 프로젝트 훅 `.claude/settings.json`(최상위 `"_cce_spike": true` 표식), 로거·래퍼·프로토콜 처리기 사본 | `-Step cleanup -Force` 가 `C:\cce-spike` 전체 삭제 |
| `C:\cce-spike\tmp\settings-none.json`, `settings-worktree.json` | `--settings` 로 넘길 파일 | 위와 같음 |
| `spikes/_log/*.jsonl`, `spikes/_evidence/*.png` | 증거 | 지우지 않는다 |
| `HKCU\Software\Classes\cce-spike` | S3-8 사전 점검용 프로토콜 처리기(**S3-8 prepare 에서만**) | `-Step cleanup` 이 제거 |
| Claude Code 백그라운드 세션 | 이 런북이 띄운 세션(상태 파일 `spikes/_log/s3-state.json` 의 `sessions`) | `-Step cleanup` 이 `claude stop` + `claude rm` |

건드리지 않는 것: `~/.claude/settings.json`(해시로 변경 없음을 확인만 한다), WT settings/state, 셸 프로필, 실행 정책. 훅은 **프로젝트 설정**(`C:\cce-spike\c\.claude\settings.json`)에만 넣으므로 사용자 전역 설정에 훅을 넣었다 빼는 일 자체가 없다. 그래서 공용 `spikes/common/backup.ps1` / `restore.ps1` 은 이 런북에서 필수가 아니다. 다만 S1/S2/S4/S5 런북과 같은 날 진행하면 그쪽 절차대로 먼저 백업해 둔다.

### 0.2 비용
bg 세션은 붙어 있지 않아도 supervisor 아래에서 살아 있고, 프롬프트를 준 세션은 구독 사용량을 쓴다. S3-3(2회)·S3-5(10회)·S3-6(1회)·S4(b)(1회)가 실제 턴을 돌린다. 짧은 프롬프트라 사용량은 작지만, 끝나면 반드시 `cleanup` 으로 세션을 지운다. 한 번에 세션을 20개 이상 띄우지 않는다.

### 0.3 사용자 설정과의 상호작용(확인함)
- 사용자 `~/.claude/settings.json` 에는 `hooks` 가 없다 → 프로젝트 훅과 충돌 없음.
- `permissions.defaultMode` 가 `auto`, `skipAutoPermissionPrompt: true` 다 → 권한 프롬프트가 잘 안 뜬다. **S3-6 은 `--permission-mode manual` 로 띄운다**(스크립트가 그렇게 한다).
- `tui: fullscreen` 이므로 대화형도 fullscreen 이다. attach 의 fullscreen 전용 렌더링과 구분하려면 S3-1 기록에 적어 둔다.

### 0.4 자동/수동 경계
스크립트의 `-Phase` 는 `prepare`(자동 준비·실행) → **사람 조작** → `collect`(자동 수집) → `record`(수동 관찰 입력, 필요한 단계만) → `analyze`(판정 + `spikes/_log/verdicts-c.jsonl` 기록). `Read-Host` 는 없다. 각 단계의 판정은 `analyze` 출력의 `[단계] 합격|불합격|기록|보류 — 증거` 줄이다.

---

## 1. 준비 (setup)

```powershell
cd C:\Users\qwer\Documents\GitHub\claude_env\spikes
.\S3-bg-attach.ps1 -Step setup
```
하는 일: `C:\cce-spike\c` 생성 + `git init` + 초기 커밋, 자산 3개 복사, 프로젝트 훅 6종(SessionStart, UserPromptSubmit, Notification, PermissionRequest, Stop, SessionEnd → `_hook-logger.ps1`, exec 형식 `args`) 작성 후 커밋(worktree 에도 실리게), `--settings` 파일 2개 작성, 사용자 settings.json 해시 기록.

**수동:** WT 새 탭(PowerShell)에서
```powershell
cd C:\cce-spike\c
claude
```
신뢰(trust) 대화상자 승인 → `/hooks` 에서 `_cce_spike` 가 들어간 항목 6종이 보이는지 확인 → `/exit`. (이 대화형 세션은 프롬프트를 보내지 않으면 사용량을 쓰지 않는다.)

```powershell
.\S3-bg-attach.ps1 -Step setup -Phase collect
```
합격: `spikes/_log/s3-notify.jsonl` 에 cwd 가 `C:\cce-spike\c` 인 `SessionStart` 기록이 1건 이상. 없으면 `/hooks` 목록을 다시 보고, 그래도 없으면 `-HookForm shell` 로 setup 을 다시 실행한다(bash 한 줄 형식). 어느 형식이 동작했는지 결과 표에 적는다.

---

## 2. S3-1 — `claude --bg`(프롬프트 없이) → attach

계획 원문: "S3-1 `claude --bg`(프롬프트 없이) → attach". 합격 기준: **S3-1 합격**(필수).

```powershell
.\S3-bg-attach.ps1 -Step S3-1 -Phase prepare
```
실행: `claude --bg --settings C:\cce-spike\tmp\settings-none.json` (cwd `C:\cce-spike\c`). 출력에서 짧은 id 를 뽑고, `agents --json` 에서 cwd·startedAt 으로 찾아 `id/state/status/pid/sessionId/name/startedAt` 을 기록한다.

**수동:** WT 새 탭에서 `cd C:\cce-spike\c; claude attach <id>`. 관찰: 붙는가, 프롬프트 상자가 보이는가, fullscreen 인가, scrollback 이 있는가. `/exit` 로 빠져나온 뒤 `claude agents --json` 에 세션이 남아 있는가(detach 일 뿐이어야 한다, R2c).

```powershell
.\S3-bg-attach.ps1 -Step S3-1 -Phase collect
.\S3-bg-attach.ps1 -Step S3-1 -Phase record -Result pass -Note "attach OK, /exit 후 세션 유지"
.\S3-bg-attach.ps1 -Step S3-1 -Phase analyze
```
합격: 실행 exit 0 + agents 등록 + 수동 record pass. 불합격: 계획대로 **C 를 제공하지 않고 A 만 출시** (이 경우 S3-3 이후는 생략 가능).

---

## 3. S3-2 — `--session-id` + `--bg`

계획 원문: "S3-2 `--session-id` + `--bg`". 합격 기준: **결과를 기록해 대체 경로를 고른다.**

```powershell
.\S3-bg-attach.ps1 -Step S3-2 -Phase prepare     # claude --bg --session-id <새 uuid> --settings ...none.json
.\S3-bg-attach.ps1 -Step S3-2 -Phase collect     # agents --json 의 sessionId 가 요청한 uuid 와 같은가, 짧은 id 가 uuid 앞 8자인가
.\S3-bg-attach.ps1 -Step S3-2 -Phase analyze
```
사람 조작 없음. 합격이면 계획 4.1 §3 의 사전 할당 경로를 그대로 쓴다. 불합격이면 대체 경로(실행 직전 시각 이후 `startedAt` + cwd 로 탐색)를 결과 표에 적는다. 이 세션은 프롬프트가 없어 유휴 상태이며, S3-4·S3-7·S4(b) 가 재사용한다.

---

## 4. S3-3 — `--settings` 의 `bgIsolation`

계획 원문: "S3-3 `--settings` 의 `bgIsolation: none` 이 전역 설정 변경 없이 적용되어 원래 폴더를 편집하는가, `worktree` 로 바꾸면 `.claude/worktrees/` 아래를 편집하는가". 합격 기준: **S3-3 합격**(필수).

```powershell
.\S3-bg-attach.ps1 -Step S3-3 -Isolation none -Phase prepare
.\S3-bg-attach.ps1 -Step S3-3 -Isolation none -Phase collect    # done 까지 최대 4분 폴링 후 파일 위치 확인
.\S3-bg-attach.ps1 -Step S3-3 -Isolation none -Phase analyze
.\S3-bg-attach.ps1 -Step S3-3 -Isolation worktree -Phase prepare
.\S3-bg-attach.ps1 -Step S3-3 -Isolation worktree -Phase collect
.\S3-bg-attach.ps1 -Step S3-3 -Isolation worktree -Phase analyze
```
실행: `claude --bg --session-id <uuid> --settings <none|worktree 파일> --permission-mode acceptEdits "<probe-<iso>.txt 를 만들어라>"`.
판정(none): `C:\cce-spike\c\probe-none.txt` 있음 + `.claude\worktrees\` 아래에 없음 + `~/.claude/settings.json` 해시 불변. 판정(worktree): 원래 폴더에 없음 + `.claude\worktrees\<이름>\probe-worktree.txt` 있음 + 해시 불변. 참고 증거로 내부 파일 `~/.claude/daemon/roster.json` 의 `dispatch.isolation` 과 `~/.claude/jobs/<id>/state.json` 의 `bgIsolation` 을 함께 기록한다(문서화되지 않은 파일이므로 설계 근거로는 쓰지 않는다).
`blocked` 로 멈추면(신뢰 대화상자 등) `claude attach <id>` 로 처리하고 collect 를 다시 실행한다.

---

## 5. S3-4 — attach 자식 pid 추적, X 닫기 vs detach 구분, 경쟁 반복 20회

계획 원문: "S3-4 attach 자식 pid 추적, X 닫기와 `/exit`·`←` detach 구분, **경쟁 반복 시험 20회**". 합격 기준: **S3-4(오분류 0)**.

```powershell
.\S3-bg-attach.ps1 -Step S3-4 -Phase prepare        # S3-2 세션을 대상으로 래퍼 명령을 출력
```
**수동(20회):** 매 회차 WT 새 탭(PowerShell 5.1)에서 prepare 가 출력한 한 줄을 `-Run <N> -Expected <...>` 만 바꿔 실행한다.
```
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\cce-spike\c\_attach-wrapper.ps1" -Id <id> -Log "<repo>\spikes\_log\s3-4-attach.jsonl" -FlagDir "C:\cce-spike\c" -Run <N> -Expected <detach|close|exit-then-close>
```
- run 1~7 `detach`: 붙은 뒤 `/exit`(또는 `←`)로 빠져나온다. 기대 결과 `detached`.
- run 8~14 `close`: 붙은 상태에서 탭의 **X** 를 누른다. 기대 결과 `windowClosed`(처리기 기록).
- run 15~20 `exit-then-close`: `/exit` 직후 최대한 빨리 X. 기대 결과는 `detached` **또는** `windowClosed` 중 하나(4.1 §6: 300ms 안이면 windowClosed, 밖이면 detached). 둘 다 있거나 둘 다 없으면 오분류.

래퍼가 하는 일(계획 4.1 §6 의 축소판): `SetConsoleCtrlHandler` 등록(C# P/Invoke, 컴파일·설치 확인함) → `claude attach <id>` 를 `Start-Process -NoNewWindow -PassThru` 로 띄워 **자식 pid 와 시작 시각** 기록 → CTRL_CLOSE 를 받으면 처리기가 즉시 플래그 + `windowClosed` 기록 → 자식 종료 후 300ms 뒤 플래그가 없을 때만 `detached`.

```powershell
.\S3-bg-attach.ps1 -Step S3-4 -Phase collect       # 회차별 표
.\S3-bg-attach.ps1 -Step S3-4 -Phase analyze
```
판정: `runs>=20`, `misclassified=0`, `missing=0` 이면 합격. `close` 회차에 `ctrl` 기록이 하나도 없거나 `handlerInstalled=false` 이면 **PS 5.1 처리기가 CTRL_CLOSE 를 받지 못한 것**이므로 "Step 1 프로토타입 필요"로 기록한다(Rust `SetConsoleCtrlHandler` 로 재시험. 자식 pid/시작 시각 추적 부분은 이미 기록되므로 그 부분만 합격 처리). 이 경우 대체 경로는 트레이가 attach 자식 pid 소멸 + WT 창 존재로 판단하는 방식이다.

주의: 래퍼 안에서 PowerShell 자신의 CTRL_CLOSE 처리기도 함께 동작한다. 처리기 호출 순서(마지막 등록이 먼저)에 기대는 실험이므로, 결과가 흔들리면 "프로토타입 필요"로 적고 넘어간다.

---

## 6. S3-5 — 응답 중 창 닫기 → 턴·파일 수정 완료, jsonl 완전 (10회)

계획 원문: "S3-5 응답 중 창 닫기 → 턴·파일 수정 완료, jsonl 완전(10회)". 합격 기준: **S3-5(10/10)**.

각 회차(N = 1..10):
```powershell
.\S3-bg-attach.ps1 -Step S3-5 -Run N -Phase prepare
```
실행: `out.txt` 삭제 후 `claude --bg --session-id <uuid> --settings ...none.json --permission-mode acceptEdits "<out.txt 에 1..200 을 쓰고 응답에도 200줄을 다시 출력>"`.
**수동(즉시):** `cd C:\cce-spike\c; claude attach <id>` → 응답이 흐르는 동안 탭 **X**(창 전체를 닫아도 된다).
```powershell
.\S3-bg-attach.ps1 -Step S3-5 -Run N -Phase collect      # state=done 까지 폴링, out.txt 줄 수, jsonl 요약
```
회차 판정: `state=done` + `out.txt` 200줄 + transcript 파싱 오류 0 + assistant 메시지 ≥ 1. 10회 뒤:
```powershell
.\S3-bg-attach.ps1 -Step S3-5 -Phase analyze
```
불합격이면 C 를 제공하지 않는다(계획 대체).
참고: 대화형 A 경로의 T-1A 와 달리 여기서는 창을 닫아도 supervisor 가 턴을 끝내야 한다. 응답이 너무 빨리 끝나 닫을 틈이 없으면 프롬프트를 더 긴 출력으로 바꾼다(스크립트의 `$prompt`).

---

## 7. S3-6 — `blocked` 턴에서 창을 닫은 뒤 대기 유지 (S3-9 의 데이터 원천)

계획 원문: "S3-6 `blocked` 턴에서 창을 닫은 뒤 대기 유지". 합격 기준: **S3-6 합격**(필수).

```powershell
.\S3-bg-attach.ps1 -Step S3-6 -Phase prepare
```
실행: 환경 변수 `CCE_PANE_KEY=<WT_SESSION>` 을 세운 뒤 `claude --bg --session-id <uuid> --settings ...none.json --permission-mode manual "<Bash 로 git log 를 실행>"` → 권한 프롬프트로 `blocked`.
**수동:** `claude attach <id>` → 권한 프롬프트가 떠 있는지 본다 → **승인하지 말고** 탭 X. 닫자마자:
```powershell
.\S3-bg-attach.ps1 -Step S3-6 -Phase record -Result record -Note closed     # 닫은 시각 기록(S3-9 가 쓴다)
.\S3-bg-attach.ps1 -Step S3-6 -Phase collect -Minutes 5                     # 15초 간격 폴링, state 와 roster pid 관찰
```
붙어 있지 않은 동안 6초 이상 지나면 `Notification(permission_prompt)` 훅이 발생해야 한다(문서: 6초 gate). 5분 뒤:
**수동:** `claude attach <id>` 로 다시 붙어 권한 프롬프트가 그대로인지 보고 승인 → 응답 완료.
```powershell
.\S3-bg-attach.ps1 -Step S3-6 -Phase record -Result pass -Note "재접속 시 프롬프트 유지, 승인 후 done"
.\S3-bg-attach.ps1 -Step S3-6 -Phase analyze
```
판정: 관찰된 상태가 `blocked` 뿐(사라지거나 `stopped` 로 바뀌지 않음) + 재접속 pass.
더 긴 관찰(R2d 의 "약 1시간" 규칙이 blocked 세션엔 적용되지 않는지)은 `-Minutes 70` 으로 한 번 더 돌릴 수 있다(선택).

---

## 8. S3-7 — respawn 과 `--resume --bg` 의 ID 유지

계획 원문: "S3-7 respawn 과 `--resume --bg` 의 ID 유지". 합격 기준: **결과를 기록해 대체 경로를 고른다.**

```powershell
.\S3-bg-attach.ps1 -Step S3-7 -Phase prepare      # 사람 조작 없음. S3-2 세션 대상(또는 -SessionId <uuid>)
.\S3-bg-attach.ps1 -Step S3-7 -Phase analyze
```
자동 순서: `claude stop <id>` → `stopped` 확인 → `claude respawn <id>` → sessionId 비교 + 내부 `jobs/<id>/state.json` 의 `bgIsolation` 기록 → `claude stop <id>` → `claude --bg --resume <uuid> --settings ...none.json` → sessionId 비교 → (실행 중인 채로) `claude --bg --resume <uuid>` 한 번 더 → 복사본 생성 여부·출력 문구 기록.
결과가 정하는 것: 두 경우 모두 ID 가 유지되면 `sessionLineage` 는 단일 항목으로 충분하고, 바뀌면 계획 4.3 §3 대로 새 ID 를 lineage 에 덧붙인다. 복사본이 생기면 그 세션도 cleanup 목록에 들어간다.
추가로 볼 것: 문서상 `--settings` 는 세션 단위이며 `--resume` 에 복원되지 않는다. `respawn` 은 `--settings` 를 다시 줄 수 없으므로, respawn 뒤 `bgIsolation` 이 기본값 `worktree` 로 돌아가면 복원 경로(4.3 §3 "`stopped` 이면 `respawn` 후 attach")를 "`stop` 상태에서 `--bg --resume <id> --settings <파일>`" 로 바꾸는 결정이 필요하다. analyze 가 이 경우를 note 에 적는다.

---

## 9. S3-8 — Windows 알림 클릭 활성화 → attach

계획 원문: "S3-8 **Tauri 2 notification 플러그인의 Windows 알림 클릭 활성화**가 앱에 전달되는가, 전달되면 `wt -w 0 new-tab ... cce claude --attach-session <id>` 로 붙는가(정확히 이 두 단계를 나눠 기록)". 합격 기준: **결과를 기록해 대체 경로를 고른다.** 불합격 시: "4.2절 대체 순서 2·3(트레이 메뉴 "입력 대기 세션 N개" → attach, 불가하면 agent view)".

### 9.1 사전 점검(Tauri 없이, OS 수준) — 지금 할 수 있다
WinRT `ToastNotification` 을 PowerShell 5.1 에서 직접 띄우고, `activationType="protocol"` 로 `cce-spike://attach/<id>` 를 실행하게 한다. 프로토콜 활성화는 앱이 떠 있지 않아도 OS 가 처리기를 실행하므로 "앱 실행 중/아님" 두 경우를 자연히 덮는다. 이것은 Tauri 플러그인과 무관하게 **"Windows 토스트 클릭이 우리 명령을 실행할 수 있는가"** 를 가른다.

```powershell
.\S3-bg-attach.ps1 -Step S3-8 -Phase prepare                 # HKCU\Software\Classes\cce-spike 등록 (cleanup 이 제거)
.\S3-bg-attach.ps1 -Step S3-8 -Phase collect -Id <S3-2 id>   # 1단계: 토스트 발송 → 클릭 → 처리기가 URI 만 기록
.\S3-bg-attach.ps1 -Step S3-8 -Phase analyze
.\S3-bg-attach.ps1 -Step S3-8 -Phase collect -Id <S3-2 id> -Force   # 2단계: 클릭 → wt -w 0 new-tab -d C:\cce-spike\c powershell -NoExit -Command "claude attach <id>"
.\S3-bg-attach.ps1 -Step S3-8 -Phase analyze
.\S3-bg-attach.ps1 -Step S3-8 -Phase collect -Variant foreground     # 참고: foreground 활성화(COM 활성화기 없음) — 클릭해도 무반응이어야 정상
```
각 단계에서 클릭은 (a) 토스트가 떠 있을 때, (b) 알림 센터로 들어간 뒤, 두 번 해 본다. 기록: `spikes/_log/s3-8-protocol.jsonl` (`uri`, `stage2`, `stage2Cmd`). 2단계 뒤 새 탭의 `/status` 세션 ID 가 대상과 같은지 확인하고 스크린샷 `spikes/_evidence/S3-8-pre-stage2.png`.
토스트는 AUMID `{1AC14E77-...}\WindowsPowerShell\v1.0\powershell.exe`("Windows PowerShell")로 뜬다. Windows 설정에서 PowerShell 알림이 꺼져 있으면 켠다.

### 9.2 Tauri 2 본시험 — Rust 설치 뒤
스캐폴드는 지금 만들지 않는다. 절차만 적는다.

1. 프로젝트: `npm create tauri-app@latest cce-notify-smoke -- --template vanilla-ts` (또는 `cargo tauri init`). `cd cce-notify-smoke && npm i && cargo tauri add notification` (`tauri-plugin-notification`, 프론트 `@tauri-apps/plugin-notification`). `src-tauri/capabilities/default.json` 에 `"notification:default"` 추가. 트레이는 필요 없다.
2. 코드(한 화면): 버튼 → `sendNotification({ title: 'cce', body: 'attach <id>', extra: { id } })`. 클릭 감지 후보 3가지를 **모두** 걸어 두고 어느 것이 오는지 기록한다.
   - `onAction((n) => log('onAction', n))` (플러그인 JS API. 소스상 iOS/Android 전용 `actionPerformed` 이벤트)
   - `onNotificationReceived((n) => log('received', n))`
   - Rust: `app.notification()` 빌더로 보낸 뒤, 창 포커스 이벤트(`WindowEvent::Focused`)와 `RunEvent::Reopen` 로그
3. 시험 A(앱 실행 중): 알림 발송 → 클릭 → 로그에 어떤 이벤트가 오는가. 창이 앞으로 오는가(OS 기본 활성화).
4. 시험 B(앱 종료 후): 알림을 보내고 앱을 끝낸 뒤 알림 센터에서 클릭 → 앱이 실행되는가, 실행되면 인자/이벤트로 `<id>` 를 받을 수 있는가.
5. 시험 C(2단계): A 또는 B 에서 이벤트가 오면, 그 처리기에서 `Command::new(wt).args(["-w","0","new-tab","-d",cwd,"powershell","-NoExit","-Command","claude attach <id>"])` 를 실행하고 5초 안에 새 탭이 붙는지(T-12 (1) 기준).
6. 기록: `spikes/_evidence/S3-8-tauri-A.png`, `-B.png`, `-C.png` + 로그 발췌를 결과 표에.

예상(플러그인 소스 근거): 데스크톱 구현(`plugins/notification/src/desktop.rs`)은 `notify-rust` 로 보내기만 하고 클릭 처리기가 없다. macOS 만 bundle id 로 OS 가 앱을 앞으로 가져오고, Windows 는 이벤트가 없을 가능성이 크다. 그 경우:
- **대체 순서 2(계획 4.2)**: 트레이 메뉴 "입력 대기 세션 N개" → 항목 클릭 → `wt -w 0 new-tab -d <cwd> cce claude --attach-session <id>`. S3-8 결과와 무관하게 항상 둔다.
- **대체 순서 3**: attach 불가 시 agent view(`claude agents`) 를 새 탭에.
- **추가 선택지(9.1 결과가 좋을 때, 계획 변경이 필요하므로 별도 결정)**: 트레이 앱이 플러그인 대신 WinRT 토스트를 직접 보내고(`windows` crate `ToastNotificationManager`, 또는 `tauri-winrt-notification`), `activationType="protocol"` + `cce://attach/<id>` 를 `tauri-plugin-deep-link` 로 받는다. 앱이 꺼져 있어도 프로토콜로 앱이 뜬다. 이 방식은 9.1 이 사실상 미리 검증해 준다.

---

## 10. S3-9 — 붙어 있지 않은 bg 세션의 `Notification` 훅과 pane 역조회

계획 원문: "S3-9 **붙어 있지 않은 bg 세션에서 `Notification` 훅이 발생하는가**, 그리고 `cce hook` 이 그 pane 을 찾을 수 있는가(`CCE_PANE_KEY` 가 supervisor 를 거쳐 상속되지 않을 수 있으므로 `session_id` 역조회 포함)". 합격 기준: **결과를 기록해 대체 경로를 고른다(S3-9 합격 시 훅 경로를 알림의 빠른 경로로 추가, 불합격이면 폴링 15초만).**

S3-6 이 끝난 뒤:
```powershell
.\S3-bg-attach.ps1 -Step S3-9 -Phase collect      # s3-notify.jsonl 에서 S3-6 세션의 Notification 기록을 뽑는다
.\S3-bg-attach.ps1 -Step S3-9 -Phase analyze
```
보는 것: `notification_type`(permission_prompt 기대), 기록 시각이 S3-6 의 `closedAt` 이후인가(= 붙어 있지 않은 동안), 훅 환경에 `CCE_PANE_KEY`/`WT_SESSION` 이 있는가(상속 여부), 프로세스 조상 체인(`powershell.exe > claude.exe > ...` 에 supervisor 가 보이는가), payload 에 `session_id` 가 있는가(역조회 가능성).
판정: 닫은 뒤 Notification 기록 ≥ 1 → 합격(훅 경로 추가). `CCE_PANE_KEY` 가 없으면 "session_id 역조회 필요"로 적는다(계획 4.1 훅 절이 이미 이 경우를 다룬다). 기록이 없으면 불합격(폴링만).
참고: `PermissionRequest` 훅은 프롬프트가 뜨는 즉시 발생하므로 같이 기록된다. 트레이의 훅 경로를 `Notification` 대신 `PermissionRequest` 로 잡는 선택지가 생기면 결과 표에 적는다.

---

## 11. S4(b) — attach 상태의 제목

계획 원문: "attach 상태에서 `sessionTitle` 로 정한 이름과 아이콘이 WT 탭에 보이는가". 합격 기준: **아이콘을 뺀 텍스트가 4.6절 형식과 같다.** 불합격 시: "`cce` 가 attach 직전에 OSC 0 을 직접 출력. 덮어써지면 C 프로젝트에 한해 `--title` 고정(아이콘 포기, 설정 창에 표시)".

형식(계획 4.6): `<Claude 상태 아이콘> <별칭> [<계정>] · <부제>`. 훅은 `<별칭> [<계정>] · <부제>` 만 정하고 아이콘은 Claude Code 가 그린다. 부제가 없으면 `<별칭> [<계정>]`.

```powershell
.\S4b-title-attach.ps1 -Phase prepare -Alias claude_env -Account 개인 -Subtitle '로그인 버그 수정'
```
하는 일: `C:\cce-spike\c\_title.txt` ← `claude_env [개인] · 로그인 버그 수정`, 새 bg 세션(`--session-id`, 프롬프트 없음). 이때 `SessionStart` 훅이 `sessionTitle` 을 낸다(붙어 있지 않은 상태에서).
**수동 1:** `cd C:\cce-spike\c; claude attach <id>` → 탭 제목을 **아이콘 포함 그대로** 복사(탭을 우클릭 → 이름 바꾸기 상자에서 복사하거나 눈으로 옮겨 적는다) → 스크린샷 `spikes\_evidence\S4b-1-sessionstart.png`.
```powershell
.\S4b-title-attach.ps1 -Phase record -Stage sessionstart -Observed '<탭 제목 그대로>' -Screenshot S4b-1-sessionstart.png
```
**수동 2:** 세션에 `안녕, 한 줄로만 답해` 전송(`UserPromptSubmit` 훅이 다시 `sessionTitle` 을 낸다). 응답 중(busy)과 응답 뒤(idle) 제목·아이콘을 각각 기록: `S4b-2-busy.png`, `S4b-3-idle.png`.
**수동 3(선택):** `Bash 로 git status 실행해 줘` 를 보내 권한 대기(waiting) 아이콘 기록: `S4b-4-waiting.png`.
```powershell
.\S4b-title-attach.ps1 -Phase record -Stage busy -Observed '<...>' -Screenshot S4b-2-busy.png
.\S4b-title-attach.ps1 -Phase record -Stage idle -Observed '<...>' -Screenshot S4b-3-idle.png
.\S4b-title-attach.ps1 -Phase collect      # 훅 기록(SessionStart/UserPromptSubmit, emitted), agents --json 의 name, 이후 SessionStart 의 session_title
.\S4b-title-attach.ps1 -Phase analyze
```
`record` 는 앞쪽 글리프(아이콘·변형 선택자)를 걷어내고 코드포인트 수·UTF-16 hex 를 기록한 뒤 남은 텍스트를 기대값과 비교한다. 첫 프롬프트 전(`sessionstart` 단계)에는 변형 접미어(T-7 (1))를 허용해 기록만 한다.
불합격이면 대체 경로 시험: WT 탭에서
```powershell
.\S4b-title-attach.ps1 -Phase osc          # OSC 0 로 제목을 찍은 직후 claude attach
.\S4b-title-attach.ps1 -Phase record -Stage osc -Observed '<...>' -Screenshot S4b-5-osc.png
```
OSC 0 제목이 유지되면 "cce 가 attach 직전 OSC 0"을, 덮어써지면 "C 프로젝트 `--title` 고정(아이콘 포기)"을 결과 표에 적는다.
끝나면 `.\S4b-title-attach.ps1 -Phase cleanup` 으로 `_title.txt` 를 지운다(남아 있으면 이후 S3 세션 제목이 바뀐다).

---

## 12. 정리

```powershell
.\S4b-title-attach.ps1 -Phase cleanup
.\S3-bg-attach.ps1 -Step cleanup           # 세션 stop/rm, HKCU cce-spike 제거, 표식 파일 삭제. 스크래치는 남김
.\S3-bg-attach.ps1 -Step cleanup -Force    # C:\cce-spike 까지 삭제
claude agents --json --all                 # 스크래치 cwd 세션이 남아 있지 않은지 확인
```
`spikes/_log/*.jsonl` 과 `spikes/_evidence/*.png` 는 증거로 남기고, `docs/spikes/results-c.md`(또는 `results.md`)의 행을 `verdicts-c.jsonl` 의 마지막 판정으로 채운다.

---

## 부록 A. 설치된 Claude Code 2.1.280 의 도움말(캡처 원문)

캡처 명령: `claude --version; claude --help; claude agents --help; claude attach --help; claude respawn --help; claude stop --help; claude logs --help; claude rm --help; claude auth status --help` (2026-09-23, 읽기 전용).

### A.1 `claude --version`
```
2.1.280 (Claude Code)
```

### A.2 `claude --help` (이 런북과 관련 있는 부분만 발췌. 전체 옵션 목록은 매우 길어 관련 항목만 옮겼다)
```
Usage: claude [options] [command] [prompt]

Options:
  --bg, --background                    Start the session in the background and
                                        return immediately. Prints the id that
                                        `claude attach`, `logs`, `stop` and `rm`
                                        take; `claude agents` lists them. With
                                        --resume <session-id>, continues that
                                        session in the background under the same
                                        ID, or starts a copy and says so when
                                        the session is already running
  -c, --continue                        Continue the most recent conversation in
                                        the current directory
  --fork-session                        When resuming, create a new session ID
                                        instead of reusing the original (use
                                        with --resume or --continue)
  -n, --name <name>                     Set a display name for this session
                                        (shown in the prompt box, /resume
                                        picker, and terminal title)
  --permission-mode <mode>              Permission mode to use for the session
                                        (choices: "acceptEdits", "auto",
                                        "bypassPermissions", "manual",
                                        "dontAsk", "plan")
  -r, --resume [value]                  Resume a conversation by session ID, or
                                        open interactive picker with optional
                                        search term
  --session-id <uuid>                   Use a specific session ID for the
                                        conversation (must be a valid UUID)
  --setting-sources <sources>           Comma-separated list of setting sources
                                        to load (user, project, local).
  --settings <file-or-json>             Path to a settings JSON file or a JSON
                                        string to load additional settings from
  -w, --worktree [name]                 Create a new git worktree for this
                                        session (optionally specify a name)

Commands:
  agents [options]                      Manage background agents
  attach <id>                           Open a background session in this
                                        terminal. <id> is the short id that
                                        `claude --bg` prints and `claude agents`
                                        lists
  auth                                  Manage authentication
  auto-mode                             Inspect or reset auto mode classifier
                                        configuration
  doctor                                Check the health of your Claude Code
                                        installation. ...
  gateway [options]                     Run the enterprise auth/telemetry
                                        gateway
  import [options] [source]             Import config from another AI coding
                                        agent into Claude Code
  install [options] [target]            Install Claude Code native build. ...
  logs <id>                             Print a background session's recent
                                        terminal output
  mcp                                   Configure and manage MCP servers
  plugin|plugins                        Manage Claude Code plugins
  project                               Manage Claude Code project state
  respawn [options] [id]                Restart a background session, or all of
                                        them with --all, so it runs the current
                                        Claude Code version
  rm <id>                               Delete a background session, and its
                                        worktree when that is safe. Works on
                                        sessions that have already exited
  setup-token                           Set up a long-lived authentication token
                                        (requires Claude subscription)
  stop|kill <id>                        Stop a background session. Its
                                        conversation is kept: `claude attach
                                        <id>` opens it again, `claude --resume`
                                        works once it is stopped
  ultrareview [options] [target]        Run a cloud-hosted multi-agent code
                                        review ...
  update|upgrade                        Check for updates and install if
                                        available
```
그 밖의 최상위 옵션(전체 목록에 있음): `--add-dir`, `--agent`, `--agents`, `--allow-dangerously-skip-permissions`, `--allowedTools`, `--append-system-prompt`, `--autocompact`, `--ax-screen-reader`, `--bare`, `--betas`, `--brief`, `--chrome`, `--cloud`, `--dangerously-skip-permissions`, `-d/--debug`, `--debug-file`, `--disable-slash-commands`, `--disallowedTools`, `--effort`, `--environment`, `--exclude-dynamic-system-prompt-sections`, `--fallback-model`, `--file`, `--forward-subagent-text`, `--from-pr`, `-h/--help`, `--ide`, `--include-hook-events`, `--include-partial-messages`, `--input-format`, `--json-schema`, `--max-budget-usd`, `--mcp-config`, `--model`, `--no-chrome`, `--no-session-persistence`, `--output-format`, `--permission-prompts`, `--plugin-dir`, `--plugin-url`, `-p/--print`, `--prompt-suggestions`, `--remote-control`, `--remote-control-session-name-prefix`, `--replay-user-messages`, `--restricted`, `--safe-mode`, `--strict-mcp-config`, `--system-prompt`, `--system-prompt-snapshot`, `--teleport`, `--tmux`, `--tools`, `--verbose`, `-v/--version`.

계획 4.1 규칙 1 의 하위 명령 표에 있으나 2.1.280 `--help` 에 **없는** 것: `config`, `migrate-installer`. 있으나 표에 **없는** 것: `auto-mode`, `gateway`, `import`, `ultrareview`. (Step 1 인자 분류 표는 이 목록으로 갱신한다.)

### A.3 `claude agents --help`
```
Usage: claude agents [options]

Manage background agents

Options:
  --add-dir <directory>                 Additional directory to allow tool
                                        access to in dispatched sessions
                                        (repeatable)
  --agent <agent>                       Default agent for sessions dispatched
                                        from agent view. Overrides the 'agent'
                                        setting.
  --all                                 With --json: also include completed
                                        background sessions
  --allow-dangerously-skip-permissions  Make bypass-permissions mode available
                                        to dispatched sessions without
                                        defaulting to it
  --cwd <path>                          Show only background sessions started
                                        under <path>
  --dangerously-skip-permissions        Alias for --permission-mode
                                        bypassPermissions
  --effort <level>                      Default effort level for sessions
                                        dispatched from agent view
  -h, --help                            Display help for command
  --json                                Print active sessions (interactive and
                                        background) as a JSON array and exit
                                        (for scripting; does not require a TTY)
  --mcp-config <config>                 MCP server configuration to apply to
                                        dispatched sessions (repeatable)
  --model <model>                       Default model for sessions dispatched
                                        from agent view
  --permission-mode <mode>              Default permission mode for sessions
                                        dispatched from agent view
  --plugin-dir <path>                   Load plugins from specified directory
                                        for the agent view and dispatched
                                        sessions; a folder of plugins loads each
                                        child (repeatable)
  --restricted                          Start dispatched sessions in restricted
                                        mode
  --setting-sources <sources>           Comma-separated list of setting sources
                                        to load (user, project, local).
  --settings <file-or-json>             Settings file or JSON string to apply to
                                        the agent view and dispatched sessions
  --strict-mcp-config                   Only use MCP servers from --mcp-config
                                        in dispatched sessions
```
`--cwd <path>` 가 있다(계획에 없음). 트레이 폴링은 `claude agents --json --all --cwd <프로젝트>` 로 범위를 줄일 수 있다.

### A.4 `claude attach --help`
```
Usage: claude attach <id>

  Open the background session in this terminal. ← returns to agent view, Ctrl+Z drops back to your shell. The session keeps running either way.
```

### A.5 `claude respawn --help`
```
Usage: claude respawn <id>|--all

  Restart a background session (or all of them) so it picks up the current Claude binary.
```

### A.6 `claude stop --help`
```
Usage: claude stop <id>

  Stop a background session. Its conversation is kept; resume it later with `claude attach <id>`.
```

### A.7 `claude logs --help`, `claude rm --help`
```
Usage: claude logs <id>

  Print the background session's recent terminal output.
Usage: claude rm <id> [--discard-unpushed <commit>@<worktree-id>] [--force-remove-worktree <worktree-id>]

  Delete a background session and its worktree. Unlike `stop`, works on already-exited sessions.
  --discard-unpushed <commit>@<worktree-id>  also discard the worktree's unpushed commits (and any uncommitted changes) while it is still the same worktree at that commit — pass the value a previous 'claude rm <id>' reported
  --force-remove-worktree <worktree-id>      delete the worktree directory even though the WorktreeRemove hook or git couldn't remove it (...) — pass the value a previous 'claude rm <id>' reported
```

### A.8 `claude auth status --help`
```
Usage: claude auth status [options]

Show authentication status

Options:
  -h, --help  Display help for command
  --json      Output as JSON (default)
  --text      Output as human-readable text
```

### A.9 `claude agents --json` 실제 출력 형태(2026-09-23, 값은 가림)
```json
[
  { "id": "3d038243", "cwd": "C:\\...", "kind": "background", "startedAt": 1785292240817,
    "sessionId": "3d038243-eee6-4097-a50f-43abb58790f7", "name": "…", "state": "blocked" },
  { "pid": 37788, "cwd": "C:\\Users\\qwer\\Documents\\GitHub\\claude_env", "kind": "interactive",
    "startedAt": 1790124094324, "sessionId": "56cbd6c5-…", "name": "claude-env-3c", "status": "busy" }
]
```
- 백그라운드 행(관찰 당시): `id, cwd, kind, startedAt, sessionId, name, state` — `pid`, `status`, `waitingFor` 가 없었다. 문서(agent view)는 `pid`·`status` 를 "프로세스가 살아 있는 동안" 싣는다고 하므로, 관찰한 행들은 supervisor 가 멈춘 세션이었을 수 있다(`daemon/roster.json` 에 워커가 거의 없었다). **S3-1 collect 가 갓 띄운 bg 세션에서 `pid/status/waitingFor` 가 실제로 나타나는지 기록한다.** 나타나지 않으면 계획 R3e/4.2 의 `waitingFor` 의존을 뺀다.
- 대화형 행: `pid, cwd, kind, startedAt, sessionId, name, status` — `state` 없음.
- bg 짧은 `id` = `sessionId` 앞 8자.

## 부록 B. 계획의 가정과 설치본의 차이(요약)
| 계획 | 실제 | 조치 |
|---|---|---|
| `agents --json` 에 `pid/status/waitingFor` (R3e, 4.2) | 관찰한 bg 행에는 없었고 `state` 만 있음. 문서상 `pid`·`status` 는 살아 있는 동안만 | S3-1 collect 로 확정. 없으면 트레이는 `state=blocked` 로만 알림 |
| `--settings` 가 세션에 남는다 | 세션 단위. `--resume`·`respawn` 에 복원되지 않음(문서) | S3-7 이 respawn 뒤 `bgIsolation` 을 기록. 되돌아가면 복원 경로를 `stop` → `--bg --resume --settings` 로 변경 검토 |
| 하위 명령 표에 `config`, `migrate-installer` (4.1 규칙 1) | 없음. 대신 `auto-mode`, `gateway`, `import`, `ultrareview` 있음 | Step 1 표 갱신 |
| `respawn` 이 stopped 세션도 재시작(R2d) | 도움말에 명시 없음 | S3-7 실측 |
| `stop` 뒤 `--resume` 로 잇기 | `stop --help` 는 `attach` 로 다시 열라고 안내; `--bg --resume` 은 같은 ID 유지 또는 복사본 | S3-7 실측 |
| 훅 객체에 임의 표식 키 | 스키마 `additionalProperties: false` | 표식은 설정 파일 최상위 `"_cce_spike": true` |
| `--settings` 로 `worktree.bgIsolation` 전달(4.1 §3) | 옵션 있음, 설정 범위 "Any file" | S3-3 실측 |

## 부록 C. 문서화되지 않은 내부 파일(읽기 전용 관찰, 설계 근거로 쓰지 않음)
- `~/.claude/daemon/roster.json`: supervisor pid, 워커별 `pid/procStart/sessionId/cwd/dispatch.isolation/dispatch.env.CLAUDE_BG_ISOLATION`.
- `~/.claude/daemon/attach-journal/<gesture>.json`: attach 시도 기록(`pid`, `procStart`, `attachMs`).
- `~/.claude/daemon/pty-pids/<short>.pid`: 워커 pid.
- `~/.claude/jobs/<short>/state.json`, `timeline.jsonl`: `state/tempo/bgIsolation/needs/name/nameSource/respawnFlags/cliVersion`.
- `~/.claude/sessions/<pid>.json`: 대화형 세션의 `sessionId/cwd/procStart/name/nameSource/status`.
S3 스크립트는 이 파일들을 **증거 보강용**으로만 읽는다. 훗날 계약이 필요하면 원칙 2 의 예외를 늘리는 결정이 따로 필요하다.
