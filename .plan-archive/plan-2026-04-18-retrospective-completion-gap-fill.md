---
type: plan
scope: ruler-retrospective-completion
date: 2026-04-18
status: approved-in-progress
parent-plan: .plan-archive/plan-2026-04-18-retrospective-redesign.md
tags: [ruler, retrospective, completion, gap-fill]
related:
  - retrospective-guide.md
  - .ruler/scripts/retrospective-collect.sh
related-plan: .plan-archive/plan-2026-04-18-retrospective-redesign.md
---

# Retrospective 완성도 보완 — Gap Fill

> 기존 [`plan.md`](./plan.md) 의 재설계는 구조/스키마 확정(progress.md Step 1-8 완료). 본 plan 은 그 **구현 완성도 Primary 50% → 100% / Secondary 70% → 95%** 작업. 범위는 collect.sh 확장 + 운영 래퍼 3종 + 합성 fixture.

---

## 1. 배경 (재설계 후 남은 gap)

사용자 관점 E2E 검토 (2026-04-18T15:00 KST) 결과, `plan.md §1 목적` 대비 현재 구현 상태:

| 목적 | 현재 | 완성도 |
|---|---|---|
| Primary: T1/T2 에러 유발 추적 | decisions.jsonl pre/post 재발동만 반영 | 50% |
| Primary: 제대로 작동하는지 | audit-log hook 실패·guard 차단 **수집만**, verdict 식 미반영 | 30% |
| Primary: 이후 영향 판단 | escalation 카운터 **스냅샷만**, 증감 반영 없음 | 40% |
| Secondary: §0.5 누락 감지 | find ∖ decisions.jsonl 차집합 → missing_files[] 출력 | 100% |
| Secondary: backfill | **자동 append 없음**. batch 세션 런타임 책임 | 0% |
| Secondary: patrol drift sync | **LLM 비교 코드 없음**. guide 문서만 | 10% |
| Ops: 트리거 UX | 메인 세션이 4-step 수동 타이핑 | 60% |
| Ops: C_external baseline | checksums.md **미생성** → Tier C 작동 불가 | 0% |
| Ops: obs-only 4주 해제 | 2026-05-16 에 수동 제거 의존 | 40% |
| Ops: 회귀 테스트 | fixture 0종, 실데이터 smoke 만 | 20% |

**마감**: 2026-05-09 (observation-only 해제 1주 전). 해제 시점에 Primary 목적 완전 작동해야 retrospective 의 "판단 가능" 계약 충족.

---

## 2. Gap 상세 (9건)

### G1. verdict 식이 audit-log hook 실패를 반영 안 함 (Primary)

- **현재**: `compute_change_impact()` 가 `audit_err_total` 을 집계만 하고 verdict 로직에 미투입 (L358-365)
- **결과**: "T1 수정 후 hook 이 새로 자주 실패하는지" 포착 불가. plan §1 "얼마나 많은 에러를 유발했는지" 미달
- **근본 원인**: verdict 식이 decisions.jsonl pre/post 재발동 delta 만 쓰고, audit-log 이벤트는 aggregate 참고용으로만 뽑음

### G2. secretary escalation 이 per-T delta 로 반영 안 됨 (Primary)

- **현재**: `esc_now = .escalation_count` 를 read 만 함 (L369-372). 스냅샷 시점값이라 per-T 시점 delta 불가
- **결과**: "T 수정 후 escalation 증가 추세" 판정 불가
- **해결 경로**: audit-log ESCALATION 이벤트의 ts 기준 pre/post 카운트로 대체 (decisions.jsonl ts 비교와 동일 패턴)

### G3. BAD 보조 R# 가 R1/R2/R3 만 구현 (Primary 보강)

- **현재**: compute_change_impact() BAD 분기에 R1 (T1 Edit ≥3) / R2 (rollback) / R3 (재발동) 3개만
- **plan.md §부록**: R4 (pending dropped) / R5 (회귀 실패) / R11 (escalation rate) 는 audit-log / pending 참조로 구현 가능
- **우선도**: 선택적 — R1/R2/R3 로 대부분 확증 가능하나 "사문화 방지" 목적 달성 불완전

### G4. missing_files → decisions.jsonl backfill 자동화 없음 (Secondary)

- **현재**: collect.sh 가 `missing_files[]` 배열만 JSON 에 담음. backfill entry 는 batch 세션 Opus 가 수동 append 하라는 명세 (retrospective-guide §Phase B Step 2)
- **결과**: `original_absent:true` entry 가 생성되지 않으면 다음 주 Phase A 가 "기록 누락 = INSUFFICIENT 강제" 로직을 발동 못 함 (L410-412 `if orig_absent = true` 는 true 인 entry 가 있어야 트리거)
- **근본 원인**: 수동 단계 = 실행 보장 없음. "사용자 개입 0" 원칙과 충돌

### G5. Phase B Step 3 Patrol drift LLM 비교 실행체 없음 (Secondary)

- **현재**: guide §Phase B Step 3 문서만. 실제 LLM 호출 스크립트 없음
- **결과**: ruler-batch 세션 Opus 가 "guide 읽고 스스로 수행" — skip 해도 감지 불가
- **해결 경로**: checklist 체크박스화 + skip 시 decisions.jsonl `phase_b_step3: skipped, reason` 강제

### G6. 수동 트리거 4-step 원자화 없음 (Ops)

- **현재**: 메인 세션이 직접 TS 생성 → collect.sh → plan 파일 heredoc → spawn-batch-session.sh 4단계 타이핑
- **결과**: (a) 실수 여지 — frontmatter mode typo 시 batch 세션이 일반 batch 분기로 가서 retrospective 미실행 (b) 실행 장벽 높아 사용자가 자주 안 돌리게 됨
- **해결 경로**: `trigger-retrospective.sh` 래퍼 1개로 원자화

### G7. C_external baseline checksums.md 미생성 (Ops)

- **현재**: patrol-tier-c.md §C_external 에 "checksums.md 와 sha256 대조" 문서화됐지만 `.ruler/external-skill-checksums.md` 파일 미존재
- **결과**: 첫 Tier C 사이클에서 대조 대상 부재 → drift 감지 로직 작동 안 됨
- **해결 경로**: `seed-external-checksums.sh` one-shot 스크립트로 baseline 생성 + git 추가

### G8. observation-only 4주 자동 해제 로직 없음 (Ops)

- **현재**: state.md `change_impact_enforcement_start: 2026-05-16` 필드를 "누가·언제" 제거하는지 불명. guide §Phase A Observation-Only Mode "state.md 필드 제거(=활성화)" 만 언급
- **결과**: 5/16 에 수동 개입 필요. 수동이면 종종 까먹음 → 영구 obs-only 고착 위험
- **해결 경로**: Phase Terminal 에 자동 해제 로직 (`today >= start AND insufficient_rate < 0.5` 조건) + 실패 시 +2주 연장 기록

### G9. 합성 fixture 회귀 테스트 없음 (Ops)

- **현재**: 실데이터 smoke test 만 (decisions.jsonl T1/T2 = 0 건이라 verdict 로직 실제로 돌아본 적 없음)
- **결과**: verdict 식 리팩토링 시 회귀 검증 불가. G1/G2 확장 후 어떤 delta 임계가 GOOD/BAD 를 뽑는지 알 수 없음
- **plan.md §6.5.5 이미 요구**: GOOD/BAD/INSUFFICIENT 3 fixture + bats/assert harness — 미구현

---

## 3. 보완 설계

### 3.1 verdict 식 확장 (G1/G2 해결)

**현재 (fix 반영 후)**:
```
if pre == 0: NEUTRAL
if post_rb > 0: BAD
if (post - pre) / pre <= -0.20: GOOD
if (post - pre) / pre >= +0.20: BAD
else: NEUTRAL
```

**확장안**:
```
# 추가 입력 (audit-log 기반, ts 필터링)
audit_err_pre  = count(audit-log.ERROR, ts in [T-3.5d, T],   file grep 매칭)
audit_err_post = count(audit-log.ERROR, ts in [T, T+3.5d],   file grep 매칭)
esc_pre        = count(audit-log.ESCALATION, ts in [T-3.5d, T])
esc_post       = count(audit-log.ESCALATION, ts in [T, T+3.5d])

# verdict 재구성
if pre == 0 AND audit_err_pre == 0: NEUTRAL
if post_rb > 0: BAD
# 종합 delta: decisions 재발동 + audit err + escalation
dec_delta   = (post - pre) / max(pre, 1)
err_delta   = audit_err_post - audit_err_pre           (절대치)
esc_delta   = esc_post - esc_pre                       (절대치)

if dec_delta <= -0.20 AND err_delta <= 0 AND esc_delta <= 0:
  verdict = GOOD
elif dec_delta >= +0.20 OR err_delta >= +3 OR esc_delta >= +5:
  verdict = BAD
else:
  verdict = NEUTRAL

Δ summary = "재발동 Δ{N}% · err Δ{M} · esc Δ{K}"
```

**임계값 근거**: err_delta +3 (hook 당 3건 증가 = 구조적 신호), esc_delta +5 (escalation 5건 증가 = 운영 영향). observation-only 4주 동안 실측해 튜닝 가능.

### 3.2 missing_files backfill 자동화 (G4)

collect.sh 에 함수 추가:
```bash
backfill_missing() {
  local dec="${RULER_DIR}/decisions.jsonl"
  [ -z "$MISSING_FILES_JSON" ] || [ "$MISSING_FILES_JSON" = "[]" ] && return 0
  
  echo "$MISSING_FILES_JSON" | jq -r '.[]' | while IFS= read -r f; do
    [ -z "$f" ] && continue
    # 중복 방지: 이미 original_absent:true entry 가 있으면 skip
    if jq -c --arg f "$f" 'select(.file == $f and .original_absent == true)' "$dec" 2>/dev/null | head -1 | grep -q .; then
      continue
    fi
    
    # mtime / git log 로 ts 추정
    local mtime_ts
    mtime_ts=$(stat -c %y "$f" 2>/dev/null | cut -d'.' -f1 | tr ' ' 'T')"+09:00"
    
    # tier 추정: rules/skills/hooks 는 T1, 그 외 unknown
    local tier="unknown"
    echo "$f" | grep -qE "/rules/|/skills/|hooks/" && tier="T1"
    
    jq -n --arg ts "$mtime_ts" --arg f "$f" --arg t "$tier" \
      '{ts: $ts, session: "retrospective-backfill", file: $f, action: "backfill", reason: "retrospective: original_absent", tier: $t, original_absent: true, meta: {inferred_from: "mtime"}}' \
      >> "$dec"
  done
}

# Step 3-2 끝에서 호출
backfill_missing
```

**결과**: 다음 주 Phase A 가 `original_absent:true` entry 를 자동 감지 → INSUFFICIENT 강제 로직 작동.

### 3.3 trigger-retrospective.sh 신규 (G6)

```bash
#!/bin/bash
# trigger-retrospective.sh — retrospective 4-step 원자 실행
set -euo pipefail

TS=$(date +%Y%m%dT%H%M%S)
OUT="/tmp/retro-${TS}.json"
PLAN="/c/Users/jsh86/.claude/.ruler/batch-plans/${TS}_retrospective.md"

mkdir -p "$(dirname "$PLAN")"

echo "[trigger] Step 1/3: retrospective-collect.sh"
bash ~/.claude/.ruler/scripts/retrospective-collect.sh --window 7d --out "$OUT"

echo "[trigger] Step 2/3: plan file"
cat > "$PLAN" <<EOF
---
type: t2-batch-plan
mode: retrospective
input: $OUT
created: $(date -Iseconds)
---
# Retrospective ${TS}

Input=\`$OUT\`. Phase A → B → C → Final → Terminal per retrospective-guide.md.
EOF

echo "[trigger] Step 3/3: spawn-batch-session.sh"
bash ~/.claude/.ruler/scripts/spawn-batch-session.sh "$PLAN"
```

**CLAUDE.md Auto Triggers 주간리뷰 줄** 을 이 스크립트 한 줄 호출로 단순화.

### 3.4 seed-external-checksums.sh one-shot (G7)

```bash
#!/bin/bash
# seed-external-checksums.sh — C_external baseline 생성
set -euo pipefail

RULER_SKILL="$HOME/.claude/skills/ruler-wf/skill.md"
AUDIT_SKILL="$HOME/.claude/skills/audit-wf/skill.md"
OUT="$HOME/.claude/.ruler/external-skill-checksums.md"

[ -f "$RULER_SKILL" ] || { echo "ERR: $RULER_SKILL missing" >&2; exit 1; }
[ -f "$AUDIT_SKILL" ] || { echo "ERR: $AUDIT_SKILL missing" >&2; exit 1; }

R_HASH=$(sha256sum "$RULER_SKILL" | cut -d' ' -f1)
A_HASH=$(sha256sum "$AUDIT_SKILL" | cut -d' ' -f1)

cat > "$OUT" <<EOF
# external-skill-checksums
# 갱신: ruler Tier C C_external 체크 시 자동 갱신 (의도적 수정 확정 후)
# Seed: $(date -Iseconds)

ruler-wf/skill.md: $R_HASH
audit-wf/skill.md: $A_HASH
last-updated: $(date -Iseconds)
EOF

echo "[seed] $OUT created"
echo "ruler-wf:  $R_HASH"
echo "audit-wf:  $A_HASH"
```

### 3.5 obs-only 자동 해제 로직 (G8)

guide §Phase Terminal 에 체크 블록 삽입:
```markdown
### obs-only 해제 판정 (2026-05-16 이후 자동)

Phase Terminal 실행 시:
1. `today >= state.md[change_impact_enforcement_start]` 인가?
2. YES: `.ruler/retrospective/*_change-impact.md` 최근 4주치 verdict_dist 병합
3. `insufficient_rate = insufficient / (good+neutral+bad+insufficient)`
4. `< 0.5` → state.md 필드 제거 + promotion-log KNOWLEDGE entry append
5. `≥ 0.5` → state.md `change_impact_enforcement_start` 를 today + 14 로 갱신 + decisions.jsonl `action:"obs_only_extended"`
```

batch 세션 Opus 가 수동 수행. 체크박스 형태라 skip 방지.

### 3.6 합성 fixture + 테스트 하네스 (G9)

구조:
```
.ruler/tests/
├── fixtures/
│   ├── good-case.jsonl          # pre 15 · post 5 · rb 0 → GOOD
│   ├── bad-case.jsonl           # pre 10 · post 25 · rb 1 → BAD
│   └── insufficient-case.jsonl  # pre 5 → INSUFFICIENT
├── test-compute-change-impact.sh
└── run-all.sh
```

test-compute-change-impact.sh:
- fixture 로 `decisions.jsonl` 치환 (DEC 환경변수 override)
- collect.sh 실행
- 생성된 `_change-impact.md` 에서 verdict 행 grep
- 기대값과 비교, 불일치 시 exit 1

### 3.7 R4/R5/R11 쿼리 추가 (G3, 선택)

BAD 분기에 append:
- **R4**: `.ruler/pending/dropped/*.md` window 내 N ≥ 5 → "R4 pattern N hits"
- **R5**: audit-log `regression_failed` 이벤트 ≥1 → "R5 pattern N hits"
- **R11**: audit-log ESCALATION / (WARN+SONNET) ≥ 0.5 → "R11 pattern"

우선순위 낮음 — 본 plan 에서는 R4/R5 만 (R11 은 G2 의 esc_delta 와 겹침).

### 3.8 Phase B Step 3 체크리스트화 (G5)

guide §Phase B Step 3 를 5 체크박스로 재작성:
```markdown
### Step 3 — Patrol 규칙 동기화 (필수 체크리스트)

batch 세션 Opus 가 순차 수행:
- [ ] missing_files 중 `patrol*|event-rules*|rules/*.md` 매칭 건 필터
- [ ] 매칭 0건 → decisions.jsonl `{phase_b_step3:skipped, reason:"no_patrol_related_missing"}` append, skip
- [ ] 각 건에 대해 LLM 질의 (prompt/response 해시 meta 기록)
- [ ] 판정별 산출: T1 즉시 → patrol Edit, T2 → pending, clean → 무처리
- [ ] 실행 요약을 decisions.jsonl `{phase_b_step3:done, t1:N, t2:M, clean:K}` 로 1줄 append
```

skip 도 반드시 기록 = 실행 보장.

---

## 4. 파일 변경 (5 신규 + 3 수정)

| # | 경로 | 종류 | 내용 |
|---|------|------|------|
| 1 | `.ruler/scripts/retrospective-collect.sh` | 수정 | verdict 식 확장 (G1/G2) + backfill_missing() (G4) + R4/R5 쿼리 (G3) |
| 2 | `.ruler/scripts/trigger-retrospective.sh` | 신규 | 4-step 원자 실행 래퍼 (G6) |
| 3 | `.ruler/scripts/seed-external-checksums.sh` | 신규 | C_external baseline seed (G7) |
| 4 | `.ruler/external-skill-checksums.md` | 신규 (seed 실행 결과) | ruler-wf/audit-wf sha256 기준값 |
| 5 | `.ruler/tests/fixtures/good-case.jsonl` | 신규 | GOOD 기대 fixture |
| 6 | `.ruler/tests/fixtures/bad-case.jsonl` | 신규 | BAD 기대 fixture |
| 7 | `.ruler/tests/fixtures/insufficient-case.jsonl` | 신규 | INSUFFICIENT 기대 fixture |
| 8 | `.ruler/tests/test-compute-change-impact.sh` | 신규 | verdict 회귀 하네스 (G9) |
| 9 | `.ruler/retrospective-guide.md` | 수정 | §Phase B Step 3 체크리스트화 (G5) + §Phase Terminal obs-only 자동 해제 로직 (G8) |
| 10 | `~/.claude/CLAUDE.md` | 수정 (외부) | Auto Triggers 주간리뷰 줄을 `trigger-retrospective.sh` 한 줄 호출로 단순화 |
| 11 | `D:/projects/button/checklist.md` | 수정 (외부) | **구현 후 마지막 단계** — retro 섹션 별도 추가. btn-button 세션의 주간 체크 절차로 편입 (BAD verdict / C_external drift / missing_files 건수 / 마지막 retro 실행 ts) |

---

## 5. Steps (10 step)

본 섹션은 progress.md 생성 시 시드. Model 라우팅 근거 명시.

- **Step 1 — verdict 식 확장 + backfill 함수** (`model: opus`)
  - collect.sh 에 audit-log pre/post 카운트 블록 + verdict 재계산 + backfill_missing() 신규
  - 사유: verdict 식 확장은 A-B 트레이드오프 판단 (err_delta/esc_delta 임계값 선택)
  - Sonnet-executable: ❌ (판정 경계 설계)

- **Step 2 — trigger-retrospective.sh** (`model: sonnet`)
  - 4-step heredoc wrapper. 실패 시 exit 경로만 고려
  - Sonnet-executable 5항목 ✅

- **Step 3 — seed-external-checksums.sh + 실행** (`model: sonnet`)
  - one-shot 스크립트 + baseline md 생성
  - Sonnet-executable ✅

- **Step 4 — 합성 fixture 3종** (`model: sonnet`)
  - JSONL 손작성. 각 case 의 pre/post entry 10-25건
  - Sonnet-executable ✅

- **Step 5 — test-compute-change-impact.sh** (`model: sonnet`)
  - fixture 주입 + md 파싱 + assert
  - Sonnet-executable ✅

- **Step 6 — R4/R5 쿼리 추가** (`model: sonnet`)
  - BAD 분기에 pending/dropped + audit-log regression grep 추가
  - Sonnet-executable ✅

- **Step 7 — guide §Phase B Step 3 체크리스트화** (`model: opus`)
  - 체크리스트 항목 설계 + skip 기록 의무 스펙
  - 사유: 런타임 책임 vs 스크립트 책임 경계 설정
  - Sonnet-executable ❌

- **Step 8 — guide §Phase Terminal obs-only 해제 로직** (`model: opus`)
  - 해제/연장 조건 문구 + insufficient_rate 계산 식
  - 사유: 임계값 0.5 정당성 + +14d 연장 정책 설계
  - Sonnet-executable ❌

- **Step 9 — CLAUDE.md 트리거 단순화 + 통합 smoke** (`model: sonnet`)
  - Auto Triggers 주간리뷰 줄 교체 + fixture/실데이터 smoke 둘 다 PASS 확인
  - Sonnet-executable ✅

- **Step 10 — button/checklist.md 에 `## Retro.` 섹션 추가** (`model: sonnet`) — **구현 후 마지막 단계**
  - 파일: `D:/projects/button/checklist.md`
  - 위치: 기존 "매 wake 실행 절차" 하단에 `## Retro. (주간 retrospective 모니터링)` 섹션 신규
  - 내용 (체크 항목):
    - [ ] 마지막 retrospective 실행 ts 확인: `stat -c '%Y' ~/.claude/.ruler/retrospective/*_change-impact.md | tail -1` (7일 초과 시 경고)
    - [ ] 최신 change-impact.md 에 `BAD` verdict 건수 grep (1건+ 있으면 revert 검토 보고)
    - [ ] `~/.claude/.ruler/external-skill-checksums.md` 의 `last-updated` 최근 갱신 여부 (drift 감지 경보)
    - [ ] collect.sh `missing_files` 배열 길이 (JSON output 기준) — 3주 연속 0건 = §0.5 정착 성공 보고
    - [ ] obs-only 해제 여부: `grep change_impact_enforcement_start ~/.claude/.ruler/state.md` — 5/16 이후 남아있으면 경보
  - 건들지 말 것: 기존 ①~③ 절차, 간섭 금지 원칙, 기존 예상 세션 목록
  - 완료 판정: grep `'^## Retro\.'` + 5 체크박스 존재
  - 사유: btn-button 3분 wake 루프에 주간 retro health 신호를 편입해 사용자 개입 없이 보고 가능. retrospective 결과가 운영 관측 파이프라인에 실제로 유입되는 최종 고리
  - Sonnet-executable 5항목 ✅

---

## 6. 검증

### 6.1 Unit-level (fixture 기반)

- test-compute-change-impact.sh 가 3 fixture 모두 기대 verdict 반환
- R4/R5 쿼리가 fixture BAD case 에서 hit 표기

### 6.2 Integration-level (실 데이터)

- `trigger-retrospective.sh` 한 번 실행 → ruler-batch 세션 spawn → Phase A/B 산출물 생성 → self-terminate
- 생성된 decisions.jsonl 에 backfill entry (`original_absent:true`) 최소 1건 이상 append 확인
- C_external: seed 후 ruler-wf/skill.md 수동 touch → 다음 Tier C 사이클에서 drift 감지 → decisions.jsonl T1 entry

### 6.3 End-to-end (목적 대비)

- Primary 검증: 최근 T1 수정 (예: retrospective-collect.sh fix commit 4a40c6c) 을 T 시점으로 놓고 verdict 추출. GOOD/BAD 중 하나가 나와야 함 (NEUTRAL 이면 pre/post 데이터 부족)
- Secondary 검증: `original_absent:true` entry 생성 후 다음 주 Phase A 가 이 entry 를 INSUFFICIENT 로 판정하는지

### 6.4 observation-only 해제 리허설

- state.md `change_impact_enforcement_start` 를 임시로 어제 날짜로 설정 → Phase Terminal 수동 실행 → insufficient_rate 계산 + 해제/연장 판정이 올바른지 dry-run

---

## 7. 마감 + 리스크

- **마감**: 2026-05-09 (obs-only 해제 1주 전) — Step 1-9 완료
- **최소 수용 기준**: Step 1/2/3/5 PASS 시 observation-only 해제 가능. Step 4/6/7/8 는 5/16 이후로 연기 가능. Step 10 은 Step 1-9 완료 후 **반드시** 수행 (운영 파이프라인 연결)
- **리스크**:
  - Step 1 의 verdict 식 임계값 (+3, +5) 이 실데이터에 맞을지 불확실 — obs-only 기간 실측으로 튜닝
  - Step 9 smoke 에서 실 T1/T2 entry 부족 시 integration 검증 불가 → fixture 기반 검증으로 대체
  - Step 3 seed 후 checksums.md 를 git 추적할지 여부 — 논의 필요 (drift 기록 히스토리 vs 빈번 변경 noise)

---

## 8. 승인 후 다음 단계

1. 사용자 승인 → `progress.md` 덮어쓰기 (기존 재설계용은 `.plan-archive/` 이동)
2. Step 1-9 순차 실행. Model 라우팅 준수 (opus 3건 / sonnet 6건)
3. 각 Edit 직전 §0.6 grep gate, 직후 §0.5 3단 기록
4. Step 9 완료 = 본 plan self-archive (`.plan-archive/plan-completion-2026-04-18.md`)

---

## 9. 실행 완료 후 추가 보완 (2026-04-18 감사 반영)

Step 1-10 완료 후 E2E 검토 + source-recording audit 에서 발견한 gap + Step 5 agent 가 찾은 잠재버그 일괄 반영.

### 9.1 잠재버그 3건 (메인 opus 직접 수정)

| # | 위치 | 증상 | 수정 |
|---|---|---|---|
| B1 | `retrospective-collect.sh` L131 | 빈 `log/` 디렉토리 → grep 실패 → pipefail 로 전체 exit | `{ grep ... \|\| true; } \| while` 로 pipe 보호 |
| B2 | `retrospective-collect.sh` L662-665 | `grep -c` stdout 에 newline 섞여 `jq --argjson` 파싱 실패 (`G=1 N=0\n0`) | `awk '$0=="GOOD"{n++} END{print n+0}'` 단일 pass 로 교체 |
| B3 | `retrospective-collect.sh` L196 + `guide.md` L220 | `test("T1\|T2")` 가 T2 다수 시 각 entry 를 독립 T-point 로 선택 → pre/post window 교차오염 | `test("^T1")` + `T2_batch_applied` 만 T-point (T2 pending 제외). guide 스펙도 동기화 |

### 9.2 Source-recording gap 보완 (Step 11-13)

| Step | 대상 | 변경 | 효과 |
|---|---|---|---|
| 11 | `button/agent/secretary.js` + `secretary/escalation.js` | `log_event('ERROR'\|'error_detected', ...)` 분기 + `.secretary-state.json` `escalation_count` 누적 | collect.sh L149/L377 의존 충족 |
| 12 | `.ruler/scripts/t1-gate.sh` | `verify_rollback()` helper 신규 + rollback 실패 시 `type:"regression_failed"` audit-log append | R5 pattern 활성화 |
| 13 | `t1-gate.sh` + `retrospective-guide.md` Phase C | `--validate-entry` 서브커맨드 + `validate_entry()` helper (필수 필드 강제) + Phase C 종료 직전 `log/{date}.md` **무조건** append | 필드 누락 방지 + batch 기록 누락 방지 |

### 9.3 검증 빈도 확보 (Step 14-17)

| Step | 대상 | 변경 | 근거 |
|---|---|---|---|
| 14 | `~/.claude/hooks/ruler-decisions-autolog.sh` + `settings.json` | PostToolUse hook — Edit/Write/MultiEdit 이 ruler 전역 파일을 건드리면 `tier:"T0_autolog"` entry 자동 append | §0.5 의무를 hook 강제로 자동화 |
| 15 | `retrospective-collect.sh` L420 + L196 | N<10 → **N<5** 임계값 완화 (Poisson CI) + T-point 범위 `T1 prefix + T2_batch_applied` 확장 | 초기 부트스트랩 기간에 INSUFFICIENT 다수화 방지 |
| 16 | `t1-gate.sh` `--validate-entry` + `validate_entry()` | tier 값 regex `^(T[0-3](_[a-z_]+)?\|archive\|observe)$` 허용 + jq PATH 보강 | 비표준 tier 명칭 감지 (예: "WRONG" 거부) |
| 17 | `violation-tier-criteria.md` + `patrol-tier-a/c.md` | T1 확장 서브카테고리 (frontmatter 누락, 오탈자, deadlink) + T2 intake 명시화 | T entry 빈도 확보 → insufficient_rate 해결 |

### 9.4 button 운영 체크리스트 업데이트 (Step 10 확장)

`D:/projects/button/checklist.md` `## Retro.` 섹션을 3 sub-block (A 주간 가동 / B 소스 건전성 / C 자동화 작동) 으로 재구성. 총 15 체크박스.

### 9.5 완료 정의 (수용 기준 재정의)

- **OP-1 (필수)**: fixture 3/3 + real collect exit 0 + 통합 smoke 1회 이상 성공 (3/3 PASSED + exit 0 현 달성)
- **OP-2 (obs-only 해제 조건)**: 4주 관찰 후 insufficient_rate < 0.5 (Step 14 hook 작동 + Step 17 criteria 완화 적용 후 측정)
- **OP-3 (자동 경로)**: 메인 세션 ruler 전역 파일 편집 시 decisions.jsonl auto-append 100% 관찰 (Step 14 hook liveness)
- **OP-4 (비서 재시작 pending)**: Step 11 변경 반영을 위해 button 비서 재시작 1회 필요 (사용자 수동 타이밍)
