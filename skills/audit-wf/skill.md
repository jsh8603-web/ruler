---
tags:
  - type/skill
  - domain/verification
  - load/trigger
name: 감사 워크플로우
description: |
  사용자가 "감사 wf", "승격 리뷰", "시스템 점검", "hook 검증", "hook 테스트",
  "정기 감사", "hook 구현" 등을 요청할 때 동작하는 스킬.
  3+1 분할 구조: hook 검증 / 승격 감사 / 시스템 정리 / 전체 감사.
---

(root: 하네스 자동 매칭 "감사 wf/승격 리뷰/시스템 점검/hook 검증")

## 목적

Claudian 역할을 수행하는 감사 전담 워크플로우.
3개 부분 감사로 분할하여 토큰 절약 + 독립 실행 지원.

**정체 (2026-04-14 명시)**: audit-wf 는 **상시 세션이 아니라 "Read 해야 할 문서 + 순서 절차"** 집합이다. 호출 주체는 (a) ruler-batch-{ts} Phase B 또는 (b) 메인 대화 세션 (사용자가 키워드 즉시 입력). 어느 쪽이든 이 skill.md 가 지시하는 Read/Phase 를 그대로 수행.

**운영 원칙 (2026-04-14)**: **자동 실행 + 요약 보고 방향**. 감사 자체는 AI 자율 수행 — 문제 발견 시 즉시 수정/승격까지 끝내고, 사용자에게는 **간결한 요약 1~2 문단**만 보고 ("N건 발견, M건 수정, K건 승격. 남은 이슈 X"). 사용자 결정 프롬프트 / 승인 질문 / 긴 리스트 덤프 **금지**. 사용자는 요약만 스캔하고 넘어간다.

**주된 자동 실행 경로 = ruler-batch Phase B**: `ruler-batch-{ts}` (Opus) 가 주간 retrospective 완료 후 Phase B 진입 조건 (B1 promotion-log 증분≥5 / B2 7일경과 / B3 Phase A rules 수정) 하나라도 true 면 같은 세션에서 이 skill 절차를 연속 실행. 발동 조건 SSOT: [`~/.claude/.ruler/patrol.md`](~/.claude/.ruler/patrol.md) §사후 Retrospective Phase B. 메인 세션 인라인 실행은 즉시 필요할 때만 보조 경로.

## 트리거 → 실행 매핑

**핵심 원칙**: 트리거에 해당하는 파일만 Read하여 토큰 낭비 최소화.

| 트리거 | Read 대상 | 내용 | 수행주기 |
|--------|----------|------|---------|
| `hook 검증` / `hook 테스트` | `hook-guard-test-plan.md` (verification/) | 현행 훅 발동+행동 검증, 테스트 케이스 | hook 변경 시 + 격주 |
| `승격 리뷰` | `audit-promotion.md` | Phase 0.5 + Log 감사 + 전파 + 메모리/품질 | 주 1회 (5건+) |
| `시스템 점검` | `audit-system.md` | 연결 검증 + stale 정리 + 보고 + 자기강화 | 격주 1회 |
| `정기 감사` / `감사 wf` | 아래 4개 순차 | 전체 실행 | 월 1회 (10건+) |
| `hook 구현` | `hook-guard-review.md` | 미구현 항목 구현 + 즉시 검증 | 필요 시 |
| `스킬 검증` | (인라인) | 전체 스킬 구조 검증 (7항목) | 스킬 변경 시 + 정기 감사 |
| `세션 감사` / `비서 효과` | skill.md 인라인 체크리스트 | audit-log 기반 세션 분석 + 비서 지표 | 주 1회 수동 |

**파일 위치**: 모두 `~/.claude/docs/verification/` 하위
- `hook-guard-test-plan.md` — 현행 훅 테스트 플랜 (settings.json 기준, 2026-04-07~)
- `audit-hook-verify.md` — 구형 Hook 검증 참조 (archive 이전 버전)
- `audit-promotion.md` — 승격 감사
- `audit-system.md` — 시스템 정리
- `promotion-audit.md` — 마스터 (포인터 + 전체 흐름)

---

## 실행 절차

### `hook 검증` / `hook 테스트`

```
1. Read `~/.claude/docs/verification/hook-guard-test-plan.md`
2. A~G절 순차 실행 (safe/research/remote/psmux/sys/scriptagent)
3. 각 섹션 체크리스트 항목 확인
4. 실패 항목은 hook-guard-review.md 레지스트리와 비교하여 원인 파악
5. 결과 요약: PASS/FAIL 항목 수 + 실패 원인
```

### `승격 리뷰`

```
1. Read `~/.claude/docs/verification/audit-promotion.md`
2. Phase 0.5: 이전 개선 검증
3. Phase 1: Promotion Log 감사 (1-1~1-4)
4. Phase 2: 상위 전파 (2-1~2-3)
5. Phase 3M: 메모리 + 품질 (인덱스, 2계층, 태그, 고아, 실행가능성)
6. 보고 템플릿에 따라 결과 출력
```

### `시스템 점검`

```
1. Read `~/.claude/docs/verification/audit-system.md`
2. Phase 3C: 연결 검증 (전파이력, CLAUDE.md, rules/, docs/)
3. Phase 3C-5: 전역 규칙 종합 감사 → Read `~/.claude/docs/verification/comprehensive-rule-audit.md` → 7-Phase(66항목) 순차 점검
4. Phase 5: Stale 정리
5. Phase 6: 보고
6. Phase 6.5~6.7: 자기강화 + 이력 축적
```

### `정기 감사` / `감사 wf` (전체)

```
1. Read `~/.claude/docs/verification/audit-promotion.md` → 실행
2. Read `~/.claude/docs/verification/audit-hook-verify.md` → 실행
3. Read `~/.claude/docs/verification/audit-system.md` → 실행
   (Phase 6에서 3개 결과 통합 보고)
4. `세션 감사` / `비서 효과` 인라인 체크리스트 → 실행
Final. Hook SSOT sync (무조건 마지막 단계) → 아래 §Phase Final 참조
```

### Phase Final — Hook SSOT sync [2026-04-14, 무조건 마지막 단계]

**원칙**: audit-wf 가 한 번 실행되면 실행 절차 **모든 단계의 맨 마지막**에 아래 훅 양방향 sync 를 고정 수행한다. Ruler Retrospective Phase B 경로로 호출됐든, `정기 감사` 전체로 호출됐든, `hook 검증` 개별로 호출됐든 — 매 invocation 당 1회 필수.

**왜 마지막인가**: 중간 단계에서 `rules/` 나 `skills/` 를 수정하면 그 변경이 새 hook 을 낳거나 기존 hook 설명/Tier 를 바꾼다. 훅을 먼저 sync 하면 나중 수정으로 또 drift — 모든 수정이 끝난 **정지 상태에서 한 번만** 맞춰야 원샷 정합성이 확보된다.

**절차**:
1. `settings.json` hook 섹션 파싱 → 등록된 hook id 집합 A
2. `~/.claude/docs/operations/hook-guard-review.md` 파싱 → 문서화된 hook id 집합 B
3. 양방향 diff:
   - **A \ B** (settings.json 에만 있음) → hook-guard-review.md 에 행 추가 (id + 설명 + Tier + 소속 규칙)
   - **B \ A** (문서에만 있음) → "구현 누락" 경고 + Tier 에 따라 즉시 구현 또는 drop
   - **A ∩ B** 이지만 설명/Tier 불일치 → **`hook-guard-review.md` 가 SSOT**. 본 문서 기준으로 settings.json 주석 또는 문서 설명 갱신
4. 동기화 후 `decisions.jsonl` 또는 audit 리포트에 `hook_sync: {added:N, removed:N, updated:N}` 기록

**SSOT 원칙**: 충돌 시 항상 `hook-guard-review.md` 가 우선. settings.json 은 runtime 설정이지만 "왜 이 hook 이 존재하는가 / 어느 규칙 소속인가 / Tier 는 무엇인가" 의 semantic 은 hook-guard-review.md 가 관할한다.

**호출처**:
- Ruler Retrospective Phase B — Phase B skip 시에도 **생략 불가** (patrol.md §Phase B 실행 순서 Final Step 참조)
- `정기 감사` / `감사 wf` — 위 실행 절차 Final 단계
- `hook 검증` / `hook 테스트` 단독 호출 — 해당 절차 맨 끝에 append

### Phase Final-B — Patrol ↔ Rules sync [2026-04-16, Phase Final 직후]

**원칙**: Phase Final (Hook SSOT sync) 완료 후, 규칙 파일 변경이 patrol 체크에 반영되었는지 교차 검증.

**절차**:
1. `decisions.jsonl` 에서 최근 `file:` 가 `rules/` 또는 `skills/` 인 항목 수집
2. 각 항목에 대해: 해당 규칙을 감시하는 patrol 체크 식별 (`grep -l`)
3. 규칙 내용과 patrol 체크 기준의 불일치 감지 → 수정안 작성
4. `decisions.jsonl` 에 `action:"rule_patrol_sync"` 기록
5. 불일치 N건 + 수정 M건 요약 보고

**SSOT**: 규칙 파일(`rules/`, `skills/`)이 우선. patrol 체크는 규칙 파일의 감시 구현이므로, 규칙 변경 시 patrol 쪽을 맞춘다.

### `세션 감사` / `비서 효과` [⚠️ 2026-04-14 이관됨 — Ruler Retrospective 로 흡수]

**이관 이유**: 기존 "주 1회 수동" 루틴은 사용자 책임전가. Ruler retrospective 가 이미 7일 자동 트리거 + 결정론적 R1~R11 임계 기반 + batch(Opus) 자동 실행 인프라 보유 → 중복 제거 + 자동화 궤도 편입.

**새 경로**:
- **자동**: `.ruler/` patrol 이 7일 주기로 자동 retrospective 발동 — 사용자 개입 0
- **수동 (급할 때)**: 메인 대화 세션에 `주간리뷰` / `룰러 리뷰` / `retrospective` 입력 → 메인 세션이 직접 `ruler-batch-{ts}` 스폰

**상세**:
- 소스 카탈로그 (비서 5지표 포함 10종): [`~/.claude/.ruler/patrol.md`](~/.claude/.ruler/patrol.md) §사후 Retrospective
- R11 (비서 미해결률 ≥ 0.5 → elif 체인 확장 task): 같은 파일 §검토 기준 표
- 수동 트리거 5-step 프로토콜: [`~/.claude/skills/ruler-wf/skill.md`](~/.claude/skills/ruler-wf/skill.md) §5b Retrospective 수동 트리거
- 산출물: `.ruler/retrospective/{YYYY-MM-DD}_plan.md` + `.ruler/preflight-rules.md` append + `patrol.md` C-check 판정 모드 조정

**audit-wf 잔존 책임**: 지식 승격 (promotion-log → rules/ memory/) + hook/skill 구조 검증 + 시스템 인덱스 연결. **사용자 개입 없이 자동 실행 + 요약 보고 방향** — 승격/수정은 자율 수행, 결과를 간결한 요약으로 보고 (사용자가 "잘 했네" 확인만 하는 수준). "사람 결정 게이트" 아님.

### `스킬 검증`

```
1. ~/.claude/skills/*/ 전체 디렉토리 순회
2. 각 스킬에 대해 7항목 검증:
   (1) skill.md 파일 존재
   (2) YAML frontmatter 시작 (첫 줄 ---)
   (3) name: 필드 존재
   (4) description: 필드 존재
   (5) tags: 필드 존재 (WARN)
   (6) 마크다운 제목(# 또는 ## ) 존재
   (7) SKILL_INDEX.md에 스킬명 등록 여부
3. 결과 리포트 출력 (PASS/FAIL/WARN 카운트)
4. FAIL 항목 즉시 수정 또는 pending 등록
```

**인라인 실행 명령** (Bash):
```bash
for dir in "$HOME/.claude/skills"/*/; do
  name=$(basename "$dir"); f="$dir/skill.md"
  [ ! -f "$f" ] && echo "[FAIL] $name: skill.md 없음" && continue
  head -1 "$f" | grep -q '^---' || echo "[FAIL] $name: frontmatter 없음"
  grep -q '^name:' "$f" || echo "[FAIL] $name: name 필드 없음"
  grep -q '^description:' "$f" || echo "[FAIL] $name: description 없음"
  grep -q '^tags:' "$f" || echo "[WARN] $name: tags 없음"
  grep -q '^#\{1,2\} ' "$f" || echo "[FAIL] $name: 제목 없음"
  grep -q "$name" "$HOME/.claude/skills/SKILL_INDEX.md" || echo "[FAIL] $name: INDEX 미등록"
done && echo "=== 검증 완료 ==="
```

### `hook 구현`

```
1. Read `~/.claude/docs/operations/hook-guard-review.md`
2. 미구현(PLANNED) 항목 식별 → 중요도순 구현
3. 각 hook 구현 후 즉시 테스트 (3회+ PASS)
4. hook-guard-review.md 상태 갱신
```

---

## 사전 조건

- `~/.claude/memory/promotion-log.md` 존재
- Obsidian 프로젝트 또는 볼트 디렉토리에서 실행

## 구현 원칙 (hook 구현 시)

- 단일 스크립트 유지 (promotion-signal.js에 모드 추가)
- bash fast-path: PreToolUse는 `test -f && grep -q` → node 필요 시만
- Claudian skip: guard/inject에 감사 프로젝트 + 볼트 체크 유지
- 교차프로젝트 격리: source_project 태그 유지
- timeout: 시그널 수집 5초, analyze 10초

## 감사 소스

| 소스 | 경로 | 수집 방식 | 내용 |
|------|------|----------|------|
| Promotion Log | `~/.claude/memory/promotion-log.md` | 수동/훅 기록 | ERROR, R/K/P 엔트리 |
| Audit Log | `~/.claude/audit-log/{날짜}.jsonl` | 자동 (scout-and-act.sh) | 세션 이벤트, JSONL 감사, git 커밋 |
| Session Registry | `D:/projects/button/agent/.secretary/.session-registry.txt` | 비서 자동 기록 | 세션↔프로젝트 매핑 |
| JSONL 원본 | `~/.claude/projects/{프로젝트}/{sessionId}.jsonl` | Claude Code 자동 기록 | 전체 도구호출, 편집파일, 명령 이력 |

> `~/.claude/audit-log/`는 scriptagent의 비서 스크립트가 3분 주기로 자동 수집하는 3종 소스(capture-pane, git log, JSONL)의 구조화 기록이다. 감사wf는 이를 promotion-log와 교차 대조하여 분석한다.

## 공통 참조

- `~/.claude/hooks/promotion-signal.js` — 단일 hook 스크립트
- `~/.claude/docs/operations/hook-guard-review.md` — Hook 중앙 레지스트리
- `~/.claude/docs/verification/comprehensive-rule-audit.md` — 전역 규칙 종합 감사 (7-Phase 66항목)
- `~/.claude/memory/promotion-log.md` — Promotion Log 데이터
- `~/.claude/memory/tools/claude-code-hooks.md` — hook 구조/제약 노하우
