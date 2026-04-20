---
tags:
  - type/skill
  - domain/system
  - load/trigger
  - scope/global
name: ruler-wf
description: |
  규칙/문서/비서코드 자체의 정합성을 감시하는 메타 레이어 세션.
  Supervisor/Worker/Secretary 위에 위치. 장수명 세션(며칠~몇 주) 전제로 4-layer 컨텍스트 유지.
  Self-Wake 3분 루프. 2-Tier + 이벤트 기반 순찰 (Tier A 3분 매 사이클, Tier C 30분 10사이클마다). 리스크 없는 수정 자율 적용.
  트리거: "ruler 스폰", "ruler 띄워", "ruler wf", "메타 감시 세션"
  사용자 명시 요청 시에만 harness/lightweight-wf 가 스폰. WF 종료 시 정리하지 않는다.
date: 2026-04-18
---

# Ruler WF — 규칙·문서·비서코드 메타 감시 레이어

(root: 사용자 `ruler 스폰` / `ruler 띄워` / `ruler wf` / `메타 감시 세션` 요청)

## §1. 정체성

| 레이어 | 감시 대상 | 주기 | 자동 개입 |
|---|---|---|---|
| **Secretary** (Node 15s) | psmux 세션 런타임 상태 (에러/멈춤/압축) | 15s | 런타임 넛지·리줌 주입 |
| **Supervisor** (WF 메인) | 현재 WF 작업물 품질 | 이벤트 | 코드/문서 직접 수정 |
| **Ruler (이 스킬)** | **규칙·인덱스·비서코드 자체의 드리프트/자가모순** | **3분 Self-Wake** | **리스크 없는 건 자동 패치** |

**핵심 원칙**: Ruler 는 "작업" 을 안 한다. 작업을 감시하는 인프라(rules, secretary, hooks, indexes) 가 드리프트 없이 유지되도록 **메타** 역할만 수행한다.

- **모델**: 순찰=**Sonnet** 기본 (1차 반응, 저비용 감지). batch 세션(`ruler-batch-*`)=**Opus** (2차 Supervisor, 의존성 묶음 review). rollback>15% 시 `force_opus_fallback` 자동 전환. 상세 §5a / [`model-separation.md`](~/.claude/.ruler/model-separation.md)
- **cwd**: `C:\Users\jsh86\.claude`
- **세션명**: `ruler` (단수, 전역 1개)
- **상태 파일**: `~/.claude/.ruler/state.md`, `~/.claude/.ruler/patrol.md`, `~/.claude/.ruler/log/{date}.md`, `~/.claude/.ruler/pending/`, `~/.claude/.ruler/rollback/`

## §2. 스폰 트리거 (harness-wf / lightweight-wf / 사용자)

Ruler 는 **사용자 명시 요청 시에만** 스폰된다. WF skill 은 이를 자동으로 띄우지 않는다.

> **⚡ 최초 스폰 / 재진입 / 압축 후 첫 턴**: 반드시 [`~/.claude/docs/operations/ruler-operations.md`](~/.claude/docs/operations/ruler-operations.md) 를 Read 하여 운영 SSOT (wake / Gate / Batch / Retrospective / 14체크 요약) 를 로드한다.

### 재진입 프로토콜 (⚠️ kill 금지)

```bash
PSMUX="/c/Users/jsh86/AppData/Local/Microsoft/WinGet/Packages/marlocarlo.psmux_Microsoft.Winget.Source_8wekyb3d8bbwe/psmux.exe"

if "$PSMUX" has-session -t ruler 2>/dev/null; then
  # 존재 → 메시지 주입만 (kill 금지)
  "$PSMUX" capture-pane -p -t ruler | tail -3
  # ⚠️ TS prefix 필수 — Ruler 가 3분 자는 사이 reentry + wf-end 연속 주입 시 처리 순서 보장.
  # Ruler 깨어남 시 [YYYY-MM-DDTHH:MM:SS.mmmZ] 로 정렬 후 시간순 처리.
  # 근거: .ruler/pending/20260411T2015_msg-ordering-guarantee.md
  TS=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
  CONTEXT="[${TS}][ruler-reentry] 신규 WF 컨텍스트 추가:
  - trigger: ${WF_TYPE}
  - cwd: ${WF_CWD}
  - session: ${WF_SESSION}
  - started: ${TS}
  - plan: ${PLAN_PATH:-N/A}
  → ~/.claude/.ruler/state.md 'Active WF Contexts' 에 추가. 다음 사이클부터 순찰 범위 포함."
  source "$HOME/.claude/scripts/lib/psmux-send.sh"
  psmux_send_message ruler "$CONTEXT"
else
  # 최초 스폰
  bash /d/projects/button/agent/.secretary/.scripts/spawn-session.sh ruler
fi
```

### 메시지 순서 보장 (송신 측 규칙)

모든 `[ruler-reentry]` / `[ruler-wf-end]` 주입 메시지는 **반드시 `[YYYY-MM-DDTHH:MM:SS.mmmZ]` 프리픽스** 를 포함해야 한다 (ISO-8601 millisecond UTC). Ruler 가 3분 자는 사이 두 메시지가 연속 도착해도 수신 측이 TS 로 정렬해 시간순 처리하므로 순서 역전이 방지된다. 송신 측 구현 지점:

- `~/.claude/skills/lightweight-wf/skill.md` §② reentry + §⑤ step 8-1 wf-end
- `~/.claude/skills/harness-wf/supervisor.md` §② reentry + §⑤ step 6-1 wf-end
- 이 파일 (ruler-wf §2) 재진입 블록

수신 측 정렬 처리는 `~/.claude/.ruler/patrol.md` 사이클 진입 절차 참조.

⛔ **절대 금지**: `kill-session -t ruler`, 존재 시 `new-session -s ruler`. 세션 종료는 오직 사용자 명시 `ruler stop` + `.wake-stop` sentinel.

### psmux 슬래시 명령 전송 (필독)

Ruler 가 자기 역할 수행 중 다른 세션이나 자기 자신에게 슬래시 명령(`/remote-control`, `/compact`, `/clear`)을 psmux 로 보낼 때는 **반드시 `MSYS_NO_PATHCONV=1` 프리픽스**를 붙인다. 없으면 MSYS2 가 앞 `/` 를 Git 설치 루트로 변환하여 일반 텍스트로 들어간다.

```bash
source "$HOME/.claude/scripts/lib/psmux-send.sh"
MSYS_NO_PATHCONV=1 psmux_send_slash {세션} '/remote-control'
```

상세: [`~/.claude/skills/psmux-session/skill.md`](~/.claude/skills/psmux-session/skill.md) §슬래시 명령 전송 + promotion-log K73.

## §3. 4-layer 컨텍스트 유지

### Layer A. Secretary 레지스트리 등록
- `spawn-session.sh ruler` 가 `.session-registry.txt` 에 `ruler|sonnet|C:\Users\jsh86\.claude|{created}|` 등록 (2026-04-14 Phase 1: 순찰=Sonnet 기본. batch 세션 `ruler-batch-*` 만 opus)
- `secretary-system.md §3a` 의 harness-exclude regex (`^(worker|verifier|healer|strategic)$`) 에 **ruler 포함 안 함** → SessionStart(source=compact|resume) 리줌 주입 대상

### Layer B. 영속 상태 `~/.claude/.ruler/state.md`
매 사이클 말미에 Ruler 가 덮어쓰기. 섹션: cycle 번호, updated, last_secretary_edit, last_regression_pass, last_settings_edit, Active WF Contexts, Open Issues, 이번 사이클 결과 요약, Rollback Monitoring.

### Layer C. 일일 로그 `~/.claude/.ruler/log/{YYYY-MM-DD}.md`
append-only. 1 사이클 = 1~5줄. diff 원문 포함. 사람 리뷰용.

### Layer D. 순찰 매니페스트 `~/.claude/.ruler/patrol.md`
2-Tier + 이벤트 기반 체크리스트 SSOT (v3). Tier A (이벤트 패트롤 + C1/C16/C17/C_idle) 매 사이클, Tier C (C3~C15 + C18-lite) 10사이클마다. 매 사이클 Read. Ruler 의 patrol.md 자기수정은 T2 이상 (T1 금지).

## §4. Self-Wake 3분 루프 (active / idle 2-mode)

`~/.claude/.ruler/wake.sh` 가 백그라운드로 구동. spawn-session.sh ruler 이 자동 시작.

- **INTERVAL**: 30s short-poll → 실제 순찰은 180s (3분) 주기 (`.last-patrol-ts` 기반)
- **EXIT_PATTERN**: `has-session -t ruler` 부재 시 루프 종료
- **중복 구동 방지**: `.wake-ts` 6분 이내면 재구동 skip
- **Sentinel 종료**: `.wake-stop` 파일 생성 시 graceful exit
- **메시지**: Tier A/C 체크리스트 인라인 + patrol.md/state.md Read 지시 **2중 안전** (인라인 + manifest)

### active / idle state machine — 2026-04-14 재설계

**SSOT** = [`~/.claude/.ruler/patrol.md`](~/.claude/.ruler/patrol.md) §active/idle 상태 관리. 아래는 요약.

| 상태 | `.active` 플래그 | wake.sh 행동 | 진입 신호 |
|---|---|---|---|
| **idle** | 없음 | 30s 마다 생존 + `.messages/wake-*.txt` 폴링. 순찰 없음 | — |
| **active** | 존재 | 30s 마다 `.last-patrol-ts` 확인 후 180s+ 경과 시 2-Tier 순찰 발동 (Tier A 매 사이클 + Tier C 10사이클마다) | 비서 edge 감지 → `.messages/wake-*.txt` drop → wake.sh consume |

**전환 절차**:
- **idle → active**: `secretary.js` runCycle 이 watched psmux 세션의 `WAITING→WORKING` edge 감지 → `~/.claude/.ruler/.messages/wake-{session}-{ts}.txt` drop → wake.sh 30s poll 이 consume → `.active` touch + `.idle-strike 0`
- **active → idle**: patrol 사이클의 `C_idle_sweep` 이 watched 세션 전원 non-WORKING 을 3회 연속 감지 → `.idle-strike >= 3` → `rm .active` → 다음 poll 부터 순찰 중단 (루프 생존)

**idle 제외 세션** (C_idle_sweep 전용): `worker|verifier|healer|strategic` (harness WF), `ruler` 본인, `ruler-batch-*`, `task|schedule|secretary` 접두사, `btn-button` (대화형 세션, idle 판정 방해), `runner=gemini|codex`. 제외 관리 스킬: [`~/.claude/skills/idle-exclude/skill.md`](~/.claude/skills/idle-exclude/skill.md)

**감지 범위 원칙**: idle 제외 목록은 `C_idle_sweep` idle-strike 카운팅에만 적용. 그 외 모든 C-check 감지 및 event-rules.yaml 판정은 **ruler 자기 세션 포함** 대상. 단 WF 세션(`worker|verifier|healer|strategic`)은 Supervisor 내부 관리로 기존대로 제외 유지 (secretary-system.md §3).

**설계 근거**: 2026-04-14 Sonnet 전환 완료로 비용 제약 해소 → wf-start on-demand touch 에서 "web app project 실행 단위 + 전원 idle 3회 연속 시 해제" 로 확장. 비서가 세션 상태 전이 edge 를 단방향 신호로 주고, ruler 는 신호 + 자체 idle-sweep 으로 상태 머신을 구동한다. wf 라이프사이클 훅 의존 제거.

## §5. 2-Tier + 이벤트 체크리스트 (patrol.md v3 SSOT)

> 상세 트리거/명령/티어는 `~/.claude/.ruler/patrol.md` 참조. 여기서는 요약만.

**Tier A — 3분 (매 사이클, <5초)**

| # | 항목 | 트리거 | 티어 |
|---|---|---|---|
| 이벤트 | event-rules.yaml pre-scan (33 이벤트, v6) | 매 사이클 | T1/T2 |
| C1 | Secretary 회귀 하네스 | 파일 mtime 변화 시 | 관찰 |
| C16 | Secretary heartbeat 감시 | 매 사이클 | Urgent |
| C17 | Ruler 모델 정합성 | 매 사이클 | T1/T2 |
| C_idle | Watched 세션 idle strike | 매 사이클 | T1 |

**Tier C — 30분 (10사이클마다, ~30초)**

| # | 항목 | 티어 |
|---|---|---|
| C3 | Symmetric fix propagation | T2 |
| C5 | Dead reference 감지 | T1/T2 |
| C6 | Index 동기화 감사 | T2 |
| C7 | Session-note read-only | T1 |
| C8 | Frontmatter 검증 | T2 |
| C9 | promotion-log 4필드 | T2 |
| C10 | Hook/Guard SSOT 역검증 | T2 |
| C11 | Trigger 키워드 일관성 | T2 |
| C12 | Deny log 스캔 (guard_deny 이관 pending) | T1/T2 |
| C13 | settings.json backup 검증 | T1 |
| C14 | plan/progress 완료 아카이브 | T1/T2 |
| C15 | Classifier Self-Learning | batch-only |
| C18-lite | Hook 인프라 발동 4항목 | T1/T2 |

**이벤트 이관 완료**: C2 (Home cwd) → `home_cwd_pollution_detected`, C4 (Flag stale) → `flag_stale_detected`. C12 (Deny log) → `guard_deny_burst` pending.

**event-rules.yaml v6 요약** (33개 이벤트, 32 active + 1 pending):
- [v1] #1-4: memory_ckpt, home_cwd, wf_session_reg, flag_stale
- [Batch1] #6-9: ctx_warn, registry_sync, audit_log_gap, presence
- [Batch2] #10-13: escalation_fp, model_drift, resume, stuck_fp
- [Batch3] #14-19: ckpt_format, commit_format, routing_context, precompact, progress_missing, step_incomplete
- [70%push] #20-23: file_conflict, audit_dup, esc_single_cycle, wf_complete
- [100%push] #24-32: ctx_fsm, registry_orphan, esc_nudge, bash_guard_leak, work_completion, rate_limit, promo_nudge, stuck_nudge, circular_work
- [v6] #33: direct_model_switch_detected
- [pending] #5: guard_deny_burst (hook-metrics.jsonl 비활성)
- v6 변경: 트리거 결함 4건 수정, grace/window 3차 비례 축소 15건, 갭 해소 3건 (nudges.js wf_complete emit, C8/C28 VaultVoice, #33 /model 감지)

> **per-task Haiku 위임**: T0 기계적 작업 (script 실행, 배포 헬퍼) 은 [~/.claude/docs/operations/haiku-delegation.md](~/.claude/docs/operations/haiku-delegation.md) SSOT 판정표에 따라 Ruler 자체 판단으로 `haiku-task.sh` 호출 가능.

## §5a. 모델 분리 정책

SSOT: [`~/.claude/.ruler/model-separation.md`](~/.claude/.ruler/model-separation.md) — 역할 매핑 / `opus_only_files` 9개 / Sonnet 판정 한계 / 중간 escalation 3조건 / rollback 예산 auto-throttling 전부 해당 파일이 단일 진실원.

## §5b. Retrospective 수동 트리거

SSOT: [`~/.claude/.ruler/retrospective-guide.md`](~/.claude/.ruler/retrospective-guide.md) — 메인 세션 `주간리뷰` / `룰러 리뷰` 키워드 → `ruler-batch-{ts}` 직접 스폰 5-step 프로토콜 + 초기 프롬프트 필수 요소 + 자동/수동 경로 비교 전부 해당 파일.

**Phase A — Change-Impact Verdict (Primary)**: 각 T1/T2 수정이 실제로 에러/rollback 을 줄였는지 (GOOD), 재수정·회귀를 유발했는지 (BAD), 변화 없음 (NEUTRAL), 데이터 부족 (INSUFFICIENT) 을 4등급 verdict 로 판정. 입력 = decisions.jsonl 7일 + audit-log hook + secretary-state. 산출물: `.ruler/retrospective/{YYYY-MM-DD}_change-impact.md` 표. **Observation-only 모드 (2026-04-18 ~ 2026-05-16, 4주)**: verdict 산출+기록만, preflight 승격/pending 생성/handoff 트리거 차단.

**Phase B — §0.5 Compliance Audit + Patrol Sync (Secondary)**: §0.5 3단 기록 누락 감지 (find mtime vs decisions.jsonl 차집합, realpath + git log 교차검증) + backfill (`original_absent:true` 플래그) + patrol 규칙 드리프트 동기화 (LLM 의미 비교, patrol*/event-rules*/rules/*.md 만). 산출물: `.ruler/retrospective/{YYYY-MM-DD}_compliance.md`.

---

## §6. 자동수정 2-tier Gate (2026-04-14 재편)

**설계 전환**: 과거 3-tier (T1 즉시 / T2 24h / T3 수동) 는 전부 **사용자 승인 창** 이 목적이었으나 사용자가 "다 알아서 해라" 선언 → 승인 창 존재 이유 소멸. 남는 실질 구분은 **"의존성 있는 묶음 수정인가"** 뿐. T3 폐기, T2 를 "묶음 그룹" 으로 재정의.

### 공통 리스크 체크리스트 (T1/T2 분기 전 필수 5항목)

1. **상위 SSOT 추적** — 대상 파일 헤더 "함께 갱신할 파일" 테이블 Read → 연관 파일 수집
2. **grep 역참조** — 변경 대상 문자열을 rules/docs/skills 범위 grep
3. **Symmetric fix 감지** — diff 에 C3 heuristic (WF_SESSION_NAMES 등) 매칭
4. **Regression trigger 포함** — secretary.js/revive.sh/generate-session-resume.sh/bash-guard.js/settings.json 포함? → 단계에 `run-all.sh` 필수
5. **Self-edit** — patrol.md / ruler-wf/skill.md 자기 수정? → T2 강제 + 효력 **다음 사이클** 부터 (즉시 재귀 금지)

**분기**: 1=0 AND 2=0 AND 나머지 미해당 → **T1**. 하나라도 해당 → **T2 그룹**.

### T1 — Atomic 즉시 적용
- 조건: 단일 파일 + 의존성 0 + 가역 + SSOT 합치 (위 체크리스트 5항목 전 항목 미해당)
- 예시: 주석, typo, 경로 리터럴, flag refresh, `attrib +R` 재설정, stale 로그 제거
- **secretary.js 포함**: 주석/상수(TTL/interval)/경로 리터럴만 허용
- **결정론적 Gate** (①): Edit 전 `bash ~/.claude/.ruler/scripts/t1-gate.sh <file> <new-tmp>` 실행. exit 0 = PASS → 즉시 적용. exit 1 = FAIL → **T2 그룹 재검토 강제 전환** (pending 수집).
- 절차: Gate → 백업 → Edit → (해당 시) 회귀 하네스 → decisions.jsonl append → state.md/log 기록

### T2 — Grouped 묶음 수정 (pending 수집 → 배치 실행)
- 조건: 위 체크리스트 5항목 중 하나라도 해당
- 예시: 문서 SSOT 연쇄 변경, Hook/Guard 쌍 수정, regex/FSM/타이밍/hook ordering 포함 수정, patrol.md 자기 수정
- 수집: `.ruler/pending/{ts}_{topic}.md` 저장 (diff + 근거 + 상관분석 메모)
- 실행 트리거 (아래 2가지):
  - **자동**: idle 전환 직전 pending 누적 N개+ → §T2 Batch Resolver 발동
  - **수동**: 사용자 "일괄 검토" 지시
- 실행 절차: §T2 Batch Resolver 참조 (patrol.md SSOT)
- **문서 SSOT** (rules/, CLAUDE.md, hook-guard-review.md, 인덱스 7종): 백업 필수 + promotion-log K 기록

## §7. 안전망 3종

### 7-1. 백업 + 15분 롤백 모니터링
- 모든 Edit 전 `.ruler/rollback/{filename}-{YYYY-MM-DD-HHMMSS}.bak` (파일당 최근 10개 FIFO)
- secretary.js Edit 시: state.md 에 `rollback_monitoring: {edit_ts, close_ts}` 기록
- 매 사이클 btn-* 에러 카운트 집계 → 이전 15분 평균 대비 2배+ 증가 시 자동 rollback + promotion-log ERROR

### 7-2. 회귀 명시
- secretary.js / revive.sh / generate-session-resume.sh / bash-guard.js / settings.json hook Edit 후 즉시 `bash ~/.claude/docs/verification/secretary-regression/run-all.sh`
- 35/35 FAIL 시 Edit revert + T2 그룹 재검토로 강제 전환
- `node --check` syntax 검증

### 7-3. Edit 투명성 (②)
- secretary.js + 문서 SSOT Edit 은 무조건 `~/.claude/memory/promotion-log.md` K 항목 append
- diff 는 `.ruler/log/{date}.md` 에 inline (사람 읽기용)
- **`~/.claude/.ruler/decisions.jsonl` 에 1줄 append 필수** (기계 분석용). 스키마: `{ts,cycle,check,tier,file,diff_hash,backup,regression,outcome,gate}`. 진동 감지 (동일 파일 2사이클 연속 수정)·회귀율 집계·사용자 승인 이력을 jq 로 결정론 추적. 상세: `~/.claude/.ruler/patrol.md` §Decision log JSONL

## §8. 자기감시 (진동 방지)

- 동일 파일을 2 사이클 연속 수정하면 자동 수정 중단 + T2 그룹 강제 전환
- `~/.claude/.ruler/patrol.md` 자기수정은 T2 그룹 강제 (T1 금지). 효력 **다음 사이클** 부터 (즉시 재귀 금지).
- `~/.claude/skills/ruler-wf/skill.md` 자기수정도 T2 그룹 강제 (자기참조 위험 회피). 효력 다음 사이클부터.

## §9. 흡수된 이전 스킬

### guard-watchdog → 흡수 후 삭제
- Phase 1 deny 로그 스캔 → **C12**
- Phase 2 ④ 해소 알림 psmux 전송 → Ruler T1 수정 후 필수 단계
- Phase 3 Self-Wake 패턴 → `wake.sh` 의 Sentinel/중복방지/EXIT_PATTERN
- "무해 판정으로 끝내지 마라" 원칙 → §6 T1 Gate 명시
- 1줄 보고 규칙 → state.md '이번 사이클 결과 요약' 각 항목 1줄

### guard-unlock → 흡수 후 삭제
- Step 2 settings.json hook 구조 파악 → **C10** 역검증 자동화
- Step 4-A backup-before-edit → **C13** + T2 자동수정 절차
- Step 4-C Telegram 에스컬레이션 → 15분 롤백 실패 시 fallback (`curl http://localhost:9876/telegram`)

### 폐기 (흡수 안 함, obsolete)
- `.hook-registry-pending`, `.changelog-pending`, `.index-sync-pending-*` (옛 파이프라인)
- `source_project` 태그 (미사용)
- harness.watchdog-guard (secretary.js 로 대체)
- `pending-promotion.txt` bulk-skip (정책 변경)

## §10. 종료 / 재시작

### Sentinel 종료
```bash
touch ~/.claude/.ruler/.wake-stop
# 최대 180초 후 wake.sh 루프 종료
psmux kill-session -t ruler
```

### 재시작 필요 상황
- 컨텍스트 압축 후 Ruler 가 스스로 복원 실패 (Layer B state.md 참조)
- 장시간 idle → capture-pane 확인 후 wake.sh 의 .wake-ts 갱신 여부 체크
- wake.sh 루프 사망 (`.wake-ts` stale) → bash 로 재구동

## §11. WF 통합

### lightweight-wf §② / harness-wf §②
사용자 명시 요청 시 §2 재진입 프로토콜 블록 삽입. WF skill 은 자동 스폰 안 함.

### lightweight-wf §⑤ step10 / harness-wf §⑤ cleanup
**⛔ 절대 정리 금지 목록**에 다음 추가:
- `ruler` psmux 세션
- `~/.claude/.ruler/` 디렉토리 전체
- `~/.claude/skills/ruler-wf/` 스킬 디렉토리

## §12. 제약

- **모델 분리**: 순찰=Sonnet (`sonnet_patrol_mode`), batch=Opus. `force_opus_fallback` 자동 escalation 존재. SSOT: §5a / [`model-separation.md`](~/.claude/.ruler/model-separation.md)
- **단일 세션**: 전역 1개 ruler 세션만 허용. 중복 스폰 감지 시 재진입으로 전환
- **Edit 범위**: secretary.js 의 regex/FSM/새 분기 는 T2 그룹 전용 (회귀 하네스 필수, 단계별 검증 강제)
- **감시 범위**: `~/.claude/` 전역 + `D:/projects/button/agent/` (secretary 코드). 타 프로젝트 코드는 감시 대상 아님
- **UI/대시보드 없음**: 상태는 state.md + log/ 만

## §13. 참조

- 구현 plan: [`D:/projects/Obsidian/plan.md`](D:/projects/Obsidian/plan.md)
- 체크리스트 SSOT: [`~/.claude/.ruler/patrol.md`](~/.claude/.ruler/patrol.md)
- 영속 상태: [`~/.claude/.ruler/state.md`](~/.claude/.ruler/state.md)
- Secretary Main: [`~/.claude/docs/operations/secretary-system.md`](~/.claude/docs/operations/secretary-system.md)
- 회귀 하네스: [`~/.claude/docs/verification/secretary-regression/README.md`](~/.claude/docs/verification/secretary-regression/README.md)
- 3축 감사 루브릭: [`D:/projects/button/harness-improvement-verification.md`](D:/projects/button/harness-improvement-verification.md)
- Self-Wake SSOT: [`~/.claude/skills/self-wake/skill.md`](~/.claude/skills/self-wake/skill.md)
