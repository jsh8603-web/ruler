---
type: ruler-t2-batch-resolver
date: 2026-04-15
tags: [ruler, gate, batch, t2, load/on-demand]
---

# Ruler T2 Batch Resolver — Gate & 6-Step Procedure

(root: [`~/.claude/.ruler/patrol.md`](~/.claude/.ruler/patrol.md) §자동수정 Gate 에서 참조)

## 2-tier Gate 재편 근거 (2026-04-14)

과거 3-tier (T1 즉시 / T2 24h / T3 수동) 는 전부 **사용자 승인 창** 이 목적이었으나 사용자 "다 알아서 해라" 선언 → 승인 창 존재 이유 소멸. 남는 실질 구분 = **"의존성 있는 묶음 수정인가"** 뿐. T3 폐기, T2 를 "묶음 그룹" 으로 재정의.

## 공통 리스크 체크리스트 (T1/T2 분기 전 필수 5항목)

매 수정 후보 발견 시 먼저 아래 5항목 전부 돌린 뒤 티어 결정:

1. **상위 SSOT 추적** — 대상 파일 헤더 "함께 갱신할 파일" 테이블 Read → 연관 파일 수집
2. **grep 역참조** — 변경 대상 문자열(경로/함수명/규칙명)을 rules/docs/skills 범위 grep
3. **Symmetric fix 감지** — diff 에 C3 heuristic (WF_SESSION_NAMES 등) 매칭
4. **Regression trigger 포함** — secretary.js/revive.sh/generate-session-resume.sh/bash-guard.js/settings.json 포함? → 단계에 `run-all.sh` 필수
5. **Self-edit** — patrol.md / ruler-wf/skill.md 자기 수정? → T2 강제 + 효력 다음 사이클부터 (즉시 재귀 금지)

**분기**: 1=0 AND 2=0 AND 나머지 미해당 → **T1 Atomic**. 하나라도 해당 → **T2 Grouped** (pending 수집).

## T1 (Atomic 즉시 적용)

- 조건: 위 5항목 전 항목 미해당
- **Edit 전 반드시 결정론적 Gate 통과**:
  ```bash
  bash ~/.claude/.ruler/scripts/t1-gate.sh <file> <new-content-tmp>
  ```
  - exit 0 (PASS) → T1 즉시 적용
  - exit 1 (FAIL) → **T2 그룹 재검토로 강제 전환** (pending 수집)
- Edit 전 `.ruler/rollback/{filename}-{ts}.bak` 백업
- Edit 직후 `.ruler/decisions.jsonl` 1줄 append
- Edit 후 즉시 `.ruler/log/{date}.md` diff inline 기록
- secretary.js/revive.sh 등 계열 파일이면 `run-all.sh` 즉시 실행
- secretary.js/revive.sh/bash-guard.js/generate-session-resume.sh 수정 후 `run-all.sh` PASS 확인되면 **Node.js secretary 프로세스 반드시 재시작**: `psmux send-keys -t btn-button 'cd /d/projects/button && node agent/secretary.js' Enter` (또는 `revive.sh` 경유)

## T2 (Grouped 묶음 수정)

- 조건: 위 체크리스트 5항목 중 하나라도 해당
- 즉시 적용하지 않고 **`.ruler/pending/{ts}_{topic}.md`** 에 수집:
  - frontmatter: `type: pending-fix`, `target_files: [...]`, `risk`, `created: {ts}`, `urgent: true|false` (기본 false)
  - 본문: diff 초안 + 근거 + 상관분석 메모 (공통 체크리스트 5항목 결과)

### Urgent 판정 기준 (frontmatter `urgent: true`)

**엄격한 원칙**: "당장 수정 안 하면 심각하게 기능에 문제 있는 경우"에 한함. drift 감지·문서 cosmetic·보강·아카이브는 urgent 아님.

**자동 urgent — 6개**:
1. **C1 regression suite 실패** — secretary.js/revive.sh 계열 실제 회귀
2. **C12 guard 교착 미해소** — 동일 세션 3분 내 3건+ guard-deny + secretary 자동해소 실패
3. **C16 secretary heartbeat stale** — Node 프로세스 hang/crash
4. **hook 미발동 + 데이터 유실 진행** — resume/routing-context 등 핵심 hook 미발동, agent 가 resume 없이 작업 중 (2026-04-16 추가)
5. **위반 연쇄 확산** — 동일 세션 2사이클 내 동일 위반 재발 (교정 실패 = 근본 원인 미해소) (2026-04-16 추가)
6. **비서 기능 전면 무효** — registry 미등록 CWD 등으로 비서 감시/넛지/리줌 전부 작동 불가 (2026-04-16 추가)

**수동 urgent**: 사용자 명시적 "urgent" / "바로 처리" 지시 시.

**Normal 강등 이유** (과거 urgent 후보):
- C10 hook drift — cosmetic
- C13 settings.json backup 부재 — "이 상태로 수정하면" 문제지 현 상태 실패 아님
- C15 classifier FAIL — live 모드 hard-block 이미 존재
- C3/C5/C6/C8/C9/C11/C14 — drift/보강/아카이브

### Runtime Urgent 승격 (batch 실행 중)

batch 세션이 Step 2 전역 Read 과정에서 normal pending 이 엄격 기준 부합 발견 시:
1. batch 세션이 즉시 사용자 질의 (AskUserQuestion 차단 시 번호 선택지 텍스트)
2. 승인 → frontmatter `urgent: true` + 실행 순서 우선화
3. 거부 → normal 유지
- ⛔ **자동 승격 금지**. 반드시 사용자 논의 1회 필수.
- decisions.jsonl `action:"runtime_urgent_escalated"` + `rationale` 기록.

### 실행 트리거 (3 임계값 + 수동)

- **자동 (normal)**: idle 전환 직전 전체 pending ≥ 10 (기본값, state.md `batch_threshold` override)
- **자동 (urgent)**: idle 전환 직전 urgent pending ≥ 3 (기본값, state.md `batch_threshold_urgent` override)
  - urgent 3건만으로도 전체 batch 발동. normal pending 도 함께 묶임
- **자동 (critical T2)**: urgent 기준 4~6번 해당 시 **idle 대기 없이 즉시 batch 스폰** (2026-04-16 추가)
  - 트리거 조건: `violation-tier-criteria.md` §Critical 판정 기준 해당 + 해당 세션이 현재 WORKING 상태
  - 절차: pending 생성 (`urgent: true`) + **즉시** `ruler-batch-{ts}` 스폰 (idle 전환 대기 없음)
  - 근거: "이대로면 계속 망가지는 상황" — agent 에게 blocker 통보 후 batch 가 근본 원인 수정해야 세션 복구 가능
  - 순찰 세션은 batch 스폰 후에도 3분 사이클 계속 (기존 동작 동일)
- **수동**: 사용자 "일괄 검토" / "pending 처리" 지시

## §T2 Batch Resolver — idle 직전 자동 배치 처리

**발동 시점**: 매 사이클 §2a stale sweep 완료 후 Active WF Contexts 가 비어 **idle 전환 직전**. 아래 2 분기 중 하나라도 해당 시 `.active` 삭제 전 배치 작업 1회 실행.

### 분기 A — 웹앱 agent(secretary process) 재시작

- **대상 명확화**: "agent" = button 웹앱의 secretary.js Node 프로세스. Worker/Supervisor psmux 세션 아님.
- **리스크 등급**: Low. in-memory state (ctxWarnTsMap / offset map / circularMap) 는 재구축 가능한 ephemeral.
- **안전 게이트 (모두 충족 시만 실행)**:
  1. Active WF Contexts 비어 있음
  2. `psmux ls` 전 세션 idle (btn-*, ruler-batch-* 포함)
  3. 직전 사이클 이후 `D:/projects/button/agent/` 하위 mtime 변경 감지
  4. `.ruler/.agent-restart-pending` flag 또는 state.md `last_secretary_edit` 존재 + 재시작 미완료
- **실행**: Agent restart 헬퍼 호출 (경로 미확정 시 분기 disabled + 재시작 필요 로그만)
- **목적**: Ruler 가 적용한 secretary 코드 수정이 런타임 반영 안 되는 유령 상태 방지

### 분기 B — Pending 누적 시 Batch Resolver

- **조건 (OR)**:
  - normal: 전체 pending ≥ 10
  - urgent: urgent pending ≥ 3
  - 수동: 사용자 지시
- **집계**:
  ```bash
  total=$(ls ~/.claude/.ruler/pending/*.md 2>/dev/null | grep -v resolved | wc -l)
  urgent=$(grep -l "urgent: true" ~/.claude/.ruler/pending/*.md 2>/dev/null | grep -v resolved | wc -l)
  ```

### Plan 파일 포맷 제약 (사용자 3초 판단용)

`.ruler/batch-plans/{ts}_{topic}.md` 는 **짧은 지도** 역할. 실제 코드 snippet 은 실행 세션이 현장에서 파일 Read 해서 결정.

- ✅ **포함**: 발동 근거 (사용자 발언 인용 1~2줄) / 공통 체크리스트 5항목 결과 / 그룹 구성 / Step 계획 (`파일 + 변경 방향 + verify` 1~2줄) / 롤백 backup 경로
- ⛔ **금지**: before/after 코드 snippet, Edit `old_string`/`new_string` 구문, 전역 Read full dump
- **원칙**: Plan 파일 = 지도, 실행 세션 = 주행. 지도에 주행 로그 쓰지 않음.

### 별도 psmux 세션 스폰 절차 (순찰 컨텍스트 보존)

순찰 세션(ruler, 장수명)이 batch 작업 직접 수행하면 compact 폭탄. **별도 단수명 세션 `ruler-batch-{ts}` 스폰 위임**.

```
ruler (장수명)              ruler-batch-{ts} (단수명)
  ├ 트리거 감지             ├ plan 파일 Read
  ├ plan 파일 생성          ├ Step 1→N 순차 실행
  ├ psmux new-session ─────▶├ 각 Step decisions.jsonl append
  ├ .active 유지 (idle 차단)├ 완료 시 [ruler-wf-end] → ruler
  └ [ruler-wf-end] 수신     └ psmux kill-session
     + state.md 반영
```

- **스폰 명령**: **반드시 `~/.claude/.ruler/scripts/spawn-batch-session.sh <plan-file-absolute-path>` 헬퍼 경유**. 즉흥 `psmux new-session` / `send-keys` 조합 금지 (Enter 누락·model 오선택·cwd 누락·self-target 위험). 헬퍼가 자동 처리: 세션명 생성 (`ruler-batch-{ts}`), 모델=opus 고정, cwd=~/.claude 고정, bypass/trust 폴링, `/remote-control` 전환, 초기 프롬프트 분리 송신 (`send-keys ... Enter` 별도 호출). 반환값 = stdout 마지막 줄 = 세션명.
- **self-target 금지**: 순찰 세션이 자기 자신에게 batch 지시 전송 금지 (데드락). 헬퍼 내부 `PSMUX_SESSION` 체크로 차단.
- **batch 세션 종료**: 모든 pending 처리 + `[ruler-wf-end]` 전송 완료 후 **`psmux kill-session -t ruler-batch-{ts}`** 로 자기 종료 (self-terminate). batch 세션은 단수명 — 작업 끝나면 즉시 kill. 필요 시 ruler 가 새 `ruler-batch-{ts}` 를 재스폰.
- **`.active` 유지 규칙**: batch 스폰 시 `echo batch_running_{ts} > .ruler/.active`. 진짜 목적 = batch hang/crash/compact 사망 감지 폴링
- **감시 지속성**: 순찰 세션은 batch 실행 중에도 3분 사이클 계속 (batch 세션은 C-check 대상 제외)

> [!CAUTION]
> **⛔ 장수명 ruler 순찰 세션은 T2 pending 항목 직접 Edit 적용 금지 (hard-rule).**
>
> 세션 모델이 Opus 여도 금지. 유일한 적용 경로 = `ruler-batch-{ts}` 스폰 위임. 위반 시 `decisions.jsonl` 에 `tier: T2_violation` 기록. 근거: 합리화 우회 방지. `t1-gate.sh` §(0b) 가 `PSMUX_SESSION=ruler` + `.t2-locked-files` 매칭 시 hard-block.

## Batch Resolver 실행 절차 (6-Step)

### Step 0 — 사후 Review (Sonnet T1 결정 재검증)

Sonnet 순찰이 쌓은 최근 T1 결정을 batch(Opus) 가 소급 review. 오판 감지 시 즉시 rollback.

- **Window**: `tail -50 ~/.claude/.ruler/decisions.jsonl | jq -s '[.[] | select(.tier=="T1" and (.model // "sonnet")=="sonnet")]'` — 기본 N_review=10
- **검증 항목**:
  1. `file` 현재 mtime 과 entry `ts` 사이에 덮어쓰기 없었는지
  2. `diff_hash` 가 현재 파일 해당 섹션 해시와 매칭되는지
  3. **Semantic re-verify** — 오판 3가지: 잘못된 파일 수정 / 공통 체크리스트 5항목 미통과 gate 우회 / self-edit 규칙 위반
- **분기**:
  - 정상 → 다음 entry
  - 오판 감지 → `cp {backup} {file}` + decisions.jsonl `action:"retroactive_rollback"` + log 기록 + (심각 시) urgent pending + 사용자 알림
- **비용 가드**: Sonnet 순찰 연속 3 사이클 무변경 → Step 0 skip

### Step 1 — Collect + Stale 검증

- `.ruler/pending/*.md` (resolved 제외) 전수 Read
- 각 항목 parse: `target_files`, `risk`, `proposed_diff`, `urgent`, `created`
- **Stale 검증**: target mtime 이 created ts 이후 변경 → `stale: true` 재검토
- 재검토 불가 → drop + `.ruler/pending/dropped/` 이동
- urgent vs normal 분류 (urgent 먼저)

### Step 2 — 전역 Read & 상관분석

- **rules 전체**: `~/.claude/CLAUDE.md`, `~/.claude/rules/*.md`
- **docs SSOT 핵심**: `~/.claude/docs/operations/hook-guard-review.md`, OPERATIONS_INDEX.md, 인덱스 7종
- **secretary 코드**: `D:/projects/button/agent/secretary.js` + `secretary/*.js` (11개 factory) + `.secretary/.scripts/*.sh`
- **hook/scripts**: `~/.claude/settings.json`, `~/.claude/scripts/*.sh`
- **event-patrol 자료** (2026-04-17 추가): `.ruler/pending/fp-adjust-*.md` 전수 Read. `reason` 필드 (예: `trigger=log_event needle=flag_stale hits=3/300s`) 파싱 → Level 1/2/3 진단 근거.
  - 함께 Read: `~/.claude/.ruler/event-rules.yaml` (해당 event spec), `~/.claude/.ruler/scripts/event-patrol.py` (파서)
- 각 pending target 이 위 범위 어디 참조되는지 grep → 상관관계 그래프

### Step 3 — 의존성 그래프 → 그룹 분해

- 노드 = 수정 후보
- 엣지 조건 (OR): 동일 target 공유 / 한쪽 상위 SSOT 가 다른쪽 target / grep 역참조 매칭
- 연결 컴포넌트 = 그룹 (G1, G2, ...)
- **fp-adjust 그룹 규칙** (2026-04-17 추가): `fp-adjust-{eventName}.md` 는 event 당 독립 그룹. 수정 대상 축:
  - Level 1: `event-rules.yaml` 의 `grace_sec` / `window_sec` 조정
  - Level 2: 동 파일의 `spec` / `trigger.type` / `supersede` 재작성
  - Level 3: `event-patrol.py` 파서 또는 `secretary.js` event 생성 로직
  - 최후: `enabled: false` (위 3단계 모두 실패 후에만). `reason` 필드로 Level 자동 선택 — threshold 값 언급 → Level 1, spec 불일치 → Level 2, 파서 한계 → Level 3.

### Step 4 — 그룹별 실행 계획 파일 생성

- 경로: `.ruler/batch-plans/{YYYYMMDDTHHMMSS}_{topic}.md`
- frontmatter: `type: t2-batch-plan`, `group_id`, `created`, `trigger: auto|manual`, `pending_count`, `groups`, `status: executing`
- 단계 분해: `edit → verify → log` 3-phase. verify 수단:
  - regression trigger 포함 → `run-all.sh` 35/35
  - 문서 변경 → grep 교차검증
  - frontmatter 변경 → YAML parse 확인

### Step 5 — 그룹 순차 실행

- **그룹 원자성**: 한 그룹 단계 실패 → 해당 단계 rollback → 나머지 skip → `partial_failed`
- 단계별 backup: `.ruler/rollback/{file}-{group_id}-{step_n}.bak`
- **진동 감지**: 동일 파일 한 배치 내 2회 수정 금지
- 각 단계 완료 시 decisions.jsonl 1줄 + log/{date}.md diff 기록
- **Agent 통보**: 수정 완료 후 대상 agent 에게 `ruler-notify.sh rule-fix` 로 직접 통보 (ruler 메인 안 거침). blocker 해제 필요 시 `ruler-notify.sh unblock` 선행

### Step 6 — 완료 정리

- 성공 그룹 → 관련 pending → `.ruler/pending/resolved/`
- 부분 실패 → pending 유지
- 계획 파일 → `.ruler/batch-plans/done/` 이동
- state.md 사이클 결과 요약 반영
- 모든 분기 처리 완료 → 원래 idle 전환 재개 (`rm .ruler/.active`)

## 중단 조건

- Batch 실행 중 `[ruler-reentry]` 수신 → 현 단계까지만 완료 → 계획 파일 보존 → `.batch-running` flag 유지 → active 진입 → 다음 idle 재개
- Regression 하네스 실패 → Edit revert + `regression_fail` 로그 + 자동 재시도 금지 → state.md 보고만

## 예외 (자동 보고)

- 회귀 하네스 실패 → 자동 rollback + state.md `regression_fail` 기록
- `t1-gate.sh` FAIL → hard-block, 다음 사이클 관찰만
