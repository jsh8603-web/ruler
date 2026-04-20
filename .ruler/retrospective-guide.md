---
type: ruler-retrospective-guide
date: 2026-04-15
last-edit: 20260418-1432
last-edit-by: btn-ruler (plan Step 1)
tags: [ruler, retrospective, audit-wf, batch-ssot]
---

# Ruler Retrospective Guide — Batch 세션 SSOT

(root: [`~/.claude/.ruler/patrol.md`](~/.claude/.ruler/patrol.md) §사후 Retrospective / [`~/.claude/skills/ruler-wf/skill.md`](~/.claude/skills/ruler-wf/skill.md) §5b 에서 참조)

> **이 파일 = `ruler-batch-*` 세션의 단일 진실원 (SSOT)**. SessionStart hook 이 batch 세션 감지 시 pointer 만 주입, 본문은 on-demand Read. patrol 본체 (`ruler-wf/skill.md`) 는 **읽지 않는다** — 역할 불일치 (patrol=Sonnet 장수명 루프, batch=Opus 일회성).

## §0. Session Identity & Lifecycle (batch SSOT 핵심)

### Identity
| 항목 | 값 |
|---|---|
| 세션명 | `ruler-batch-{YYYYMMDDTHHMMSS}` |
| 모델 | Opus (spawn-batch-session.sh 고정) |
| cwd | `C:\Users\jsh86\.claude` |
| 수명 | **일회성** (수 분 ~ 1시간, 작업 완료 즉시 self-terminate) |
| 상위 세션 | 없음 (메인 세션이 스폰 후 관여 X, patrol 도 개입 X) |
| 역할 | retrospective 분석 + audit-wf Phase B 조건부 실행 |

### Boundaries (건드리면 안 되는 것)
- **patrol 세션과 독립**: `state.md` / `log/{date}.md` / `pending/` 편집은 Phase C 종료 단계에서만
- **worker/verifier/healer/strategic 무관**: harness WF 배선 touch 금지
- **button 프로젝트 배선 무관**: `D:\projects\button\` 코드 편집 금지 (rules 드리프트 분석 대상이면 예외)
- **secretary.js 편집 금지**: audit-wf Phase B 가 승격 감사로 발견해도 T2 pending 큐잉만, 직접 Edit 금지
- **사용자 interaction 0**: 질문/확인 금지. 판단 애매 → 보수적 skip + decisions.jsonl 로그

### Input Contract
- **필수**: `/tmp/retro-{ts}.json` (retrospective-collect.sh 산출, 10개 소스 통합)
- **없으면**: 즉시 Phase A skip → Phase B 조건만 평가 → skip 시 self-terminate
- **메인 세션 초기 프롬프트**: input 경로 + phase 지시 (A/B/C) + 완료 기준만 담김. 나머지는 본 파일 §1~§6 에서 Read.

### Output Contract
| 산출물 | 경로 | 작성 단계 |
|---|---|---|
| plan | `.ruler/retrospective/{YYYY-MM-DD}_plan.md` | Phase 2 |
| review | `.ruler/retrospective/{YYYY-MM-DD}_review.md` | Phase A |
| 적용 Edit | `patrol.md` / `preflight-rules.md` / `rules/*.md` (해당 시) | Phase A/B |
| 결정 로그 | `.ruler/decisions.jsonl` append | 매 Edit 직후 |
| 상태 갱신 | `.ruler/state.md` (`last_audit_wf_ts`, `promotion_log_last_count`, `memory_index_last_count`) | Phase C |
| 종료 신호 | `[ruler-wf-end]` → `ruler` 세션 송신 | Phase C 마지막 |

### Self-Terminate Protocol
Phase C 통합 요약 출력 직후 즉시 다음을 순서대로 수행 후 **스스로 세션 종료**:

```bash
# 1. decisions.jsonl append (Phase C 요약)
echo '{"ts":"'$(date -Iseconds)'","action":"retrospective_executed",...}' >> ~/.claude/.ruler/decisions.jsonl

# 2. state.md 갱신 (Edit 도구)

# 3. plan 파일 이동
mv ~/.claude/.ruler/retrospective/{date}_plan.md ~/.claude/.ruler/retrospective/done/

# 4. ruler 세션에 종료 신호
source "$HOME/.claude/scripts/lib/psmux-send.sh"
psmux_send_message ruler "[ruler-wf-end] batch=$PSMUX_SESSION rules_applied=N promoted=N"

# 5. 자가 kill (secretary 레지스트리 자동 정리됨)
psmux kill-session -t $PSMUX_SESSION
```

**kill 실패 시 fallback**: `echo TASK_DONE_RULER_BATCH` 출력 후 사용자 개입 대기 (수동 kill). 단, 완료 보고 후 추가 작업 금지 — IDLE 유지.

### 비정상 종료 조건 (early-exit)
| 상황 | 대응 |
|---|---|
| input JSON 없음 / 비어있음 | Phase A skip → Phase B 평가 → 모두 false 면 decisions.jsonl `skip_reason:"no_input"` append → self-terminate |
| R1~R11 매칭 0건 | Phase A 결과=empty → preflight 추가 없음 → Phase B 로 진행 (정상) |
| retrospective-collect.sh 실패 | 메인 세션 스폰 단계 오류 → batch 세션은 애초에 안 뜸, 고려 불필요 |
| Phase B 진입 조건 전부 false | Phase Final (Hook SSOT sync) 만 수행 후 self-terminate. Phase Final 은 **무조건**. |

### Idle Discipline (과거 실패 교훈)
> **실제 사례**: 이 SSOT 가 없던 시절 `ruler-batch-20260414T1625` 가 12시간+ IDLE 로 떠서 compact 7회 + MEMORY IDLE ckpt 11건 누적. 종료 조건 불명확이 근본 원인.

- **작업 완료 = 즉시 self-terminate**. 다음 지시 대기 금지.
- **compact 발생 시**: MEMORY append 는 **진행 중 결정/산출물만**. `IDLE 지속` 류 filler ckpt 금지.
- **IDLE 전환 감지**: Phase C 출력 후 IDLE 로 돌아갔다면 **즉시** self-terminate 수행. "사용자 지시 대기" 모드 금지.
- **사용자 질문 금지**: 판단 애매 시 보수적 skip + `decisions.jsonl` 에 reason 기록. Phase C 요약에서 남은 이슈로 보고.

### Compact Resilience (세션이 길어졌을 때)
batch 세션은 보통 compact 전에 끝나지만, Phase B 대규모 감사 시 touch 가능. 이 경우:
- 리줌 후 본 파일 **§0 만 Read** (나머지는 필요 시 on-demand)
- MEMORY append 는 현재 Phase (A/B/C) + 다음 step 만 1줄. ckpt spam 금지.
- 중단된 Edit 이 있으면 재개, 없으면 Phase C 로 jump → self-terminate.

### §0.5 편집 기록 의무 (공유 체인 루프 — patrol↔batch)

**목적**: patrol 과 batch 가 **같은 타겟 파일** 을 시점 다르게 편집할 때, 직전 편집자의 의도/결정을 자동 참조하며 연쇄 수정하는 루프. 별도 storage 없이 기존 3개 SSOT 에 분산 기록 + 링크로 체인 재구성.

**3단 기록 (매 Edit 직후 필수)**:
1. **`.ruler/decisions.jsonl` append** — t1-gate.sh 가 강제 (edit 직후 1줄). 포맷:
   ```json
   {"ts":"2026-04-15T15:02:00+09:00","session":"ruler-batch-20260414T1625","file":".ruler/retrospective-guide.md","action":"edit","reason":"§0.5~0.7 shared chain loop","prev":null,"supersedes":null,"tier":"T1"}
   ```
   - `prev` = 같은 파일에 대한 **직전 decisions.jsonl entry id** (grep 결과 tail 1). 첫 편집이면 null.
   - `supersedes` = 직전 결정이 이번에 뒤집히면 id 명시 (rollback 아님, 의도 변경).
   - `t1-gate.sh` 의 prev/supersedes 필드 지원은 **별 task 플래그** (본 세션 범위 밖). 그 전까지는 **session 이 직접 append 시 수기 포함**.
2. **`~/.claude/.ruler/log/YYYY-MM-DD.md` batch 블록 append** — Phase C self-terminate 직전 1회. 포맷:
   ```
   ## [ruler-batch-{ts}] {요약 한 줄}
   - edited: <파일 경로 목록>
   - decisions: <decisions.jsonl entry ts 목록 또는 hash>
   - reason: <1-2줄>
   - test-case: <해당되면>
   ```
   patrol 사이클 블록과 시간순 섞여도 OK. 헤더 `[ruler-batch-*]` prefix 로 구분.
3. **(선택) 타겟 파일 frontmatter `last-edit` 포인터** — `.ruler/*.md` 류 ruler 전역 문서 수정 시:
   ```yaml
   last-edit: 20260415-1502  # decisions.jsonl ts 또는 hash
   last-edit-by: ruler-batch-20260414T1625
   ```
   편집자가 파일 상단만 봐도 직전 수정 맥락 1 step 진입. git diff 오염 감수. 코드 파일 (`.js`, `.sh`) 에는 적용 안 함 (inline `BUG-*` 주석이 대체).

### §0.6 편집 전 Read 의무 (gate)

**모든 ruler 전역 파일 편집 전**:
```bash
grep '"file":"<target>"' ~/.claude/.ruler/decisions.jsonl | tail -5
```
최근 5건 결정 맥락 확인 필수. 상충 entry 발견 시:
- **consistent** (같은 방향 연쇄): 정상 진행, append 시 `prev` = 최신 id
- **conflict** (방향 반대): append 시 `supersedes` = 상충 id + reason 명시
- **rollback** 의심: 진행 중단, decisions.jsonl 에 `rollback_suspicion` entry 만 append 후 self-terminate. patrol 다음 사이클이 handoff.

**코드 파일 (button 레포)**: gate 는 `inline BUG-* 주석 grep` 으로 대체 (decisions.jsonl 은 ruler 전역만). 편집 전 해당 함수/근처 100 라인 Read 필수.

### §0.7 Drift Prevention (세션 시작 pwd 검증)

**배경**: 이 SSOT 작성 이전에 `ruler-batch-20260414T1625` 세션이 `D:\projects\button` 에 박혀 12h+ IDLE + 스코프 벗어난 button 레포 디버깅 수행. 근본 원인 = `spawn-session.sh` 가 `ruler` 만 cwd=~/.claude 고정하고 `ruler-batch-*` 패턴은 누락 (2026-04-15 수정됨).

**방어선 3겹**:
1. **spawn-session.sh 패턴 매칭**: `case "$SESSION" in ruler|ruler-batch-*) PROJECT_DIR="/c/Users/jsh86/.claude" ;; esac` (1차 방어, 2026-04-15 적용 — 이후 스폰부터 유효).
2. **세션 시작 pwd 자가 검증**: 첫 Bash tool 호출 시 `pwd` 확인. `/d/projects/*` 또는 `/c/msys64/home/*` 이면 **즉시** `cd ~/.claude` + decisions.jsonl `drift_detected` entry 1줄 append. 사용자 통보 후 본 작업 착수.
3. **전역 CLAUDE.md `.home-cwd-warning` 패턴 참조**: `~/.claude/CLAUDE.md` §Workflow Principles 의 `SessionStart hook → $HOME/.claude/.home-cwd-warning touch` 패턴과 동일 철학. ruler 계열은 `.home-cwd-warning` 대신 **spawn 시점 고정** 으로 대체 (1차 방어가 더 단단).

**plan/progress/harness/execution-log 작성 시 경계**:
- batch 세션은 `~/.claude/.ruler/batch-plans/{ts}-{slug}/plan.md + progress.md` 에만 작성
- patrol 의 `D:\projects\ruler\plan.md + progress.md` (repo 루트) **건드리지 않음** (주제 다름)
- button 레포 `plan.md + progress.md` **건드리지 않음** (batch 범위 밖)

---

## 원칙

사람 주간 리뷰는 **책임전가**. 사용자 개입 0. AI 가 스스로 과거 수정 이력을 분석하고 규칙으로 승격한다.

## 발동 조건 (OR)

**자동 경로** (patrol 감지):
- 마지막 retrospective 로부터 7일 경과 (`.ruler/retrospective/last_ts` 추적)
- `rollback_budget_warn: true` 트리거
- `force_opus_fallback: true` 트리거
- batch 세션 Step 0 review 에서 같은 파일 3회+ 수정 이력 감지

**수동 경로** (메인 세션 `주간리뷰` / `룰러 리뷰` / `retrospective` 키워드):
- 메인 세션이 직접 `ruler-batch-{ts}` 스폰. patrol 개입 없음.

**실행 주체**: 양 경로 모두 `ruler-batch-{ts}` (Opus).

## 수동 트리거 프로토콜 (메인 세션 → batch 직접 스폰)

```bash
# 1) ts 생성
TS=$(date +%Y%m%dT%H%M%S)

# 2) 소스 수집
bash ~/.claude/.ruler/scripts/retrospective-collect.sh \
  --window 7d \
  --out /tmp/retro-${TS}.json

# 3) plan 파일 작성 (retrospective input 경로 포함)
PLAN_FILE="/c/Users/jsh86/.claude/.ruler/batch-plans/${TS}_retrospective.md"
cat > "$PLAN_FILE" <<EOF
---
type: t2-batch-plan
mode: retrospective
input: /tmp/retro-${TS}.json
created: $(date -Iseconds)
---
# Retrospective ${TS}

Input=\`/tmp/retro-${TS}.json\`. Phase A→B→C per retrospective-guide.md §3-phase. Self-terminate after Phase C per §0.
EOF

# 4) batch 세션 스폰 — spawn-batch-session.sh 헬퍼 (opus/cwd/Enter 자동 처리)
bash ~/.claude/.ruler/scripts/spawn-batch-session.sh "$PLAN_FILE"
```

## 소스 카탈로그 (수집 대상 전수)

| 소스 | 경로 | 역할 | 수집 방법 |
|---|---|---|---|
| 결정 로그 | `.ruler/decisions.jsonl` | 모든 Edit 메타 | `tail -N` + jq filter |
| 일일 로그 | `.ruler/log/{date}.md` | 사람 읽기용 diff inline | `find -mtime -7` |
| 롤백 백업 | `.ruler/rollback/*.bak` | Edit 이전 원본 | `ls -t` + diff 대조 |
| pending 활성 | `.ruler/pending/*.md` | 현재 미해결 제안 | 전수 Read |
| pending resolved | `.ruler/pending/resolved/*.md` | 적용 완료 기록 | 전수 Read |
| pending dropped | `.ruler/pending/dropped/*.md` | stale 폐기 | 전수 Read |
| batch plan 이력 | `.ruler/batch-plans/done/*.md` | 과거 batch 실행 결과 | 전수 Read |
| 회귀 이력 | `.ruler/log/{date}.md` 내 `regression_*` | 회귀 실패 이력 | grep |
| 사용자 지시 이력 | `.ruler/state.md` "Idle Transition" + archive | 사용자 결정 맥락 | Read |
| 외부 상태 (비서 5지표) | `~/.claude/audit-log/{date}.jsonl` + `.error-solutions.json` + hook-metrics.jsonl | ERROR/WARN/SONNET/ESCALATION/solution_cache + 위험 키워드 | `tail -200` + jq |

**수집기**: `bash ~/.claude/.ruler/scripts/retrospective-collect.sh --window 7d --out /tmp/retrospective-input-{ts}.json`
- 출력: 10개 소스를 단일 JSON 으로 정규화 (entries[] 배열)
- Opus 는 이 JSON 하나만 읽으면 됨 (전역 Read 폭발 방지)

## Phase A — T1/T2 Change-Impact Verdict [Primary]

> **목적**: 각 T1/T2 수정이 실제로 에러를 줄였는지 / 재수정·회귀를 유발했는지 **인과 판정**. 단순 빈도 관찰 (구 R1~R11) 은 §부록 으로 이동 — Phase A Verdict 의 **보조 재료** 로 재배치.

### 입력

- `decisions.jsonl` 7일치 **T1** entry (스키마: `ts/check/tier/file/outcome/phase`). T2 는 T-point 미사용 — pending batch 처리는 change event 가 아니며, 동일 (file,check) T2 다수 시 pre/post window 중복 계산됨.
- Δ 관찰 소스 (T 시점 전후 각 **3.5일** window, T-file 단위 분리):
  - `decisions.jsonl` 동일 `check` + 동일 `file` 재발동 건수
  - `retroactive_rollback` / `outcome:"rolled_back"` 발생
  - `~/.claude/audit-log/{date}.jsonl` hook 실행 실패 / guard 차단 빈도
  - `D:/projects/button/agent/.secretary/.secretary-state.json` + escalation 카운터

### 처리 (per T1 entry)

1. T 시점 식별 (`ts` 필드)
2. Pre-Δ (T-3.5d ~ T) 지표 snapshot
3. Post-Δ (T ~ T+3.5d) 지표 snapshot
4. 지표별 변화율 + 방향 판정

### Verdict 스키마 (4등급)

| Verdict | 기준 |
|---|---|
| **GOOD** | Post-Δ 에러/rollback ↓ 20%+ AND 신규 에러 0건 |
| **NEUTRAL** | 변화 ±10% 이내 OR window 부족 (<3일) |
| **BAD** | Post-Δ 에러/rollback ↑ 20%+ OR 같은 target 재수정 OR `retroactive_rollback` 발생 |
| **INSUFFICIENT** | Pre-T window 내 해당 `check×file` 이벤트 **N < 10** (Poisson CI 하한 대신 단순 임계) OR Post window <3일 OR pre/post 3.5d 간격 미달 |

**보조 판정 (BAD 확증)**: BAD 판정 직후 §부록 R1~R11 패턴 중 해당 `file/check` 매칭 건수가 pre window 대비 +50% 이상이면 BAD 확정 + `Δ summary` 칼럼에 **"R# pattern X hits"** 1줄 표기. 매칭 없으면 보조 표기 생략.

**`original_absent:true` 예외**: Phase B Step 2 backfill 로 `original_absent:true` 가 붙은 entry 는 pre/post Δ 계산 불가 → **INSUFFICIENT 강제** (기록 누락 = 판정 누락 악순환 차단).

### 출력 — `.ruler/retrospective/{YYYY-MM-DD}_change-impact.md`

```markdown
> ⚠️ OBSERVATION-ONLY MODE (until 2026-05-16)

| T                    | file            | tier | action              | verdict | Δ summary                     |
|----------------------|-----------------|------|---------------------|---------|-------------------------------|
| 2026-04-18 01:21 KST | secretary.js    | T1   | WORKING_RE 재설계   | GOOD    | guard FP -70%, escalation -45%|
| 2026-04-16 22:56 KST | t1-gate.sh      | T1   | delete 용도 오용    | BAD     | 같은 체크 3회 재발동 · R3 pattern 5 hits |
```

### BAD 판정 후속 (observation 해제 이후)

- `.ruler/pending/revert-{ts}-{file}.md` 생성 — revert 또는 재검토 handoff
- 다음 사이클 patrol 이 pending 처리 → Phase C (audit-wf 조건부) 큐잉 후보

### Observation-Only 모드 (2026-04-18 ~ 2026-05-16, 4주)

`.ruler/state.md` 의 `change_impact_enforcement_start: 2026-05-16` 필드가 **현재 date 이후** 인 동안:
- verdict 산출 + md 기록 ✅
- preflight 승격 ❌
- `pending/revert-*.md` 생성 ❌
- handoff 트리거 ❌
- 출력 md 상단 배너: `> ⚠️ OBSERVATION-ONLY MODE (until 2026-05-16)`

**해제 조건**: 2026-05-16 retrospective 에서 verdict 분포 검토 → INSUFFICIENT < 50% 시 state.md 필드 제거(=활성화). 이상이면 +2주 연장.

### 구현 위치

`.ruler/scripts/retrospective-collect.sh` 내 `compute_change_impact()` bash 함수 — `decisions.jsonl` + `audit-log/{date}.jsonl` 파싱 + jq/awk verdict 계산 + md 표 렌더링. (§progress.md Step 3)

---

## Phase B — §0.5 Compliance Audit + Patrol Sync [Secondary]

> **목적**: §0.5 3단 기록 누락 감지 + patrol.md / event-rules.yaml / rules/*.md 의미 드리프트 동기화. "최근 7일 §0.5 누락 감사" 의 **단일 소유자** (Phase C audit-wf Phase Final-B 가 이 경계를 위임 명시).

### Step 1 — 누락 감사

```bash
# 1) 지난 7일 실제 변경 파일 (source of truth: mtime, 경로 정규화)
find ~/.claude/rules ~/.claude/skills ~/.claude/docs ~/.claude/.ruler \
     D:/projects/button/agent/secretary.js \
     D:/projects/button/agent/secretary/*.js \
     -type f -mtime -7 \
  | xargs -I{} realpath "{}" 2>/dev/null \
  | sort -u > /tmp/retro-actual.txt

# 2) decisions.jsonl 기록 file 목록 (경로 정규화)
jq -r 'select(.ts > "2026-04-11") | .file // (.files[]? // empty)' \
     ~/.claude/.ruler/decisions.jsonl \
  | xargs -I{} realpath "{}" 2>/dev/null \
  | sort -u > /tmp/retro-recorded.txt

# 3) 차집합 + git log 교차검증 (NTFS mtime 오탐 방어)
comm -23 /tmp/retro-actual.txt /tmp/retro-recorded.txt \
  | while read f; do
      # button repo 는 git log --since, .claude 는 mtime 신뢰
      if [[ "$f" == /d/projects/button/* ]]; then
        git -C D:/projects/button log --since=7.days --name-only --pretty=format: -- "$f" 2>/dev/null | grep -q . && echo "$f"
      else
        echo "$f"
      fi
    done > /tmp/retro-missing.txt
```

- **.gitignore/git ls-files 필터**: secretary.js 번들링 같은 build artifact 는 누락 후보에서 제외
- **Symlink 정규화**: `~/.claude/.ruler/` ↔ `D:/projects/ruler/.ruler/` 경로 mismatch 는 realpath 로 통일

### Step 2 — 누락 건별 backfill

각 누락 파일마다:
- `mtime` + `git log -p` (button) 으로 변경 시점/행위자/사유 추정
- `decisions.jsonl` append — 필수 필드: `reason:"retrospective backfill"`, **`original_absent:true`**, tier 추정 (`T1`/`T2`/`unknown`), `meta: {inferred_from: "mtime|git_log"}`
- `log/{date}.md` "누락 복구" 섹션 append

**Phase A 재평가**: `original_absent:true` entry 는 위 Verdict 스키마에서 **INSUFFICIENT 강제** (pre/post Δ 계산 불가).

### Step 3 — Patrol 규칙 동기화 (필수 체크리스트)

Step 2 backfill 직후 진입. 산문형 "수행 권장" 을 **체크리스트** 로 승격해 skip 시에도 기록이 남도록 강제한다. Python/bash 중 편한 도구로 수행하되 **매 항목의 결과는 반드시 decisions.jsonl 에 흔적을 남긴다** (도구 중립, 기록 의무는 고정).

- [ ] `missing_files` 중 `patrol*` / `event-rules*` / `rules/*.md` 패턴 매칭 건 필터
- [ ] 매칭 0건이면 decisions.jsonl 에 `{phase_b_step3:"skipped", reason:"no_patrol_related_missing"}` append **후 skip 강제** (기록 없이 생략 금지)
- [ ] 각 매칭 건에 대해 LLM 의미 비교 질의 (프롬프트/응답 해시를 `meta:{prompt_hash, response_hash}` 에 기록)
- [ ] 판정별 산출: **T1 즉시** → patrol Edit + 별도 decisions.jsonl entry / **T2** → `pending/patrol-sync-{id}.md` 생성 / **clean** → 무처리
- [ ] 실행 요약을 decisions.jsonl 에 `{phase_b_step3:"done", t1:N, t2:M, clean:K}` 1줄 append (실행 요약 append 의무)

### 출력 — `.ruler/retrospective/{YYYY-MM-DD}_compliance.md`

```markdown
## 누락 감사
- 실제 변경: N건
- decisions.jsonl 기록: M건
- 누락: K건 → backfill + patrol sync 수행
  - original_absent:true → Phase A INSUFFICIENT K건

## Patrol Drift (누락 건 대상, patrol*/event-rules*/rules/*.md 만)
- T1 즉시 갱신: N건 ({파일:라인})
- T2 pending: M건
- clean: K건
```

---

## Phase C — 심층 감사 연계 (audit-wf 조건부) [기존 Phase B 승격]

> **경계**: Phase B 가 "최근 7일 §0.5 누락" 단일 소유자 — Phase C 는 그 범위 밖 (장기 drift, 파일 리스트 추적, 인덱스 정합성, rollback 품질 저하) 만 다룬다. `~/.claude/skills/audit-wf/skill.md` Phase Final-B 가 이 경계를 명시적으로 위임한다 (progress.md Step 6).

### 진입 조건 (결정론적, OR)

| # | 조건 | 측정 | 성격 |
|---|---|---|---|
| B1 | `promotion-log.md` 증분 ≥ **10**건 | state.md `promotion_log_last_count` 비교 | 일상 |
| B2 | 마지막 audit-wf 실행 ≥ 7일 | state.md `last_audit_wf_ts` | 정기 |
| B3 | SSOT 전파 이벤트: `rules/*.md` 수정 **2건+** OR `skills/*/skill.md` 신규 | Edit 목록 + `find skills -mtime -N` | 전파 |
| B4 | `decisions.jsonl` rollback 비율 ≥ **10%** (최근 50건) | grep count / 50 | 품질 |
| B5 | `preflight-rules.md` 규칙 추가 ≥ 1건 (observation 해제 이후) | Phase A append 여부 | 희귀 |
| B6 | `MEMORY.md` 인덱스 영역 증분 ≥ 10 (ckpt 제외) | state.md `memory_index_last_count` 비교 | 인덱스 정합성 |

하나라도 true → Phase C 진입. 모두 false → skip (Phase Final 은 무조건 진행).

**경량 분기 — Rules Propagation Subroutine**: `rules/*.md` 1건 단독 수정 (B3 full 미달) → full audit 대신 **포인터 레지스트리 전수 grep** 만 수행. 평균 10초.

### 실행 순서

1. `Read ~/.claude/docs/verification/audit-promotion.md` → Phase 0.5 + 1~3M (B1 발동 시)
2. `Read ~/.claude/docs/verification/audit-system.md` → Phase 3C + 5 + 6 (B2/B3)
3. **B6 분기**: MEMORY.md 인덱스 ↔ `memory/**/*.md` 양방향 grep → 단절 항목 보강
4. **B4 분기**: rollback 50건 분석 → rules/skill 품질 저하 원인 매핑
5. **B5 분기**: 신규 preflight 규칙이 기존 워크플로우 충돌 dry-run
6. 발견 이슈 즉시 자율 수정/승격 — 사용자 결정 프롬프트 금지

### Phase C skip 시

decisions.jsonl `phase_c:false, skip_reason:"B1=N B2=N ..."`. **Phase Final 은 생략하지 않음**.

### Batch log 자동 append (무조건 실행, Step 13)

**무조건 실행**: self-terminate 직전 `log/$(date +%Y-%m-%d).md` 에 batch 블록 1회 append. skip 불가. Phase C 가 skip 된 세션도 이 append 는 수행한다 (감사 트레이스 끊김 방지 — 과거 배치 세션 ~80% 가 log/ 미기록이었던 문제 해소).

```bash
echo -e "\n### [ruler-batch-${SESSION}] $(date +%H:%M) — Phase C completed\n- ..." \
  >> "${HOME}/.claude/.ruler/log/$(date +%Y-%m-%d).md"
```

실제 append 시 `- ...` 는 해당 세션의 주요 결정/처리 요약 1-3줄로 대체한다 (예: `- phase_c:false skip_reason:"..."` / `- T2 pending 3건 resolve` / `- preflight rule R{N} 승격`).

---

## Phase Final — Hook SSOT Sync [유지, 무조건]

- `settings.json` hook 섹션 ↔ `~/.claude/docs/operations/hook-guard-review.md` 양방향 diff
- 한쪽 누락 → 다른 쪽 기준 보강
- 설명/Tier 불일치 → **`hook-guard-review.md` 가 SSOT**
- **왜 마지막인가**: Phase A/B/C 수정으로 hook 이 생겨나거나 설명이 바뀔 수 있다. 정지 상태에서 한 번만 맞춘다.
- **무조건 수행**: Phase B/C skip 시에도 생략 불가.

---

## Phase Terminal — state 갱신 + self-terminate [기존 Phase C 이름변경]

### 통합 요약 보고 (review.md 재정의)

출력 형식 (기존 review.md 대체):

```markdown
---
type: retrospective
window: {pre_ts} ~ {post_ts}
generated_by: ruler-batch-{ts}
---

## 이번 주 변경 × 효과 매트릭스 (Phase A)
{change-impact 표 — GOOD/NEUTRAL/BAD/INSUFFICIENT 건수 요약 + 대표 사례 1-2건}

## §0.5 준수 + Patrol Sync (Phase B)
- 누락 감사: {N} 건 backfill (original_absent:true {M}건 → Phase A INSUFFICIENT)
- Patrol Drift: T1 {N} / T2 {M} / clean {K}

## 심층 감사 (Phase C, 조건부 실행)
- 발동 조건: {B1-B6 true/false}
- 실행 결과: {승격 N건, 정리 M건} OR "skipped"

## Hook SSOT 점검 (Phase Final)
- drift: {N건 → hook-guard-review.md 기준 보강}

## 부록 — 빈도 패턴 (R1~R11, Phase A 판정 보조)
{BAD 판정 건에 매칭된 R# 만 1-2줄 요약}
```

- 단일 1~2문단 최종 요약도 decisions.jsonl entry 로 append: `{action:"retrospective_executed", phase_a:{G,N,B,I 건수}, phase_b:{missing,T1,T2,clean 건수}, phase_c:bool, hook_drift:N}`

### state.md 갱신

`last_retrospective_ts`, `last_audit_wf_ts` (Phase C 실행 시), `promotion_log_last_count`, `memory_index_last_count` 갱신.

### obs-only 해제 판정 (2026-05-16 이후 자동, G8)

Observation-only 기간 (`state.md[change_impact_enforcement_start]` 기준) 이 만료 임박/도달했는지 판단하고 enforcement 를 자동 활성화하거나 연장한다. `### 완료 처리 → self-terminate` 직전에 **매 Phase Terminal 마다 수행** (today 가 start 이전이어도 누적 rate 는 계산만 해서 `decisions.jsonl` 에 snapshot 으로 append — 의사결정 발동은 start 도달 시만).

**임계값 근거 (opus)**: 0.5 는 "표본 신뢰 하한". `INSUFFICIENT` 는 change-impact.md 에서 `pre=0 AND audit_err_pre=0` (데이터 부족) 으로 붙는 verdict 이므로, 누적 집계의 절반 이상이 INSUFFICIENT 라는 건 Primary 판정식이 돌아갈 수 있는 T 시점 자체가 모자란다는 뜻. N<10 으로 표본 부족 판정이 절반 이상이면 집계 자체를 신뢰할 수 없으므로 데이터 확보 기간 **+14d 연장**이 안전. 0.5 미만이면 NEUTRAL/GOOD/BAD 가 과반 → verdict 식이 실질 신호를 내고 있으므로 enforcement 활성화로 진행.

**5-step 판정 절차**:

1. **누적 `INSUFFICIENT` 비율 계산**:
   ```bash
   # .ruler/retrospective/*_change-impact.md 에서 verdict 칼럼 등장 빈도 추출 (현재 retrospective 포함)
   cnt_good=$(cat ~/.claude/.ruler/retrospective/*_change-impact.md 2>/dev/null | grep -c '^| GOOD')
   cnt_neutral=$(cat ~/.claude/.ruler/retrospective/*_change-impact.md 2>/dev/null | grep -c '^| NEUTRAL')
   cnt_bad=$(cat ~/.claude/.ruler/retrospective/*_change-impact.md 2>/dev/null | grep -c '^| BAD')
   cnt_insuf=$(cat ~/.claude/.ruler/retrospective/*_change-impact.md 2>/dev/null | grep -c '^| INSUFFICIENT')
   total=$((cnt_good + cnt_neutral + cnt_bad + cnt_insuf))
   # 0 나눗셈 가드: total=0 이면 rate=1.0 로 강제 → 연장 경로로 진입
   [ "$total" -eq 0 ] && rate="1.000" || \
     rate=$(awk -v i="$cnt_insuf" -v t="$total" 'BEGIN{printf "%.3f", i/t}')
   today_ymd=$(date +%Y-%m-%d)
   ```
   `insufficient_rate = cnt_insuf / (cnt_good + cnt_neutral + cnt_bad + cnt_insuf)`.

2. **해제 후보 판정**: `insufficient_rate < 0.5` → 해제 후보 (Step 3 경로). 이상이면 연장 경로 (Step 4).

3. **해제 경로 (Step 2 YES)**: `state.md` 의 `change_impact_enforcement_start:` 필드를 `today_ymd` 로 override 설정 (즉시 enforcement 활성화). 원래 값이 미래 날짜였어도 당겨짐 — "데이터가 신뢰 가능하므로 obs 기간 단축"이 의도. promotion-log KNOWLEDGE append: `"Ruler obs-only 해제, N=${total} insufficient_rate=${rate}, enforcement start → ${today_ymd}"`. `new_start = today_ymd` 로 Step 5 에 넘긴다.

4. **연장 경로 (Step 2 NO, `insufficient_rate >= 0.5`)**: `state.md` 의 `change_impact_enforcement_start:` 를 `(current value) + 14d` 로 재기록 (bash: `date -d "${cur} + 14 days" +%Y-%m-%d`). promotion-log KNOWLEDGE append: `"Ruler obs-only +14d 연장, N=${total} insufficient_rate=${rate}, enforcement start ${cur} → ${new_start}"`. 14d 선택 이유: 2 retrospective cycle (7d × 2) 동안 추가 표본 확보 → 다음 Phase Terminal 에서 재판정. `new_start = cur + 14d` 를 Step 5 에 넘긴다.

5. **`decisions.jsonl` snapshot append (무조건, 해제/연장 어느 경로든 1줄)**:
   ```bash
   decision="released"   # Step 3 경로면 "released", Step 4 경로면 "extended"
   # new_start 는 Step 3 또는 Step 4 에서 세팅된 값
   jq -cn --arg ts "$(date +%Y-%m-%dT%H:%M:%S+09:00)" \
          --arg sess "$PSMUX_SESSION" \
          --arg dec "$decision" \
          --argjson rate "$rate" \
          --arg ns "$new_start" \
     '{ts:$ts, session:$sess, file:".ruler/state.md", action:"obs_only_judgment",
       phase_terminal_obs_decision:$dec, rate:$rate, new_start:$ns,
       tier:"T1", outcome:"applied"}' \
     >> ~/.claude/.ruler/decisions.jsonl
   ```

**Skip 조건**: `state.md` 에 `change_impact_enforcement_start` 필드가 이미 없다 (=obs-only 이미 해제 완료) → Step 1-5 전체 skip + decisions.jsonl `{phase_terminal_obs_decision:"already_released", rate:null, new_start:null}` 1줄만 append.

**사용자 개입 0 원칙**: 판정·기록 모두 batch 세션 Opus 가 자동 수행. 사용자 승인 대기 금지 (§Self-Terminate Protocol 준수).

### 완료 처리 → self-terminate (§0 Self-Terminate Protocol)

- `[ruler-wf-end]` → 순찰 세션 수신
- `.ruler/retrospective/{date}_plan.md` → `retrospective/done/`
- batch 세션 자체 kill (`psmux kill-session -t $PSMUX_SESSION`)

---

## Pre-flight 규칙 등록 [유지]

- `.ruler/preflight-rules.md` 는 patrol.md 와 별도 SSOT — 자동 생성 규칙 전용.
- `t1-gate.sh` 가 Edit 직전 매칭 검사. `forbidden_change` 패턴 등장 → T2 강제 + decisions.jsonl `gate:"preflight_block"`.
- 규칙 TTL 30일. 매칭 0건이면 자동 만료 (`.ruler/preflight-rules.md/archive/`).
- 규칙 충돌 감지: 같은 target 다른 forbidden 2개+ → 다음 batch task 자동 큐잉.
- **Observation-only 기간 (2026-04-18 ~ 2026-05-16)**: Phase A BAD 판정은 preflight 승격하지 않는다 (위 Phase A Observation-Only Mode 참조). R9 (TTL 만료) 자동 archive 는 계속 수행.

---

## 자동화 경로 매핑 (사용자 액션 0 점검표)

- ❌ "사용자 주간 리뷰" → ✅ batch 세션 7일 주기 자동 retrospective
- ❌ "사용자 rollback 판정" → ✅ Phase A Change-Impact Verdict 자동 판정
- ❌ "사용자 force_opus_fallback 수동 해제" → ✅ 30 사이클 0 rollback 자동 clear
- ❌ "사용자 regression ack" → ✅ run-all.sh 자동 rollback + promotion-log ERROR
- ❌ "사용자 모델 전환 지시" → ✅ wake.sh 플래그 감지 자동 헬퍼 호출

---

## §부록 — R1~R11 빈도 패턴 (Phase A Δ 보조 재료)

> **역할 변화**: 구 3-Phase 파이프라인에서 R1~R11 은 "빈도 관찰 → preflight 승격" 로직의 본체였으나, 본 재설계에서 **Phase A Verdict 의 보조 재료** 로 재배치. BAD 판정 신뢰도 강화 + 사문화 방지 + Pre-flight 규칙 TTL 연계.

### R1~R11 판정 기준 (결정론적)

| # | 패턴 | 임계 | 판정 | Phase 연계 |
|---|---|---|---|---|
| R1 | 동일 파일 T1 Edit | window 내 ≥3회 | **재수정 남용** | Phase A BAD 확증 |
| R2 | retroactive_rollback | 1건+ | **Sonnet 오판 확정** | Phase A BAD 직접 트리거 |
| R3 | 같은 체크 재발동 | T1 해결 후 동일 target 4 사이클 내 재출현 | **미완 수정** | Phase A BAD 확증 |
| R4 | pending dropped 빈도 | window 내 ≥5건 stale drop | **pending 수명 초과** | Phase B Step 3 연계 |
| R5 | 회귀 실패 | 1건+ | **인프라 취약** | Phase A BAD 확증 |
| R6 | rollback_rate >5% | 2 window 연속 | **구조적 Sonnet 부적합** | Phase C B4 연계 |
| R7 | same guard-deny | 서로 다른 세션 3회+ | **guard 규칙 자체 결함** | Phase B Step 3 연계 |
| R8 | batch plan partial_failed | 1건+ | **의존성 그래프 결함** | Phase C B3 연계 |
| R9 | preflight 매칭 0건 30일 | TTL 만료 | **규칙 사문화** | Pre-flight TTL 자동 archive |
| R10 | 규칙 충돌 | 같은 target 서로 다른 forbidden 2개+ | **규칙 모순** | Pre-flight 등록 연계 |
| R11 | 비서 미해결률 | ESCALATION / (WARN+SONNET) ≥ 0.5 (7d) | **elif 체인 부족** | Phase A BAD 확증 + Phase C |

### 분석 쿼리 (Phase A `compute_change_impact()` 내부 활용)

```bash
# A. 재수정 패턴 (R1) — 동일 파일이 window 내 N회+ 수정
tail -500 ~/.claude/.ruler/decisions.jsonl \
  | jq -s '[.[] | select(.tier | test("T1|T2_batch_applied"))] | group_by(.file)[] | select(length>=3) | {file: .[0].file, count: length, cycles: [.[].cycle]}'

# B. 원복 이력 (R2)
tail -500 ~/.claude/.ruler/decisions.jsonl \
  | jq -s '[.[] | select(.action=="retroactive_rollback" or .outcome=="rolled_back")]'

# C. 규칙 위반 근접 (R3/R7)
tail -500 ~/.claude/.ruler/decisions.jsonl \
  | jq -s '[.[] | {check, cycle}] | group_by(.check)[] | select(length>=5)'
```

**사용 맥락**: `compute_change_impact()` 함수가 verdict=BAD 인 각 entry 에 대해 A/B/C 쿼리를 `--window 7d` 로 실행 후 매칭 R# 만 `Δ summary` 칼럼에 append. 매칭 없으면 보조 표기 생략 (§Phase A 보조 판정 규칙 준수).
