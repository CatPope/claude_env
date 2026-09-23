# 스파이크 런북 — A 경로 (S1 → S5 → S4 → S2)

계획 `docs/planning/plan-ralplan.md` §5 Step 0 의 A 경로 판정용 스파이크를 사람이 손으로 돌리기 위한 절차다.
S3 과 S4(b) 는 다른 레인(`spikes/S3-bg-attach.ps1`, `spikes/S4b-title-attach.ps1`)에서 따로 한다.

## 0. 전제와 규칙

| 항목 | 내용 |
|---|---|
| 실행 셸 | **Windows PowerShell 5.1** (`powershell.exe`). 모든 `.ps1` 은 5.1 문법(`&&`·삼항 없음)으로 썼고 UTF-8 BOM 으로 저장했다. pwsh 7 이 있으면 스크립트가 감지해 안내만 한다(pwsh 7 은 S1 의 pane 으로만 쓴다). |
| 동시 설치 중인 것 | PowerShell 7, Rust. **Rust 가 없으므로 `cce.exe` 대신 `spikes/common/cce-stub.ps1`(C# `SetConsoleCtrlHandler` 를 쓰는 대역)이 실행기 역할을 한다.** 훅은 `spikes/common/cce-spike-hook.sh`(Git Bash) 가 `cce hook` 역할을 한다. |
| 실행 방법 | 항상 저장소 루트에서:  `powershell -NoProfile -ExecutionPolicy Bypass -File spikes\<스크립트>.ps1 -Step <단계> ...`. WT pane 안에서 실행해야 하는 단계(`cce-stub`, `S2 -Step run/resume`, `s1-mark`)는 그 pane 의 PowerShell 에서 `& 'C:\...\spikes\...ps1'` 로 실행한다(위 명령이 `-ExecutionPolicy Bypass` 를 쓰므로 실행 정책과 무관하게 돈다). |
| 산출물 | `spikes/_log/` (로그·측정값·사본), `spikes/_backup/<타임스탬프>/` (원본 백업). 둘 다 `.gitignore` 에 있다. 결과는 `docs/spikes/results.md` 에 옮겨 적는다. |
| 건드리는 사용자 파일 | WT `settings.json`(S1 만, 표식 주석 한 줄), `~/.claude/settings.json`(훅 항목만, 표식 `cce-spike` 가 경로에 들어간 항목만 넣고 뺌), WT `state.json`(S1(f) 되쓰기만). 프로필(`$PROFILE`, `.bashrc`)은 **건드리지 않는다** — OSC 9;9 는 pane 마다 `source` 하는 헬퍼로 넣는다. |
| 표식 방식 | 브리프의 `"_cce_spike": true` 키 대신 **훅 명령 경로에 들어 있는 `cce-spike` 문자열**을 표식으로 쓴다. 설정 스키마에 없는 키를 넣었을 때 Claude Code 가 설정 파일을 거부할 위험을 피하기 위해서다. 제거는 표식이 있는 항목만 걸러내고, 기존 항목(OMC statusline, 다른 레인의 훅)은 그대로 둔다. |
| 전역 훅의 부작용 | 훅은 사용자 전역 설정에 들어가므로 **모든 Claude 세션**에서 실행되어 `_log/hooks.jsonl` 에 줄이 남는다. 그러나 `CCE_PANE_KEY` 가 없는 세션(스텁으로 띄우지 않은 세션, VS Code 등)에서는 상태·제목을 절대 쓰지 않는다(`skipped:true` 로만 남음). 이것이 S5(e) 의 확인 대상이기도 하다. |
| 순서 | **백업 → S1 → S5 → S4 → S2 → 복원.** S5 가 설치한 훅을 S4·S2 가 그대로 쓴다(이미 있으면 다시 설치하지 않음). |
| 권한 모드 | 사용자 설정이 `defaultMode: auto` 라 권한 요청이 거의 뜨지 않는다. **waiting 시나리오(S4 의 waiting 상태, S2(d))는 `-ClaudeArgs --permission-mode,manual` 을 붙여 띄운다.** |

### 0.1 백업 (맨 처음 한 번)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File spikes\common\backup.ps1 -WhatIf     # 무엇을 복사할지 확인
powershell -NoProfile -ExecutionPolicy Bypass -File spikes\common\backup.ps1 -Label start
```

각 `-Step prepare` 도 자체 백업을 한 번 더 남긴다(`before-S1` 등). 복원은 §6.

---

## 1. S1 — WT 레이아웃 (`spikes/S1-wt-layout.ps1`)

**계획의 확인 내용(원문):** (a) `persistedWindowLayouts` 키 구조 (b) commandline 재실행 여부 (c) 복원 후 `WT_SESSION` 유지 여부 (d) 폴더 복원 (e) 창 2개를 10초 간격으로 닫을 때 저장 내용과 자동 저장 간격 (f) WT가 꺼진 상태에서 되쓴 파일을 WT가 읽는가

**합격 기준(원문):** (d): pwsh 5.1·pwsh 7·Git Bash·WSL(Ubuntu) pane 각각에서 복원 후 `pwd` 출력이 닫기 전과 문자열로 같다(4/4). (e): 두 번째 창만 저장됨을 재현하고 간격을 초 단위로 기록. (a)(b)(c)(f)는 결과를 기록해 설계 분기에 쓴다

**불합격 시 대체(원문):** (d) 실패한 셸 → 통합 수정 후 재시험. (c) 다름 → 2순위 매칭. (f) 실패 → `wt.exe` 재구성

### 절차

1. `-Step prepare`
   `powershell -NoProfile -ExecutionPolicy Bypass -File spikes\S1-wt-layout.ps1 -Step prepare`
   → 백업 후 WT `settings.json` 첫 줄 뒤에 `"firstWindowPreference": "persistedWindowLayout", // cce-spike:S1` 을 넣는다(이미 키가 있으면 값만 바꾸고 원래 값을 표식 뒤에 기록). 사람이 할 일이 번호로 출력된다.
2. 감시 켜기(WT 밖 아무 콘솔, 예: VS Code 터미널):
   `powershell -NoProfile -ExecutionPolicy Bypass -File spikes\S1-wt-layout.ps1 -Step watch -Seconds 1200`
   → 숨김 프로세스가 1초마다 `state.json` 해시·크기·`persistedWindowLayouts` 수·WT 프로세스 수·창 수를 `_log/s1-state-watch.jsonl` 에 남기고, 바뀔 때마다 사본을 `_log/s1-state-snapshots/` 에 저장한다.
3. **[수동]** WT 창 1 을 열고 pane 4개(PS 5.1 / pwsh 7(있으면) / Git Bash / WSL Ubuntu)를 만든다. pane 마다 서로 다른 폴더로 `cd` 한다.
4. **[수동]** pane 마다 OSC 9;9 헬퍼를 source 한다(프로필 수정 없음):
   - PS: `. C:\Users\qwer\Documents\GitHub\claude_env\spikes\common\osc99.ps1`
   - Git Bash: `source /c/Users/qwer/Documents/GitHub/claude_env/spikes/common/osc99.sh`
   - WSL: `source /mnt/c/Users/qwer/Documents/GitHub/claude_env/spikes/common/osc99.sh`
5. **[수동]** pane 마다 표식(before)을 남긴다:
   - PS: `& 'C:\Users\qwer\Documents\GitHub\claude_env\spikes\common\s1-mark.ps1' before`
   - Git Bash: `/c/Users/qwer/Documents/GitHub/claude_env/spikes/common/s1-mark.sh before`
   - WSL: `/mnt/c/Users/qwer/Documents/GitHub/claude_env/spikes/common/s1-mark.sh before`
   (기록: 셸 종류, cwd(Windows 경로), `WT_SESSION`, `WT_PROFILE_ID` → `_log/s1-panes.jsonl`)
6. **[수동]** WT 창 2 를 열고(PS 5.1 탭 1개, 다른 폴더) 같은 표식을 라벨을 붙여 남긴다: `s1-mark.ps1 before -Label win2`.
7. **[수동]** 창 2 를 X 로 닫고 **10초**를 센 뒤 창 1 을 X 로 닫는다.
8. **[수동]** 시작 메뉴로 WT 를 다시 연다. 복원된 pane 마다 `pwd` 를 보고 표식(after)을 남긴다(5 번 명령의 `before` → `after`, 창 2 는 `-Label win2`).
9. `-Step layout` (a)(b): `persistedWindowLayouts` 를 예쁘게 출력하고 키 구조를 `_log/s1-state-keys.txt` 에 남긴다. `commandline` 문자열 포함 여부를 함께 찍는다.
10. `-Step count`: 현재 WT 창 수와 제목(UIA 탭 이름 포함)을 찍는다.
11. `-Step analyze`: (c)(d) before/after 쌍 비교(cwd 문자열 동일, `WT_SESSION` 동일), (e) 감시 로그의 변경 시각과 간격(초), (a)(b) 키 구조, (f) 되쓰기 결과.
12. **S1(f)**: WT 를 모두 닫는다(`allowHeadless` 가 켜져 있으면 프로세스가 남으므로 종료 확인) → `-Step rewrite` (감시 사본 중 창 수가 가장 많은 것을 `state.json` 에 되쓴다. 원본은 `_backup/state.before-rewrite.*.json`) → WT 를 열고 `-Step count` → `-Step analyze`.
13. `-Step cleanup`: 표식 줄 제거(원래 값 복원). WT 를 닫은 상태에서 하는 편이 안전하다.

### 무엇을 보나 / 판정
- (d) `analyze` 의 `(d) 폴더 복원 n/4`. 4/4 이면 합격. 실패한 셸은 헬퍼(OSC 9;9)가 실제로 나갔는지부터 본다.
- (c) `WT_SESSION 유지=True/False`. False 면 계획 4.3 절 2순위 매칭으로 간다.
- (e) 변경 이벤트가 창 2 닫힘 직후·창 1 닫힘 직후에 각각 찍히는지, 마지막 사본의 `persistedWindowLayouts` 가 1개(마지막 창만)인지, 이벤트 간격(`+n.ns`)을 초 단위로 적는다.
- (a)(b) 키 구조 텍스트를 results 에 붙인다. `commandline` 이 저장되면 (b) 는 "재실행 가능성 있음"으로 기록하고 실제 재실행은 복원된 pane 에서 관찰한다.
- (f) 되쓴 파일의 창 수 = 복원 뒤 관측 창 수이면 합격.

---

## 2. S5 — 훅 환경 (`spikes/S5-hook-env.ps1`)

**계획의 확인 내용(원문):** (a) interactive 훅에 `CCE_PANE_KEY`·`WT_SESSION`이 보이는가 (b) 훅 셸(Git Bash/PowerShell)과 exec 형식 절대경로(공백·한글) (c) 훅 시간, 그리고 **`cce claude`가 실행 시 한 번 호출하는 `claude auth status`의 지연**(콜드·웜 각 10회, ms) (d) `Restricted` 재현과 `RemoteSigned` 이후 동작 (e) VS Code 터미널에서 `cce hook`이 아무 일도 하지 않는지

**합격 기준(원문):** (a) 보임, (b) 두 셸 동작, (c) 훅 p95 100ms 이하. 실행 지연은 측정값을 보고한다(p95가 1초를 넘으면 실행 간 캐시(짧은 TTL)를 rev 5에서 검토), (d) 재현·해결, (e) 레지스트리 변경 0

**불합격 시 대체(원문):** (a) 실패 → `session_id`로 레지스트리 역조회

### 절차

1. `-Step prepare`
   `powershell -NoProfile -ExecutionPolicy Bypass -File spikes\S5-hook-env.ps1 -Step prepare`
   → 백업, `_log\경로 테스트 dir\`(공백+한글)에 훅 스크립트 사본 생성, `~/.claude/settings.json` 에 5 이벤트 × 4 형식 = 20 항목 추가:
   - `exec-bash`: `command: "C:\Program Files\Git\bin\bash.exe"`, `args: [<script>, <Event>, exec-bash, <logDir>]` (계획의 기본 형식)
   - `shell-bash-path`: 기본 셸(Git Bash) 문자열 `'C:/.../경로 테스트 dir/cce-spike-hook.sh' <Event> ...` (슬래시 + 작은따옴표)
   - `shell-ps-path`: `shell: "powershell"`, `& 'C:\...\경로 테스트 dir\cce-spike-hook.ps1' -Event ...`
   - `exec-ps`: `command: "powershell.exe"`, `args: [-NoProfile, -ExecutionPolicy, Bypass, -File, ...]`
   설치한 항목이 요약 출력된다. **실행 중인 Claude 세션은 다음 시작부터 반영된다.**
2. **[수동]** WT 의 PowerShell pane 에서 대역 실행기로 Claude 를 띄운다:
   `& 'C:\Users\qwer\Documents\GitHub\claude_env\spikes\common\cce-stub.ps1' -Scenario s5 -ClaudeArgs --permission-mode,manual`
   프롬프트 하나(`1+1은?`), 권한 요청이 뜨는 프롬프트 하나(`C:\Temp\s5.txt 를 만들어 줘` → 허용), 그리고 `/exit`.
3. **[수동]** (e) VS Code 통합 터미널에서 이 저장소 폴더로 가서 그냥 `claude` 를 띄우고 프롬프트 하나를 보낸 뒤 `/exit`. (`WT_SESSION`·`CCE_PANE_KEY` 가 없어야 한다)
4. `-Step bench -N 20`: 4 형식의 훅 명령을 PowerShell 에서 직접 20회 실행해 프로세스 생성을 포함한 벽시계 p50/p95 를 잰다 → `_log/s5-bench.json`.
5. `-Step auth -N 10 -ColdGapSeconds 20`: `claude auth status` 웜 10회(연속) + 콜드 10회(20초 간격, 총 약 3.5분) → `_log/s5-auth-latency.json`.
6. `-Step policy`: 현재 정책을 출력하고(**사용자 정책은 바꾸지 않는다**), 자식 프로세스에 `-ExecutionPolicy Restricted|AllSigned|RemoteSigned|Bypass` 를 줘서 `.ps1` 실행 차단·허용을 재현한다. exec 형식 훅(`-ExecutionPolicy Bypass`)이 정책과 무관하게 exit 0 인지 본다 → `_log/s5-policy.json`.
7. `-Step analyze`.
8. S4·S2 가 끝난 뒤 `-Step cleanup` (표식 훅만 제거).

### 무엇을 보나 / 판정
- (a) analyze 의 "stub 세션 n개, 그 훅 로그 m건, 둘 다 보인 건 m건 → 합격". 이벤트별 건수(SessionStart/UserPromptSubmit/Notification/Stop/SessionEnd)도 찍힌다. 0건인 이벤트가 있으면 그 이벤트는 그 상황에서 발생하지 않은 것이다.
- (b) 4 형식(`exec-bash`, `shell-bash-path`, `shell-ps-path`, `exec-ps`)이 모두 로그에 있으면 합격. 특정 형식만 없으면 그 형식의 인용·경로 처리가 실패한 것이다.
- (c) 두 값을 구분해 적는다. ① `dur_ms` = 스크립트 자체 시간(bash 내장만 사용, 수 ms), ② `[bench]` = 프로세스 생성 포함 벽시계. **사전 측정(이 문서 부록 A.4)에서 bash.exe exec 형식 ≈ 245ms, powershell.exe ≈ 220ms 로 둘 다 100ms 를 넘는다.** 이는 스크립트 훅의 바닥값이고, 계획의 p95 100ms 기준은 Rust `cce.exe` 를 exec 형식으로 직접 호출할 때(Step 2 의 hyperfine)에 적용한다. results 에는 "스크립트 훅으로는 미달, cce.exe 로 재측정" 으로 적는다.
- (c) `auth status` p95 가 1000ms 를 넘으면 캐시 검토. 사전 측정은 웜·콜드 모두 160~180ms.
- (d) Restricted 에서 `scriptRan=False`, RemoteSigned 에서 `True`, Bypass 훅 exit 0 이면 합격. (사전 실행에서 이미 이 결과가 나왔다 — 부록 A.5)
- (e) `TERM_PROGRAM=vscode` 항목의 `skipped=true`, `status_written`·`title_emitted` 비어 있음, `WT_SESSION`·`CCE_PANE_KEY` 비어 있음이면 합격.

---

## 3. S4 — 제목, interactive (`spikes/S4-title.ps1`)

**계획의 확인 내용(원문):** (a) `sessionTitle`로 정한 이름이 WT 탭에 `<아이콘> <이름>`으로 보이는가, busy·idle·waiting의 아이콘 글리프와 코드포인트 수, idle에서 아이콘 유무 (c) 부제까지 같은 이름이 둘일 때 변형 접미어 (d) **Claude 자동 생성 제목을 얻을 수 있는가**: 이름이 없는 세션에서 statusline `session_name`, transcript의 제목 레코드, `claude agents --json`의 `name` 가운데 어디에 나타나는가. 하위 확인 두 가지: (d-1) `SessionStart`에서 이름을 정하면 자동 제목이 여전히 생성·획득되는가, (d-2) **이름을 `SessionStart`가 아니라 첫 `UserPromptSubmit`에서 정할 때** 자동 제목이 여전히 생성되고 얻을 수 있는가(statusline `session_name`, transcript, 그 밖) (e) 사용자가 `/rename`한 값을 감지할 수 있는가(다음 `SessionStart`의 `session_title`, statusline `session_name`, transcript). **도구 자신의 형식(T-7 정규식 일치 + 부제가 레지스트리 `subtitle`과 같음)은 `/rename`으로 세지 않는다** (f) `UserPromptSubmit`의 `sessionTitle`이 첫 프롬프트에서 바로 탭에 반영되는가

**합격 기준(원문):** (a) 세 상태 모두에서 아이콘을 뺀 텍스트가 정한 이름과 같다. (d)는 d-1 또는 d-2 가운데 하나라도 자동 제목을 얻을 수 있으면 합격이며, 합격 시에만 4.6절 출처 2를 켠다(Q8 재검토). (e)는 결과로 감지 수단을 확정한다. (c)의 변형 접미어 형식은 T-7의 첫 프롬프트 전 정규식에 넣는다

**불합격 시 대체(원문):** (a) 실패 → 훅 `terminalSequence`로 제목 출력(Claude와 같은 글리프 사용) → 그것도 안 되면 `--suppressApplicationTitle`(아이콘 포기, 사용자 승인). (d) 실패 → 부제 대체값(첫 프롬프트 요약). 기존 statusline(OMC HUD 등)을 쓰는 경우 statusline 방식은 쓰지 않는다

### 이 스파이크가 쓰는 자동 제목 출처(statusline 은 쓰지 않는다)
사용자 설정에 OMC HUD statusline 이 있으므로 statusline 을 교체하지 않는다. 대신 로컬에서 확인한 세 출처를 모두 본다:
1. transcript `.jsonl` 의 `{"type":"ai-title","aiTitle":"..."}` 레코드 (로컬 관찰: 이 세션 transcript 에 44개, 턴마다 갱신. 문서화되지 않은 계약)
2. `~/.claude/sessions/<pid>.json` 의 `name` / `nameSource` (`derived` = 기본 표시 이름 `claude-env-3c`, `auto` = 자동 제목. 문서화되지 않은 계약)
3. `claude agents --json` 의 `name` (문서화됨. 단, 문서상 이름 없는 interactive 세션은 **기본 표시 이름**을 보이고 첫 프롬프트 제목은 보이지 않는다)

### 절차 (제목 모드마다 반복: `both` → `SessionStart`(d-1) → `UserPromptSubmit`(d-2))

1. `-Step prepare -Mode both -Base 'claude_env [개인]'` (S5 의 훅이 있으면 재사용). `_log/title-mode.txt`, `title-base.txt` 기록.
2. `-Step snapshot -Label before` (sessions json 사본, `agents --json`, stub transcript 줄 수).
3. **[수동]** WT PowerShell pane: `& 'C:\...\spikes\common\cce-stub.ps1' -Scenario s4-both -ClaudeArgs --permission-mode,manual`. 첫 프롬프트 전 탭 제목을 본다(`<아이콘> claude_env [개인]` 이어야 함).
4. 다른 콘솔에서 `-Step collect -Label both -Seconds 120` 를 켜 둔다(0.5초마다 WT 창 제목 + UIA 탭 이름, 바뀔 때만 기록, 코드포인트 포함 → `_log/s4-titles.jsonl`).
5. **[수동]** 프롬프트 전송(`로그인 버그를 고쳐줘. 먼저 계획만 말해`) → busy 5초 이상 → 응답 완료(idle) 5초 이상 → `C:\Temp\s4.txt 만들어줘` 로 권한 요청(waiting) 5초 이상 → 허용.
6. **[수동]** (c) 같은 폴더에서 두 번째 탭을 열어 같은 명령·같은 프롬프트로 두 번째 세션을 띄운다.
7. **[수동]** (e) 첫 세션에서 `/rename 내이름` → 5초 뒤 `-Step snapshot -Label after-rename` → `/exit` → 같은 pane 에서 `& '...\cce-stub.ps1' -Scenario s4-both -Resume` (SessionStart(resume) 입력의 `session_title` 관찰) → `/exit`.
8. `-Step snapshot -Label after` → `-Step analyze`.
9. `-Mode SessionStart`, `-Mode UserPromptSubmit` 로 1~8 을 반복(단계 6·7 은 생략 가능). (a) 가 불합격이면 `-Mode osc` 로 대체 경로(`terminalSequence`)를 시험한다.
10. 마지막에 `-Step cleanup` (훅 제거 + 제목 모드 none).

### 무엇을 보나 / 판정
- (a) analyze 가 라벨별로 관측한 탭 제목을 `icon='✳' [U+2733] text='claude_env [개인] · 로그인 버그를 ...' 이름과 같음=True` 형식으로 찍는다. busy·idle·waiting 각각에서 `이름과 같음=True` 면 합격. 관측한 글리프 집합과 코드포인트 수를 results 의 `<ICON>` 란에 적는다(사전 관측: `✳` U+2733, `◐` U+25D0 — 부록 A.6). idle 에 아이콘이 없으면 `icon=없음` 으로 찍힌다.
- (c) `접미어 '...'` 줄. 문서상 형식은 두 단어 접미어(`-graceful-unicorn`). 관측 형식을 T-7 첫 프롬프트 전 정규식에 넣는다.
- (d) 세션마다 `transcript ai-title n개 / sessions json nameSource / agents name` 이 찍히고 "이름을 정한 뒤에도 자동 제목을 얻을 수 있음: True/False (d-1|d-2)" 로 판정한다. 하나라도 True 면 합격 → 4.6절 출처 2 를 켜되, **출처가 transcript/sessions json 이면 문서화되지 않은 계약이므로 ADR 원칙 2 예외에 추가해야 한다.**
- (e) `SessionStart 입력 session_title` 값, 스냅샷 간 `name/nameSource` 변화, transcript 새 레코드 유형 목록에서 `/rename` 이 어디에 나타나는지 확정한다.
- (f) "훅 → 탭 관측 지연 n.ns" 가 찍히면 반영된 것. `관측하지 못했다` 면 collect 가 꺼져 있었는지 먼저 확인한다.

---

## 4. S2 — 닫기 신호 (`spikes/S2-close-signal.ps1`)

**계획의 확인 내용(원문):** 응답 중 탭 닫기·창 닫기 → (a) 처리기가 1초 안에 레지스트리를 쓰는가 (b) jsonl에 마지막 사용자 메시지와 완료된 턴이 모두 있는가, 스트리밍 중 응답이 어떻게 남는가 (c) `SessionEnd` 발생 여부 (d) **권한 요청에서 멈춘 턴(`lastStatus=waiting`)을 닫았을 때**: 기대 상태는 state `interrupted` + 플래그 `interrupted=true`(턴이 끝나지 않았으므로). jsonl에 사용자 메시지가 남고, 복원 시 제목에 ⏸중단 표시가 붙는가. 10회. **반례(d-2):** 턴이 끝나고 `Notification(idle_prompt)`가 온 뒤 창을 닫으면 `windowClosed`이지 `interrupted`가 아니어야 한다(복원 시 ⏸중단 없음). 10회 (e) **경쟁 반복 시험:** 자식 claude 정상 종료 직후에 창을 닫는 경우와 창 닫기만 하는 경우를 각각 20회

**합격 기준(원문):** (a) 20/20 (b) 20/20 (d) 10/10 `interrupted`이고 복원 후 ⏸중단 표시 10/10, 반례 d-2는 10/10 `windowClosed`이고 ⏸중단 0/10 (e) 40회 중 오분류 0

**불합격 시 대체(원문):** (a) 실패 → 트레이가 pid 소멸로 판단

### 대역이 흉내 내는 것 (계획 4.1 §6)
- `cce-stub.ps1` 이 UUID 를 만들어 `claude --session-id <uuid>` 로 띄우고 `CCE_PANE_KEY=WT_SESSION` 을 넘긴다.
- C# 처리기: `CTRL_C`/`CTRL_BREAK` 는 TRUE 로 무시. `CTRL_CLOSE_EVENT` 는 원자적 `closing` 플래그 → `_log/status/<uuid>.status`(훅이 갱신: busy/idle/waiting) 를 읽어 `busy|waiting` 이면 `interrupted` + `<uuid>.interrupted` 플래그, 그 밖이면 `windowClosed` 를 `_log/registry.jsonl` 에 추가하고 쓰기까지 걸린 ms 를 기록.
- 자식 종료 경로: 300ms 대기 → `closing` 플래그가 없을 때만 `closed` 기록 → 3초 더 대기(linger, 경쟁 시험용).
- 훅(`cce-spike-hook.sh`): `SessionStart(resume)` 에서 플래그가 있으면 `sessionTitle` 을 `claude_env [개인] · ⏸중단 <부제>` 로, 첫 `UserPromptSubmit` 에서 플래그를 지우고 원래 형식으로 되돌린다. `Notification(idle_prompt)` 는 `idle` 로 기록한다(rev 5 승인 조건).
- 분석기는 append-only 레지스트리에 우선순위 `windowClosed`/`interrupted` > `closed` 를 적용해 최종 상태를 정한다.

### 절차

1. `-Step prepare` (훅 재사용, 제목 모드 both).
2. **[수동]** 회차마다 WT PowerShell pane 에서:
   `& 'C:\Users\qwer\Documents\GitHub\claude_env\spikes\S2-close-signal.ps1' -Step run -Scenario <시나리오> [-ClaudeArgs --permission-mode,manual]`
   | 시나리오 | 사람이 하는 일 | 기대 최종 상태 | 회수 |
   |---|---|---|---|
   | `busy` | `1부터 200까지 한 줄에 하나씩 쓴 out.txt 를 만들어 줘` 를 보내고 **응답이 흐르는 중에 창(또는 탭)을 X 로 닫는다** | `interrupted` + 플래그 | 10 |
   | `waiting` | (`--permission-mode,manual`) `C:\Temp\s2.txt 를 만들어 줘` → **권한 대화상자가 떠 있을 때 X** | `interrupted` + 플래그 | 10 |
   | `idle_prompt` | `1+1은?` → 응답 끝 → **60초 이상 기다려 idle 알림이 온 뒤 X** | `windowClosed`, 플래그 없음 | 10 |
   | `race-exit` | 프롬프트 하나 → 끝난 뒤 `/exit` 를 치고 **3초 안에 X** | `windowClosed`(closed 를 이김), `interrupted` 아님 | 20 |
   | `close-only` | Claude 가 뜨면 **프롬프트 없이(또는 idle 에서) 바로 X** | `windowClosed` | 20 |
3. **[수동]** `busy`·`waiting`·`idle_prompt` 각 회차 뒤 복원 확인: 새 pane 에서 `-Step resume -Scenario <같은 시나리오>` → 탭 제목에 `⏸중단` 이 있는지(idle_prompt 는 없어야 함) 보고, 프롬프트 하나를 보내 표시가 사라지는지 본 뒤 `/exit`. (한 회차마다 하지 않고 시나리오 끝에 몰아서 해도 되지만, 그러면 마지막 세션만 복원된다. 10/10 을 채우려면 회차마다 한다.)
4. `-Step collect` (stub 세션 transcript 를 `_log/s2-transcripts/` 로 복사) → `-Step analyze` → `-Step cleanup`.

### 무엇을 보나 / 판정
analyze 표의 열: `final`(최종 상태), `lastStatus`(닫는 순간 상태 파일 값), `flag`(interrupted 플래그), `handlerMs`(처리기 쓰기 ms), `closedAlso`(closed 도 기록됐는지 = 경쟁 발생), `sessionEnd`, `txUser`(마지막 프롬프트가 transcript 에 있음), `txAsst`(그 뒤 assistant 레코드 수), `txStop`(마지막 assistant `stop_reason`; 비어 있으면 스트리밍 중 잘림), `resumeMark`(복원 시 ⏸중단), `clearedAfterPrompt`.
- (a) `handlerMs < 1000` 인 회차 수 / 처리기가 돈 회차 수 = 20/20 이상.
- (b) `txUser=True` 20/20. `txStop` 이 비어 있는 회차는 "스트리밍 중 응답 뒷부분 유실(AC-2 완화로 수용)" 로 기록.
- (c) `sessionEnd` 열: 창 닫기 뒤 SessionEnd 가 돌았는지(1.5초 예산). 기록용.
- (d) busy·waiting: `interrupted + flag` 10/10, `resumeMark=True` 10/10. (d-2) idle_prompt: `windowClosed` 10/10, `resumeMark` 0/10.
- (e) race-exit 20 + close-only 20 에서 오분류 0. 오분류 정의: `interrupted` 가 나오거나, 처리기가 돌았는데 최종이 `windowClosed` 가 아니거나(우선순위 역전), close-only 가 `windowClosed` 가 아닌 경우.

---

## 5. 시간 계획(참고)
S1 약 40분(WT 열고 닫기 2회 + 되쓰기), S5 약 20분(auth 콜드 측정 3.5분 포함), S4 약 30분 × 모드 3개, S2 약 90분(70회차 + 복원 30회). 하루에 끝나지 않으면 `-Step cleanup` 없이 두고 이어서 해도 된다(훅은 무해).

## 6. 복원 (맨 마지막)

```powershell
# 1) 훅 제거(어느 스크립트로 해도 같다)
powershell -NoProfile -ExecutionPolicy Bypass -File spikes\S5-hook-env.ps1 -Step cleanup
# 2) WT 표식 제거
powershell -NoProfile -ExecutionPolicy Bypass -File spikes\S1-wt-layout.ps1 -Step cleanup
# 3) WT 를 모두 닫은 뒤 전체 원복(해시 검증). 가장 최근 백업 대신 특정 백업을 쓰려면 -Timestamp <폴더명>
powershell -NoProfile -ExecutionPolicy Bypass -File spikes\common\restore.ps1 -WhatIf
powershell -NoProfile -ExecutionPolicy Bypass -File spikes\common\restore.ps1 -Timestamp <start 백업 폴더명>
```
`restore.ps1` 은 항목마다 `RESTORED / UNCHANGED / ABSENT-AS-BEFORE / HASH-MISMATCH` 를 표로 보여 주고, 백업 시점에 없던 파일이 생겼으면 `NEW-FILE-KEPT` 로 알린다(`-RemoveCreated` 로 삭제).

---

## 부록 A. 로컬 확인 기록 (2026-09-23, 읽기 전용 명령만)

### A.1 버전·경로
- `claude --version` → `2.1.280 (Claude Code)`, 실행 파일 `C:\Users\qwer\.local\bin\claude.exe`
- Windows Terminal `1.24.11911.0`; `settings.json` 5,424 bytes, `//` 주석 없음, `firstWindowPreference` 없음; `state.json` 339 bytes, 최상위 키 `generatedProfiles, persistedWindowLayouts, settingsHash`, `persistedWindowLayouts` **0개**(기능이 꺼져 있어 저장된 것이 없음 → S1(a) 구조는 켠 뒤에만 볼 수 있다)
- Git Bash `C:\Program Files\Git\bin\bash.exe` = GNU bash 5.2.26 (msys). `jq` 없음(훅은 bash 내장만 쓴다).
- pwsh 7: 이 시점에 없음(설치 중). WSL: `Ubuntu-24.04`, `docker-desktop`.
- `Get-ExecutionPolicy -List`: CurrentUser `RemoteSigned`, Process `Bypass`, 나머지 Undefined. PS 5.1 `$PROFILE` 파일 없음, pwsh 7 프로필 없음, `.bashrc` 없음, `.bash_profile` 있음(268 bytes).
- `~/.claude/settings.json`: 훅 없음, `statusLine` = OMC HUD (`node.exe C:/Users/qwer/.claude/hud/omc-hud.mjs`), `permissions.defaultMode: auto`, `skipAutoPermissionPrompt: true`.

### A.2 `claude auth status` (JSON 이 기본 출력, `--json` 불필요)
```json
{ "loggedIn": true, "authMethod": "claude.ai", "apiProvider": "firstParty", "email": "y0***@gmail.com",
  "orgName": "...'s Organization", "subscriptionType": "max", "configDirectory": "C:\\Users\\qwer\\.claude" }
```

### A.3 `claude agents --json` 발췌
```json
{ "pid": 37788, "cwd": "C:\\Users\\qwer\\Documents\\GitHub\\claude_env", "kind": "interactive",
  "startedAt": 1790124094324, "sessionId": "56cbd6c5-...", "name": "claude-env-3c", "status": "busy" }
{ "id": "3d038243", "kind": "background", "sessionId": "3d038243-...", "name": "문서 수정 승인 조항 추가", "state": "blocked" }
```
interactive 세션의 `name` 은 기본 표시 이름(`<폴더>-<2자>`), background 세션의 `name` 은 자동 제목이다.
같은 세션의 `~/.claude/sessions/37788.json`: `"name":"claude-env-3c","nameSource":"derived"`, 다른 세션은 `"nameSource":"auto"`. 필드: `pid, sessionId, cwd, startedAt, procStart, version, kind, entrypoint, name, nameSource, nameSince, status, statusUpdatedAt, updatedAt, messagingSocketPath`.
이 세션 transcript 의 레코드 유형: `user 108, assistant 174, attachment 516, system 37, ai-title 44, last-prompt 45, mode 45, permission-mode 45, atis-latch 45, queue-operation 48, file-history-snapshot 13, file-history-delta 4`. `ai-title` 예: `{"type":"ai-title","aiTitle":"...","sessionId":"..."}`.

### A.4 훅 명령 벽시계(사전 측정, N=5, `-Step bench`)
| 형식 | p50 | p95 |
|---|---|---|
| exec-bash (`bash.exe` + args) | 244.6 ms | 248.8 ms |
| exec-ps (`powershell.exe -NoProfile -File`) | 217.2 ms | 221.8 ms |
| bash 스크립트 자체(`dur_ms`) | 수 ms | — |
| `claude auth status` 웜 / 콜드(1초 간격) | 160 / 168 ms | 181 / 180 ms |

### A.5 실행 정책 재현(사전 실행, `-Step policy`)
자식 `-ExecutionPolicy Restricted` → `.ps1` 차단("이 시스템에서 스크립트를 실행할 수 없으므로"), `AllSigned` → 차단, `RemoteSigned` → 실행, `Bypass` → 실행. exec 형식 훅(`-ExecutionPolicy Bypass`) exit 0.

### A.6 WT 탭 제목 관측(UIA, 이 세션의 WT)
`✳ lighting-array-analysis`, `◐ 회의록 확인`, `✳ 중단되었던 일 진행`, `◐ 폴더를 깃 레포로 생성` → 글리프 `✳` = U+2733, `◐` = U+25D0 (각 1 코드포인트). WT 창 제목(GetWindowText)은 활성 탭 제목과 같았다.

### A.7 `claude --help` 에서 확인한 플래그(계획 4.1 인자 분류와 관련)
`--session-id <uuid>`, `-r/--resume [value]`, `-c/--continue`, `--fork-session`, `-n/--name`, `--bg/--background`(`--resume <id>` 와 함께 쓰면 **같은 ID 로 백그라운드에서 이어감**), `--settings <file-or-json>`, `--permission-mode <acceptEdits|auto|bypassPermissions|manual|dontAsk|plan>`, `-p/--print`, `--bare`, `--safe-mode`. 하위 명령: `agents, attach, auth, auto-mode, doctor, gateway, import, install, logs, mcp, plugin|plugins, project, respawn, rm, setup-token, stop|kill, ultrareview, update|upgrade`.

## 부록 B. 문서·로컬 사실이 계획과 다르거나 보충하는 점
1. **훅 출력 형식**: `sessionTitle`·`terminalSequence` 는 최상위가 아니라 `{"hookSpecificOutput":{"hookEventName":"SessionStart","sessionTitle":"..."}}` 안에 둔다(훅 문서). 스크립트는 이 형식을 쓴다.
2. **자동 제목과 `agents --json`**: 세션 문서에 따르면 이름 없는 interactive 세션의 listings(`agents --json` 포함)에는 첫 프롬프트 제목이 아니라 기본 표시 이름(`my-app-3f`)이 나온다. 첫 프롬프트 제목은 session picker 와 statusline `session_name` 에만 나오고, 계획 accept 시의 제목만 listings 에도 나온다. 따라서 계획 4.6절 출처 2 의 "`agents --json` 의 `name` 으로만 얻을 수 있으면 트레이 폴링" 경로는 interactive 세션에서는 기대하기 어렵다. 로컬 관찰의 transcript `ai-title` 레코드와 `sessions/<pid>.json` `nameSource:auto` 가 대안이며, 둘 다 문서화되지 않은 계약이다(S4(d) 로 확정).
3. **이름을 정하면 자동 제목이 대체된다**: "Naming the session replaces [the generated title]". d-1/d-2 는 정확히 이 점을 시험한다. `/clear` 는 `--name`/`/rename` 이름은 유지하지만 AI 제목은 버린다.
4. **중복 이름 접미어**: 살아 있는 세션과 이름이 겹치면 두 단어 접미어(`auth-refactor-graceful-unicorn`). AI 제목·기본 표시 이름은 검사하지 않는다. `-p`·background 의 `--name` 도 시작 시 검사하지 않는다.
5. **Windows 훅 셸**: `shell` 필드(`"bash"|"powershell"`)가 있고 기본은 Git Bash, 없으면 PowerShell. `args` 가 있으면 `shell` 은 무시된다. statusline 문서: Git Bash 경로의 역슬래시가 먹히므로 command 문자열에는 슬래시를 쓴다(4.5절 설치기가 지켜야 함). `CLAUDE_CODE_GIT_BASH_PATH` 는 훅 문서에 없다(미확인).
6. **`SessionEnd` 예산**: 1.5초 공유이지만 훅의 `timeout` 을 크게 주면 최대 60초까지 올라간다. `UserPromptSubmit` 의 기본 timeout 은 30초.
7. **`Notification` 유형**: 문서 목록에 `elicitation_url_dialog`, `agent_completed`, `quota_auto_resume_*` 도 있다. 훅은 `elicitation_url_dialog` 도 waiting 으로 넣었다.
8. **권한 모드**: 사용자 설정이 `auto` 라 권한 요청이 뜨지 않을 수 있다 → waiting 시험은 `--permission-mode manual` 로 띄운다(`--help` 의 choices 에 `manual` 이 있다).
9. **훅 시간 100ms**: 스크립트 훅(bash/powershell)의 프로세스 바닥값이 220~250ms 라 스파이크 훅으로는 기준을 못 넘긴다. 기준은 `cce.exe` 에 적용해야 한다(위 A.4).
10. **`--bg --resume <id>` 는 같은 ID 유지**(`--help` 원문) → S3-7 의 한쪽(`--resume --bg`)은 문서로 이미 답이 있다(다른 레인 참고).
11. **`claude auth status`** 는 기본이 JSON 이고 `email`·`subscriptionType` 을 준다(4.1절 4 의 계정 캐시에 바로 쓸 수 있다).
