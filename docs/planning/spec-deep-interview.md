# Deep Interview Spec: claude_env — Windows Terminal용 Claude Code 세션 관리 도구

## Metadata
- Interview ID: 4b8edc8c-0628-4dcb-a189-cc9081c42bbf
- Rounds: 11 (+ Round 0 topology)
- Final Ambiguity Score: 17.5%
- Type: greenfield
- Generated: 2026-09-23
- Threshold: 0.2
- Threshold Source: default
- Initial Context Summarized: no
- Status: PASSED (pending approval)

## Clarity Breakdown
| Dimension | Score | Weight | Weighted |
|-----------|-------|--------|----------|
| Goal Clarity | 0.90 | 0.40 | 0.36 |
| Constraint Clarity | 0.75 | 0.30 | 0.225 |
| Success Criteria | 0.80 | 0.30 | 0.24 |
| **Total Clarity** | | | **0.825** |
| **Ambiguity** | | | **0.175** |

## Topology
| Component | Status | Description | Coverage / Deferral Note |
|-----------|--------|-------------|--------------------------|
| 세션 보존·복원 | active (1차) | 터미널을 닫아도 작업이 보존되고, 다시 열면 창·탭·분할·Claude 대화가 복원됨 | AC-1 ~ AC-6 |
| 탭 이름 | active (1차) | 탭 제목 = 상태 아이콘 + 별칭 + 계정 | AC-7 ~ AC-9 |
| 관리 UI | active (1차) | 트레이에 상주하고, 창은 설정할 때만 여는 설정 중심 UI | AC-10 ~ AC-11 |
| 계정 무중단 전환 | deferred (2차) | 구독 계정 여러 개를 사용량 95%에서 선제 전환 | Round 7에서 사용자가 2차로 미룸. 2차 요구사항은 아래 기록 |

## Goal
Windows Terminal에서 Claude Code를 여러 탭으로 쓰는 사용자를 위해, 트레이에 상주하는 자동화 도구를 만든다.
- 터미널을 닫으면 진행 중인 응답이 끝난 뒤 안전하게 종료한다.
- 다시 열면 창·탭·분할 배치와 각 Claude 대화를 자동으로 복원한다.
- 탭 제목을 "Claude Code 상태 아이콘 + 프로젝트 별칭 + 계정"으로 유지한다.
- 2차에서는 등록한 구독 계정 여러 개를 사용량 한도 전에 자동 전환한다.

## Constraints
- 터미널: Windows Terminal. 셸: PowerShell, Git Bash, WSL 등 여러 셸의 탭을 모두 지원한다.
- 형태: Windows Terminal을 대체하지 않는다. 별도 런처(트레이 상주 앱)가 탭을 열고 상태를 관리한다.
- UI: 설정 위주. 평소에는 창을 열지 않고 자동으로 동작한다. "보기 좋고 세련된" 설정 화면이어야 한다.
- 계정: Claude 구독 계정(Pro/Max, `/login` 방식). API 키는 대상이 아니다.
- 상태 아이콘: Claude Code가 이미 탭 제목 앞에 붙이는 실행 상태 아이콘을 그대로 쓴다. 새로 만들지 않는다.
- 대상: 우선 본인 PC 환경.

## Non-Goals
- 자체 터미널 에뮬레이터 개발
- API 키(Console) 계정 지원
- 1차에서의 계정 자동 전환 (2차로 미룸)
- VS Code 등 Windows Terminal 이외의 터미널 앱
- 사용자가 창을 닫은 뒤에도 백그라운드에서 계속 실행하는 방식 (tmux 방식은 채택하지 않음)

## Acceptance Criteria
### 세션 보존·복원
- [ ] AC-1: Claude가 응답하는 중에 Windows Terminal 창을 닫으면, 그 응답이 끝날 때까지 기다렸다가 종료한다. 응답이나 파일 수정이 중간에 끊기지 않는다.
- [ ] AC-2: 창을 닫은 뒤 각 Claude 탭의 대화 기록이 `claude --resume` 목록에 온전히 남아 있다. 마지막 메시지도 빠지지 않는다.
- [ ] AC-3: 도구 설정이 켜진 상태로 Windows Terminal을 열면, 사용자 조작 없이 이전의 창 개수·탭 순서·분할(pane) 배치가 복원된다.
- [ ] AC-4: 복원된 Claude 탭은 원래 폴더에서 원래 대화(세션 ID)로 이어진다.
- [ ] AC-5: 복원된 일반 셸 탭(PowerShell/Git Bash/WSL)은 원래 셸 종류와 작업 폴더로 열린다.
- [ ] AC-6: 예: 창 2개, Claude 탭 3개와 일반 탭 2개, 분할 1개였던 상태를 닫았다 열면 동일하게 복원된다.

### 탭 이름
- [ ] AC-7: 탭 제목 형식은 `<Claude Code 상태 아이콘> <별칭> [<계정>]`이다. Claude Code의 대화 주제 텍스트는 별칭으로 대체한다.
- [ ] AC-8: 별칭 기본값은 프로젝트 폴더명이다. 사용자가 프로젝트별로 바꿀 수 있다.
- [ ] AC-9: Claude가 작업 중·대기·입력 필요로 상태를 바꿔도 아이콘만 바뀌고 별칭과 계정은 유지된다. 1차에서는 현재 로그인된 계정을 표시한다.

### 관리 UI
- [ ] AC-10: 트레이 아이콘으로 상주하고, 설정 창에서 복원 기능 켜기/끄기, 프로젝트 별칭, 계정 표시 이름을 편집할 수 있다.
- [ ] AC-11: 평소 사용에는 UI 조작이 필요 없다 (복원·제목 설정이 자동).

### 2차: 계정 무중단 전환 (기록용)
- [ ] 여러 구독 계정을 등록할 수 있다.
- [ ] 현재 계정의 사용량이 95%에 이르면 응답 사이의 쉬는 틈에 다음 계정의 자격증명으로 바꾸고, 같은 대화를 `--resume`으로 이어간다.
- [ ] 전환 후 탭 제목의 계정 표시가 바뀐다.

## Assumptions Exposed & Resolved
| Assumption | Challenge | Resolution |
|------------|-----------|------------|
| 자체 터미널 앱이 필요하다 | 탭을 누가 가지고 있느냐 | Windows Terminal + 런처 |
| "작업이 날아감"은 한 가지 문제다 | 무엇을 잃는가 | 네 가지 모두 겪음: 진행 중 응답 끊김, 기록 소실, 이어가기 번거로움, 탭 배치 소실 |
| 구독 계정도 끊김 없이 바꿀 수 있다 | 자격증명을 바꾸려면 프로세스를 재시작해야 함 | 한도에 걸리기 전 95%에서, 응답 사이 쉬는 틈에 선제 전환 |
| 네 기능 모두 1차에 필요하다 | 최소 버전은 무엇인가 | 1차 = 복원 + 탭 이름, 계정 전환은 2차 |
| 탭 상태 표시를 새로 만들어야 한다 | 사용자 피드백 | Claude Code 기존 아이콘을 유지하고 텍스트만 바꿈 |
| UI가 핵심 조작 수단이다 | 가장 자주 하는 행동은 무엇인가 | 거의 열지 않음. 설정 위주, 자동화 중심 |
| 창을 닫으면 백그라운드에서 계속 돈다 | 닫는 순간의 동작 | 현재 응답이 끝난 뒤 종료하고, 다시 열 때 resume |

## Technical Context (greenfield — 계획 단계에서 검증할 위험)
- **R1. Windows Terminal의 기본 배치 복원:** `firstWindowPreference: persistedWindowLayout`이 창·탭·분할을 복원한다. 다만 각 탭에서 실행할 명령(`claude --resume <id>`)까지 되살려 주는지는 확인이 필요하다.
- **R2. 창 닫기 가로채기:** Windows Terminal 창을 닫을 때 자식 프로세스(claude)가 응답을 마칠 때까지 종료를 미룰 수 있는지 확인해야 한다. 안 된다면 대안이 필요하다(예: 닫기 확인, 세션 스냅샷 주기 저장).
- **R3. 대화 기록 소실의 원인:** Claude Code가 트랜스크립트를 쓰는 시점과 강제 종료 시 마지막 메시지가 빠지는 이유를 조사해야 한다.
- **R4. 탭 제목 덮어쓰기:** Claude Code가 설정하는 제목에서 아이콘은 두고 텍스트만 바꾸는 방법을 찾아야 한다. 후보: Claude Code 훅/설정, Windows Terminal `suppressApplicationTitle`, 이스케이프 시퀀스(OSC) 등.
- **R5. (2차) 사용량 읽기:** 구독 계정의 5시간·주간 사용량을 프로그램에서 읽을 수 있는지가 95% 선제 전환의 전제다.
- **R6. (2차) 자격증명 교체:** 구독 계정 로그인 정보의 저장 위치와 여러 계정을 안전하게 보관·교체하는 방법을 확인해야 한다.
- 스택: 미정 (트레이 상주 + 세련된 설정 UI가 필요하다. 계획 단계에서 결정).

## Ontology (Key Entities)
| Entity | Type | Fields | Relationships |
|--------|------|--------|---------------|
| 트레이 상주 앱 (Launcher) | core | 설정, 복원 on/off | 탭 배치 스냅샷을 저장·복원함, 탭을 엶 |
| 프로젝트 | core domain | 경로, 별칭 | 하나의 탭에서 열림 |
| 탭 | core domain | 셸 종류, 작업 폴더, 제목, 순서 | 창·분할에 속함, Claude 세션을 가질 수 있음 |
| 창 / 분할(pane) | supporting | 배치 | 탭을 포함 |
| 셸 | supporting | PowerShell / Git Bash / WSL | 탭에서 실행 |
| Claude 세션 | core domain | 세션 ID, 폴더 | resume 대상 |
| 탭 배치 스냅샷 | core | 창·탭·분할·세션 ID 목록 | 종료 시 저장, 시작 시 복원 |
| 탭 상태 아이콘 | external (Claude Code) | 작업 중 / 대기 / 입력 필요 | 탭 제목 앞부분 |
| 탭 제목 | supporting | 아이콘 + 별칭 + 계정 | 탭에 표시 |
| 계정 | core (2차) | 구독 자격증명, 표시 이름 | Claude 세션을 실행 |
| 사용량 한도 | external | 5시간/주간, 사용률 | 계정에 속함 |
| 전환 임계값 | supporting (2차) | 95% | 계정 전환을 촉발 |

## Ontology Convergence
| Round | Entity Count | New | Changed | Stable | Stability Ratio |
|-------|-------------|-----|---------|--------|----------------|
| 1 | 5 | 5 | - | - | N/A |
| 2 | 6 | 1 | 0 | 5 | 83% |
| 3 | 7 | 1 | 0 | 6 | 86% |
| 4 | 8 | 1 | 0 | 7 | 88% |
| 5 | 9 | 1 | 0 | 8 | 89% |
| 6 | 10 | 1 | 0 | 9 | 90% |
| 7 | 10 | 0 | 1 | 9 | 100% |
| 8 | 10 | 0 | 1 | 9 | 100% |
| 9 | 11 | 1 | 0 | 10 | 91% |
| 10 | 12 | 1 | 0 | 11 | 92% |
| 11 | 12 | 0 | 0 | 12 | 100% |

## Interview Transcript
<details>
<summary>Full Q&A (11 rounds + Round 0)</summary>

### Round 0
**Q:** 4개 구성(세션 보존·복원, 탭 이름, 계정 무중단 전환, 관리 UI)이 맞나요?
**A:** 맞습니다.

### Round 1
**Q:** 매일 쓸 때 이 도구는 어떤 모습이어야 하나요?
**A:** 기존 터미널 + 런처
**Ambiguity:** 77%

### Round 2
**Q:** 터미널을 닫았을 때 '작업이 날아갔다'고 느낀 상황은?
**A:** 진행 중 응답 끊김, 대화 기록 사라짐, 이어가기 번거로움, 탭 배치 잃음 (모두)
**Ambiguity:** 72%

### Round 3
**Q:** 등록할 계정 종류는?
**A:** 구독 계정 (Pro/Max)
**Ambiguity:** 65%

### Round 4
**Q:** 탭 제목에는 무엇이 보여야 하나요?
**A:** 직접 정한 별칭(기본 폴더명) + 상태 + 계정
**Ambiguity:** 60%

### Round 5 (Contrarian)
**Q:** 자격증명 교체 + resume 자동 재시작(몇 초간 끊김)이면 '무중단'인가요?
**A:** 한도 전에 95%에서 미리 전환
**Ambiguity:** 50%

### Round 6
**Q:** 작업 중인 창을 닫으면?
**A:** 현재 응답이 끝난 뒤 종료
**Ambiguity:** 44%

### Round 7 (Simplifier)
**Q:** 최소 버전은?
**A:** 복원 + 탭 이름. (추가 의견: 상태 아이콘은 Claude Code 기존 방식이 마음에 듦)
**Ambiguity:** 36%

### Round 8 (Ontologist)
**Q:** 런처 창을 열었을 때 가장 자주 하는 행동은?
**A:** 거의 안 열어봄
**Ambiguity:** 31%

### Round 9
**Q:** Claude 탭 3개 + 일반 탭 2개였다면 무엇이 복원되어야 하나요?
**A:** 모든 탭 + 창·분할
**Ambiguity:** 26%

### Round 10
**Q:** 지원 터미널·셸 범위는?
**A:** Windows Terminal + 여러 셸
**Ambiguity:** 22%

### Round 11
**Q:** 탭 제목 합격 형식은?
**A:** 아이콘 + 별칭 + 계정. (추가 의견: UI는 거의 설정 위주)
**Ambiguity:** 17.5%
</details>
