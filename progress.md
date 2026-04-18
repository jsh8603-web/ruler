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

- [ ] **Step 3 — `.ruler/scripts/retrospective-collect.sh` Δ 수집 + verdict 통합** (model: sonnet)
  - 파일: `D:/projects/ruler/.ruler/scripts/retrospective-collect.sh`
  - 변경: (a) pre-T / post-T 각 3.5일 윈도우 `decisions.jsonl` 서브셋 추출 블록 신규. 출력: `/tmp/retro-{ts}/pre-{check}-{file}.json`, `post-{check}-{file}.json`. (b) §0.5 누락 감사용 교차 비교: `find -mtime -7 (plan §3.3 Step1 범위)` ∖ `jq '.file' decisions.jsonl` → `missing-files.json` append. (c) **`compute_change_impact()` bash 함수 신규** — `decisions.jsonl` + `~/.claude/audit-log/{date}.jsonl` 파싱 → T 시점별 pre/post Δ 계산 → verdict (GOOD/NEUTRAL/BAD/INSUFFICIENT) 산출 → `.ruler/retrospective/{date}_change-impact.md` 표 렌더 (`| T | file | tier | action | verdict | Δ summary |`). INSUFFICIENT 게이트는 단순 `if N<10` (Poisson 신뢰구간 생략, §7.2 Q1 Cost 권고 채택). Phase A `verdict_observation_only: true` 모드 (첫 4주) 배너 출력 포함. (d) 기존 `--window 7d --out` 인터페이스 유지.
  - 건들지 말 것: `--window`/`--out` 플래그 파싱, 기존 R1~R11 수집 블록, 스크립트 실행권한.
  - 완료 판정: (a) `bash .ruler/scripts/retrospective-collect.sh --window 7d --out /tmp/retro-test.json` 실행 성공 (b) 출력 JSON 에 `pre_window` / `post_window` / `missing_files` 키 존재 (`jq 'has("pre_window")'` = true) (c) 출력 md (`retrospective/{date}_change-impact.md`) 에 plan §3.2 표 포맷 + observation-only 배너 존재.
  - Sonnet-executable 5항목: (1) 경로 ✅ (2) 라인 = "기존 R 수집 블록 이후 append + verdict 함수 별도 블록" (3) before/after = 신규 bash 블록 + 신규 함수 (4) 경계 ✅ (5) 판정 jq+grep ✅.
  - 사유 (§7.2 Q1 반영): Python 제거 → bash+jq+awk 통합, model opus→sonnet 강등 (기계적 구현 + 판정 임계값은 단순 `N<10`).

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

### 2026-04-18T09:01 KST NUDGE_1 (98% tok) — 비서 mute 메커니즘 구축 중 강제 compact

**마지막 결정/발견**:
- 원인 규명 완료 (이중): cloud workspace 계정 sticky (가설 B) + Windows 경로 cloud 인식 불가 + **비서 NUDGE 가 `/ultraplan` prompt 에 섞여 cloud 혼란** (4지선다 팝업 유발)
- handoff.sh `REFINE_PROMPT` 를 GitHub URL 기반으로 재작성 완료 (`https://github.com/jsh8603-web/ruler/blob/main/plan.md`). cloud 가 자력 clone 해서 읽음 실증.
- watch.js 에 API Error/Stream idle 감지 → textarea 자동 입력 + Enter 재시도 (3회 상한) + screenshot 저장 로직 추가.
- 비서 mute 메커니즘 설계: flag `~/.claude/.secretary-mute/{session}` — handoff.sh touch, watch.js `process.on('exit')` cleanup, `psmux-send-helper.js sendSafe()` 진입부에 가드 1개 (모든 nudge/ctx-warn/escalation 차단).

**미완 작업** (다음 세션 재개 시 여기서 계속):
- ✅ `D:/projects/button/agent/secretary/psmux-send-helper.js`: mute 가드 추가 (L70 부근)
- ✅ `~/.claude/scripts/ultraplan-handoff.sh`: mute flag touch 추가 (Ctrl+L pane clear 직전)
- ✅ `~/.claude/scripts/ultraplan-watch.js`: `process.on('exit')` cleanup 추가 (main 시작부)
- ⏸ watch.js screenshot 블록에 Edge fg 통합 (L240-273): `bringEdgeFg(page)` 헬퍼 만들어 `page.bringToFront() + PowerShell bring-edge-foreground.ps1` 순서로 호출 — **편집 도중 compact 도달, 재개 시 완료 필요**
- ❌ **비서 재시작 필수** — psmux-send-helper.js 변경 반영 (재시작 절차 파악 필요)
- ❌ 깨끗한 새 ultraplan 호출 테스트 (mute 반영 + fg screenshot 검증)

**동기화 필요**:
- Edge 창 사용자가 닫음 → 기존 cloud 세션 `session_01Uk1DjKyJFFyerfmrmJM92s` 은 cancel 처리. 재호출 시 새 session URL 생성
- 사용자 구두 결정: "비서 일시정지하고 ultraplan 가동" / "캡처하라면 함수에 창 프론트 띄우기 추가" / "remote 복귀 시점에 비서 재가동"
- 기각 대안: "다시봐줘 버튼 자동 클릭" — 사용자가 채팅창에 직접 입력한 텍스트였음. retry 는 오직 textarea input 방식.
- watch.js screenshot 편집 중단점: L273 직후 (fg 통합 미완). L252/L267/L283 의 `await page.screenshot(...)` 세 곳 앞에 `await bringEdgeFg(page)` 호출 삽입 필요.

**다음 의도** (우선순위):
1. 압축 리줌 후 watch.js L240-290 범위 재개 — `bringEdgeFg` 헬퍼 추가
2. 비서 재시작 방법 파악 (button agent 프로세스 재기동)
3. 새 `/ultraplan refine` 재시도 (mute+fg+retry 전체 검증)
4. cloud refine 결과 수신 → plan.md §7.2 L346/L390 중복, change-impact.py 잔존 references, §9 pre-separation 정리
5. 그 후 Phase 3 → Step 1 (retrospective-guide.md 재작성) 진입

---

### 2026-04-18T02:48 KST NUDGE_1 (102% tok) — 강제 compact 핸드셰이크

- 직전 turn 에서 §7.2 Supervisor 잠정 판정 (Q1 bash통합 / Q2 4주 관찰 / Q3 R# 보조 1줄) plan.md 에 기록 완료. 사용자가 추가로 §부록 Code-Context-Packet 구조 수동 편집 (line 1-33 prepend) — 본 세션 분석 변경 없음, 이어받을 다음 세션이 §부록 인지하면 됨.
- 핸드셰이크 flag 파일 생성 + COMPACT_READY echo 직후 secretary 가 `/compact` 주입 → 압축 리줌이 progress.md + plan.md §7.2 + MEMORY.md ckpt 로 맥락 복원.
- 다음 세션 첫 행동: cloud session_014GGwaNRmFuBjhzyMtduAs9 결과 (가설 A vs B) 사용자에게 확인 요청 → §7.2 정식 채택 또는 cloud 결과 덮어쓰기 결정.

---

### 2026-04-18T02:46 KST 체크포인트 (95% tok) — `/ultraplan refine plan.md` 재호출

**상황**:
- 사용자가 `/ultraplan refine plan.md` 재호출. cloud session URL: `https://claude.ai/code/session_014GGwaNRmFuBjhzyMtduAs9` (이전 시도 동일 URL — `ruler-ul-test` 신규 psmux 세션 검증 결과 4초만에 응답).
- secretary 95% warn 넛지 도착 → 저장+계속 명령. 중지 금지.
- 현재 모델 unknown (likely Sonnet 잔존). 컨텍스트 236.7k → §E B 조건 (sonnet 누적 <100k) 미충족 → **Opus 전환 불가**.

**행동 결정**:
- cloud /ultraplan 결과 대기 + 본 세션은 **로컬 fallback (가설 B 시나리오) 잠정 판정** 을 plan.md §7.2 에 미리 기록. cloud 가 ruler 접근 가능하면 (가설 A) cloud 결과로 §7.2 덮어씀, 불가하면 (가설 B) §7.2 가 정식 결정.
- §7.1 Q1/Q2/Q3 잠정 판정은 이전 체크포인트 §동기화필요 에 이미 sketch 됨 (Q1=Cost채택 / Q2=절충안 / Q3=(a) Cost축소안). 본 턴에서 plan.md §7.2 로 정식 기록.

**다음 의도**:
- 사용자가 cloud 결과 (ruler/Button workspace) 확인 받으면:
  - 가설 A → cloud 결과로 §7.2 덮어쓰고 Phase 3 (구현) 진입 plan
  - 가설 B → §7.2 잠정 판정 정식화, Phase 2α skip 후 Phase 3 진입
- 어느 쪽이든 240k compact 후 다음 세션이 §7.2 를 baseline 으로 이어받음

**동기화 필요**:
- plan.md §7.2 작성 후 sec-msg-* 임시 저장 → 압축 리줌이 §B5 supplement 로 복원 가능
- `ruler-ul-test` 세션은 cloud 결과 확인 후 정리 대상

---

### 2026-04-18T02:44 KST 체크포인트 (93% tok)

**마지막 결정/발견**:
- Phase 1 Agent Team 3개 완료 (TA/DA/Cost) → plan.md §6.5 ACCEPT 13건 반영 / §7.1 DEFER 3건 Open
- Phase 2α ultraplan 1차 시도: cloud workspace = Button WOL Web App 에 고정. `/ultraplan refine D:/projects/ruler/plan.md` send 됐으나 원격은 Button bundle 로 workspace 설정 → `D:/projects/ruler/` 접근 불가 → 사용자에게 Paste/Cancel AskUserQuestion 팝업 → 사용자 interrupted
- 원인 가설: (A) session id 기반 repo 결정 → 새 psmux 세션 교체로 해결 / (B) Claude Code account-level workspace state 고정 (직전 button /ultraplan 호출 유산) → 로컬 수정 불가
- 가설 검증 스크립트 `/tmp/ultraplan-ws-test.sh` 실행 완료. 신규 psmux 세션 `ruler-ul-test` (cwd=D:\projects\ruler) 에서 Claude spawn + /ultraplan refine plan.md 호출. 4초만에 URL 감지
- **URL**: `https://claude.ai/code/session_014GGwaNRmFuBjhzyMtduAs9`
- **사용자 확인 대기 중**: 브라우저에서 위 URL workspace 명이 "ruler"(가설 A) 인지 "Button WOL"(가설 B) 인지

**다음 의도**:
- 사용자 브라우저 확인 결과 받으면:
  - 가설 A → handoff.sh 에 "새 세션 + 새 Claude 프로세스 스폰 + target repo cwd" 패턴 반영 (30-45분)
  - 가설 B → 로컬 수정 불가 확정, Phase 2α skip + §7.1 DEFER 3건 Supervisor 직접 판단 + Phase 3 진입
- 어느 쪽이든 이번 plan.md 의 refine 본문은 cloud 가 ruler 를 읽지 못하면 (가설 B) 받을 수 없음 → 로컬 경로로 fallback

**동기화 필요**:
- handoff.sh: 2026-04-18 Ctrl+L pre-send fix 적용 완료 (promotion-log KNOWLEDGE 엔트리). 추가로 가설 A 확인 시 세션 스폰 로직 확장 필요
- `ruler-ul-test` 세션: 검증 완료 후 `psmux kill-session -t ruler-ul-test` 로 정리 대상
- plan.md §7.1 DEFER 3건 Supervisor 선판단 (가설 B 경우 반영):
  - Q1 Python 제거: ✅ Cost 권고 (bash+jq 통합)
  - Q2 Phase A 4주 유예: ⚠️ 절충안 (구현 + 관찰 전용 4주)
  - Q3 R1~R11: ✅ (a) Cost 축소안 (부록 + BAD 시 보조 1줄)
- 원래 `btn-ruler` 세션의 interrupted /ultraplan (session_01Xp97JSt3MsbGEisXEAHG6d) 은 방치 — 브라우저에서 탭 닫기만 하면 cleanup
