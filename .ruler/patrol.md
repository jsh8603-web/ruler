---
type: ruler-patrol-manifest
version: 4
date: 2026-04-16
tags: [ruler, patrol, manifest, hub, 2-tier, event-driven]
last-edit: 20260418-1440
last-edit-by: btn-ruler-step2
---

# Ruler Patrol Manifest — 허브

v4: 체크리스트 본체를 Tier 별 파일로 분리. 본 파일은 **사이클 로직 + 런타임 경로 + 공통 규칙**만 유지. ruler 세션은 매 사이클 이 허브 → 해당 Tier 파일만 Read.

## 모드 — 2-Tier 사이클

| Tier | 주기 | 대상 | Read 파일 |
|------|------|------|-----------|
| **A** | 3분 (매 사이클) | 이벤트 패트롤 + C1/C16/C17/C_idle | [`patrol-tier-a.md`](~/.claude/.ruler/patrol-tier-a.md) |
| **C** | 30분 (10사이클마다) | C3/C5~C11/C13~C15/C18-lite/C_memory/C_fp_ttl/C_ultraplan_hygiene | [`patrol-tier-c.md`](~/.claude/.ruler/patrol-tier-c.md) |

**사이클 로직**:
```
cycle_count += 1

1. Tier A: patrol-tier-a.md Read → 실행
   a. 이벤트 패트롤 (event-rules.yaml pre-scan)
      - candidate 시: event-rules.yaml 해당 블록만 Read (patrol 파일 불필요)
   b. C1 → C16 → C17 → C_idle 순회
2. if cycle_count % 10 == 0:
   Tier C: patrol-tier-c.md Read → 실행
```

매 사이클 첫 단계: wake-loop.md §사이클 진입 절차 → Tier A → (10사이클마다) Tier C.

## 런타임 경로 (on-demand 링크)

| 주제 | 파일 |
|---|---|
| **Tier A 체크리스트** (이벤트 + C1/C16/C17/C_idle) | [`~/.claude/.ruler/patrol-tier-a.md`](~/.claude/.ruler/patrol-tier-a.md) |
| **Tier C 체크리스트** (C3~C15 + C18-lite + blocker + 이관현황) | [`~/.claude/.ruler/patrol-tier-c.md`](~/.claude/.ruler/patrol-tier-c.md) |
| 이벤트 규칙 SSOT | [`~/.claude/.ruler/event-rules.yaml`](~/.claude/.ruler/event-rules.yaml) |
| 위반 T1/T2 분류 지침 (감지→통보→교정 판정) | [`~/.claude/.ruler/violation-tier-criteria.md`](~/.claude/.ruler/violation-tier-criteria.md) |
| Wake 루프 + active/idle 상태 머신 + 사이클 진입 절차 | [`~/.claude/.ruler/wake-loop.md`](~/.claude/.ruler/wake-loop.md) |
| 모델 분리 (Sonnet 순찰 / Opus batch) | [`~/.claude/.ruler/model-separation.md`](~/.claude/.ruler/model-separation.md) |
| T1/T2 Gate + Batch Resolver 6-step | [`~/.claude/.ruler/t2-batch-resolver.md`](~/.claude/.ruler/t2-batch-resolver.md) |
| Retrospective R1~R11 | [`~/.claude/.ruler/retrospective-guide.md`](~/.claude/.ruler/retrospective-guide.md) |

### 각 C-check 판정 모드 → 모델 라우팅

- **sonnet-decide**: 기계적 탐지·측정, Sonnet 순찰이 즉시 수행 가능
- **batch-only**: semantic 판정 필요, Sonnet 은 감지·수집만 → pending 에 넣고 batch 세션이 해결

---

## 사후 Retrospective 실행 순서

> **SSOT**: [`~/.claude/.ruler/retrospective-guide.md`](~/.claude/.ruler/retrospective-guide.md) — 각 Phase 상세 절차는 해당 파일 참조. 본 섹션은 순서 요약 포인터.

실행 순서: **Phase A → B → C → Final → Terminal**

| Phase | 명칭 | 목적 | 조건 |
|---|---|---|---|
| **Phase A** | T1/T2 Change-Impact Verdict | 각 T1/T2 수정의 실제 효과 인과 판정 (GOOD/NEUTRAL/BAD/INSUFFICIENT) | 항상 (input JSON 없으면 skip → Phase B) |
| **Phase B** | §0.5 Compliance Audit + Patrol Sync | §0.5 3단 기록 누락 감지 + patrol/event-rules/rules 의미 드리프트 동기화 | 항상 |
| **Phase C** | 심층 감사 연계 (audit-wf 조건부) | 장기 drift / 파일 리스트 추적 / 인덱스 정합성 / rollback 품질 저하 | 결정론적 조건 B1~B6 중 하나라도 true |
| **Phase Final** | Hook SSOT Sync | `settings.json` hook ↔ `hook-guard-review.md` 양방향 diff | **무조건** (Phase C skip 시에도 생략 불가) |
| **Phase Terminal** | state 갱신 + self-terminate | `state.md` 갱신 + decisions.jsonl Phase C 요약 + self-terminate 5-step | 항상 (마지막) |

**Phase C skip 시**: `decisions.jsonl` 에 `phase_c:false, skip_reason` append → Phase Final 은 계속 진행.

---

## 위반 처리 흐름 (End-to-End)

```
감지 (event-patrol.py pre-scan / C-check 수동 점검)
 ↓
분류 (violation-tier-criteria.md — T1 즉시 vs T2 그룹)
 ↓
T1 경로:                          T2 경로:
 ├─ pane 확인 (현재 상태)           ├─ ruler-notify.sh violation → agent
 ├─ 즉시 수정 (Edit)               ├─ critical? → blocker + 즉시 batch 스폰
 ├─ ruler-notify.sh violation       │              → batch 수정 → rule-fix 통보
 │   → agent 에게 통보              ├─ non-critical? → 임시 지침 + pending 수집
 ├─ decisions.jsonl 기록            │                 → idle 시 batch 일괄 실행
 └─ 완료                           └─ batch 완료 → decisions.jsonl + [ruler-wf-end]
```

> 각 단계 상세: [`violation-tier-criteria.md`](~/.claude/.ruler/violation-tier-criteria.md) | Batch 6-step: [`t2-batch-resolver.md`](~/.claude/.ruler/t2-batch-resolver.md)

## Ruler ↔ Batch 동기화

| 메커니즘 | 설명 |
|---|---|
| `decisions.jsonl` 공유 체인 | `prev`/`supersedes` 필드로 patrol↔batch 결정 연결. 편집 전 grep 의무 (retrospective-guide §0.6) |
| `[ruler-wf-end]` 완료 신호 | batch→patrol psmux send-keys (batch session ID, rules_applied, promoted count) |
| 일일 로그 | `.ruler/log/YYYY-MM-DD.md` batch 블록 섹션 |
| Batch→Agent 직접 통보 | `ruler-notify.sh rule-fix` / `unblock` — ruler 메인 안 거침 |

> 상세: [`retrospective-guide.md`](~/.claude/.ruler/retrospective-guide.md) §0.5~0.7

---

## 안전망 3종 (모든 티어 공통)

### 롤백 백업
- 저장: `.ruler/rollback/{filename}-{YYYY-MM-DD-HHMMSS}.bak`
- 유지: 파일명당 최근 10개 (FIFO)

### 15분 롤백 모니터링 (secretary.js Edit 시만)
- Edit 시점 + 15분 = rollback window
- 매 사이클 (3분 간격 5회) btn-* 세션 에러 카운트 집계
- 이전 15분 평균 대비 2배+ 증가 → 자동 rollback + promotion-log ERROR
- 창 종료 시 state.md `rollback_monitoring` 제거

### Edit 투명성
- secretary.js + 문서 SSOT Edit = promotion-log K 항목 append
- diff 는 `.ruler/log/{date}.md` inline
- **`.ruler/decisions.jsonl` 에 1줄 append 필수** (기계분석용)

---

## Decision log JSONL

- **위치**: `~/.claude/.ruler/decisions.jsonl` (append-only)
- **스키마**: `{ts, cycle, check, tier, file, diff_hash, backup, regression, outcome, gate}`
- **tier 값**: `T1` / `T2` / `T2_batch_applied`
- **기록 의무**: 모든 티어 Edit 직후 1줄 append. 실패 시 `outcome:"failed"`
- **용도**:
  1. 진동 감지 — `tail -50 decisions.jsonl | jq -s 'group_by(.file)[] | select(length>=2)'`
  2. 회귀율 집계 — `jq -s '[.[] | select(.regression != "35/35")] | length'`
  3. Retrospective R1~R11 분석 입력

---

## 자기감시 규칙

- **진동 방지**: 동일 파일 2 사이클 연속 수정 → 자동 수정 중단 + T2 그룹 강제
- **patrol*.md 자기수정**: 항상 T2 그룹 (T1 금지). **효력 다음 사이클부터**
- **skill.md 자기수정**: 동일
- **self-edit skip 가드**: 같은 사이클 내 self-edit 발생 시 나머지 C-check 는 방금 고친 규칙 재해석하지 않음

---

## 종료 조건

- Sentinel 파일 `~/.claude/.ruler/.wake-stop` 존재 → wake.sh 루프 종료
- `psmux ls` 에 `ruler` 부재 → 자동 종료
- 사용자 명시 `ruler stop` / `psmux kill-session -t ruler`

---

## 참조

- Ruler skill: [`~/.claude/skills/ruler-wf/skill.md`](~/.claude/skills/ruler-wf/skill.md)
- 운영 허브: [`~/.claude/docs/operations/ruler-operations.md`](~/.claude/docs/operations/ruler-operations.md)
- 영속 상태: [`~/.claude/.ruler/state.md`](~/.claude/.ruler/state.md)
- 일일 로그: `~/.claude/.ruler/log/{YYYY-MM-DD}.md`
- 회귀 하네스: [`~/.claude/docs/verification/secretary-regression/README.md`](~/.claude/docs/verification/secretary-regression/README.md)
- Coverage 확장 계획: [`~/.claude/.ruler/batch-plans/202604151600-event-driven-patrol/coverage-expansion-plan.md`](~/.claude/.ruler/batch-plans/202604151600-event-driven-patrol/coverage-expansion-plan.md)
