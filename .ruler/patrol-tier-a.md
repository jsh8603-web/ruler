---
type: ruler-patrol-tier-a
version: 5
date: 2026-04-16
tags: [ruler, patrol, tier-a, checklist]
---

# Tier A — 매 사이클 (3분)

> 본체: [`~/.claude/.ruler/patrol.md`](~/.claude/.ruler/patrol.md)
> candidate 시 event-rules.yaml 해당 블록만 Read — patrol.md 전체 Read 불필요.
> 사이클 보고 양식: [`~/.claude/docs/operations/ruler-operations.md`](~/.claude/docs/operations/ruler-operations.md) §9 — 1줄 기본 + 이상 시 확장 필드

## 이벤트 패트롤 (event-rules.yaml 매칭)

매 사이클 **C-check 순회 전**에 먼저 event-rules.yaml 의 활성 이벤트를 pre-scan 한다. cheap 한 log_event tail / mtime_poll 로 "후보" 를 먼저 거른 뒤, 후보만 판정에 올린다.

### 호출

```bash
export PATH="/c/Program Files/nodejs:$PATH"
"C:/Users/jsh86/AppData/Local/Programs/Python/Python312/python.exe" ~/.claude/.ruler/scripts/event-patrol.py \
    --rules ~/.claude/.ruler/event-rules.yaml \
    --audit-log ~/.claude/audit-log/$(date +%Y-%m-%d).jsonl \
    --window-sec 60
```

- **stdout**: JSON Lines, 각 이벤트 1줄. `status ∈ {candidate, clean, skipped, spec_unparseable, deferred, no_audit_log, io_error}`
- **stderr**: 진단 로그 + 최종 `summary total=N active=A skipped=S candidates=C`
- **exit 0**: 정상 (candidates > 0 여도 exit 0 — 판정은 본체 책임)
- **exit 1**: YAML parse 실패 또는 rules 파일 부재 (치명)

### 후보 처리

| status | 의미 | 본체 동작 |
|---|---|---|
| `candidate` | spec 매칭 가능성 있음 | **event-rules.yaml 해당 이벤트 블록만 Read** → violation_detector.check 수행 |
| `clean` | 스캔 결과 0 hits | skip |
| `skipped` | `enabled:false` or `pending_source_revive` | 무시 |
| `spec_unparseable` | loader 한계 | **본체가 spec 문자열을 LLM 직접 해석** + decisions.jsonl `loader_fallback` 기록 |
| `deferred` | `heavy_scan` 타입 | 별 tier — 본 루프 제외 |
| `no_audit_log` / `io_error` | 인프라 문제 | Urgent pending 생성 |

### 본체 판정 절차 (candidate 받은 이벤트별)

1. **event-rules.yaml 해당 이벤트 블록만 Read** (rule_refs / expected_behavior / check / on_violation 전부 거기 있음)
2. `violation_detector.check` 자연어 spec 수행 (mtime/tail grep/registry 조회 등)
3. `supersede` 조건 평가 → 하나라도 만족이면 state 해소 + skip
4. 위반 확정 시 `on_violation.notify_agent.channel` 에 따라 통보:
   - `sendWithFile`: ruler-notify.sh 경유
   - `log_only`: `.ruler/log/{date}.md` 1줄 + decisions.jsonl 기록
   - `auto_fix`: `flag_stale_detected` 만 v1 허용 (rm+backup)
5. **T1/T2 분류**: [`~/.claude/.ruler/violation-tier-criteria.md`](~/.claude/.ruler/violation-tier-criteria.md) 참조
6. 3단 기록 (decisions.jsonl + log + MEMORY ckpt 필요 시)

### 이벤트 규칙 SSOT

- **위치**: [`~/.claude/.ruler/event-rules.yaml`](~/.claude/.ruler/event-rules.yaml)
- **현재 v6**: 활성 32 + pending 1 (33 이벤트)
- **관리**: ruler-batch 세션만 Edit 가능 (opus_only)

---

## 감지 범위 원칙 (전 C-check 공통)

> ⛔ **pending/ 보호**: pending 파일은 batch 처리 전까지 삭제/이동 금지. 상세 → [`patrol-tier-c.md`](~/.claude/.ruler/patrol-tier-c.md) §pending 보호 규칙
>
> **감지는 ruler 자기 세션 포함, WF 격리는 유지.**
> 모든 C-check 감지 및 event-rules.yaml 판정에서 **ruler 자기 세션을 제외하지 않는다**.
> 단, WF 세션(`worker|verifier|healer|strategic`)은 기존대로 Supervisor 내부 관리 — ruler 감지 대상 아님 (secretary-system.md §3 의도된 격리).
> idle 제외 목록(`C_idle_sweep` L96)은 idle-strike 카운팅 전용.

## C1 — Secretary 회귀 하네스 (mtime 트리거)
- **트리거**: `secretary.js`, `revive.sh`, `generate-session-resume.sh`, `bash-guard.js`, `settings.json` 중 하나 mtime 변경. **변경 없으면 skip** (stat 1회 <1ms).
- **명령**: `export PATH="/c/Program Files/nodejs:$PATH" && bash ~/.claude/docs/verification/secretary-regression/run-all.sh`
- **통과**: `35/35 PASS`
- **실패**: state.md FAIL 기록 + 마지막 Edit auto-rollback + T2 그룹 재검토 + promotion-log ERROR + **Urgent 즉시 escalate**
- **판정 모드**: sonnet-decide (bash 실행+exit code)

## C16 — Secretary heartbeat 감시
- **목적**: secretary.js Node 프로세스 hang/crash 감지
- **대상 (우선순위)**: `.secretary/.secretary-state.json` mtime → `.secretary/.ctx-warn-ts/` 최신 파일 mtime → `.classifier-audit/classifier-{today}.jsonl`
- **임계**: 가장 최근 mtime 5분+ stale → hang 의심
- **추가**: `tasklist | findstr node.exe` → 부재=crashed, 존재하나 stale=hang
- **조치**: crashed/hang 모두 **Urgent pending 즉시 생성**
- **판정 모드**: sonnet-decide (Urgent 시 즉시 Opus escalate)

## C17 — Ruler 세션 모델 정합성
- **목적**: Ruler 순찰 세션이 state.md `sonnet_patrol_mode` 정책과 일치 모델로 도는지 검증, drift 시 자동 전환
- **검사**:
  - (a) Registry entry: `.session-registry.txt` `^ruler\|` 2번째 필드
  - (b) 실제 pane model: `capture-pane -t ruler -p` 에서 `Sonnet 4\.\d\|Opus 4\.\d\|Haiku` 추출
  - (c) state.md 정책: `sonnet_patrol_mode` / `force_opus_fallback`
  - (d) `spawn-session.sh` L113 기본값: `case "$SESSION"` 블록 `ruler.*MODEL="sonnet"`
- **기대값**:
  - `sonnet_patrol_mode=true` AND `force_opus_fallback=false` → 모두 `sonnet`
  - `force_opus_fallback=true` → 모두 `opus`
- **drift 조치**: registry 갱신 T1 / state.md 정책 ↔ pane 불일치 AND `sonnet_switch_pending=true` → `model-switch-and-send.sh` 자동 호출 (self-target 내부 처리) / spawn-session.sh 수정 T2
- **판정 모드**: sonnet-decide

## C_idle_sweep — Watched 세션 idle strike 판정
- **목적**: Watched 세션 전원 non-WORKING 이면 ruler 스스로 idle 로 진입
- **절차**:
  1. `.session-registry.txt` Read
  2. 제외 필터: `^(worker|verifier|healer|strategic|ruler)$` / `ruler-batch-` / `task|schedule|secretary` 접두사 / `btn-button` / `runner=gemini|codex`
  3. 남은 watched 세션 `capture-pane -S -30` 으로 현재 status 확인
  4. WORKING 하나라도 → `.idle-strike` 0 리셋
  5. 전원 non-WORKING → `.idle-strike` +1
  6. `.idle-strike >= 3` 도달: (SSOT: wake.sh idle_strike_threshold=3, 2026-04-16 5→3 복원)
     - `rm -f .active`
     - `echo 0 > .idle-strike`
     - `touch .wake-stop` (wake.sh 자가 중지 sentinel)
     - state.md `idle_strike_count: 0` 갱신
     - `log/{date}.md` 기록
  7. 사이클 요약에 `strike={n}, working={k}/{total}` 포함
- **판정 모드**: sonnet-decide
- **자동수정 티어**: T1

---

## C_wf — WF 실행 중 절차 준수 체크

- **목적**: `.wf-active` 존재 시 해당 WF 타입의 blocker 항목 체크
- **트리거**: 프로젝트 디렉토리에 `.wf-active` 파일 존재
- **절차**:
  1. 레지스트리 세션의 CWD 에서 `.wf-active` 존재 확인 (registry dir 기준 stat, ruler 포함, WF 세션 제외)
  2. 존재 시 `type=` 값 읽기 (harness/coding/lightweight/handoff/planning)
  3. [`~/.claude/.ruler/patrol-wf-checks.md`](~/.claude/.ruler/patrol-wf-checks.md) 해당 §섹션 **blocker 항목만** offset Read
  4. blocker 항목 (COM-1, S-1, W-1, C-7, C-11 등) 에 대해 grep/stat 증거 수집
  5. 위반 발견 시 `ruler-notify.sh violation` 으로 해당 Supervisor 에게 통보
  6. 비-blocker 항목은 **Tier C** 사이클에서 샘플링 (매 사이클 전수 불필요)
- **`.wf-active` 미존재 + `guide.md` 존재**: §6 Handoff 체크 (장수명 릴레이)
- **`.wf-active` 미존재 + `guide.md` 미존재**: skip (2회 stat, <1ms)
- **판정 모드**: sonnet-decide (blocker 시 Urgent)
- **자동수정 티어**: blocker = T1 즉시, 비-blocker = T2

## C_model — 세션 모델 준수 검증 (progress 기반)

- **목적**: 레지스트리 세션(ruler 포함, WF 세션 제외)의 실제 모델과 progress.md 기대 모델 교차 검증
- **절차**:
  1. `.session-registry.txt` Read → 각 세션의 `model` 필드 (secretary 60s 갱신, JSONL ground truth)
  2. 해당 세션 CWD 의 `progress.md` 에서 현재 미체크 step 의 `model:` 값 추출
  3. registry.model ≠ expected → **drift 감지**
  4. 추가 확인: 해당 세션의 audit-log 에 `model-switch-and-send.sh` 호출 기록 존재 여부
     - 기록 없이 모델 변경 = **`.sh` 헬퍼 미경유 위반** (직접 `/model` 사용 의심)
  5. 위반 시 `ruler-notify.sh violation "{session}" "model_drift: expected={X} actual={Y}, helper_used={bool}"`
- **progress.md 미존재 또는 WF 중**: skip (WF 는 Supervisor 가 내부 관리)
- **판정 모드**: sonnet-decide
- **자동수정 티어**: T1 (통보만, 자동 전환은 C17 이 ruler 전용으로 담당)
