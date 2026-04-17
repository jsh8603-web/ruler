---
type: ruler-retrospective-guide
date: 2026-04-15
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
psmux send-keys -t ruler '[ruler-wf-end] batch='$PSMUX_SESSION' rules_applied=N promoted=N' Enter

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

## 검토 기준 R1~R11 (결정론적, Opus 판정 여지 최소화)

| # | 패턴 | 임계 | 판정 | 조치 |
|---|---|---|---|---|
| R1 | 동일 파일 T1 Edit | window 내 ≥3회 | **재수정 남용** | preflight 규칙: "이 파일 T1 경로 금지 → batch-only" |
| R2 | retroactive_rollback | 1건+ | **Sonnet 오판 확정** | 해당 C-check 판정 모드 → batch-only 강등 + preflight |
| R3 | 같은 체크 재발동 | T1 해결 후 동일 target 4 사이클 내 재출현 | **미완 수정** | Opus semantic 재분석 → 근본 원인 수정 큐잉 |
| R4 | pending dropped 빈도 | window 내 ≥5건 stale drop | **pending 수명 초과** | N_stale 하향 or review 사이클 단축 |
| R5 | 회귀 실패 | 1건+ | **인프라 취약** | opus_only_files 확장 + 해당 계열 batch-only |
| R6 | rollback_rate >5% | 2 window 연속 | **구조적 Sonnet 부적합** | force_opus_fallback 자동 발동 |
| R7 | same guard-deny | 서로 다른 세션 3회+ | **guard 규칙 자체 결함** | settings.json deny 룰 retrospective 격상 |
| R8 | batch plan partial_failed | 1건+ | **의존성 그래프 결함** | Step 3 그룹 분해 재검토 |
| R9 | preflight 매칭 0건 30일 | TTL 만료 | **규칙 사문화** | archive 이동 |
| R10 | 규칙 충돌 | 같은 target 서로 다른 forbidden 2개+ | **규칙 모순** | Opus 우선순위 + 하나 retire |
| R11 | 비서 미해결률 | ESCALATION / (WARN+SONNET) ≥ 0.5 (7d) | **elif 체인 부족** | `secretary.js` elif 확장 task + solution_cache 정리 |

모든 판정은 **숫자 임계 기반**. Opus 역할은 (a) 규칙 문구 생성 (b) semantic reason 추론 (c) 규칙 간 의존성 정리.

## 분석 쿼리

```bash
# A. 재수정 패턴 — 동일 파일이 window 내 N회+ 수정
tail -500 ~/.claude/.ruler/decisions.jsonl \
  | jq -s '[.[] | select(.tier | test("T1|T2_batch_applied"))] | group_by(.file)[] | select(length>=3) | {file: .[0].file, count: length, cycles: [.[].cycle]}'

# B. 원복 이력
tail -500 ~/.claude/.ruler/decisions.jsonl \
  | jq -s '[.[] | select(.action=="retroactive_rollback" or .outcome=="rolled_back")]'

# C. 규칙 위반 근접
tail -500 ~/.claude/.ruler/decisions.jsonl \
  | jq -s '[.[] | {check, cycle}] | group_by(.check)[] | select(length>=5)'
```

## AI 판정 출력 — `.ruler/retrospective/{YYYY-MM-DD}_review.md`

```
---
type: retrospective
window: cycles 52-82 (30 사이클)
generated_by: ruler-batch-{ts}
---
## 재수정 패턴 분석
- {file}: N회 수정, 원인={Opus semantic 추론}
  → 교훈: "{이 파일은 이런 방향으로 수정하면 안 됨}"

## 원복 이력
- ...

## 추출 Pre-flight 규칙 (자동 승격)
- rule_id: preflight-{seq}
  target: {파일 경로 pattern}
  forbidden_change: {구체 패턴}
  reason: {근거}
  registered_to: .ruler/preflight-rules.md
```

## Pre-flight 규칙 등록

- `.ruler/preflight-rules.md` 신설. patrol.md 와 별도 SSOT — 자동 생성 규칙 전용.
- `t1-gate.sh` 가 Edit 직전 매칭 검사. `forbidden_change` 패턴 등장 → T2 강제 + decisions.jsonl `gate:"preflight_block"`.
- 규칙 TTL 30일. 매칭 0건이면 자동 만료 (`.ruler/preflight-rules.md/archive/`).
- 규칙 충돌 감지: 같은 target 다른 forbidden 2개+ → 다음 batch task 자동 큐잉.

## 3-Phase 파이프라인

```
(1) 소스 수집                  (2) 계획 (지도)                (3) 실행 (주행)
 retrospective-                retrospective-plan.md          ruler-batch-{ts}
 collect.sh --7d            →  (짧은 지도, 방향성만)        →  (patrol.md 규칙 Edit
 → /tmp/*.json                 ↓                                + preflight-rules.md append
                               batch 세션 스폰                    + decisions.jsonl 기록)
                               (ruler-batch-{ts}, opus)
```

### Phase 1 — 소스 수집
`retrospective-collect.sh` 자동 실행. JSON 산출. 순찰 세션(Sonnet)이 조건 감지 시 트리거만.

### Phase 2 — 계획 파일 생성 (`.ruler/retrospective/{YYYY-MM-DD}_plan.md`)

**포맷 제약 (batch plan 과 동일)**: 코드 snippet 금지. `before/after` / `old_string`/`new_string` 금지. 전역 grep dump 금지.

- ✅ **포함**: (a) 발동 조건 1줄 (b) 수집 소스 summary (건수만) (c) R1~R10 매칭 테이블 (d) **추출 방향성 규칙** (각 1~3줄 자연어) (e) 실행 step 계획
- **예시/방향성 문장** — "이 파일은 A 방향 수정 금지" / "C12 가 재발하니 guard 재검토" 같은 방향성. 구현 구문 금지.
- **사용자 3초 판단 창** — plan 1페이지 요약.

### Phase 3 — Batch 세션 실행

**Phase A (Retrospective)**:
- `spawn-batch-session.sh <plan-file>` (opus 고정)
- 초기 프롬프트: 헬퍼가 plan 파일 경로 자동 주입 (Read 지시 포함)
- batch 세션이 plan 기반 Edit:
  - patrol.md 규칙 섹션 보강 (C-check 판정 모드 변경, opus_only_files 확장)
  - `.ruler/preflight-rules.md` 에 rule_id append
  - TTL 만료 규칙 archive 이동

**Phase B (Audit-WF 연계)** — Phase A 완료 후 같은 batch 세션이 audit-wf 절차 연속 실행.

**Phase B 진입 조건 (결정론적, OR)**:

| # | 조건 | 측정 | 성격 |
|---|---|---|---|
| B1 | `promotion-log.md` 증분 ≥ **10**건 | state.md `promotion_log_last_count` 비교 | 일상 |
| B2 | 마지막 audit-wf 실행 ≥ 7일 | state.md `last_audit_wf_ts` | 정기 |
| B3 | SSOT 전파 이벤트: `rules/*.md` 수정 **2건+** OR `skills/*/skill.md` 신규 | Edit 목록 + `find skills -mtime -N` | 전파 |
| B4 | `decisions.jsonl` rollback 비율 ≥ **10%** (최근 50건) | grep count / 50 | 품질 |
| B5 | `preflight-rules.md` 규칙 추가 ≥ 1건 | Phase A 가 append 여부 | 희귀 |
| B6 | `MEMORY.md` 인덱스 영역 증분 ≥ 10 (ckpt 제외) | state.md `memory_index_last_count` 비교 | 인덱스 정합성 |

하나라도 true → Phase B 진입. 모두 false → skip + batch 종료 (단 Phase Final 은 무조건).

**경량 분기 — Rules Propagation Subroutine**: `rules/*.md` 1건 단독 수정 (B3 full 미달) → full audit 대신 **포인터 레지스트리 전수 grep** 만 수행. 평균 10초, ruler-batch 오버헤드 無.

**Phase B 실행 순서**:
1. `Read ~/.claude/docs/verification/audit-promotion.md` → Phase 0.5 + 1~3M (B1 발동 시)
2. `Read ~/.claude/docs/verification/audit-system.md` → Phase 3C + 5 + 6 (B2/B3)
3. **B6 분기**: MEMORY.md 인덱스 ↔ `memory/**/*.md` 양방향 grep → 단절 항목 보강
4. **B4 분기**: rollback 50건 분석 → rules/skill 품질 저하 원인 매핑
5. **B5 분기**: 신규 preflight 규칙이 기존 워크플로우 충돌 dry-run
6. 발견 이슈 즉시 자율 수정/승격 — 사용자 결정 프롬프트 금지
7. **Phase Final — Hook SSOT sync (무조건, 마지막 단계)**:
   - `settings.json` hook 섹션 ↔ `~/.claude/docs/operations/hook-guard-review.md` 양방향 diff
   - 한쪽 누락 → 다른 쪽 기준 보강
   - 설명/Tier 불일치 → **`hook-guard-review.md` 가 SSOT**
   - **왜 마지막인가**: 중간 단계 수정으로 hook 이 생겨나거나 설명이 바뀐다. 정지 상태에서 한 번만 맞춘다.
8. state.md 갱신: `last_audit_wf_ts`, `promotion_log_last_count`, `memory_index_last_count`

**Phase C — 통합 요약 보고**:
- Phase A + B 결과를 **단일 1~2문단 요약** 으로 출력. 긴 리스트 덤프 금지.
- 포맷: "이번 retrospective: {rule_extracted}건 Pre-flight 추출, {applied}건 적용. 승격 감사: {promoted}건, {stale}건 정리. 훅 점검: {hook_checked}. 남은 이슈: {remaining}"
- decisions.jsonl append: `{action:"retrospective_executed", phase_b:true|false, rules_applied:N, promoted:N, stale_cleaned:N}`

**완료 처리**:
- `[ruler-wf-end]` → 순찰 세션 수신
- `.ruler/retrospective/{date}_plan.md` → `retrospective/done/`
- batch 세션 자체 kill

**Phase B skip 시**: decisions.jsonl `phase_b:false, skip_reason:"B1=N B2=N ..."`. skip 시에도 **Phase Final (Hook SSOT sync) 은 생략하지 않음**.

**원칙 재확인**: 3-phase 는 T2 Batch Resolver 와 같은 pipeline. 차이점 = 트리거가 "시간/비율 임계"(Retrospective) vs "pending 누적"(Batch). 실행 인프라 공유.

## 자동화 경로 매핑 (사용자 액션 0 점검표)

- ❌ "사용자 주간 리뷰" → ✅ batch 세션 7일 주기 자동 retrospective
- ❌ "사용자 rollback 판정" → ✅ Step 0 semantic re-verify 자동 rollback
- ❌ "사용자 force_opus_fallback 수동 해제" → ✅ 30 사이클 0 rollback 자동 clear
- ❌ "사용자 regression ack" → ✅ run-all.sh 자동 rollback + promotion-log ERROR
- ❌ "사용자 모델 전환 지시" → ✅ wake.sh 플래그 감지 자동 헬퍼 호출
