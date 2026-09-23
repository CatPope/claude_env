# 스파이크 결과 — C 경로 (S3, S4(b))

- 계획: `docs/planning/plan-ralplan.md` §5 Step 0 (S3 bg-attach, S4(b) 제목(attach))
- 절차: `docs/spikes/runbook-c.md`
- 스크립트: `spikes/S3-bg-attach.ps1`, `spikes/S4b-title-attach.ps1`, `spikes/common/c-lib.ps1`, `spikes/c-assets/*`
- 자동 판정 로그: `spikes/_log/verdicts-c.jsonl` (각 스크립트의 `analyze` 가 덧붙인다)
- 환경: Windows 11 Home 10.0.26200, Windows Terminal 1.24.11911.0, Claude Code 2.1.280, Windows PowerShell 5.1.26100
- 상태: **미실행** (스크립트·절차만 준비됨. 실행 후 아래 표를 채운다)

`docs/spikes/results.md` 가 생기면 이 표의 행을 그 파일에 옮겨 붙이고 이 파일은 지운다.

## S3 bg-attach (계획 §5 Step 0 S3)

| 항목 | 확인할 내용(계획 원문 요약) | 합격 기준(계획 원문) | 합격/불합격 | 증거 | 선택한 대체 경로 |
|---|---|---|---|---|---|
| S3-1 | `claude --bg`(프롬프트 없이) → attach | 합격 필수 | 미실행 | `spikes/_log/s3-bg-attach.jsonl` (kind=launch/collect/manual, step=S3-1) | — |
| S3-2 | `--session-id` + `--bg` | 결과를 기록해 대체 경로를 고른다 | 미실행 | 같은 파일 step=S3-2 (`sameId`, `shortIsPrefix`) | 불합격 시: 실행 직전 시각 이후 `startedAt` + cwd 로 `agents --json` 탐색(계획 4.1 §3) |
| S3-3 (none) | `--settings` 의 `bgIsolation: none` 이 전역 설정 변경 없이 적용되어 원래 폴더를 편집하는가 | 합격 필수 | 미실행 | step=S3-3-none (`originalExists`, `worktreeHits`, `userSettingsUnchanged`), `C:\cce-spike\c\probe-none.txt` | — |
| S3-3 (worktree) | `worktree` 로 바꾸면 `.claude/worktrees/` 아래를 편집하는가 | 합격 필수 | 미실행 | step=S3-3-worktree, `C:\cce-spike\c\.claude\worktrees\*\probe-worktree.txt` | — |
| S3-4 | attach 자식 pid 추적, X 닫기와 `/exit`·`←` detach 구분, 경쟁 반복 시험 20회 | 오분류 0 | 미실행 | `spikes/_log/s3-4-attach.jsonl` (run 별 start/child/ctrl/end), analyze 표 | PS 5.1 처리기가 CTRL_CLOSE 를 못 받으면 "Step 1 프로토타입 필요"로 기록하고 Rust `SetConsoleCtrlHandler` 로 재시험 |
| S3-5 | 응답 중 창 닫기 → 턴·파일 수정 완료, jsonl 완전 (10회) | 10/10 | 미실행 | step=S3-5-r1..r10 (`outLines`, `transcript`), `C:\cce-spike\c\out.txt` | 불합격 시 C 를 제공하지 않고 A 만 출시 |
| S3-6 | `blocked` 턴에서 창을 닫은 뒤 대기 유지 | 합격 필수 | 미실행 | step=S3-6 (`series`, `distinctStates`), 재접속 manual 기록 | 불합격 시 A 만 출시 |
| S3-7 | respawn 과 `--resume --bg` 의 ID 유지 | 결과를 기록해 대체 경로를 고른다 | 미실행 | step=S3-7 (`respawnSameId`, `resumeBgSameId`, `copies`) | ID 가 바뀌면 `sessionLineage` 에 새 ID 추가(계획 4.3 §3) |
| S3-8 (사전) | OS 수준 토스트 클릭 활성화(프로토콜) → 처리기 → `wt -w 0 new-tab … claude attach` | 기록 | 미실행 | `spikes/_log/s3-8-protocol.jsonl` (stage2 여부) | — |
| S3-8 (Tauri) | Tauri 2 notification 플러그인의 Windows 알림 클릭 활성화가 앱에 전달되는가 / 전달되면 `wt -w 0 new-tab … cce claude --attach-session <id>` 로 붙는가(두 단계 따로) | 기록 | 미실행 (Rust 설치 뒤 runbook §S3-8 Tauri 절차) | 스모크 프로젝트 로그, 스크린샷 `spikes/_evidence/S3-8-*.png` | 실패 시 계획 4.2 대체 순서 2(트레이 메뉴 "입력 대기 세션 N개") · 3(agent view). 프로토콜 활성화 + deep-link 를 별도 선택지로 검토 |
| S3-9 | 붙어 있지 않은 bg 세션에서 `Notification` 훅이 발생하는가, `cce hook` 이 그 pane 을 찾을 수 있는가(`session_id` 역조회 포함) | 결과를 기록해 대체 경로를 고른다 | 미실행 | `spikes/_log/s3-notify.jsonl` (event=Notification, env.CCE_PANE_KEY, ancestry) | 합격 시 훅 경로를 알림의 빠른 경로로 추가, 불합격이면 폴링 15초만 |

## S4(b) 제목(attach) (계획 §5 Step 0 S4(b))

| 항목 | 확인할 내용 | 합격 기준(계획 원문) | 합격/불합격 | 증거 | 선택한 대체 경로 |
|---|---|---|---|---|---|
| S4(b) | attach 상태에서 `sessionTitle` 로 정한 이름과 아이콘이 WT 탭에 보이는가 | 아이콘을 뺀 텍스트가 4.6절 형식과 같다 | 미실행 | `spikes/_log/s4b-title.jsonl` (observe: icon/iconCodepoints/textWithoutIcon/match), `spikes/_evidence/S4b-*.png`, `agents --json` name | `cce` 가 attach 직전에 OSC 0 을 직접 출력(`-Phase osc`). 덮어써지면 C 프로젝트에 한해 `--title` 고정(아이콘 포기, 설정 창에 표시) |

## 설치된 Claude Code(2.1.280)와 계획의 차이 (runbook 부록 요약)

| 계획의 가정 | 실제(2.1.280 `--help`) | 영향 |
|---|---|---|
| `claude agents --json` 필드에 `pid`, `status`, `waitingFor` 가 있다(R3e) | 관찰한 백그라운드 행에는 `id/cwd/kind/startedAt/sessionId/name/state` 만 있었다(문서상 `pid`·`status` 는 프로세스가 살아 있는 동안만 실림). 대화형 행에는 `pid`·`status` 가 있다 | S3-1 collect 가 갓 띄운 bg 세션에서 확정한다. 없으면 트레이 폴링은 `state=blocked` 로만 알림을 만든다(내부 `jobs/<id>/state.json` 의 `needs` 는 문서화되지 않은 계약이라 쓰지 않는다) |
| `--settings` 로 넘긴 `bgIsolation` 이 세션에 남는다 | `--settings` 는 세션 단위이며 `--resume`·`respawn` 에 복원되지 않는다(문서, ≥2.1.196) | S3-7 이 respawn 뒤 `bgIsolation` 을 기록. 기본값 `worktree` 로 되돌아가면 계획 4.3 §3 의 "`stopped` 이면 `respawn` 후 attach" 를 "`--bg --resume <id> --settings <파일>`" 로 바꾸는 결정 필요 |
| `claude respawn <id>` 가 멈춘 세션도 다시 시작한다(R2d) | `--help`: "Restart a background session (or all of them) so it picks up the current Claude binary" — stopped 세션에 대한 동작은 명시가 없다 | S3-7 에서 실측 |
| `claude stop` 뒤 `claude --resume` 로 잇는다 | `stop --help`: "resume it later with `claude attach <id>`", `--bg --help`: `--resume <session-id>` 는 같은 ID 로 이어가거나 이미 실행 중이면 복사본을 만든다 | S3-7 에서 실측. ID 유지 여부가 `sessionLineage` 설계를 정한다 |
| bg 짧은 id 는 별도 값 | 로컬 관찰: 짧은 id = sessionId 앞 8자 | `--session-id` 를 미리 주면 attach id 도 미리 안다(S3-2 로 확인) |
| `--settings <file-or-json>` | 있음. 설정 `worktree.bgIsolation` 은 "Any file" 범위 | S3-3 이 실제 적용 여부를 본다 |
| 훅 `args` exec 형식 | 문서에 있음(`type: command`, `command`, `args`). 훅 객체 스키마는 `additionalProperties: false` 이므로 `_cce_spike` 표식은 훅 객체가 아니라 **설정 파일 최상위**에 둔다 | 표식 위치만 다름 |
