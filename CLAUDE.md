# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 현재 상태 (2026-09-24 기준)

계획 확정, 확인 실험(Step 0 스파이크) 착수 직전에서 **일시 중단** 상태입니다. 아직 제품 코드는 없습니다.

- 요구사항 명세: `docs/planning/spec-deep-interview.md`
- 합의 계획(rev 5, 확정): `docs/planning/plan-ralplan.md` — Rust `cce.exe` + Tauri 2 트레이 앱. 실행 방식 A(일반 claude) 기본, C(백그라운드 세션) 프로젝트별 선택.
- 실험 스크립트와 안내서: `spikes/`, `docs/spikes/runbook.md`(A 경로: S1→S5→S4→S2), `docs/spikes/runbook-c.md`(C 경로: S3, S4b). 결과는 `docs/spikes/results.md`, `results-c.md`에 적습니다.
- 설정 백업 완료: `spikes/_backup/20260923-120737-start` (git 제외). 실험 중 바꾼 설정은 `spikes/common/restore.ps1 -Timestamp 20260923-120737-start`로 되돌립니다.
- 설치됨: Rust(cargo 1.98, `%USERPROFILE%\.cargo\bin`), PowerShell 7.6(스토어판, `%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe`). `wt.exe`, `winget.exe`도 그 폴더에 있어 일부 셸 PATH에는 없습니다.

**이어서 할 일:** S1부터 안내서대로 진행합니다. 단, S1은 Windows Terminal 창을 전부 닫아야 하므로 **Claude 세션을 WT 밖(일반 콘솔이나 VS Code 터미널)에서 이어가야** 합니다. 실험 뒤 계획에 반영할 차이점은 `docs/spikes/runbook.md` 부록 B와 `runbook-c.md` §8에 있습니다 (예: `claude agents --json` 필드, 훅 시간 하한 ≈250ms, `--settings`가 resume 시 복원되지 않음).

## 목표 (출처: `docs/기획/초안.txt`)

Windows에서 Claude Code 작업 환경을 관리하는 도구입니다. 요구사항:

1. **세션 보존·복원** — Claude Code가 실행 중인 터미널을 닫아도 작업 내용이 안전하게 저장되어야 합니다 (현재는 종종 날아감). 설정을 켠 상태로 터미널을 다시 열면, 작업하던 탭들이 그대로 복원되어야 합니다 (Windows의 Ctrl+Shift+T처럼).
2. **탭 이름** — 터미널(PowerShell 등) 탭 이름이 해당 프로젝트 이름으로 표시되어야 합니다.
3. **계정 무중단 전환** — 여러 Claude 계정을 등록해 두고, 한 계정의 사용량이 거의 소진되면 작업을 끊지 않고 다른 계정으로 전환해야 합니다.
4. **UI** — 보기 좋고 세련된 UI로 간편하게 조작할 수 있어야 합니다.

## 작업 진행 규칙 (이 프로젝트 한정)

사용자 의견이 필요한 사항이 아니면, 아래 단계별 오케스트레이션 모드로 멈추지 않고 진행합니다.

| 단계 | 모드 |
|---|---|
| 요구사항 구체화 | `deep-interview` |
| 합의 계획 | `ralplan` (Planner → Architect → Critic) |
| 가능 여부 확인(스파이크) | `ultrawork` |
| 1차 구현 | `team` |
| 반복 테스트·수정 | `ultraqa` + `ralph` |
| 화면 확인 | `visual-verdict` |
| 최종 검증 | `verify` → `code-review` |
| 머지·배포 | `merge-readiness` → `release` |
| 2차(계정 전환) | 스파이크 `ralph` → `ralplan --deliberate` → `ralph` → `security-review` |

- 다음 단계로 넘어가기 전마다 어떤 모드가 맞는지 다시 검토하고, 필요하면 구성을 바꿉니다. 바꿀 때는 이유를 짧게 알립니다.
- 에이전트를 띄울 때는 `model=fable`을 씁니다. 가벼운 모델로 충분한 단순 조회(파일 찾기, 짧은 확인)만 `haiku`를 씁니다. `opus`/`sonnet`은 쓰지 않습니다.
- 사용자 의견·결정이 필요한 경우(범위, UX 트레이드오프, 약관 같은 판단)는 AskUserQuestion 선택지로 묻습니다. 산문 질문으로 끝내지 않습니다.
- 이 레포는 데모 버전이고 개발자는 사용자와 Claude뿐입니다. `git commit`/`git push`는 확인 없이 해도 됩니다.

## 저장소 메모

- `.omc/`는 oh-my-claudecode의 로컬 런타임 상태이며 `.gitignore`로 제외합니다. 요구사항 명세(`.omc/specs/deep-interview-claude-env.md`)와 합의 계획(`.omc/plans/ralplan-claude-env.md`)도 여기에 있어 로컬에만 존재합니다.
- 원격: https://github.com/CatPope/claude_env (Public).
