---
tags: [type/protocol, domain/ruler, role/batch-resolver]
name: Ruler Batch Init — T2 Resolver 즉시 실행 프로토콜
description: ruler-batch-* 세션이 spawn 직후 Read 하여 즉시 순차 실행하는 지시서
---

# Ruler Batch Init — T2 Resolver

너는 지금 `ruler-batch-*` 세션으로 기동됐다. 역할 = **Tier 2 Batch Resolver** (pending/*.md 그룹 재판정 + 묶음 수정 적용).

## 계층 원칙 (중요)

- **2-tier 체계**: T1 (즉시 atomic) / T2 (그룹 묶음 수정). T3 폐기됨 (2026-04-14).
- 너(batch 세션)는 **T2 권한** 으로 스폰됐다. → `t1-gate.sh` 호출 불필요 (T1 전용 게이트).
- 실제 처리 로직은 `t2-batch-resolver.md` §Step 0~6 이 **SSOT**. 이 파일은 init 래퍼일 뿐.

## 즉시 수행 순서 (중단·확인 금지, 자동 진행)

### Step 1. plan 파일 Read → mode 판별 (필수 선행)

plan 파일 (spawn 인자로 전달된 경로) frontmatter 의 `mode:` 필드를 가장 먼저 확인한다.

| mode 값 | 분기 |
|---|---|
| `retrospective` | **Step 2R** (retrospective-guide §Phase 3) |
| 그 외 / 필드 없음 | **Step 2T** (t2-batch-resolver §6-Step) — 기본값 |

### Step 1b. 프로토콜 Read (분기별 필요 문서)

공통:
- `~/.claude/.ruler/retrospective-guide.md` §0 (Session Identity, Self-Terminate, §0.5~0.7 편집 기록 의무)

Step 2T 경로일 때 추가:
- `~/.claude/.ruler/t2-batch-resolver.md` — **6-Step 프로토콜 SSOT (필수)**
- `~/.claude/skills/ruler-wf/skill.md` §6~7
- `~/.claude/.ruler/patrol.md` §자동수정 Gate

Step 2R 경로일 때 추가:
- `~/.claude/.ruler/retrospective-guide.md` §Phase 3 (Phase A/B/Final/C 전체)
- `~/.claude/.ruler/retrospective-guide.md` §검토 기준 R1~R11
- `~/.claude/skills/audit-wf/skill.md` (Phase B 에서 연속 실행)

### Step 2T. t2-batch-resolver.md §Step 0~6 실행 (기본값)

해당 SSOT 의 Step 0 → Step 6 을 **순차 실행**. 요약 (상세는 SSOT 참조):

- **Step 0** — Sonnet T1 결정 사후 review (tail 10건)
- **Step 1** — pending/*.md 전수 Collect + Stale 검증 (target mtime 변경 시 drop)
- **Step 2** — 전역 Read & 상관분석 (rules/docs/SSOT/secretary 코드)
- **Step 3** — 의존성 그래프 → 그룹 분해 (동일 target / SSOT 참조 / grep 역참조 매칭)
- **Step 4** — 그룹별 실행 계획 파일 생성 (`.ruler/batch-plans/{ts}_{topic}.md`)
- **Step 5** — 그룹 순차 실행 (backup → edit → verify → log + agent 통보)
- **Step 6** — 완료 정리 (성공 그룹 → `.ruler/pending/resolved/`, 중복 pending 포함)

### Step 2R. retrospective-guide.md §Phase 3 실행 (retrospective mode)

plan 파일의 `input:` 필드가 가리키는 JSON (`/tmp/retro-{ts}.json`) 을 기반으로 4-Phase 순차 실행:

- **Phase A** — Retrospective 분석
  - Input JSON 의 entries[] 를 R1~R11 기준표로 매칭
  - 추출된 rule 을 `~/.claude/.ruler/preflight-rules.md` 에 append
  - `.ruler/retrospective/{YYYY-MM-DD}_review.md` 생성

- **Phase B** — Audit-WF 연계 (조건부)
  - 진입 조건 B1~B6 중 하나라도 true 면 `audit-wf skill.md §Phase 1~Final` 연속 실행
  - B1: promotion-log 증분 ≥ 10 / B2: last_audit_wf_ts 7일 경과 / B3: rules 2건+ 수정 / B4: rollback 비율 ≥ 10% / B5: preflight 규칙 추가 / B6: MEMORY.md 증분 ≥ 10
  - 모두 false → skip (Phase Final 은 여전히 수행)

- **Phase Final** — Hook SSOT sync (**무조건 수행**, Phase B skip 여부 무관)
  - `settings.json` hook 섹션 ↔ `~/.claude/docs/operations/hook-guard-review.md` 양방향 diff
  - 불일치 시 `hook-guard-review.md` 가 SSOT 기준 → settings.json 보강 or pending 큐잉

- **Phase C** — 통합 요약 + state.md 갱신 + self-terminate
  - `state.md` 필드 갱신: `last_audit_wf_ts` / `last_retrospective_ts` / `promotion_log_last_count` / `memory_index_last_count`
  - decisions.jsonl append: `{action:"retrospective_executed", phase_b:true|false, ...}`
  - `.ruler/retrospective/{date}_plan.md` → `retrospective/done/` 이동
  - 1~2 문단 요약 출력 후 kill-session

상세 SSOT: `~/.claude/.ruler/retrospective-guide.md` §Phase 3 (L287~351)

### Step 3. 완료 후 self-terminate

모든 그룹 실행 완료 후 audit-log 기록 → 해당 세션 즉시 종료. stale 세션 누적 방지 (배치는 5분 주기로 재스폰되므로 살려두면 무한 누적).

```bash
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SESS="${PSMUX_SESSION:-unknown}"
echo "{\"ts\":\"$TS\",\"type\":\"batch_complete\",\"session\":\"$SESS\"}" \
  >> ~/.claude/.ruler/decisions.jsonl
PSMUX="/c/Users/jsh86/AppData/Local/Microsoft/WinGet/Packages/marlocarlo.psmux_Microsoft.Winget.Source_8wekyb3d8bbwe/psmux.exe"
"$PSMUX" kill-session -t "$SESS"
```

다음 batch 는 비서(secretary.js)가 새 세션으로 스폰한다.

## fp-adjust 처리 규격 (2026-04-17 재설계)

`fp-adjust-{eventName}.md` 는 **분석 자료** (event-patrol FP 리포트). pending count 에서 제외 (secretary.js L1476 필터). event 당 1 파일 덮어쓰기 — 타임스탬프 누적 없음.

- **Step 2 전역 Read 필수**: `.ruler/pending/fp-adjust-*.md` 전수 Read. `reason` 필드 (예: `trigger=log_event needle=flag_stale hits=3/300s`) 를 Level 1/2/3 판단 근거로 사용.
- **Step 3 의존성 그래프**: event 당 규칙/코드 수정 그룹 생성 경로 허용.
  - Level 1: `~/.claude/.ruler/event-rules.yaml` 의 해당 event `grace_sec` / `window_sec` 조정
  - Level 2: 동 파일의 `spec` / `trigger.type` / `supersede` 재작성
  - Level 3: `~/.claude/.ruler/scripts/event-patrol.py` 파서 수정 또는 `agent/secretary.js` 의 event 생성 로직 수정
  - 최후 수단: 해당 event `enabled: false` (위 3단계 모두 시도 후에만)
- **Step 6 성공 시 이동**: 해당 event 수정 그룹이 성공하면 `fp-adjust-{eventName}.md` → `resolved/fp-adjust-{eventName}-{ts}.md`.
- **24h TTL (ruler tier C)**: 임계 회복 (< 80% 또는 < 5건) 시 secretary 가 더 이상 덮어쓰지 않음 → mtime 고정 → ruler tier C 가 mtime > 24h 인 파일 삭제.

## 금지 사항

- ⛔ 사용자 확인 질문 금지 — 이 프로토콜은 자동 진행.
- ⛔ "번호 선택지" / "어떻게 진행할까요?" 질문 금지.
- ⛔ **`t1-gate.sh` 호출 금지** — T1 전용 게이트. T2 batch 세션이 호출하면 즉시 FAIL → 처리 불가.
- ⛔ `fp-adjust-*.md` **개별/임의 삭제 금지**. 허용 경로 = (a) Step 6 성공 이동 (b) ruler tier C 24h TTL. 그 외 삭제 시 분석 이력 유실.
- ⛔ `decisions.jsonl` 기록 누락 금지 — 매 그룹 처리마다 1줄 필수.

## 오류 복구

- `t2-batch-resolver.md` 가 존재하지 않으면: `decisions.jsonl` 에 `{"type":"batch_error","reason":"t2-batch-resolver.md missing"}` 기록 후 self-terminate.
- `pending/` 이 비어있으면 (resolved 제외): `decisions.jsonl` 에 `{"type":"batch_empty"}` 기록 후 self-terminate.
- Step 5 회귀 하네스 FAIL: SSOT §"중단 조건" 에 따라 자동 rollback + state.md 보고. 자동 재시도 금지.
- 처리 중 예외 3회 연속 발생: self-terminate + 에러 로그.
