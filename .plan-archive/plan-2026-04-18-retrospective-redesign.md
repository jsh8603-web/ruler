<!-- STATUS: plan-refined-2026-04-18, ready-for-implementation (progress.md Steps 1,2,3,5,6,7,8) -->

---
type: plan
scope: ruler-retrospective-redesign
date: 2026-04-18
status: awaiting-approval
tags: [ruler, retrospective, redesign, change-impact]
related:
  - retrospective-guide.md
  - patrol.md
  - .ruler/scripts/retrospective-collect.sh
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

## 5. 편집 대상 (5 파일)

ruler repo 내부 3개 + 외부 2개 (§7.2 Q1 Python 제거 반영):

| # | 경로 | 소속 | 수정 내용 |
|---|------|------|----------|
| 1 | `retrospective-guide.md` | ruler | §1~§4 재작성. Phase A/B/C/Final/Terminal 재배치. R1~R11 부록 이동. Phase A 판정 스키마 + Phase B §0.5 감사 절차. |
| 2 | `patrol.md` | ruler | §사후 Retrospective 실행 순서 Phase A→B→C→Final→Terminal 로 갱신. |
| 3 | `.ruler/scripts/retrospective-collect.sh` | ruler | Δ 계산용 pre-T/post-T 윈도우 수집 + 누락 감사 교차 비교 JSON + **`compute_change_impact()` bash 함수** (verdict 계산, change-impact md 렌더). |
| 4 | `~/.claude/skills/ruler-wf/skill.md` §5b | 외부 | 수동 트리거 프로토콜에 Phase A/B 신규 설명. |
| 5 | `~/.claude/skills/audit-wf/skill.md` | 외부 | Phase Final-B (rules↔patrol 파일 리스트 diff) 역할을 "Phase B 누락 감사의 보완" 으로 재정의. 중복 제거. |

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

<!-- PHASE-1-COMPLETE: 2026-04-17T17:35:00Z agent_team=3 accept=13 defer=3 -->

## 6.5. Agent Team 검증 반영 (Phase 1 결과)

Phase 1 에서 TA/DA/Cost 3 에이전트 병렬 검증. ACCEPT 13건을 본 섹션 및 해당 Phase 정의에 반영. DEFER 3건은 §7.1 Open Questions 로 ultraplan refine 에게 위임.

### 6.5.1 retrospective-collect.sh 개선 (Step 3 범위 확장)

- **tail -500 cap 제거** → 날짜 기반 필터 (`awk 'ts > (now - window_sec)'`). 활발주 (1000+ entries/week) 에도 pre-T 범위 완전 cover. **근거**: 4일치 decisions.jsonl 이미 551건 (TA Q5 / DA A3 실측).
- **경로 정규화**: `find` 출력 + `jq '.file'` 출력 모두 `realpath` (또는 cygpath -w) 통과 후 비교. reverse-symlink junction (`~/.claude/.ruler` ↔ `D:/projects/ruler/.ruler`) 경로 문자열 mismatch 방지.
- **git log 교차검증**: `git log --since=7.days --name-only` 결과와 `find -mtime -7` 결과 교집합만 §0.5 누락 감사 후보로. Windows NTFS mtime 오탐 (DST/touch/checkout) 방어.
- **.gitignore/git ls-files 필터**: secretary.js 번들링 같은 build artifact 를 누락 후보에서 제외.

### 6.5.2 Phase A verdict 기준 강화

- **표본 크기 게이트 추가 (5번째 판정 조건)**: pre-T window 내 해당 check×file 이벤트 N < 10 → **INSUFFICIENT 강제**. Poisson 신뢰구간 기반 하한. ±20% 임계는 N ≥ 10 에서만 유효.
- **T-file 단위 분리 + 3.5d 간격 미달 시 INSUFFICIENT**: pre/post window overlap 방어의 최소 규칙. 완전 DiD 는 과잉 (개발 비용 > 이득).

### 6.5.3 Phase B §0.5 누락 감사 정확도 강화

- **backfill entry 에 `original_absent:true` 필드**: Phase A 가 이 flag 인 entry 를 `retroactive_rollback` 판정 불가로 분리 → INSUFFICIENT. 기록 누락 = 판정 누락 악순환 차단.
- **Step 3 LLM 의미 비교 범위 축소**: backfill 건 중 파일명이 `patrol*` / `event-rules*` / `rules/*.md` 연관 건만 LLM 비교 진입. 나머지는 decisions.jsonl entry 만 append. **실측 기반**: 누락 30건 중 patrol 연관 5-10건 예상 → LLM 호출 1/3-1/6 수준.
- **`pending/revert-{ts}-{file}.md` 소비자 명시**: Phase A Step 0 에 "이전 사이클 revert handoff 파일 소비 → 현재 verdict 입력에 재료로" 를 추가. 고아 파일 방지.

### 6.5.4 외부 skill 2개 drift 추적

- **신규 파일**: `.ruler/external-skill-checksums.md` — plan §5 편집 대상 #5, #6 의 sha256 저장. ruler Tier C 순찰이 실제 파일 해시와 대조, drift 감지.
- 또는 대안: decisions.jsonl entry 에 `external:true` + `sha256:{hash}` 필드. ruler C_memory 단계에서 교차 검증. 구현 단순도로 파일 방식 선호.

### 6.5.5 compute_change_impact() 품질 강화 (bash 통합)

- **합성 fixture 3종 의무화**: (a) GOOD verdict 가능 케이스 (pre 10건+ post 50% 감소) (b) BAD verdict 케이스 (post 25% 증가 + retroactive_rollback) (c) INSUFFICIENT 케이스 (N<10). `bats` 또는 shell assert harness.
- **Smoke test 변경**: plan §6.1 "지난 7일 baseline 대비 GOOD/BAD 추출" 은 baseline=0 승격으로 검증 불가 → **합성 fixture 주입 dry-run** 으로 대체. 실데이터 smoke 는 별도.

### 6.5.6 LLM 의미 비교 결정론성

- Phase B Step 3 LLM 호출 시 **프롬프트 해시 + 응답 해시** 를 decisions.jsonl `meta` 필드에 기록. 3주 누적 후 같은 (파일, 규칙) 쌍에 대한 판정 일관성 메타 리포트. 결정론성 확보는 불가하므로 **추적** 으로 대체.

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
| "compute_change_impact() bash 함수 유지보수 부담" | retrospective-collect.sh 내 jq+awk 블록 80-120 라인 예상. 단일 스크립트 유지. |

---

## 7.1 Open Questions for Ultraplan Refine (Phase 1 DEFER 3건)

Phase 1 Agent Team 검증 결과 ACCEPT 13건은 §6.5 로 반영. 아래 3건은 scope/philosophy 판단이라 ultraplan refine 의 넓은 context 에서 결정 권고.

### Q1. Python (change-impact.py) 제거 여부

- **원안**: `scripts/change-impact.py` 신규 150줄 (Python) — datetime 파싱 편의 + 구조화된 verdict 계산
- **Cost 권고**: `.ruler/scripts/retrospective-collect.sh` 에 bash 함수로 통합 + Python 제거. 런타임 경로 3종 (`py -3`/`python3`/절대경로) 부담 회피 + 단일 스크립트 유지
- **판단 요청**: 단일 스크립트 통합이 실용적인가, Python 분리가 장기 유지보수에 더 이득인가?

### Q2. Phase A 활성화 시점 — 즉시 vs 4주 유예

- **원안**: Phase A + Phase B 동시 구현. 초회부터 verdict 산출
- **Cost 권고**: Phase B 먼저 단독 배포 (즉시 27건 gap 감지 실측). Phase A 는 4주 데이터 축적 후 활성화 (초회 판정 가능 건수 20-30 중 대부분 INSUFFICIENT 예상)
- **절충안**: Phase A 구현은 하되 초회 4주간 `preflight 승격 금지 — 관찰 전용` 모드. verdict 축적만.
- **판단 요청**: 사용자 Primary 요구 (인과 판정) 를 4주 늦추는 것이 허용되는가, 아니면 첫날부터 (불완전해도) verdict 가 필요한가?

### Q3. R1~R11 verdict 통합 방식

- **(a) Cost 축소안**: 부록 유지 + Phase A BAD 판정 시 "R# 빈도 보조 확인" 1줄. 구현 복잡도 최소
- **(b) DA 편입안**: verdict 표 5번째 행 추가 "R# pattern N+ hits → soft-BAD". 명시적이지만 튜닝 포인트 증가
- **(c) 폐기**: R1~R11 부록도 제거, decisions.jsonl 기반 verdict 만
- **판단 요청**: R1~R11 를 사문화하지 않으면서 verdict 과잉복잡화도 피하는 선이 어디인가?

---

<!-- PHASE-2α-SKIP: 2026-04-18T02:50:00Z reason=cloud_workspace_locked_to_button hypothesis=B -->

## 7.2 Supervisor 판정 (§7.1 DEFER 3건 — 로컬 정식 채택)

> **배경**: cloud `/ultraplan refine` 은 workspace 가 Button WOL 에 고정되어 ruler repo 접근 불가 (NUDGE_1~4 참조). 가설 B (workspace 고정) 확정 → 아래 3건 판정이 **정식 결정**.

### Q1. Python (change-impact.py) 제거 — ✅ Cost 권고 (bash+jq 통합)

- **결정**: `.ruler/scripts/change-impact.py` 신설 **취소**. `.ruler/scripts/retrospective-collect.sh` 에 `compute_change_impact()` bash 함수로 통합 + jq/awk 로 verdict 계산.
- **근거**: (a) ruler patrol/batch 모두 bash+jq 만 사용 (Python 의존 0) (b) decisions.jsonl 4일 551건 규모에서 jq 파싱 충분 (c) 단일 스크립트 = patrol 의 3분 wake 루프 오버헤드 최소.
- **trade-off**: 5번째 INSUFFICIENT 게이트 (Poisson CI) 는 `if N<10` 단순화 로 대체. 정밀도 손실 수용.
- **plan/progress 영향**: §5 표 #4 삭제 완료 (신규 .py 없음). §8 Step 4 제거 (본 refine 에서 처리).

### Q2. Phase A 활성화 시점 — ✅ 절충안 (구현 + 4주 관찰 전용)

- **결정**: Phase A 는 1차 배포 (Step 1+3) 에서 구현 완료. 단 **2026-04-18 ~ 2026-05-16 (4주) 는 `verdict_observation_only: true` 모드** — verdict 산출 + md 기록은 하되 **preflight 승격 / pending/revert-*.md 생성 / handoff 트리거 전부 차단**.
- **근거**: Primary (인과 판정) 를 4주 늦추지 않으면서, 초기 INSUFFICIENT 폭주 (Cost 예측: 20-30건 중 대부분) 가 실행 행위를 유도하지 않도록 격리.
- **구현 위치**: `.ruler/state.md` 에 `change_impact_enforcement_start: 2026-05-16` 필드. `compute_change_impact()` 가 이 date 이전이면 verdict 산출·기록만, preflight/revert skip. 출력 md 상단에 `> ⚠️ OBSERVATION-ONLY MODE (until 2026-05-16)` 배너.
- **해제 조건**: 2026-05-16 retrospective 에서 verdict 분포 (GOOD/BAD/INSUFFICIENT 비율) 검토 → INSUFFICIENT < 50% 시 해제. 이상이면 +2주 연장.

### Q3. R1~R11 verdict 통합 — ✅ (a) Cost 축소안

- **결정**: R1~R11 정의는 `retrospective-guide.md §부록` 이동 (§3.1 그대로). Phase A BAD verdict 산출 시 출력 md 의 `Δ summary` 칼럼에 **"R# pattern X hits"** 1줄 보조 표기.
- **근거**: (a) verdict 본체는 decisions.jsonl Δ 만으로 결정 (튜닝 포인트 1개 유지) (b) R1~R11 빈도 패턴은 BAD 근거 강화 재료로만 — 사문화 방지 + verdict 오염 회피 (c) DA 편입안 (5번째 판정행) 은 임계 2개 동시 튜닝 → 4주 관찰과 충돌.
- **구현 위치**: `compute_change_impact()` 의 verdict=BAD 분기에서 R1~R11 `--window 7d` 결과를 읽어 해당 file/check 에 매칭되는 R# 만 추출. 매칭 없으면 보조 표기 생략.

### §6.5 보완 (Q1/Q2/Q3 반영)

- **§6.5.4 외부 skill drift**: `external-skill-checksums.md` 파일 방식 그대로. 단, **patrol-tier-c.md §C_external 항목 추가** 가 필요 → progress.md Step 8 (신규, sonnet, 1 line append) 로 분리.
- **§6.5.5 fixture**: Python 제거 → `compute_change_impact()` + bats 또는 shell assert harness. 합성 fixture 3종 (GOOD/BAD/INSUFFICIENT) 의무 유지.

---

## 8. 다음 단계

1. 사용자 승인 → `progress.md` 의 Step 1~7 (+ Step 8 신규) 순차 실행
2. step 별 model 라우팅 (progress.md 와 동기):
   - Step 1 (retrospective-guide.md 재작성): `model: opus` — Phase 구조 재정의 + 판정 스키마 설계
   - Step 2 (patrol.md 실행 순서): `model: sonnet` — 기계적 치환
   - Step 3 (retrospective-collect.sh + compute_change_impact 통합): `model: sonnet` — bash+jq 구현, N<10 단순화
   - Step 5 (ruler-wf skill.md §5b): `model: sonnet` — 텍스트 편집
   - Step 6 (audit-wf skill.md Phase Final-B 재정의): `model: opus` — 역할 분담 설계
   - Step 7 (Smoke test + 합성 fixture dry-run): `model: sonnet` — 검증만
   - Step 8 (patrol-tier-c.md §C_external 1-line append, §6.5.4 후속): `model: sonnet`
3. 각 SSOT 편집 전 **§0.6 grep gate** 필수: `grep '"file":"<target>"' decisions.jsonl | tail -5`
4. 각 Edit 직후 **§0.5 3단 기록**: decisions.jsonl append + log/{date}.md batch 블록 + (.ruler/*.md 에 한해) frontmatter last-edit

---

## 9. Repo 분리 완료 — External Dependencies

> ruler repo 는 이미 분리 완료 (`github.com/jsh8603-web/ruler`, 본 plan.md 가 repo 루트에 존재). 본 섹션은 external dependency 추적용.

- **외부 편집 대상 2개**: `~/.claude/skills/ruler-wf/skill.md` §5b, `~/.claude/skills/audit-wf/skill.md` — §6.5.4 의 `external-skill-checksums.md` + patrol-tier-c.md §C_external 이 drift 감지 담당.
- **외부 read-only 소비**: `D:/projects/button/agent/secretary.js` + `.secretary/` 상태, `~/.claude/audit-log/*.jsonl` — retrospective Phase A Δ 입력으로만 참조, 편집 금지 (retrospective-guide §0 Boundaries).
- **Symlink 투과**: `~/.claude/.ruler/` ↔ 본 repo `.ruler/` (SYMLINK-SETUP.md 참조). 경로 정규화는 §6.5.1 realpath 처리로 방어.
