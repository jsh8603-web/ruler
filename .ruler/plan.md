---
type: plan
scope: ruler-retrospective-redesign
date: 2026-04-18
status: awaiting-approval
tags: [ruler, retrospective, redesign, change-impact]
related:
  - retrospective-guide.md
  - patrol.md
  - scripts/retrospective-collect.sh
related-plan: null
---

# Retrospective 재설계 — T1/T2 변경 인과 추적 + §0.5 누락 동기화

> 본 plan 은 이 ruler repo 의 **`retrospective-guide.md` + `patrol.md` + `scripts/retrospective-collect.sh`** 를 중심으로 **기존 Phase 구조의 역할을 재정의**하는 작업. 리팩토링 범위는 repo 외부 2개 skill(`~/.claude/skills/ruler-wf/skill.md`, `~/.claude/skills/audit-wf/skill.md`) 까지 확장.
> 
> Repo root: [`CLAUDE.md`](./CLAUDE.md) — 불변 사항, SSOT 맵, 역할 분리 정의.

---

## 1. 목적 (사용자 원문)

### Primary

**T1/T2 수정 (비서 기능 + 규칙) 이 어떤 영향을 줬는지 추적한다.**

- 각 T1/T2 변경이 **얼마나 많은 에러를 유발했는지**
- **제대로 작동하고 있는지**
- **이후 미치는 영향이 어떤지**
- → **해당 시점의 수정이 잘되었다 / 잘못되었다** 판단 가능해야 함

### Secondary

**§0.5 편집 기록 의무 누락 감지 + patrol 규칙 동기화.**

- `retrospective-guide.md §0.5` 에 이미 명시: 매 Edit 직후 `decisions.jsonl` + `log/{date}.md` + (선택) frontmatter 3단 기록.
- 기록 **누락 시 patrol 규칙과 의미 동기화**가 필요.

---

## 2. 현재 구현 진단 — 재설계 명분

### 2.1 기능 A 이미지(외부 분석) 지적

| 원 의도 | 현재 R1~R11 구현 |
|---|---|
| "X 규칙 수정 → Y 현상 줄었나?" (인과) | "이번 주 이런 패턴 N회 나왔다" (단순 관찰) |
| 변경 전/후 **시계열 비교** | 단일 7일 window 빈도 카운트 |
| 비서 기능 추가가 실제로 써먹혔나 | 기능 사용 추적 없음 |

### 2.2 실측 baseline (결정적 증거)

**2026-04-18T01:24:14 KST** `ruler-batch-20260418T011559` 가 **"first-ever retrospective baseline"** 실행:

- R1~R11 판정: 3 R1 borderline hits — **all benign operational patterns**
- preflight 승격: **0건**
- Phase B variant: `lightweight_B3` (pointer grep PASS)
- Phase Final: Hook SSOT 18 entries fully aligned
- 승격 0 / promoted 0 / stale_cleaned 0 / hook_drift 0

→ 기능 A 이미지 지적대로 **현재 구현은 패턴 빈도 관찰에 그쳐 실제 인과 판정을 못 내림**. 실측 근거 확보.

### 2.3 이전 제안(내부 Phase D) 재검토

내가 먼저 제안했던 "wf/규칙/비서 ↔ patrol 의미 비교 Phase D" 는:
- **Primary 목적 누락** (변경→효과 Δ 없이 의미 비교만)
- **§0.5 누락 감사 단계 없음** (의미 비교로 바로 점프)

→ 재설계에 **흡수 + 재배치**.

---

## 3. 통합 재설계 — Phase 재배치

### 3.1 전체 Phase 배치

```
Phase A — T1/T2 Change-Impact Verdict        [Primary]
Phase B — §0.5 Compliance Audit + Patrol Sync [Secondary]
Phase C — 심층 감사 연계 (audit-wf 조건부)     [기존 Phase B 승격]
Phase Final — Hook SSOT Sync                  [유지]
Phase Terminal — state 갱신 + self-terminate  [기존 Phase C 이름변경]
```

**R1~R11 처리**: `retrospective-guide.md §부록` 이동. Phase A 의 **Δ 판정 보조 재료** 로 활용 (빈도 신호 자체가 BAD verdict 의 근거가 됨). 폐기 아님.

### 3.2 Phase A — T1/T2 Change-Impact Verdict

**입력**:
- `decisions.jsonl` 7일치 T1/T2 entry (스키마 확인됨: `ts/check/tier/file/outcome/phase`)
- Δ 관찰 소스 (T 시점 전후 각 3.5일 윈도우):
  - `decisions.jsonl` 동일 `check` / 동일 `file` 재발동 건수
  - `retroactive_rollback` / `outcome:"rolled_back"` 발생
  - `~/.claude/audit-log/{date}.jsonl` hook 실행 실패 / guard 차단 빈도
  - `D:/projects/button/agent/.secretary/.secretary-state.json` + escalation 카운터

**처리 per T1/T2 entry**:
1. T 시점 식별 (`ts` 필드)
2. Pre-Δ (T-3.5d ~ T) 지표 snapshot
3. Post-Δ (T ~ T+3.5d) 지표 snapshot
4. 지표별 변화율 + 방향 판정

**판정 verdict**:

| Verdict | 기준 |
|---|---|
| **GOOD** | Post-Δ 에러/rollback ↓ 20%+ AND 신규 에러 0건 |
| **NEUTRAL** | 변화 ±10% 이내 OR window 부족 (<3일) |
| **BAD** | Post-Δ 에러/rollback ↑ 20%+ OR 같은 target 재수정 OR retroactive_rollback |
| **INSUFFICIENT** | Post 데이터 부족 (T < 3일 전) — 다음 주 재평가 |

**출력**: `retrospective/{date}_change-impact.md`

```
| T                    | file            | tier | action              | verdict | Δ summary                     |
|----------------------|-----------------|------|---------------------|---------|-------------------------------|
| 2026-04-18 01:21 KST | secretary.js    | T1   | WORKING_RE 재설계   | GOOD    | guard FP -70%, escalation -45%|
| 2026-04-16 22:56 KST | t1-gate.sh      | T1   | delete 용도 오용    | BAD     | 같은 체크 3회 재발동          |
```

**BAD 판정 시**: `pending/revert-{ts}-{file}.md` 생성. 다음 사이클 handoff.

### 3.3 Phase B — §0.5 Compliance Audit + Patrol Sync

**Step 1 — 누락 감사**:

```bash
# 1) 지난 7일 실제 변경 파일 (source of truth: mtime)
find ~/.claude/rules ~/.claude/skills ~/.claude/docs ~/.claude/.ruler \
     D:/projects/button/agent/secretary.js \
     D:/projects/button/agent/secretary/*.js \
     -type f -mtime -7

# 2) decisions.jsonl 에 기록된 file 목록
jq -r 'select(.ts > "2026-04-11") | .file // (.files[]? // empty)' decisions.jsonl | sort -u

# 3) 차집합 = §0.5 미준수 건
comm -23 <(실제변경 sort) <(기록된 sort)
```

**Step 2 — 누락 건별 backfill**:
- `mtime` + `git log` (button) 으로 변경 시점/행위자 추정
- 변경 사유 주석/commit 으로 유추
- `decisions.jsonl` 에 `reason:"retrospective backfill"` + tier 추정 append
- `log/{date}.md` "누락 복구" 섹션 append

**Step 3 — Patrol 규칙 동기화** (누락 건 대상):
- 변경된 규칙/코드 의미 vs `patrol.md` / `patrol-tier-*.md` / `event-rules.yaml` 감지 기준 LLM 비교
- 판정:
  - **T1 즉시**: 정면 충돌 → patrol Edit + 별도 decisions.jsonl entry
  - **T2 pending**: drift 하지만 오탐만 → `pending/patrol-sync-{id}.md`
  - **clean**: 정합 유지

**출력**: `retrospective/{date}_compliance.md`

```
## 누락 감사
- 실제 변경: N건
- decisions.jsonl 기록: M건
- 누락: K건 → backfill + patrol sync 수행

## Patrol Drift (누락 건 대상)
- T1 즉시 갱신: N건 ({파일:라인})
- T2 pending: M건
- clean: K건
```

### 3.4 Phase C — 심층 감사 연계 (기존 Phase B 승격)

B1~B6 발동 조건 유지. audit-wf 조건부 실행. 본 plan 범위 밖(변경 없음).

### 3.5 Phase Final — Hook SSOT Sync

`settings.json` ↔ `hook-guard-review.md` 양방향 diff. 본 plan 범위 밖(유지).

### 3.6 Phase Terminal — state 갱신 + self-terminate

기존 Phase C 내용 그대로. 이름만 변경 (Phase C 는 "심층 감사" 에 할당됨).

---

## 4. review.md 재정의

**변경 전** (현재): R1~R11 단순 관찰 나열.
**변경 후**:

```markdown
## 이번 주 변경 × 효과 매트릭스 (Phase A)
{change-impact 표 — GOOD/NEUTRAL/BAD/INSUFFICIENT}

## §0.5 준수 + Patrol Sync (Phase B)
- 누락 감사: N건 backfill
- Patrol Drift: T1 {N} / T2 {M} / clean {K}

## 부록 — 빈도 패턴 (R1~R11, Phase A 판정 보조)
{기존 빈도 분석, Phase A verdict 근거로 활용}
```

---

## 5. 편집 대상 (6 파일)

ruler repo 내부 4개 + 외부 2개:

| # | 경로 | 소속 | 수정 내용 |
|---|------|------|----------|
| 1 | `retrospective-guide.md` | ruler | §1~§4 재작성. Phase A/B/C/Final/Terminal 재배치. R1~R11 부록 이동. Phase A 판정 스키마 + Phase B §0.5 감사 절차. |
| 2 | `patrol.md` | ruler | §사후 Retrospective 실행 순서 Phase A→B→C→Final→Terminal 로 갱신. |
| 3 | `scripts/retrospective-collect.sh` | ruler | Δ 계산용 pre-T/post-T 윈도우 수집 + 누락 감사 교차 비교 JSON 추가. |
| 4 | `scripts/change-impact.py` (신규) | ruler | T 시점 Δ 계산 헬퍼. decisions.jsonl + audit-log 파싱. |
| 5 | `~/.claude/skills/ruler-wf/skill.md` §5b | 외부 | 수동 트리거 프로토콜에 Phase A/B 신규 설명. |
| 6 | `~/.claude/skills/audit-wf/skill.md` | 외부 | Phase Final-B (rules↔patrol 파일 리스트 diff) 역할을 "Phase B 누락 감사의 보완" 으로 재정의. 중복 제거. |

**불변 사항 준수 확인**:
- Identity / Lifecycle / cwd 고정 / §0.5 의무 / §0.6 gate / self-terminate / 모델 정책 / 7일 주기 / Phase Final 강제 / T1/T2/T3 분류 — **모두 유지**. 재설계는 **Phase A/B 의 내용 재정의** 만 건드림.

---

## 6. 검증 (Phase 3)

1. **Smoke test**: 지난 7일 범위로 수동 retrospective 1회 실행 (메인 세션 `룰러 리뷰` 키워드 → `ruler-batch-{ts}` 스폰).
   - Phase A/B 산출물 (`retrospective/{date}_change-impact.md`, `_compliance.md`) 검토
   - 오늘 01:24 baseline (0 승격) 대비 **변경이 실제로 GOOD/BAD 판정을 추출**하는지 확인
2. **토큰 실측**: Phase A + B 합산 Opus 토큰. **100k 초과 시 조건부화** (변경 10건+ 시만 Phase A 심층, 이하면 요약).
3. **BAD 판정 오탐**: 첫 1-2주 수동 리뷰. verdict 임계값 튜닝 (±20% → ±15% 등).
4. **누락 감사 0건 수렴**: §0.5 기록 의무 준수율 추적. 연속 3주 누락 0건 = 의무 정착 성공.

---

## 7. Ultra-Plan 리뷰 포인트 (설계wf Debate v2 입력)

설계wf / debate 가 공격(attack) 할 가능성 높은 지점 미리 체크:

| Attack 벡터 | 방어 |
|---|---|
| "pre-T 3.5d window 가 충분한가? 짧은 사이클 변경은 Δ 감지 불가" | 변경 자체가 3.5d 간격 이상일 경우만 Δ 신뢰. 미만은 INSUFFICIENT 판정. |
| "LLM 의미 비교(Phase B Step 3) 오탐률 모름" | 첫 1-2주 수동 리뷰로 튜닝. 오탐 높으면 T1 기준 엄격화 or T2 만 허용. |
| "누락 감사가 find mtime 기반 — 파일 많으면 false positive" | 범위 제한: `rules/ + skills/ + docs/operations/ + .ruler/ + button/agent/secretary.js` 만. audit-log 참조로 교차 검증. |
| "Phase A/B 동시 실행 시 토큰 200k 초과" | Phase B 는 Phase A 의 BAD 건부터 우선. 나머지는 변경 건수 가드 (10건+) |
| "R1~R11 부록 이동 = 사실상 폐기?" | Phase A 처리 절차에서 R1~R11 을 Δ 보조 재료로 명시 사용. 사문화되지 않음. |
| "§0.5 backfill 은 사후 기록 = 부정확" | `reason:"retrospective backfill"` 명시로 구분. git log + mtime 최대한 활용. 원본 불명 건은 `tier:"unknown"` 유지. |
| "change-impact.py 신규 스크립트 유지보수 부담" | decisions.jsonl jq 쿼리 + Python 150 라인 내외 예상. 최소 구현 유지. |

---

## 8. 다음 단계

1. 사용자 승인 → `progress.md` 작성 (6개 편집을 step 분할)
2. 각 step 별 model 라우팅:
   - Step 1 (retrospective-guide.md 재작성): `model: opus` — 설계 비중 큼
   - Step 2 (patrol.md 실행 순서): `model: sonnet` — 기계적 치환
   - Step 3 (retrospective-collect.sh): `model: sonnet` — 스크립트 변경
   - Step 4 (change-impact.py 신규): `model: opus` — 설계 포함
   - Step 5 (ruler-wf skill.md): `model: sonnet` — 텍스트 편집
   - Step 6 (audit-wf skill.md Phase Final-B 재정의): `model: opus` — 역할 분담 설계
3. 각 SSOT 편집 전 **§0.6 grep gate** 실행 필수 (`grep '"file":"<target>"' decisions.jsonl | tail -5`).
4. 각 Edit 직후 **§0.5 3단 기록** 수행.

---

## 9. Ruler repo 분리 이후 관점

ruler 리포가 별도 분리되면:
- 이 `plan.md` + `CLAUDE.md` 는 **리포 루트** 에 그대로 존속.
- 외부 편집 대상 2개 (ruler-wf skill.md, audit-wf skill.md) 는 **cross-repo 링크** 로 이관 추적.
- `D:/projects/button/agent/secretary.js` 등 외부 의존성은 리포 README 의 "External Dependencies" 섹션으로 정리.
- retrospective 가 인용하는 audit-log 경로 (`~/.claude/audit-log/`) 는 read-only 소비자로 유지.
