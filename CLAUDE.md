---
type: ruler-repo-root
date: 2026-04-18
tags: [ruler, ssot, invariants, repo-root]
---

# Ruler — 메타 감시 레이어 Repo Root

이 폴더는 **규칙/문서/비서코드 자체의 정합성을 감시**하는 메타 레이어의 SSOT. 상위 계층(Supervisor/Worker/Secretary) 과 독립된 **장수명 세션 패트롤(Sonnet)** + **일회성 배치 세션(Opus)** 2-layer 구조.

> **위치**: Repo 루트 = `D:\projects\ruler\` (remote: `github.com/jsh8603-web/ruler`). 규칙·스크립트는 `.ruler/` 하위, 원래 참조 경로 `~/.claude/.ruler/` 는 symlink 로 투과. 스킬 2개 (`skills/ruler-wf`, `skills/audit-wf`) 는 pre-commit hook sync. 구조 상세 → [`SYMLINK-SETUP.md`](./SYMLINK-SETUP.md).

---

## SSOT 파일 맵

| 파일 | 역할 | 수정 권한 |
|---|---|---|
| `patrol.md` | 패트롤 본체 — C-check 체크리스트 + 사후 Retrospective Phase 실행 순서 | patrol/batch |
| `patrol-tier-a.md` | Tier A (매 사이클 3분) 상세 | patrol/batch |
| `patrol-tier-c.md` | Tier C (30분 10사이클) 상세 | patrol/batch |
| `patrol-wf-checks.md` | WF 세션 진행 중 blocker 체크 | batch 우선 |
| `retrospective-guide.md` | **ruler-batch 세션 SSOT** — Identity/Lifecycle/§0.5~0.7/Phase 정의 | batch 전용 |
| `event-rules.yaml` | 이벤트 패트롤 규칙 (v6: 활성 32 + pending 1) | **ruler-batch 만** (`opus_only`) |
| `model-separation.md` | patrol(Sonnet) ↔ batch(Opus) 모델 정책 | batch 전용 |
| `state.md` | 사이클 카운터 / idle-strike / sonnet_patrol_mode 등 runtime state | patrol 자가 갱신 |
| `preflight-rules.md` | retrospective 가 승격한 예방 규칙 (다음 세션 회피 체크리스트) | batch append |
| `violation-tier-criteria.md` | T1/T2/T3 분류 기준 | batch 전용 |
| `t2-batch-resolver.md` | T2 pending batch 처리 절차 | batch 전용 |
| `batch-init.md` | batch 세션 초기화 체크리스트 | batch 자가 참조 |
| `wake-loop.md` | wake.sh 운영 메모 | patrol/batch |
| `decisions.jsonl` | **모든 Edit 결정 로그 (append-only)** | 모든 편집 주체가 즉시 append |
| `log/{YYYY-MM-DD}.md` | 일일 사람 읽기용 로그 | 세션별 append |
| `pending/*.md` | 미해결 제안 (T2 대기) | 생성/resolve/drop |
| `batch-plans/{ts}_*.md` | 지난 batch 세션 plan 이력 | batch 자가 작성 |
| `retrospective/{date}_*.md` | 주간 retrospective 산출물 | batch Phase A/C |
| `scripts/*.sh`, `scripts/*.py` | retrospective-collect.sh / event-patrol.py / t1-gate.sh 등 | batch/사용자 |

---

## 핵심 유지 사항 (Immutable Constraints — 재설계 plan 이 절대 건드리지 않는 전제)

### Identity / Lifecycle
- **patrol 세션**: `ruler` psmux 세션, Sonnet (force_opus_fallback 시 opus), cwd=`C:\Users\jsh86\.claude`, **장수명 (며칠~몇 주)**. 3분 wake 루프, 30분마다 Tier C.
- **batch 세션**: `ruler-batch-{YYYYMMDDTHHMMSS}`, **Opus 고정** (`spawn-batch-session.sh`), cwd 동일, **일회성 (수분~1시간, 작업 완료 = 즉시 self-terminate)**.
- **spawn 패턴 매칭 (방어선 1)**: `spawn-session.sh` `case "$SESSION" in ruler|ruler-batch-*) PROJECT_DIR="/c/Users/jsh86/.claude" ;; esac`. 이 고정이 깨지면 `.home-cwd-warning` 재현. (§0.7 drift prevention)

### 역할 분리 (patrol ↔ batch)
- **patrol**: C-check 루프 + 판정 + T1 즉시 수정 + decisions.jsonl append. Tier A/C 구조.
- **batch**: 주간 retrospective + T2 pending 일괄 처리 + audit-wf Phase B 조건부 + Phase Final Hook SSOT sync. 사용자 interaction 0.
- **교차 영역**: 둘 다 같은 타겟 파일 편집 가능 — §0.5 공유 체인 루프 + §0.6 grep gate 로 연쇄 수정 조율.

### §0.5 편집 기록 의무 (3단 기록, 매 Edit 직후 필수)
1. **`decisions.jsonl` append** — t1-gate.sh 강제. 스키마 `{ts, session, file, action, reason, prev, supersedes, tier, outcome}`.
2. **`log/{YYYY-MM-DD}.md` batch 블록 append** — Phase C self-terminate 직전 1회.
3. **(선택) 타겟 파일 frontmatter `last-edit` 포인터** — `.ruler/*.md` 만.

→ 이 규칙의 **누락 감사** 가 재설계 Phase B 의 Step 1 대상.

### §0.6 편집 전 Read gate
```bash
grep '"file":"<target>"' ~/.claude/.ruler/decisions.jsonl | tail -5
```
상충 entry 발견 시: consistent / conflict / rollback_suspicion 분기. 코드 파일은 inline `BUG-*` 주석 grep 으로 대체.

### Self-Terminate Protocol (batch 세션)
Phase C 출력 직후 즉시 5-step 수행 후 스스로 kill:
1. decisions.jsonl append (Phase C 요약)
2. state.md 갱신
3. plan 파일 `retrospective/done/` 이동
4. `psmux send-keys -t ruler '[ruler-wf-end] batch=...'`
5. `psmux kill-session -t $PSMUX_SESSION`

**IDLE 전환 감지 시 즉시 self-terminate**. "사용자 지시 대기" 모드 **금지** (과거 `ruler-batch-20260414T1625` 12h+ IDLE 사례).

### 모델 정책
- **patrol**: Sonnet 기본. `state.md` `sonnet_patrol_mode: true`. `force_opus_fallback: true` 시만 Opus. Tier A C17 이 drift 자동 전환.
- **batch**: Opus 고정. sonnet/haiku 불가.
- **event-rules.yaml 편집**: `ruler-batch` 만 (`opus_only` 플래그).

### Retrospective 주기
- **자동**: 마지막 retrospective 로부터 **7일 경과** OR rollback_budget_warn OR force_opus_fallback OR 같은 파일 3회+ 수정 감지.
- **수동**: 메인 세션 `주간리뷰` / `룰러 리뷰` / `retrospective` 키워드 → 메인 세션이 직접 `ruler-batch-{ts}` 스폰.

### Phase Final Hook SSOT Sync (무조건 수행)
`settings.json` hook 섹션 ↔ `~/.claude/docs/operations/hook-guard-review.md` 양방향 diff. Phase B skip 시에도 **생략 불가**. SSOT = `hook-guard-review.md`.

### T1/T2/T3 분류 (violation-tier-criteria.md)
- **T1**: 즉시 수정 (patrol 즉시 or batch 우선). 복구 불가 / 다른 세션 영향 / 복구 비용 > 오탐 비용.
- **T2**: pending 큐 → batch 일괄 처리 (24h 반영 허용).
- **T3**: 감사 wf 또는 사용자 결정 대기.

---

## 현재 진행 작업

- **Retrospective 재설계 plan**: [`plan.md`](./plan.md) — Primary=T1/T2 변경→효과 Δ 인과 판정, Secondary=§0.5 누락 감사 + patrol sync.
- **사용자 승인 대기 상태**. 승인 시 `progress.md` 생성 + SSOT 6개 파일 Edit 착수.
- **실측 baseline**: 2026-04-18T01:24 KST `ruler-batch-20260418T011559` 가 첫 retrospective 실행 — R1~R11 기준 **0 preflight 승격**. "단순 관찰" 한계 경험적 확인.

---

## 외부 참조 (ruler → 상위)

| 지점 | 파일 |
|---|---|
| 전역 Hook 레지스트리 | `~/.claude/docs/operations/hook-guard-review.md` |
| 전역 감사 wf | `~/.claude/skills/audit-wf/skill.md` + `~/.claude/docs/verification/audit-*.md` |
| 전역 메모리 | `~/.claude/memory/MEMORY.md` + `promotion-log.md` |
| 메인 세션 CLAUDE.md | `~/.claude/CLAUDE.md` |
| 비서 소스 | `D:/projects/button/agent/secretary.js` + `secretary/*.js` |
| 비서 hook 소스 | `~/.claude/hooks/*.js` + `~/.claude/hooks/*.sh` |
