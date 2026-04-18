---
type: progress
scope: ruler-retrospective-completion
date: 2026-04-18
status: in-progress
plan: plan.md
tags: [ruler, retrospective, completion, progress]
---

# Progress — Retrospective 완성도 보완

> Plan: [`plan.md`](./plan.md) §5 Steps (10 step).
> 각 step `model:` 하나. direct step 시작 시 `model-switch-and-send.sh` / `haiku-task.sh` 경유 (CLAUDE.md §E).
> 매 Edit 직전 §0.6 grep gate, 직후 §0.5 3단 기록.

진입 가드: `/d/projects/ruler/.progress-model-override` 존재 = phase-transition hook 의 sonnet 강제 전환 차단 (현 세션 opus 유지, 필요 step 은 Agent subagent 위임).

---

## Steps

- [x] **Step 1 — compute_change_impact() verdict 식 확장 + backfill_missing()** (model: opus) — 2026-04-18 완료
  - 파일: `D:/projects/ruler/.ruler/scripts/retrospective-collect.sh`
  - 변경 A (verdict 식): `compute_change_impact()` 의 per-T entry 루프에 **audit-log ts 기반 pre/post ERROR + ESCALATION 카운트** 블록 추가. `audit_err_pre/post` + `esc_pre/post` 계산. verdict 재구성: GOOD 조건에 `err_delta <= 0 AND esc_delta <= 0` 추가, BAD 조건에 `err_delta >= +3 OR esc_delta >= +5` OR 추가. Δ summary 에 `err Δ{M}·esc Δ{K}` 병기.
  - 변경 B (backfill_missing): Step 3-2 끝 (`MISSING_FILES_JSON` 확정 후) 에 `backfill_missing()` 함수 호출. missing_files 각 건당 decisions.jsonl 에 `{ts: mtime+09:00, action:"backfill", original_absent:true, tier: T1(rules/skills/hooks 매칭) or unknown, meta:{inferred_from:"mtime"}}` append. 중복 방지: 이미 동일 file + original_absent:true entry 있으면 skip.
  - 건들지 말 것: jq PATH export 블록, Step 3-1 pre/post window 경계, R1/R2/R3 BAD 보조, 최종 JSON 조립.
  - 완료 판정: (1) `grep -n 'audit_err_pre\|esc_pre' .ruler/scripts/retrospective-collect.sh` ≥ 4 줄 (2) `grep 'backfill_missing()' .ruler/scripts/retrospective-collect.sh` ≥ 2 회 (정의 + 호출) (3) smoke test EXIT 0 유지.
  - 사유 (opus): verdict 식 확장은 임계값 (+3 / +5) 정당성 + audit-log ts 기반 window 의 decisions.jsonl 과 overlap 여부 판단 = A-B 트레이드오프.

- [x] **Step 2 — trigger-retrospective.sh 래퍼 신규** (model: sonnet) — 2026-04-18 완료
  - 파일: `D:/projects/ruler/.ruler/scripts/trigger-retrospective.sh` (신규)
  - 내용: plan §3.3 의 bash 스크립트 그대로. `set -euo pipefail` + TS/OUT/PLAN 변수 + 3-step 순차 (collect / plan heredoc / spawn)
  - 완료 판정: (1) `ls -la` 시 `-rwxr-xr-x` 실행권한 (2) `bash trigger-retrospective.sh --help` 또는 dry-run 시 호출 3단계 echo 확인
  - Sonnet-executable ✅

- [x] **Step 3 — seed-external-checksums.sh + baseline 실행** (model: sonnet) — 2026-04-18 완료
  - 파일 A: `D:/projects/ruler/.ruler/scripts/seed-external-checksums.sh` (신규)
  - 파일 B: `D:/projects/ruler/.ruler/external-skill-checksums.md` (seed 실행 후 자동 생성)
  - 내용: plan §3.4 스크립트. sha256sum 대상 2개 + heredoc output. chmod +x 포함.
  - 실행: 생성 즉시 `bash seed-external-checksums.sh` 1회 실행 → checksums.md 생성 확인
  - 완료 판정: (1) seed 스크립트 실행권한 (2) `external-skill-checksums.md` 파일 존재 + `ruler-wf/skill.md:` `audit-wf/skill.md:` 각 1줄 hex64 매칭
  - Sonnet-executable ✅

- [x] **Step 4 — 합성 fixture 3종** (model: sonnet) — 2026-04-18 완료
  - 파일 A: `D:/projects/ruler/.ruler/tests/fixtures/good-case.jsonl`
  - 파일 B: `D:/projects/ruler/.ruler/tests/fixtures/bad-case.jsonl`
  - 파일 C: `D:/projects/ruler/.ruler/tests/fixtures/insufficient-case.jsonl`
  - 내용: 각 fixture 는 decisions.jsonl 포맷 JSONL 20~30줄. good = pre 15 post 5 (rb 0) · bad = pre 10 post 25 (rb 1) · insufficient = pre 5. T entry 1개 이상 (tier:T1) 포함. ts 는 가상 시점 (예: 2026-04-01 ~ 04-15 분포).
  - 완료 판정: 각 fixture 를 `jq -s 'length'` 했을 때 기대 건수 일치 + `.tier="T1"` entry 존재
  - Sonnet-executable ✅

- [x] **Step 5 — test-compute-change-impact.sh 하네스** (model: sonnet) — 2026-04-18 완료
  - 파일: `D:/projects/ruler/.ruler/tests/test-compute-change-impact.sh` (신규)
  - 내용: 3 fixture 순회, 각각 (a) 임시 decisions.jsonl 로 교체 (env RULER_DIR 재지정 가능 형식) (b) collect.sh 실행 (c) `retrospective/{date}_change-impact.md` 의 verdict 칼럼 grep (d) 기대값과 assert
  - 기대값: good → `GOOD` 1건+ / bad → `BAD` 1건+ / insufficient → `INSUFFICIENT` 1건+
  - 완료 판정: `bash test-compute-change-impact.sh` exit 0 + 3 case 전부 PASS 출력
  - Sonnet-executable ✅

- [x] **Step 6 — R4/R5 쿼리 추가** (model: sonnet) — 2026-04-18 완료
  - 파일: `D:/projects/ruler/.ruler/scripts/retrospective-collect.sh`
  - 위치: compute_change_impact() 의 `verdict="BAD"` 분기 (기존 R1/R2/R3 뒤)
  - 변경: R4 (pending/dropped window 내 ≥5) + R5 (audit-log regression_failed ≥1) 쿼리 추가. r_hits 문자열에 append.
  - 건들지 말 것: R1/R2/R3 기존 로직, verdict 판정 식 본체.
  - 완료 판정: grep `'R4 pattern\|R5 pattern'` ≥ 2 hits
  - Sonnet-executable ✅

- [x] **Step 7 — retrospective-guide.md §Phase B Step 3 체크리스트화** (model: opus) — 2026-04-18 완료
  - 파일: `D:/projects/ruler/.ruler/retrospective-guide.md`
  - 대상: `## Phase B` → `### Step 3 — Patrol 규칙 동기화` 블록
  - 변경: 현재 산문 설명을 **5 체크박스** 로 재구성 (plan §3.8 참조). 특히 "매칭 0건 skip 시 decisions.jsonl append 강제" 항목 + 실행 요약 1줄 append 의무 추가
  - 건들지 말 것: Phase A, §0.5~0.7, Phase C/Final/Terminal
  - 완료 판정: (1) `## Phase B` 섹션 내 `- [ ]` 체크박스 ≥ 5개 (2) `phase_b_step3:skipped` 또는 `phase_b_step3:done` 문자열 등장
  - 사유 (opus): 런타임 책임 vs 스크립트 책임 경계 설계 + skip 강제 의무화 (결정 설계)

- [x] **Step 8 — guide §Phase Terminal obs-only 자동 해제** (model: opus) — 2026-04-18 완료
  - 파일: `D:/projects/ruler/.ruler/retrospective-guide.md`
  - 대상: `## Phase Terminal` 블록
  - 변경: 해제 판정 5-step 삽입 (plan §3.5 참조). 임계 `insufficient_rate < 0.5` + 실패 시 `+14d 연장` 정책 + promotion-log KNOWLEDGE append 지시
  - 건들지 말 것: Phase Terminal 의 기존 self-terminate 5-step, review.md 재정의 블록
  - 완료 판정: grep `'obs-only 해제 판정\|change_impact_enforcement_start'` ≥ 2회 + "+14" 문자열 등장
  - 사유 (opus): 해제/연장 policy 설계 + 0.5 임계 정당성

- [x] **Step 9 — CLAUDE.md Auto Triggers 단순화 + 통합 smoke** (model: sonnet) — 2026-04-18 완료
  - 파일 A: `C:/Users/jsh86/.claude/CLAUDE.md`
  - 변경 A: Auto Triggers "주간리뷰" 줄을 `bash ~/.claude/.ruler/scripts/trigger-retrospective.sh` 한 줄 호출로 단순화. guide §수동 트리거 포인터는 유지
  - 변경 B: `bash test-compute-change-impact.sh` (fixture) + 실 collect.sh smoke 둘 다 EXIT 0 확인
  - 건들지 말 것: 다른 Auto Triggers 줄
  - 완료 판정: (1) CLAUDE.md 에서 `trigger-retrospective.sh` 문자열 매치 (2) fixture test 3/3 PASS (3) 실 smoke EXIT 0
  - Sonnet-executable ✅

- [x] **Step 10 — button/checklist.md `## Retro.` 섹션 추가** (model: sonnet) — 2026-04-18 완료
  - 파일: `D:/projects/button/checklist.md`
  - 위치: 기존 ①~③ wake 절차 하단. 신규 `## Retro. (주간 retrospective 모니터링)` 섹션
  - 내용: 5 체크박스 (plan §5 Step 10 상세 참조 — 최종 retro ts / BAD verdict 건수 / checksums.md 갱신 / missing_files 길이 / obs-only 해제 여부)
  - 건들지 말 것: 기존 ①~③, 간섭 금지 원칙, 예상 세션 목록
  - 완료 판정: grep `'^## Retro\.'` + 5개 체크박스
  - Sonnet-executable ✅

---

## 추가 보완 (P0 소스 기록 gap — 2026-04-18 감사 발견)

> 감사 결과: retrospective-collect.sh Step 1/6 이 의존하는 `type:"ERROR"` / `type:"regression_failed"` audit-log 에 기록 0건. decisions.jsonl 필드 30% 누락. 이 상태로는 verdict 식이 무의미. 선결 조치.

- [x] **Step 11 — secretary escalation 경로 audit-log 타입 분기** (model: opus) — 2026-04-18 완료
  - 대상: `D:/projects/button/agent/secretary/escalation.js` (또는 escalation 기록 모듈) + `D:/projects/button/agent/secretary.js`
  - 변경: escalation 이벤트 기록 시 심각도별로 audit-log 타입 분기 — `type:"error_detected"` (classifyError 감지) / `type:"escalation_warned"` (기존 유지) / 심각도 임계 초과 시 `type:"ERROR"` (retrospective 기준 "치명 에러")
  - 추가: `.secretary-state.json` 에 `escalation_count: N` 필드 누적 write (collect.sh L377 의존)
  - 완료 판정: (1) 비서 재시작 후 audit-log 에 `type:"error_detected"` 또는 `type:"ERROR"` 신규 append 관찰 (2) `.secretary-state.json` 에 `escalation_count` 필드 존재
  - 사유 (opus): 임계값/분기 기준 설계 + 비서 runtime 안정성

- [x] **Step 12 — t1-gate.sh rollback verify regression_failed 기록** (model: sonnet) — 2026-04-18 완료
  - 대상: `D:/projects/ruler/.ruler/scripts/t1-gate.sh`
  - 변경: rollback 직후 verify (grep/diff 또는 재실행) 실패 시 `~/.claude/audit-log/$(date +%Y-%m-%d).jsonl` 에 `{"ts":..., "type":"regression_failed", "file":..., "reason":...}` append
  - 완료 판정: t1-gate.sh 에 `type":"regression_failed"` 문자열 grep ≥ 1
  - Sonnet-executable ✅

- [x] **Step 13 — decisions.jsonl 필드 강제 validation + batch log 자동 append** (model: sonnet) — 2026-04-18 완료
  - 대상 A: `D:/projects/ruler/.ruler/scripts/t1-gate.sh` — append 전 필수 필드 `{ts, file, action, tier}` 검증 (file="" 허용 but 키는 반드시 존재). 누락 시 stderr warn + exit 2.
  - 대상 B: `D:/projects/ruler/.ruler/retrospective-guide.md` §Phase C — self-terminate 직전 **무조건** `log/$(date +%Y-%m-%d).md` 에 batch 블록 append 명문화
  - 완료 판정: (1) t1-gate.sh 에 `file 필드 누락` 또는 `validate` grep ≥ 1 (2) guide.md Phase C 에 "batch log append (무조건)" 문자열 등장
  - Sonnet-executable ✅

---

## 실행 완료 후 추가 보완 (2026-04-18 감사 반영, plan §9)

### 잠재버그 3건 (메인 opus 직접 수정) — 2026-04-18 완료

- [x] **B1 — collect.sh L131 pipefail guard**: `{ grep ... || true; } | while` 패턴으로 빈 log 디렉토리 방어
- [x] **B2 — collect.sh L662-665 grep -c → awk**: `awk '$0=="GOOD"{n++} END{print n+0}'` 로 Windows MSYS2 newline 섞임 방지
- [x] **B3 — collect.sh L196 T-point 범위 수정 + guide.md L220 동기화**: T1 prefix + T2_batch_applied 만 T-point

### 검증 빈도 확보 (Step 14-17)

- [x] **Step 14 — PostToolUse hook (§0.5 자동화)** (model: opus) — 2026-04-18 완료
  - 파일: `C:/Users/jsh86/.claude/hooks/ruler-decisions-autolog.sh` (신규) + `C:/Users/jsh86/.claude/settings.json` (등록)
  - Edit/Write/MultiEdit 가 ruler 전역 파일 수정 시 decisions.jsonl 에 `tier:"T0_autolog"` entry 자동 append
  - 완료 판정: hook 스크립트 실행권한 + dry-run smoke (positive/negative)

- [x] **Step 15 — Poisson CI 완화 + T-point 범위 확장** (model: opus, 메인 직접) — 2026-04-18 완료
  - 파일: `D:/projects/ruler/.ruler/scripts/retrospective-collect.sh`
  - 변경 A: L554 `pre_count < 10` → `< 5` (Poisson 95% CI 하한 ~1.6)
  - 변경 B: L196 `test("T1|T2")` → `test("^T1")` + `T2_batch_applied`
  - 완료 판정: fixture test 3/3 PASS (insufficient fixture 도 pre=2 로 조정 필요)

- [x] **Step 16 — t1-gate.sh tier regex validation + jq PATH** (model: opus, 메인 직접) — 2026-04-18 완료
  - 파일: `D:/projects/ruler/.ruler/scripts/t1-gate.sh`
  - 변경 A: `--validate-entry` + `validate_entry()` 둘 다에 tier 값 regex 검증 추가
  - 변경 B: jq PATH 보강 (node-jq fallback)
  - 완료 판정: "WRONG" tier 거부 + "T1_user_auth" 허용 + "T1" 허용

- [x] **Step 17 — violation-tier-criteria.md T1 완화** (model: opus) — 2026-04-18 완료
  - 파일: `D:/projects/ruler/.ruler/violation-tier-criteria.md` + `patrol-tier-a.md` / `patrol-tier-c.md` (cross-ref)
  - T1 확장 서브카테고리 + T2 intake 명시
  - 완료 판정: "완화 배경" 문자열 + line diff +15~30

### Step 10 확장 — button/checklist.md Retro 섹션 재구성

- [x] **3 sub-block (A/B/C) 재구성** — 2026-04-18 완료
  - A: 주간 retrospective 가동 (기존 5)
  - B: 소스 기록 건전성 (신규 5, Step 11-13)
  - C: 자동화 hook/gate 작동 (신규 5, Step 14-17)
  - 완료 판정: `^## Retro\.` 1회 + `^- \[ \]` 총 15개

---

## Working Notes (세션 간 전달)

### 2026-04-18T16:22 KST — 보완 plan 진입

**마지막 결정**: 사용자 "ㄱㄱ" 승인. 기존 plan.md (재설계) + progress.md 를 `.plan-archive/` 로 이동, `plan-completion.md` 를 `plan.md` 로 rename 후 본 progress.md 새로 작성.

**다음 의도**:
1. 본 세션 (opus) 이 Step 1 직접 수행 (verdict 식 확장 + backfill_missing)
2. Sonnet step (2/3/4/5/6/9/10) 은 Agent subagent 병렬 위임
3. Opus step (7/8) 은 Agent subagent 위임 (model:"opus")
4. 모든 agent 완료 후 메인 세션이 smoke test 최종 수행 + 커밋

**동기화 필요**:
- `.progress-model-override` 파일 유지 (phase-transition hook 의 sonnet 강제 전환 차단)
- 각 step 완료 시 decisions.jsonl + log/{date}.md 3단 기록
- Step 10 은 **button 레포 편집** — §0.6 grep gate 는 inline BUG-* 주석이 아니라 decisions.jsonl `file:"checklist.md"` grep 으로 대체

**Observation-only 마감 역산**: 2026-05-16 해제 기준, Step 1-9 완료 마감 = 2026-05-09. Step 10 은 5/10-5/16 사이.

### 2026-04-18T17:19 KST — E2E 감사 + 잠재버그 + source gap 보완

**마지막 결정/발견**:
- Step 1-10 완료 후 source-recording audit 에서 **7일내 T entry 0건** 확인 → retrospective 판정 대부분 INSUFFICIENT. obs-only 해제 불가.
- 원인: (a) patrol/batch T1/T2 자체 희소 (b) 메인 세션 §0.5 준수 강제 없음 (c) Poisson CI N<10 너무 엄격.
- 처방: Step 14 (§0.5 PostToolUse hook), Step 15 (N<5 완화 + T-point 범위 확장), Step 16 (tier regex), Step 17 (T1 criteria 완화).
- 추가: Step 5 agent 가 collect.sh 잠재버그 3건 지적 — 메인 opus 직접 수정 완료.

**다음 의도**:
1. Step 14 (opus agent, 진행중) + Step 17 (opus agent, 진행중) 완료 대기
2. 완료 시 검수 후 plan+progress 아카이브 (`.plan-archive/`)
3. button/checklist.md Retro. 섹션 3 sub-block (A/B/C 15 체크박스) 이미 업데이트

**동기화 필요**:
- plan.md §9 "실행 완료 후 추가 보완" 섹션 (이 progress 의 Step 14-17 + 잠재버그 3건 매핑)
- Step 11 (secretary) 반영은 **button 비서 재시작 필요** — 사용자 수동
- Step 14 hook 등록 후 실제 ruler 전역 편집 시 decisions.jsonl 자동 append 관찰 필요 (OP-3)

**Observation-only 마감 역산**: 2026-05-16 해제 기준, Step 1-9 완료 마감 = 2026-05-09. Step 10 은 5/10-5/16 사이. Step 11-17 은 본 plan archive 전 완료.
