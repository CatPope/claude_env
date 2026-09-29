# 유사 오픈소스 조사

- 조사일: 2026-09-29
- 기준 문서: `docs/requirements.md`
- 비교 기능: ① 세션 보존·복원 ② 탭 제목 ③ 트레이 설정 UI ④ 계정 자동 전환
- 방법: 각 프로젝트의 README 원문으로 기능을 확인했다. 스타 수, 마지막 push, 라이선스는 조사일에 `gh api`로 조회했다. 열어 보지 못한 프로젝트는 넣지 않았다.

## 1. 요약

- Windows Terminal에서 ①②③을 묶어 자동으로 해 주는 도구는 없다. 기존 도구는 기능 하나씩만 맡는다.
- ④는 claude-swap(★2.9k)이 Windows에서 거의 완성된 수준이다. 우리 2차 범위와 많이 겹친다.
- 아무도 하지 않는 것:
  - Windows Terminal을 열기만 하면 자동 복원(FR-3), 여러 창을 차례로 닫아도 전부 복원(FR-6)
  - 창을 닫는 순간 중단 상태 기록, 복원 뒤 "중단됨" 표시와 자동 이어가기(FR-1, FR-7)
  - Claude 자체 상태 아이콘을 살린 채 `별칭 [계정] · 부제` 제목(FR-10, FR-11, FR-14)
  - 복원·제목·계정을 한곳에서 다루는 트레이 UI

## 2. 프로젝트 비교

표의 ◎는 완전 지원, ○는 부분 지원, -는 없음이다.

| # | 프로젝트 | ★ / 마지막 push / 라이선스 | Windows | ① | ② | ③ | ④ |
|---|---|---|---|---|---|---|---|
| 1 | [claude-code-workspaces](https://github.com/volkanncicek/claude-code-workspaces) | 1 / 2026-09-23 / MIT | WT 네이티브 | ○ 수동 | - | - | - |
| 2 | [claude-session-manager](https://github.com/nukIeer/claude-session-manager) | 0 / 2026-09-20 / MIT | 전용 | ○ 1시간 주기 | ○ | - | - |
| 3 | [wt-restore-claude-tabs](https://github.com/andrelsjunior/wt-restore-claude-tabs) | 0 / 2026-08-28 / MIT | WSL→WT | ○ 탭만 | ○ | - | - |
| 4 | [TabSignal](https://github.com/MathiasClaesson/TabSignal) | 0 / 2026-09-23 / MIT | 전용 | - | ○ 방식 다름 | - | - |
| 5 | [claude-swap](https://github.com/realiti4/claude-swap) | 2,892 / 2026-09-28 / MIT | 지원 | - | - | ○ TUI | ◎ |
| 6 | [claude-account-switcher](https://github.com/codextde/claude-account-switcher) | 1 / 2026-09-22 / MIT | 지원 | - | - | ○ 트레이 | ◎ |
| 7 | [claude-profiles-windows](https://github.com/kevinabouhanna/claude-profiles-windows) | 1 / 2026-09-28 / MIT | 트레이 | - | - | ○ | ○ |
| 8 | [herdr](https://github.com/herdrdev/herdr) | 41,299 / 2026-09-29 / Apache-2.0 | 네이티브 | ○ 방식 다름 | - | - | - |
| 9 | [Intelligent Terminal](https://github.com/microsoft/intelligent-terminal) | 2,035 / 2026-09-29 / MIT | WT 포크 | ○ | - | - | - |
| 10 | [sky-session-claude](https://github.com/skfd/sky-session-claude) | 0 / 2026-09-20 / 확인 필요 | 트레이 | ○ 수동 | - | ○ | - |
| 11 | [CCManager](https://github.com/kbwo/ccmanager) | 1,253 / 2026-09-27 / MIT | 지원 | ○ 약함 | - | - | - |
| 12 | [usagebar](https://github.com/hsnsdt/usagebar) | 2 / 2026-09-23 / MIT | 지원 | - | - | ○ | 사용량만 |
| 13 | [cc-account-switcher](https://github.com/fairy-pitta/cc-account-switcher) | 65 / 2026-08-19 / MIT | 미지원 | - | - | - | ○ |

## 3. 프로젝트별 내용

### 1. claude-code-workspaces
- `ccw restore`가 마지막 스냅샷으로 WT 탭·분할을 다시 열고 각 대화를 이어간다. 수동 실행이고 여러 창 복원은 README에 없다.
- 상태는 `claude agents --json`과 대화 기록으로 읽는다.
- 참고: WT 분할을 여는 런처 코드, 상태 판정 방식, `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE` 주의 사항.

### 2. claude-session-manager (nukIeer)
- Claude Code가 세션마다 `%USERPROFILE%\.claude\sessions\<pid>.json`(세션 ID, 작업 폴더, 표시 이름)을 쓴다는 점을 이용한다.
- 작업 스케줄러가 1시간마다 저장하고, `.bat`을 눌러 `claude --resume`으로 복원한다. 폴더당 세션 하나로 합쳐지고 분할은 복원하지 않는다.
- 참고: PID와 세션을 잇는 근거. 실험 S2와 FR-4에 쓴다.

### 3. wt-restore-claude-tabs
- 대화 기록 `.jsonl`에서 폴더, 세션 ID, 세션 이름을 읽어 탭마다 `claude --resume`을 연다. 분할은 복원하지 않는다.
- 탭 이름 우선순위: `/rename` 이름 → Claude가 만든 이름. **Claude 자동 제목이 jsonl에 남는다는 근거**다(FR-13, 실험 S4).
- WT 배치 저장은 사용자가 직접 연 탭을 셸 명령만으로 저장하고, 도구가 `wt`로 연 탭은 전체 명령으로 저장한다(실험 S1 관련).

### 4. TabSignal
- 제목은 `name · branch`를 OSC 2로 쓰고, Claude 자체 제목은 끈다. **FR-11(Claude 아이콘 유지)과 반대 방향**이다.
- 훅과 PowerShell prompt에서 OSC 9;9(현재 폴더)를 보내 WT가 폴더를 복원하게 한다(FR-5).
- 훅 프로세스는 터미널이 없으므로, 프로세스 트리를 거슬러 탭의 셸 콘솔에 `AttachConsole`로 붙어 `CONOUT$`에 쓴다. 실험 S4 실패 시 대체 경로에 그대로 쓸 수 있다.
- 설치·제거 백업과 왕복 테스트(`tests/Install.Tests.ps1`)는 NFR-3의 본보기다.

### 5. claude-swap
- 5시간·7일 사용량이 임계값(기본 90%)에 이르면 남은 양이 가장 많은 계정으로 바꾼다. 쿨다운, 히스테리시스, 여러 전략이 있다.
- README: Windows와 Linux에서는 자격증명 파일이 바뀌면 Claude Code가 다시 읽어 **재시작 없이 다음 메시지부터 새 계정을 쓴다.** Claude Code와 같은 자격증명 잠금을 쓴다. 새 계정의 첫 메시지는 캐시를 다시 쌓느라 사용량이 더 든다.
- 우리 FR-22 설계를 바꿀 수 있는 정보다(아래 5절).

### 6. claude-account-switcher (codextde)
- **Tauri + Rust + React 트레이 앱으로 우리 스택과 가장 가깝다.** 임계값 90%, 히스테리시스, 쿨다운 10분. 전환 때 계정 확인 → 원자적 쓰기 → `claude auth status` 확인.
- 모듈 구성(`credentials.rs`, `usage.rs`, `engine.rs`, `service.rs`, `tray.rs`, `updater.rs`), 트레이 진행 막대, 자동 업데이트 서명 흐름이 참고할 만하다.
- 스타가 적은 새 프로젝트라 품질은 코드로 확인해야 한다.

### 7. claude-profiles-windows
- Windows 트레이. 자동 전환은 claude-swap을 번들로 넣고 JSON 출력을 파싱해 맡긴다. 자격증명은 claude-swap만 만진다.
- 우리가 2차를 직접 만들지 않고 연동할 때의 본보기다.

### 8. herdr
- 백그라운드 서버가 터미널 프로세스를 들고 있어 창을 닫아도 에이전트가 계속 돈다. 재시작 뒤에는 배치를 복원하고 지원되는 에이전트 세션을 이어간다.
- WT 안에서 도는 tmux 같은 런타임이라 NFR-1과 사용감이 다르다. 우리 방식 C와 같은 문제를 다르게 푸는 대안이다.

### 9. Intelligent Terminal (Microsoft)
- Windows Terminal의 실험적 포크. PR #628 "Durable sessions"가 탭 배치를 저장하고 닫기·종료·크래시 뒤에 복원한다.
- Claude Code 대화를 이어가는 기능은 아니다. 이 기능이 정식 WT에 들어오면 FR-6 구현을 다시 봐야 한다. **지켜볼 대상.**

### 10. sky-session-claude
- WPF 트레이. jsonl을 스캔해 두 번 클릭으로 이어간다. 상태를 `complete`, `waiting-you`, `cut-off`, `limit`, `interrupted` 등으로 나눈다.
- UI Automation으로 콘솔 제목을 찾아 해당 WT 탭에 포커스를 준다. FR-8(알림 클릭으로 세션 열기)에 참고할 수 있다.
- README는 MIT지만 GitHub에는 라이선스가 잡히지 않는다. 코드를 가져오기 전에 확인해야 한다.

### 11. CCManager
- 자체 TUI. 기록을 세션이 생기고 없어질 때마다 남겨 크래시에도 살아남는다. 다만 대화는 복원하지 않고 같은 명령을 다시 실행할 뿐이다.
- 참고: 도구별 상태 감지, 상태 변경 훅.

### 12. 사용량 모니터
- **usagebar**: Tauri v2 + Rust, Windows. `api.anthropic.com/api/oauth/usage`를 쓴다(README: 비공식, 커뮤니티가 찾아냄). 자격증명은 읽기만 하고 토큰 갱신은 Claude Code에 맡긴다. 95% 알림이 있다. **2차 사용량 읽기의 Rust 참고 구현.**
- [usage-monitor-for-claude](https://github.com/jens-duttke/usage-monitor-for-claude)(★302): 계정별 `CLAUDE_CONFIG_DIR` 인스턴스, 임계값 초과 시 명령 실행.
- [Claude-Code-Usage-Monitor](https://github.com/CodeZeno/Claude-Code-Usage-Monitor)(★544, Rust): 작업 표시줄 위젯.

### 13. cc-account-switcher (fairy-pitta)
- Windows 네이티브 미지원. PreToolUse 훅에서 사용량 캐시를 보고, 오래됐으면 네트워크로 갱신한 뒤 전환한다.
- 훅 안에서 네트워크를 부르는 설계는 NFR-2와 충돌한다. 따라 하지 않는다.

### 설계 참고용 (macOS 전용)
- [session-guard](https://github.com/tylerlaprade/session-guard): 훅과 데몬으로 중단된 세션을 보관한다. "작업 중이던 세션만 자동 이어가기" 규칙이 FR-7에 참고된다. **GPL-3.0이라 코드를 가져오면 안 된다.**
- [claude-sessions](https://github.com/jhammant/claude-sessions): 프로세스와 대화를 잇는 신뢰도 등급, "스냅샷을 줄이지 않는다" 원칙과 30개 이력 보관. 복원 엔진과 NFR-4에 그대로 쓸 만하다.

### 관련이 낮은 것
| 프로젝트 | 이유 |
|---|---|
| [claude-squad](https://github.com/smtg-ai/claude-squad) (★8.5k, AGPL) | tmux 필수, Windows 언급 없음 |
| [opcode](https://github.com/winfunc/opcode) (★22k, AGPL, Tauri 2) | GUI 래퍼, 터미널 탭 모델 아님 |
| [Crystal](https://github.com/stravu/crystal) | worktree 병렬 GUI, 2026-02 이후 멈춤 |
| [claude-terminal](https://github.com/Mr8BitHK/claude-terminal) | Windows용 자체 터미널(NFR-1 밖). 첫 프롬프트로 탭 이름을 만드는 방식은 참고 |
| [claude-code-terminal-title](https://github.com/bluzername/claude-code-terminal-title) | Windows 미지원, 라이선스 불명확 |
| [cc-switch](https://github.com/farion1231/cc-switch) (★138k) | API 제공자 전환 도구, 구독 계정 순환과 다름 |
| brenoluizdev·akon47·Lukeneo12의 계정 전환기 | 수동 전환만, 자동 순환 없음 |

## 4. 약관 관련 기록

법적 판단이 아니라 공식 문서와 프로젝트의 말만 옮긴다. 2차 착수 전 Q4에서 검토한다.

- [Consumer Terms](https://www.anthropic.com/legal/consumer-terms): API 키로 접근하거나 명시적으로 허용된 경우가 아니면 봇, 스크립트 등 자동화 수단으로 서비스에 접근할 수 없다. 로그인 자격증명을 공유하거나 계정을 남에게 줄 수 없다. 여러 계정 보유를 직접 다룬 조항은 찾지 못했다.
- [Claude Code Legal and compliance](https://code.claude.com/docs/en/legal-and-compliance): Pro·Max 사용 한도는 일반적인 개인 사용을 전제로 한다. 개발자는 Claude.ai 자격증명이나 세션 토큰을 수집·저장·중개할 수 없고, 로그인은 Anthropic 자체 흐름으로 끝나야 한다. **계정 전환 도구는 모두 OAuth 토큰을 백업·저장하므로 이 문구와의 관계를 검토해야 한다.**
- claude-swap 이슈 [#31](https://github.com/realiti4/claude-swap/issues/31): 관리자는 "추가 접근을 만들거나 한도를 우회하지 않으며, 로그아웃 후 다른 계정으로 로그인하는 것과 같다"고 답했다.
- cc-switch README: 공식 클라이언트 밖에서 구독을 쓰면 약관 위반일 수 있으니 위험을 스스로 판단하라고 적었다.

## 5. 계획에 반영할 기술 사실

| # | 사실 | 출처 | 영향 |
|---|---|---|---|
| 1 | Windows에서 자격증명 파일과 `~/.claude.json`의 `oauthAccount`를 바꾸면 실행 중인 claude가 다음 API 호출부터 새 계정을 쓴다 | claude-swap, codextde | FR-22를 "resume으로 다시 실행"이 아니라 "쉬는 틈에 파일만 교체"로 만들 수 있다. 2차 실험 S7에서 검증 |
| 2 | 사용량은 비공식 `api.anthropic.com/api/oauth/usage`로도 읽는다 | usagebar | statusline `rate_limits` 외 대안. 스키마가 바뀔 수 있다 |
| 3 | `%USERPROFILE%\.claude\sessions\<pid>.json`에 세션 ID, 폴더, 표시 이름이 있다 | nukIeer | PID↔세션 연결. 실험 S2, FR-4 |
| 4 | Claude가 만든 세션 이름이 jsonl에 남는다 | wt-restore-claude-tabs | FR-13 자동 제목 가정의 근거. 실험 S4(d) |
| 5 | 훅 프로세스는 `AttachConsole` + `CONOUT$`로 탭에 제목을 쓸 수 있다. 폴더 복원에는 OSC 9;9가 필요하다 | TabSignal | 실험 S4 대체 경로, FR-5 |
| 6 | WT 배치 저장은 사용자가 연 탭은 셸만, `wt`로 연 탭은 전체 명령을 저장한다 | wt-restore-claude-tabs | 실험 S1(b), FR-4 복원 경로 |

## 6. 결론

**판단:** 우리 1차(①②③)를 대신할 도구는 없다. 계획대로 진행한다. 2차(④)는 claude-swap이 Windows에서 이미 해결했으므로, 2차 착수 전에 직접 구현과 연동(claude-profiles-windows 방식)을 비교해 정한다.

**Step 1 구현 전에 살펴볼 프로젝트**

| 순서 | 프로젝트 | 볼 것 | 쓰는 곳 |
|---|---|---|---|
| 1 | TabSignal | AttachConsole 제목 쓰기, OSC 9;9, 설치·제거 왕복 테스트 | S1, S4, NFR-3 |
| 2 | claude-code-workspaces | WT 탭·분할 런처, `agents --json` 상태 판정 | 복원 엔진 |
| 3 | wt-restore-claude-tabs, claude-session-manager | jsonl·`sessions\<pid>.json`에서 세션 정보 얻기, WT 명령줄 이스케이프 | S1, S2, S4, FR-13 |
| 4 | claude-sessions (macOS) | 연결 신뢰도 등급, 스냅샷 보호 원칙 | 복원 엔진 안전 설계 |
| 5 | claude-account-switcher, usagebar | Tauri 2 + Rust 트레이 구조, 사용량 모듈 | 트레이 UI, 2차 준비 |
| 6 | claude-swap | 2차 직접 구현 대 연동 비교, 관리자의 약관 입장 | 2차, Q4 |
| 7 | Intelligent Terminal PR #628, herdr | WT 복원 기능 동향, 방식 C 대안 | 지켜보기 |

**라이선스 주의:** session-guard(GPL-3.0), claude-squad·opcode(AGPL-3.0)는 코드를 가져오지 않는다. sky-session-claude와 claude-code-terminal-title은 라이선스를 확인하기 전에는 가져오지 않는다.
