# 스파이크 결과 — A 경로 (S1, S5, S4, S2)

- 계획: `docs/planning/plan-ralplan.md` §5 Step 0. 절차: `docs/spikes/runbook.md`.
- 실행 환경: Windows 11 Home, WT 1.24.11911.0, Claude Code 2.1.280, PowerShell 5.1 (pwsh 7: ___ ), Rust: 없음(대역 `cce-stub.ps1` 사용)
- 실행일: ____-__-__   실행자: ____
- 증거 파일은 `spikes/_log/`(gitignore) 에 있고, 여기에는 파일 이름·발췌·측정값을 옮겨 적는다.
- 판정 규칙: 합격 기준은 계획 표의 원문을 그대로 쓴다. 자료가 없으면 "미실행", 기준을 못 채우면 "불합격" 과 함께 "선택한 대체 경로" 를 채운다.

## S1 — WT 레이아웃

| 항목 | 확인할 내용 | 합격 기준 | 합격/불합격 | 증거(파일·측정값) | 선택한 대체 경로 |
|---|---|---|---|---|---|
| S1(a) | `persistedWindowLayouts` 키 구조 | 결과를 기록해 설계 분기에 쓴다 | | `_log/s1-state-keys.txt`, `_log/s1-layouts-pretty.json` 발췌: | (해당 없음. 4.4절 되쓰기 안전장치 (1) 의 "확인한 키 구조" 로 사용) |
| S1(b) | commandline 재실행 여부 | 결과를 기록 | | `layout` 출력의 `'commandline' 포함 여부`, 복원된 pane 에서 명령이 다시 실행됐는지(관찰): | 재실행에 기대지 않고 `restore-check`(계획 7절) |
| S1(c) | 복원 후 `WT_SESSION` 유지 여부 | 결과를 기록 | | `analyze` 의 `WT_SESSION 유지=` (pane 별): | 다름 → 4.3절 2순위 매칭 |
| S1(d) | 폴더 복원 | pwsh 5.1·pwsh 7·Git Bash·WSL(Ubuntu) 각각 복원 후 `pwd` 가 닫기 전과 문자열로 같다(4/4) | | `analyze` 의 `(d) 폴더 복원 n/4`, `_log/s1-panes.jsonl` 발췌(셸별 before/after cwd): | 실패한 셸 → 통합 수정 후 재시험 |
| S1(e) | 창 2개를 10초 간격으로 닫을 때 저장 내용과 자동 저장 간격 | 두 번째 창만 저장됨을 재현하고 간격을 초 단위로 기록 | | `_log/s1-state-watch.jsonl` 변경 이벤트(시각, layouts 수, 간격 초): | 4.4절 보관기 합치기(`closeGraceSeconds`) |
| S1(f) | WT 가 꺼진 상태에서 되쓴 파일을 WT 가 읽는가 | 결과를 기록 | | `_log/s1-rewrite.jsonl`, `_log/s1-count.jsonl`(되쓴 창 수 vs 관측 창 수): | 실패 → `wt.exe` 재구성(4.4절) |

## S5 — 훅 환경

| 항목 | 확인할 내용 | 합격 기준 | 합격/불합격 | 증거(파일·측정값) | 선택한 대체 경로 |
|---|---|---|---|---|---|
| S5(a) | interactive 훅에 `CCE_PANE_KEY`·`WT_SESSION` 이 보이는가 | 보임 | | `analyze (a)`: stub 세션 n개 / 훅 로그 m건 / 둘 다 보인 건 k건. 이벤트별 건수: | 실패 → `session_id` 로 레지스트리 역조회 |
| S5(b) | 훅 셸(Git Bash/PowerShell)과 exec 형식 절대경로(공백·한글) | 두 셸 동작 | | `analyze (b)`: 4 형식(`exec-bash`, `shell-bash-path`, `shell-ps-path`, `exec-ps`) 실행 기록: | |
| S5(c)-1 | 훅 시간 | 훅 p95 100ms 이하 | | `_log/s5-bench.json` p50/p95 (형식별), `dur_ms` p95. 사전 측정: exec-bash p95 249ms, exec-ps 222ms (스크립트 자체 수 ms): | 스크립트 훅으로는 미달 → 기준은 Step 2 의 `cce.exe`(hyperfine) 에 적용 |
| S5(c)-2 | `claude auth status` 지연(콜드·웜 각 10회, ms) | 측정값을 보고(p95 > 1초면 실행 간 캐시 검토) | | `_log/s5-auth-latency.json` warm p50/p95, cold p50/p95. 사전 측정: warm 160/181, cold 168/180 ms: | |
| S5(d) | `Restricted` 재현과 `RemoteSigned` 이후 동작 | 재현·해결 | | `_log/s5-policy.json`: Restricted scriptRan=__, RemoteSigned scriptRan=__, Bypass 훅 exit=__ (사용자 정책은 바꾸지 않고 자식 프로세스 범위로 재현): | |
| S5(e) | VS Code 터미널에서 `cce hook` 이 아무 일도 하지 않는지 | 레지스트리 변경 0 | | `analyze (e)`: vscode 훅 로그 n건 중 상태·제목을 쓴 건 0건, `WT_SESSION`/`CCE_PANE_KEY` 비어 있음: | |

## S4 — 제목 (interactive)

| 항목 | 확인할 내용 | 합격 기준 | 합격/불합격 | 증거(파일·측정값) | 선택한 대체 경로 |
|---|---|---|---|---|---|
| S4(a) | `sessionTitle` 로 정한 이름이 WT 탭에 `<아이콘> <이름>` 으로 보이는가; busy·idle·waiting 의 아이콘 글리프와 코드포인트 수; idle 에서 아이콘 유무 | 세 상태 모두에서 아이콘을 뺀 텍스트가 정한 이름과 같다 | | `_log/s4-titles.jsonl` 발췌(상태별 제목·codepoints). 글리프 집합 `<ICON>` = { ___ } (사전 관측 `✳` U+2733, `◐` U+25D0). idle 아이콘: 있음/없음: | 실패 → 훅 `terminalSequence`(`-Mode osc`) → 그것도 안 되면 `--suppressApplicationTitle`(아이콘 포기, 사용자 승인) |
| S4(c) | 부제까지 같은 이름이 둘일 때 변형 접미어 | 관측 형식을 T-7 첫 프롬프트 전 정규식에 넣는다 | | `analyze (c)` 의 접미어 문자열(문서 기대: 두 단어 `-xxx-yyy`): | |
| S4(d-1) | `SessionStart` 에서 이름을 정하면 자동 제목이 여전히 생성·획득되는가(출처: transcript `ai-title` / `sessions/<pid>.json` `nameSource` / `agents --json` `name`) | d-1 또는 d-2 하나라도 얻을 수 있으면 (d) 합격 → 4.6절 출처 2 를 켠다 | | `-Mode SessionStart` 세션의 `analyze (d)` 줄: ai-title n개 / nameSource / agents name: | 실패 → 부제 대체값(첫 프롬프트 요약, 출처 3) |
| S4(d-2) | 첫 `UserPromptSubmit` 에서 이름을 정할 때 자동 제목이 여전히 생성되고 얻을 수 있는가 | 위와 같음 | | `-Mode UserPromptSubmit` 세션의 `analyze (d)` 줄: | 위와 같음. 합격 출처가 문서화되지 않은 계약이면 ADR 원칙 2 예외에 추가 |
| S4(e) | 사용자가 `/rename` 한 값을 감지할 수 있는가(다음 `SessionStart` 의 `session_title`, statusline `session_name`, transcript). 도구 자신의 형식은 `/rename` 으로 세지 않는다 | 결과로 감지 수단을 확정한다 | | `analyze (e)`: SessionStart(resume) `session_title` 값, `sessions json` name/nameSource 변화, transcript 새 레코드 유형: | 확정한 수단: ___ |
| S4(f) | `UserPromptSubmit` 의 `sessionTitle` 이 첫 프롬프트에서 바로 탭에 반영되는가 | 반영 여부와 지연을 기록 | | `analyze (f)`: 훅 시각 → 탭 관측 시각, 지연 초: | |

## S2 — 닫기 신호 (A 의 AC-1·AC-2)

| 항목 | 확인할 내용 | 합격 기준 | 합격/불합격 | 증거(파일·측정값) | 선택한 대체 경로 |
|---|---|---|---|---|---|
| S2(a) | 처리기가 1초 안에 레지스트리를 쓰는가 | 20/20 | | `_log/s2-analysis.json` `handlerMs` 분포(최대·p95), 1초 안 n/20: | 실패 → 트레이가 pid 소멸로 판단 |
| S2(b) | jsonl 에 마지막 사용자 메시지와 완료된 턴이 모두 있는가, 스트리밍 중 응답이 어떻게 남는가 | 20/20 | | `txUser` n/20, `txAsst`, `txStop`(비어 있음 = 잘림) 요약, `_log/s2-transcripts/<uuid>.jsonl` 마지막 레코드 유형: | AC-2 완화(승인됨) |
| S2(c) | `SessionEnd` 발생 여부 | 기록 | | `sessionEnd` 열 n/20, SessionEnd 훅 `reason` 값: | |
| S2(d) busy | 응답 중 닫기 → state `interrupted` + 플래그, jsonl 에 사용자 메시지, 복원 시 ⏸중단 | 10/10 `interrupted`, 복원 후 ⏸중단 10/10 | | busy: interrupted+플래그 n/10, resumeMark n/10, clearedAfterPrompt: | |
| S2(d) waiting | 권한 요청에서 멈춘 턴(`lastStatus=waiting`)을 닫았을 때 위와 같음 | 10/10, 10/10 | | waiting: interrupted+플래그 n/10, resumeMark n/10 (`--permission-mode manual` 로 실행): | |
| S2(d-2) 반례 | `Notification(idle_prompt)` 뒤 닫기 → `windowClosed`, ⏸중단 없음 | 10/10 `windowClosed`, ⏸중단 0/10 | | idle_prompt: windowClosed n/10, resumeMark n/10 (0 이어야 함), 훅 로그의 `notification_type=idle_prompt` → `status_written=idle` 확인: | |
| S2(e) race-exit | 자식 claude 정상 종료 직후 창 닫기 20회 | 40회 중 오분류 0 | | race-exit n회, 오분류 n (`closedAlso=True` 이면서 final=`windowClosed` 인 회차 수 = 경쟁이 실제로 발생한 횟수): | |
| S2(e) close-only | 창 닫기만 20회 | 40회 중 오분류 0 | | close-only n회, 오분류 n: | |

## 종합 판정과 설계 반영

| 결정 항목 | 근거 스파이크 | 결정 |
|---|---|---|
| 복원 매칭: 1순위 `WT_SESSION` 유지 vs 2순위 탭 순서 매칭 | S1(c) | |
| `state.json` 되쓰기 vs `wt.exe` 재구성 | S1(a)(f) | |
| pane 찾기: `CCE_PANE_KEY` vs `session_id` 역조회 | S5(a) | |
| 훅 형식(exec + 절대경로) 확정, 셸 폴백 | S5(b)(d) | |
| 부제 출처 2(자동 제목) 채택 여부와 출처(Q8 재검토) | S4(d) | |
| `/rename` 감지 수단 | S4(e) | |
| T-7 `<ICON>` 집합·변형 접미어 정규식 | S4(a)(c) | |
| AC-1 대체 충족(중단 감지 + 이어가기) 성립 여부 | S2(a)(d)(e) | |
| AC-2 완화 기준 성립 여부 | S2(b) | |

## 미해결·후속
- (여기에 스파이크 중 드러난 새 위험, 재시험이 필요한 항목, 다른 레인(S3, S4(b))에 넘길 관찰을 적는다)
