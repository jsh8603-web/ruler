---
type: progress
scope: ruler-retrospective-redesign
date: 2026-04-18
status: in-progress
plan: plan.md
tags: [ruler, retrospective, progress]
---

# Progress — Retrospective 재설계

> Plan: [`plan.md`](./plan.md) §3 통합 재설계 + §5 편집 대상 6파일 + §8 step 라우팅.
> 각 step `model:` 또는 `wf:` 중 **정확히 하나**. direct step 시작 시 `model-switch-and-send.sh` / `haiku-task.sh` 경유 (CLAUDE.md §E).
> 매 Edit 직전 `§0.6 grep gate`, 직후 `§0.5 3단 기록` 수행 (plan.md §8-3/4).

---

## Steps

- [ ] **Step 1 — `retrospective-guide.md` 재작성** (model: opus)
  - 파일: `D:/projects/ruler/.ruler/retrospective-guide.md`
  - 내용: §1~§4 재작성. Phase A (Change-Impact) / B (§0.5 Compliance + Patrol Sync) / C (심층 감사 연계) / Final (Hook SSOT) / Terminal (state + self-terminate) 재배치. Phase A 판정 스키마 (GOOD/NEUTRAL/BAD/INSUFFICIENT) 신규 작성. Phase B §0.5 3-Step 절차 (누락 감사 / backfill / patrol drift 분류) 신규 작성. R1~R11 은 `§부록` 으로 이동 + Phase A Δ 보조 재료로 재지시.
  - 건들지 말 것: §불변 사항 (Identity / Lifecycle / cwd / §0.5 의무 / §0.6 gate / self-terminate / 모델 정책 / 7일 주기 / T1/T2/T3 분류) — 모두 유지.
  - 완료 판정: ① grep `'^## Phase A'` → 매치 ② grep `'GOOD|NEUTRAL|BAD|INSUFFICIENT'` → 판정 표 존재 ③ R1~R11 정의가 `§부록` 아래로 이동 (grep `'^## §부록|^### R[0-9]'`)
  - 사유 (opus): Phase 구조 재정의 + 판정 스키마 설계 = 추상화 계층 변경, A-B 트레이드오프 포함.

- [ ] **Step 2 — `patrol.md` 실행 순서 갱신** (model: sonnet)
  - 파일: `D:/projects/ruler/.ruler/patrol.md`
  - 대상 섹션: §사후 Retrospective (진입 전 `grep -n '^## §사후\|^## Retrospective\|Phase A\|Phase B'` 로 라인 확정)
  - 변경: 현재 Phase 순서 표기 → `Phase A → B → C → Final → Terminal` 로 치환. 각 Phase 1-줄 설명도 plan §3.1 표기로 동기화.
  - 건들지 말 것: Tier A/B/C 순찰 정의, 체크리스트 항목 (E*/C*), self-wake 루프, 다른 섹션 전체.
  - 완료 판정: grep `'Phase A.*Phase B.*Phase C.*Phase Final.*Phase Terminal'` (multiline) 매치 + 기존 Phase 표기 잔존 0건 (`grep -c 'Phase D'` = 0, `grep -c '기존 Phase'` = 0).
  - Sonnet-executable 5항목: (1) 경로 ✅ (2) 라인은 Step 진입 시 grep 선행 (3) before/after = "현행 문자열 → 새 Phase 순서" (4) 경계 명시 ✅ (5) 판정 grep ✅.

- [ ] **Step 3 — `.ruler/scripts/retrospective-collect.sh` Δ 수집 + 교차 비교 JSON 추가** (model: sonnet)
  - 파일: `D:/projects/ruler/.ruler/scripts/retrospective-collect.sh`
  - 변경: (a) pre-T / post-T 각 3.5일 윈도우 `decisions.jsonl` 서브셋 추출 블록 신규. 출력: `/tmp/retro-{ts}/pre-{check}-{file}.json`, `post-{check}-{file}.json`. (b) §0.5 누락 감사용 교차 비교: `find -mtime -7 (plan §3.3 Step1 범위)` ∖ `jq '.file' decisions.jsonl` → `missing-files.json` append. 기존 `--window 7d --out` 인터페이스 유지.
  - 건들지 말 것: `--window`/`--out` 플래그 파싱, 기존 R1~R11 수집 블록, 스크립트 실행권한.
  - 완료 판정: (a) `bash .ruler/scripts/retrospective-collect.sh --window 7d --out /tmp/retro-test.json` 실행 성공 (b) 출력 JSON 에 `pre_window` / `post_window` / `missing_files` 키 존재 (`jq 'has("pre_window")'` = true).
  - Sonnet-executable 5항목: (1) 경로 ✅ (2) 라인 = "기존 R 수집 블록 이후 append" (3) before/after = 신규 bash 블록 추가 (4) 경계 ✅ (5) 판정 jq ✅.

- [ ] **Step 4 — `.ruler/scripts/change-impact.py` 신규 작성** (model: opus)
  - 파일: `D:/projects/ruler/.ruler/scripts/change-impact.py` (신규)
  - 기능: `decisions.jsonl` + `~/.claude/audit-log/{date}.jsonl` 파싱 → T 시점별 pre/post Δ 계산 → verdict (GOOD/NEUTRAL/BAD/INSUFFICIENT) 산출 → `.ruler/retrospective/{date}_change-impact.md` 표 렌더. 인자: `--decisions <path> --audit-log-dir <path> --window-days 3.5 --out <md path>`.
  - 건들지 말 것: 기존 `.ruler/scripts/` 내부 다른 파일 (event-patrol.py, retrospective-collect.sh 등).
  - 완료 판정: (a) 구문 체크 `python -m py_compile .ruler/scripts/change-impact.py` (b) dry-run `python .ruler/scripts/change-impact.py --decisions .ruler/decisions.jsonl --out /tmp/ci-test.md` 성공 (c) 출력 md 에 plan §3.2 표 포맷 (`| T | file | tier | action | verdict | Δ summary |`) 존재.
  - 사유 (opus): 판정 임계값·window 정의·데이터 스키마 설계 포함. ±20% / INSUFFICIENT 판정 경계 케이스 판단 필요.

- [ ] **Step 5 — `~/.claude/skills/ruler-wf/skill.md` §5b 보완** (model: sonnet)
  - 파일: `C:/Users/jsh86/.claude/skills/ruler-wf/skill.md`
  - 대상 섹션: `§5b Retrospective 수동 트리거` (진입 전 `grep -n '§5b\|수동 트리거'` 라인 확정)
  - 변경: Phase A (Change-Impact) / Phase B (§0.5 Compliance) 신규 설명 2-3 단락 추가. 산출물 경로 (`retrospective/{date}_change-impact.md`, `_compliance.md`) 기재. 기존 트리거 명령 (`bash ~/.claude/.ruler/scripts/retrospective-collect.sh ...`) 유지.
  - 건들지 말 것: §1~§5a, §6 이후 전 섹션. ruler-batch 스폰 프로토콜 원문.
  - 완료 판정: grep `'Phase A\|Change-Impact'` + grep `'Phase B\|Compliance'` 각각 §5b 블록 내 매치.
  - Sonnet-executable 5항목: (1) 경로 ✅ (2) 라인 = grep 선행 (3) 추가 단락 = "plan §3.2 / §3.3 요약" (4) 경계 ✅ (5) 판정 grep ✅.

- [ ] **Step 6 — `~/.claude/skills/audit-wf/skill.md` Phase Final-B 재정의** (model: opus)
  - 파일: `C:/Users/jsh86/.claude/skills/audit-wf/skill.md`
  - 변경: 기존 Phase Final-B "rules ↔ patrol 파일 리스트 diff" 역할을 "**Phase B (Compliance) 의 보완 감사** — ruler Phase B 가 다루지 못한 범위 (장기 drift / 파일 리스트 추적) 에 한정" 으로 재정의. 중복 범위 (최근 7일 §0.5 누락 감사) 는 ruler Phase B 로 위임한다는 명시 문장 추가.
  - 건들지 말 것: Phase Final-A, 다른 Phase 정의, audit 트리거 조건.
  - 완료 판정: (a) grep `'Phase Final-B'` 주변 `'ruler Phase B'` 또는 `'Compliance'` 참조 매치 (b) "최근 7일 §0.5 누락 감사" 단일 소유자 표기 (ruler Phase B) 명시 문장 존재.
  - 사유 (opus): 두 skill 간 책임 경계 설계 = 역할 분담 + 추상화 계층 변경.

- [ ] **Step 7 — Smoke test + verdict 오탐 1차 리뷰** (model: sonnet)
  - 대상: Step 1-6 완료 후 수동 retrospective 1회.
  - 절차: (a) 메인 세션에서 `룰러 리뷰` 키워드로 `ruler-batch-{ts}` 스폰 (b) Phase A/B 산출물 (`retrospective/{date}_change-impact.md`, `_compliance.md`) 생성 확인 (c) 오늘 01:24 baseline (승격 0) 대비 변경이 실제 GOOD/BAD verdict 을 추출하는지 육안 확인.
  - 건들지 말 것: 재설계 본체 (Step 1-6 산출물) — 이 step 은 검증만, 수정 금지. 수정 필요 시 별도 step 으로 분할.
  - 완료 판정: ① 두 산출 md 파일 존재 ② verdict 최소 1건 GOOD 또는 BAD (전부 INSUFFICIENT 이면 window 재조정 필요 → pending) ③ 토큰 실측 기록 (Phase A+B 합산, plan §6.2 기준 100k 미만).
  - Sonnet-executable 5항목: (1) 경로 = 산출 md (2) 라인 N/A (검증 step) (3) before/after N/A (4) 경계 ✅ (5) 판정 ✅.

---

## Working Notes (세션 간 전달)

- 마지막 결정: plan.md §8 step 라우팅을 progress.md 7-step 으로 확정. Step 7 smoke test 추가 (plan §6 검증 항목 중 1번).
- 다음 의도: 사용자 승인 후 Step 1 (opus direct) 착수. 그 전에 §0.6 grep gate (`grep '"file":"retrospective-guide.md"' .ruler/decisions.jsonl | tail -5`).
- 동기화 필요:
  - Step 2/3 진입 시 grep 으로 정확한 라인 범위 확정 후 §Steps 블록 업데이트.
  - Step 4 완료 후 `scripts/change-impact.py` 를 plan §5 편집 대상 표 #4 에 파일 크기/라인 수 기록 (plan §7 "150 라인 내외 예상" 실측).
  - 각 Edit 직후 `.ruler/decisions.jsonl` + `.ruler/log/2026-04-18.md` 3단 기록 (§0.5).
