---
type: ruler-patrol-tier-c
version: 1
date: 2026-04-16
tags: [ruler, patrol, tier-c, checklist]
---

# Tier C — 10사이클마다 (30분)

> 본체: [`~/.claude/.ruler/patrol.md`](~/.claude/.ruler/patrol.md)

## ⛔ pending/ 보호 규칙 (전 C-check 공통)

> **pending 파일은 batch 처리 전까지 삭제/이동 금지.**
>
> 1. `~/.claude/.ruler/pending/` 내 파일(fp-adjust 포함)은 **batch 세션이 처리**할 때만 `resolved/`로 이동한다.
> 2. patrol 순찰(Tier A/C)에서 pending 파일을 "중복", "오래됨", "불필요" 등의 이유로 **임의 삭제/이동하지 않는다**.
> 3. fp-adjust 파일은 **event 당 1 파일 덮어쓰기** (2026-04-17 재설계). `fp-adjust-{eventName}.md` 형식, 타임스탬프 누적 없음. `pending count 에서 제외` (secretary.js L1476 필터) → batch threshold 무관.
> 4. pending 파일 생성/삭제/이동 **모든 조작**은 `decisions.jsonl`에 1줄 기록 필수. 미기록 조작은 규칙 위반.
> 5. 허용된 삭제/이동 경로 (이외 금지):
>    (a) batch 세션(`ruler-batch-*`)이 처리 완료 후 `resolved/`로 이동
>    (b) fp-adjust-*.md 에 한해 ruler tier C `C_fp_ttl` 가 24h+ stale 판정 시 삭제 (FP rate 회복 자연 청소)

## C3 — Symmetric fix propagation
- **검사**: `git log --since="6 hours ago" D:/projects/button/agent/secretary.js` 최근 6시간 커밋
- **heuristic**: 변경 1파일 + diff 에 `WF_SESSION_NAMES` / `WF_SESSION_RE` 등장 → symmetric 매칭 필요성 높음
- **조치**: T2 그룹 (semantic 판단)
- **판정 모드**: batch-only

## C5 — Dead reference 감지
- **대상**: `~/.claude/rules/*.md`, `~/.claude/docs/**/*.md`, `~/.claude/skills/**/skill.md`, `~/.claude/CLAUDE.md`
- **패턴**: `\]\((~/.claude/|D:[/\\]projects[/\\]|G:[/\\]내\s드라이브)[^\s)"']+\.(md|js|sh|json)\)` (마크다운 링크 문법 `](...)` 내부만 매칭)
- **검증**: 각 경로 `test -e`
- **조치**: T1 보고 + T2 그룹 링크 수정
- **판정 모드**: sonnet-decide (감지) / batch-only (수정)

## C6 — Index 동기화 감사
- **인덱스 7개**: MEMORY.md / DOMAIN_INDEX.md / PATTERN_INDEX.md / OPERATIONS_INDEX.md / VERIFICATION_INDEX.md / PC_TOOLS_INDEX.md / SKILL_INDEX.md
- **검사**: 관할 폴더 `.md` 목록 ↔ 인덱스 포인터 라인 개수 비교, 누락 리스트업
- **조치**: T2 포인터 자동 추가
- **판정 모드**: sonnet-decide

## C7 — Session-note read-only 검증
- **스캔**: `~/.claude/.session-notes/*.md`
- **검사**: `attrib "{path}"` 출력 `R` 플래그
- **조치**: 해제된 파일 → T1 `attrib +R "{path}"`
- **판정 모드**: sonnet-decide

## C8 — Frontmatter 검증
- **스캔**: `~/.claude/**/*.md` (archive / skills/templates / .session-notes 제외)
- **검사**: 첫 5줄 `---` frontmatter + `tags:` 필드 (필수). `date:` 권장 (기존 파일 grandfather)
- **VaultVoice 추가 검증** (v6): `99_vaultvoice/` 경로 또는 vaultvoice 태그 파일 → `title:`, `aliases:` 필드 존재 필수 (vaultvoice.md §frontmatter 필수)
- **조치**:
  - `tags:` 누락 → T2 자동 주입 (기본값=폴더명)
  - `date:` 누락 (mtime > 2026-04-14T10:30Z 신규 파일만) → T2 자동 주입
  - VaultVoice `title:`/`aliases:` 누락 → T2 pending (피드에서 파일명이 제목으로 표시됨)
- **판정 모드**: sonnet-decide

## C9 — promotion-log ERROR 4필드 완결성
- **대상**: `~/.claude/memory/promotion-log.md` `### E{n}. {slug}` 블록
- **검색**: `grep -nE "^### E[0-9]+" ~/.claude/memory/promotion-log.md`
- **필수 필드**: 상황 / 원인 / 해결 / 방지책 각 20자+
- **추가**: E-number 중복 검사
- **조치**: T2 그룹 (원기록자 보강, 자동 완성 위험)
- **판정 모드**: batch-only

## C10 — Hook/Guard SSOT 역검증
- **양방향**: `hook-guard-review.md` 표 ↔ `settings.json` `hooks.*`
- **Drift**: diff 저장 → T2 pending
- **판정 모드**: sonnet-decide (감지) / batch-only (해결)

## C11 — Trigger 키워드 일관성
- **소스**: `~/.claude/CLAUDE.md` Auto Triggers
- **타겟**: `~/.claude/skills/*/skill.md` "트리거" 섹션
- **매칭**: CLAUDE.md 키워드 N개 ↔ skill 파일 N개 모두 언급
- **Drift**: T2 pending
- **판정 모드**: sonnet-decide

## C12 — Deny log 스캔 [guard-watchdog 흡수]
> ⚠️ **event-rules.yaml `guard_deny_burst` 로 치환 대기중** (enabled:false, hook-metrics.jsonl mtime=2026-04-07 stale 선결).
> 재활성 시 이 섹션 삭제 + event 로 이관.

- **명령**: `tail -100 ~/.claude/hook-metrics.jsonl | grep "guard-deny"`
- **교착 판정**: 동일 세션 3분 내 3건+
- **조치**: secretary 자동해소 확인 → T1 보고 / 미해소 → T2 그룹 + **Urgent**
- **판정 모드**: batch-only

## C13 — settings.json backup-before-edit 검증 [guard-unlock 흡수]
- **트리거**: `.ruler/rollback/settings.json-*.bak` 존재 시 최근 Edit 후 백업 확인
- **검사**: state.md `last_settings_edit` 조회
- **Edit 있음 + 백업 없음**: T1 소급 백업 생성
- **판정 모드**: sonnet-decide (settings.json 자체 Edit 은 opus_only)

## C14 — plan.md / progress.md 완료 아카이브 (tiered signals)
- **스캔**: `D:/projects/*/plan.md` + 같은 경로 `progress.md`
- **원칙**: "테스트 제외 마지막 실질 step 이 구현되었는가" 가 최종 기준.

**Tier 1 — 싼 신호 (매 plan 필수)**
- progress.md `[x]` / `[ ]` 카운트 (테스트 제외)
- progress.md 없으면 plan.md 마지막 실질 step 식별
- `git log --oneline -20` 주제 매칭
- plan.md mtime

**판정 테이블**:

| 상태 | 신호 | 판정 | 티어 |
|---|---|---|---|
| 100% `[x]` | — | **Done** | T1 아카이브 |
| mixed | 24h 내 관련 커밋 | **Active** | skip |
| mixed | 24h+ 없음, mtime 4h+ | **Abandoned 의심** | T2 |
| 마지막 step 주제 grep 매칭 | — | **Done** | T1 아카이브 |
| 키워드 미매칭 + mtime 4h+ | — | **Abandoned 의심** | T2 |
| 0% / 갓 작성 | mtime 4h 이내 | Fresh | skip |

**Living-doc 감지**: plan.md 500줄+ + 첫 헤더 프로젝트명 수준 + `Step N:` 5개 미만 + progress.md 가 세션 누적 로그 성격 → skip.

**아카이브 절차 (T1)**:
- slug = plan.md 첫 `# ` 헤더 → kebab-case
- date = plan.md mtime
- `mkdir -p {proj}/.plan-archive/`
- `mv plan.md .plan-archive/plan-{date}-{slug}.md`
- progress.md 있으면 동시 이동
- **최초 실행 전 사용자 dry-run 확인 필수**

- **판정 모드**: sonnet-decide (Tier 1) + batch-only (Tier 2 semantic)

## C15 — Classifier Self-Learning
- **트리거**: `.classifier-audit/classifier-*.jsonl` 내 동일 `unknown:X` 5회+ & 2일+ span & `.last-classifier-review` mtime > 24h
- **명령**: `bash ~/.claude/.ruler/scripts/review-classifier.sh`
- **통과**: 제안 0건 OR dry-run `decisions.jsonl` append
- **live 전환 gate**: phase 2 커밋 존재 AND agent uptime ≥ 7일 AND audit 총 ≥ 200건
- **판정 모드**: batch-only (secretary.js 수정 경로 — opus_only)

## C18-lite — Hook 인프라 발동 검증 (축소판)
- **목적**: hook/guard 가 실제로 발동하는지 in-production 행동 검증.
- **남은 4항목** (hook 인프라 발동 — 비서가 커버 못하는 영역):

| 상황 | 기대 동작 | 확인 |
|---|---|---|
| auto-compact | `session-start-resume.sh FIRE` | `hook-debug-early.log` grep |
| 사용자 프롬프트 | `routing-context.sh prompt` SILENT/NUDGE | hook-debug-early.log |
| bash 첫 `sleep N≥2` | Guard block | audit-log `bash_guard_sleep_blocked` |
| non-project plan.md Write | Guard block | audit-log `guard_block_file_standards` |

- **방법**: 최근 30분 `hook-debug-early.log` + audit-log tail 에서 상황 trigger 감지 + window 내 기대 동작 로그 부재 = **MISS**.
- **제외**: worker/verifier/healer/strategic.
- **판정**: MISS 1건+ → pending 생성. 정상 = 1줄 요약.
- **판정 모드**: sonnet-decide (표 대조) / batch-only (MISS 해석)

## C19 — 라우팅 판정 수행 여부 (B1)
- **검사**: 활성 세션의 최근 audit-log (jsonl_audit) 에서 tool 사용 패턴 확인 + 해당 세션 JSONL tail 에서 `[라우팅]` 패턴 검색
- **대상**: progress.md 존재하는 세션 (plan 세션만)
- **기준**: plan 세션에서 step 전환 시 `[라우팅]` 출력이 있어야 함
- **판정 방법**: JSONL 대화 로그에서 `[라우팅]` 패턴 grep → 없으면 위반 후보
- **조치**: T2 pending (라우팅 누락은 세션의 모델 선택 정확도에 영향)
- **판정 모드**: batch-only (대화 맥락 해석 필요)

## C20 — Sonnet-executable 5항목 검증 (B2-4)
- **검사**: `D:/projects/*/progress.md` 에서 `model: sonnet` step 추출
- **기준**: 각 sonnet step 에 5항목 (파일경로, 라인/심볼, before/after, 경계, 완료기준) 존재
- **방법**: plan.md 에서 해당 step 블록 Read → 5항목 체크리스트 대조
- **조치**: 3/5 이상 누락 → T2 pending (`model: opus` 재분류 권고)
- **판정 모드**: batch-only (plan.md 내용 해석)

## C21 — Haiku 위임 판정표 준수 (B4)
- **검사**: audit-log `registry_model_refresh` 에서 `haiku` 모델 전환 감지 + 직전 task 유형 대조
- **기준**: haiku 전환 시 haiku-delegation.md 6항목 체크리스트 충족 여부
- **방법**: model=haiku 전환된 세션의 직전 audit-log 패턴 분석 (tool 유형, 에러 유무, task 파일 존재)
- **제외**: haiku-task.sh 경유한 정상 위임 (마커 확인)
- **조치**: T2 pending (위임 판정표 우회 또는 오용)
- **판정 모드**: batch-only (task 유형 해석)

## C22 — 다파일 Edit 후 plan 부재 (B7-1)
- **검사**: 최근 30분 audit-log `jsonl_audit` 이벤트에서 `edited=` 필드 파싱
- **기준**: 세션당 3개+ 파일 Edit + 해당 세션 CWD 에 plan.md 부재 → 위반
- **제외**: `.ruler/` 경로 Edit (ruler 자체 작업), `memory/` 경로 Edit
- **방법**: jsonl_audit `context` 필드의 `edited=` CSV 파싱 → 고유 파일 수 집계
- **조치**: T2 pending (소급 plan 작성 또는 규모 확인)
- **판정 모드**: sonnet-decide (regex 파싱 가능)

## C23 — psmux send-keys MSYS 경로 검출 (B8)
- **검사**: audit-log 또는 hook-debug-early.log 에서 `send-keys` 명령 tail
- **기준**: send-keys 내용에 `/c/Users` 또는 `/d/projects` 같은 MSYS2 경로 포함 → 위반
- **방법**: `grep -E 'send-keys.*(/[cd]/[A-Z])' audit-log` 또는 hook 로그
- **조치**: T1 보고 (cmd.exe 세션에 MSYS 경로 전송 시 실패)
- **판정 모드**: sonnet-decide (regex 검출)

## C24 — 자원 소모 사전 동의 검증 (B9-1)
- **검사**: 최근 30분 audit-log `jsonl_audit` 에서 Agent 스폰 패턴 (tools=Agent) 집계
- **기준**: 세션당 3개+ Agent 스폰 + 직전 대화에서 사용자 승인 키워드 부재 → 위반 후보
- **방법**: jsonl_audit `context` 필드의 `tools=` 에서 Agent 카운트
- **제외**: wf 세션 (Supervisor 가 Agent 스폰하는 것은 정상)
- **조치**: T2 pending (사용자 동의 없이 대량 Agent 스폰 = CLAUDE.md 최우선 규칙 위반)
- **판정 모드**: batch-only (대화 맥락 해석 — 승인 키워드 판단)

## C25 — 전역 규칙 무단 편집 검증 (B9-2)
- **검사**: 최근 30분 audit-log `jsonl_audit` 에서 `edited=` 필드 중 `rules/*.md` 또는 `docs/operations/*.md` 경로 감지
- **기준**: 규칙 파일 Edit + 직전 대화에서 사용자 승인/지시 부재 → 위반
- **제외**: ruler/ruler-batch 세션 (ruler 는 T2 Gate 통과 의무 있으나 별도 프로토콜)
- **조치**: T1 보고 + T2 pending (전역 규칙 일관성 훼손 위험)
- **판정 모드**: batch-only (대화 맥락 — 사용자 지시 존재 판단)

## C26 — commit 감지 정확도 (A6)
- **검사**: `git log --since="30 minutes ago" --oneline D:/projects/button` ↔ audit-log `jsonl_audit` 의 `edited=` 비교
- **기준**: git 에 커밋이 있는데 audit-log 에 해당 파일의 Edit 기록이 없으면 → 비서 commits.js 감지 누락
- **방법**: git log 파싱 → 변경 파일 목록 → audit-log 의 edited 파일과 교차
- **조치**: T2 pending (commits.js 감지 로직 점검)
- **판정 모드**: sonnet-decide (git + audit 대조)

## C27 — revival 오탐 (A10)
- **검사**: audit-log `session_revived` 이벤트 + 해당 세션의 직전 상태
- **기준**: session_revived 직후 세션이 실제로 작업 중이었으면 → 오탐
- **방법**: session_revived 이벤트 타임스탬프 직전 60s 내 jsonl_audit 존재 → 세션이 활성이었음 → 불필요한 revival
- **조치**: T2 pending (resume.js revival threshold 점검)
- **판정 모드**: sonnet-decide (시간대 교차 비교)

## C28 — VaultVoice 규칙 준수 (B6)
- **검사 1 (미러링)**: Pi SSH 가용 시 `ssh pi@{ip} ls ~/gdrive/99_vaultvoice/` 실행
- **기준 1**: Obsidian (~/.claude/) 에 VaultVoice 관련 파일 존재 시 Pi 에도 동일 파일 존재해야 함
- **방법 1**: Pi SSH 접속 → 파일 목록 대조. SSH 불가 시 skip.
- **검사 2 (파일명 패턴, v6 추가)**: Pi `99_vaultvoice/` 또는 로컬 VaultVoice 파일명이 `YYYY-MM-DD_HHMMSS_type.md` 형식 준수
- **기준 2**: `^\d{4}-\d{2}-\d{2}_\d{6}_\w+\.md$` 패턴 매칭. 미준수 파일 = VaultVoice 피드에서 필터 누락
- **방법 2**: `ls` 출력을 정규식 매칭. 패턴 미준수 파일 리스트업.
- **조치**: T2 pending (Pi 미러링 누락 / 파일명 수정)
- **판정 모드**: batch-only (SSH 가용성 + 파일 대조 + 정규식 매칭)

## C29 — 파일 배치 규칙 검증 (B2)
- **검사**: `~/.claude/` 하위 최근 24시간 내 생성된 `.md` 파일 (`find ~/.claude -name "*.md" -newer /tmp/c29-marker -not -path "*/archive/*"`)
- **기준**: `file-standards.md` 폴더 배치 기준표에 따라 올바른 폴더에 위치해야 함
  - `rules/` = 전역 강제 규칙
  - `docs/domain/` = 도메인 상세
  - `docs/patterns/` = 반복 패턴
  - `docs/operations/` = 운영 절차
  - `docs/verification/` = 감사/검증
  - `memory/` = 주제별 지식
  - `skills/` = 스킬 파일
- **방법**: 신규 파일의 frontmatter `tags` 에서 유형 추정 → 폴더 매칭 대조
- **조치**: T2 pending (파일 이동 또는 폴더 재배치)
- **판정 모드**: batch-only (태그 ↔ 폴더 의미 해석)

## C30 — remote 세션 Guard 검증 (B5 + C1)
- **검사**: hook-debug-early.log 에서 remote 세션의 `EnterPlanMode` / `AskUserQuestion` 호출 시도 탐색
- **기준**: `.remote-session` 플래그 존재 시 두 도구 모두 Guard 차단 필수
- **방법**:
  1. `test -f ~/.claude/.remote-session` → remote 세션 여부 확인
  2. remote 세션이면: `grep -E 'EnterPlanMode|AskUserQuestion' ~/.claude/hook-debug-early.log` → Guard block 로그 존재 확인
  3. Guard block 없이 도구 호출 성공 로그 있으면 → 위반
- **조치**: T1 보고 (Guard 미작동은 UX 장애 직결)
- **판정 모드**: sonnet-decide (regex 감지)

## C31 — WebSearch/WebFetch Guard 검증 (C1)
- **검사**: hook-debug-early.log 에서 `WebSearch` / `WebFetch` 호출 로그 탐색
- **기준**: PreToolUse hook 이 웹 도구 호출 시 필요에 따라 차단/경고해야 함
- **방법**:
  1. `grep -E 'WebSearch|WebFetch' ~/.claude/hook-debug-early.log | tail -10`
  2. 호출 기록 존재 시 Guard 응답 (allow/block/warn) 확인
  3. Guard 응답 없이 호출 성공 → hook 미등록 또는 미발동
- **검증 보조**: `settings.json` 에서 PreToolUse matcher 에 WebSearch/WebFetch 등록 확인
- **조치**: T2 pending (hook 미등록 시 settings.json 수정)
- **판정 모드**: sonnet-decide (로그 + settings.json 파싱)

## C32 — Stop hook 등록 및 존재 검증 (C7)
- **검사**: Stop hook 인프라 존재 확인 (외부 관측 불가 → 등록/파일 수준 검증)
- **기준**: settings.json 에 Stop hook 등록 + 실행 스크립트 존재 + 실행 가능
- **방법**:
  1. `settings.json` 에서 `"Stop"` 이벤트 등록 확인 (`jq '.hooks.Stop' ~/.claude/settings.json`)
  2. 등록된 스크립트 경로의 `test -x` 확인
  3. 스크립트 내용 Read → 기대 동작 (알림/로그) 로직 존재 확인
- **한계**: 실제 Stop 이벤트 발동은 관측 불가 — 등록+파일+로직 3중 확인으로 대체
- **조치**: T2 pending (hook 미등록 또는 스크립트 부재)
- **판정 모드**: sonnet-decide (파일 존재 + JSON 파싱)

## C33 — psmux 메시지 Bash 도구 경유 검증 (B8)
- **검사**: audit-log 에서 psmux send-keys 가 Bash 도구(tool call) 경유했는지 확인
- **기준**: CLAUDE.md "psmux 메시지는 반드시 Bash 도구로 실행. 텍스트 출력은 전달되지 않는다."
- **방법**:
  1. audit-log `jsonl_audit` 의 `tools=` 필드에서 Bash 호출 추출
  2. Bash 명령 중 `psmux send-keys` 포함 여부 확인
  3. psmux 관련 메시지가 Bash 도구 외부 (텍스트 출력만) 로 시도된 흔적 감지
- **제외**: secretary.js 내부 sendDirect/sendWithFile (비서 코드 경유, 규칙 대상 아님)
- **조치**: T2 pending (에이전트가 텍스트로 psmux 명령 출력하면 전달 안 됨)
- **판정 모드**: batch-only (대화 맥락 해석 — 텍스트 vs tool call 구분)

---

## Blocker 대기 프로토콜

ruler 가 hook/script/규칙을 수리할 때, 해당 기능에 의존하는 agent 세션에 "대기" → "재개" 를 통보하는 프로토콜.

### 흐름

```
1. 위반 감지 (이벤트 패트롤 또는 C-check)
2. 규칙/인프라 교정이 필요한 경우:
   a. ruler-notify.sh --mode blocker → 해당 세션에 "수리 중, 대기" 통보
   b. blocker 상태 파일 생성 (~/.claude/.ruler/state/blockers/{target}-{key}.blocker)
3. ruler 가 규칙 문서/스크립트 수정 (T2 그룹 또는 batch)
4. 수정 완료 후:
   a. ruler-notify.sh --mode unblock → "수리 완료, 재개 OK" 통보
   b. ruler-notify.sh --mode rule-fix --cite {경로} → "규칙 강화됨, 다시 Read" 통보
   c. blocker 상태 파일 자동 제거
```

### Race 방어

- agent 가 blocker 중 같은 기능을 재시도하면 → 다음 사이클에서 blocker 파일 존재 감지 → 재통보 (idempotent)
- blocker 파일에 TTL 없음 (ruler 가 unblock 할 때만 제거). 30분+ stale blocker 는 Tier C 에서 경고.

### 교정 범위 (사용자 확정)

- ruler 가 손대는 것: **규칙 문서, 스크립트, hook 설정** (agent 의 작업 흐름은 건들지 않음)
- 교정 작업은 대부분 **T2** (어떤 규칙이 왜 위반됐는지 분석 + 해당 규칙 보강 → semantic 판단 필요)
- T1 가능: auto_fix 지정된 것만 (현재 `flag_stale_detected` rm만)

### ruler-notify.sh 모드

| 모드 | 용도 | blocker 상태 |
|---|---|---|
| `violation` (기본) | 위반 사실 통보, 규칙 준수 요청 | — |
| `blocker` | 수리 중, 대기 요청 | 생성 |
| `unblock` | 수리 완료, 재개 OK | 제거 |
| `rule-fix` | 규칙 강화 완료, 다시 Read 요청 (`--cite` 로 경로 전달) | — |

---

## 이벤트 이관 현황

| C# | 항목 | 이벤트 | 상태 | 비고 |
|---|---|---|---|---|
| C2 | Home cwd 오염 스윕 | `home_cwd_pollution_detected` | **삭제됨** | v3 |
| C4 | Flag staleness 스윕 | `flag_stale_detected` | **삭제됨** | v3 |
| C12 | Deny log 스캔 | `guard_deny_burst` | **pending** | hook-metrics.jsonl 선결 |

v2/v3 이관 후보: C6→index_drift / C7→session_note_writable / C8→md_frontmatter_missing / C9→promo_error_incomplete / C10→hook_ssot_drift / C11→trigger_keyword_drift / C13→settings_edit_no_backup

---

## C_memory — 메모리 위생 순찰

> 설계 SSOT: `D:\projects\button\plan.md` §D (Memory System Redesign v2)

### 순찰 범위 (Scope)

**C_memory 대상 = 세션 시작 시 자동 로드되는 MEMORY.md 인덱스 라인만.** 개별 `.md` 문서 파일은 E5/E8 경로 존재 확인 외에는 건드리지 않는다.

| # | 경로 | 자동 로드 | 순찰 대상 |
|---|------|-----------|-----------|
| 1 | `~/.claude/projects/*/memory/MEMORY.md` | **YES** (세션 시작) | **1차 순찰 대상** |
| 2 | `/d/projects/*/memory/MEMORY.md` | NO (프로젝트 내부) | 존재 시 참조만 |
| 3 | `~/.claude/memory/MEMORY.md` | **NO** (참고용) | E1-E10 + C1-C6 전부 적용 (비자동로드라 영구 항목 공격적 정리) |

**핵심 원칙**: 전역 MEMORY.md(#3)도 E1-E10 + C1-C6 순찰 대상이지만, 자동 로드되지 않으므로 영구 항목은 **공격적 정리** (CLAUDE.md/코드에 이미 반영된 내용, 프로젝트 특화 내용, 순수 참고용 research → 삭제). 자동 로드되는 프로젝트별 MEMORY.md(#1)는 **보수적 정리** (실제 사용 중인 feedback/reference 보존).

### 순찰 경로 열거 (실행 시)

```bash
# 1차: 프로젝트별 (자동 로드)
ls ~/.claude/projects/*/memory/MEMORY.md 2>/dev/null
# 2차: D: 프로젝트 내부
ls /d/projects/*/memory/MEMORY.md 2>/dev/null
# 3차: 전역 (참고용 — ckpt만 순찰)
ls ~/.claude/memory/MEMORY.md 2>/dev/null
```

### 사전 조건

- MEMORY.md 수정 전 `.memory-lock` 파일 생성 → 완료 후 삭제 (C6 동시접근 방지)
- 활성 세션 0개일 때만 실행 (보수적 접근)

### 영구 메모리 (ckpt 없는 줄) — E1~E10

| # | 검증 | 방법 | 조치 |
|---|------|------|------|
| E1 | 중복 | description 유사도 비교 | 병합 |
| E2 | 고아 파일 (인덱스 없음) | `memory/*.md` vs MEMORY.md 교차 | 인덱스 추가 or 삭제 |
| E3 | 고아 인덱스 (파일 없음) | MEMORY.md 포인터 vs 실제 파일 교차 | 인덱스 줄 제거 |
| E4 | archived인데 인덱스에 남음 | frontmatter `status: archived` 체크 | 인덱스에서 제거 |
| E5 | stale reference | `related-files` 경로 `ls` 존재 확인 | archive 후보 |
| E6 | stale project | `related-plan` → `.plan-archive/` 확인 | archive |
| E7 | 모순 feedback | 같은 주제 두 항목 비교 | 최신 유지 |
| E8 | 삭제된 코드 참조 | `related-files` 파일 존재 확인 | stale 후보 |
| E9 | frontmatter 누락 | 파싱 | 포맷 보정 |
| E10 | 인덱스 과잉 | 프로젝트별 줄 수 > 20 | 정리 실행 |

- **판정 모드**: E1-E4, E9-E10 = sonnet-decide (기계적). E5-E8 = batch-only (의미 판단).
- **E5 실행 방법**: `related-files` 배열의 각 경로를 `test -e` → 없으면 stale 후보. 파일이 rename/이동일 수 있으므로 즉시 삭제하지 않고 T2 pending.
- **전역 MEMORY.md 영구 항목 정리 기준**: 전역(`~/.claude/memory/MEMORY.md`)은 자동 로드되지 않으므로 영구 항목은 최소화. CLAUDE.md/코드에 이미 반영된 내용, 특정 프로젝트에만 해당하는 내용, 순수 참고용(research 등)은 적극 삭제. PBI/ODBC 등 여러 프로젝트에서 공유되는 도구 노하우만 유지.

### 체크포인트 (ckpt 마커 있는 줄) — C1~C6

| # | 검증 | 방법 | 조치 |
|---|------|------|------|
| C1 | 세션 종료 + 커밋 존재 | registry liveness + `git log --grep` (ckpt 키워드) | 삭제 |
| C2 | 세션 종료 + 커밋 없음 | registry | stale 후보 (내용 검토 후 판단) |
| C3 | 같은 세션 복수 ckpt | 세션명/시각 비교 (`[ckpt-...:세션명]`) | 최신만 유지 |
| C4 | 세션 살아있음 | registry liveness 체크 | **skip** (건드리지 않음) |
| C5 | 24h+ 경과 | 시각 체크 | 삭제 (최종 안전망) |
| C6 | 동시 접근 방지 | `.memory-lock` 파일 or 활성 세션 0 체크 | 충돌 방지 |

- **C4 > C5 우선**: 세션이 살아있으면 24h 넘어도 삭제 안 함.
- **Registry liveness**: `.secretary/.session-registry.txt` 에서 세션명 조회 → `psmux ls` 에 존재 확인.
- **ckpt 형식**: `[ckpt-YYYYMMDDHHMM:세션명]`. 세션명 없는 레거시 형식도 처리 (세션명 없으면 C4 skip 불가 → C5 24h 안전망만 적용).
- **판정 모드**: C1, C3, C5 = sonnet-decide (기계적). C2 = batch-only (의미 판단). C4 = 즉시 skip. C6 = 사전 조건.

---

## C_fp_ttl — fp-adjust-*.md 24h TTL 청소 (2026-04-17 신설)

> 배경: secretary 가 event 당 1 파일 덮어쓰기 (`fp-adjust-{eventName}.md`). FP rate 회복 (threshold 미달) 시 secretary 가 더 이상 덮어쓰지 않음 → mtime 고정 → 이 체크가 24h+ stale 파일을 삭제해 자연 청소.

### 검사

- 대상: `~/.claude/.ruler/pending/fp-adjust-*.md` 전부 (`resolved/` 하위 제외)
- 기준: 파일 mtime 이 24h+ stale
- 방법: `find ~/.claude/.ruler/pending -maxdepth 1 -name 'fp-adjust-*.md' -mmin +1440`

### 조치

- T1: 24h+ stale 파일 직접 삭제 (semantic 판단 불필요, FP rate 회복 확정)
- decisions.jsonl 1줄 append (`action:"fp_ttl_gc"`, `file:{경로}`, `outcome:"removed"`)

### 주의

- 24h 이내 파일은 **절대 삭제 금지** (secretary 가 덮어쓸 수도, 실제 FP 분석이 진행 중일 수도 있음)
- 배치가 Step 6 성공 이동 중인 경우 skip (`ruler-batch-*` 세션 활성 시 대기)
- 삭제 후 같은 event 가 threshold 재도달하면 secretary 가 재생성 — 정상 흐름

### 판정 모드

sonnet-decide (mtime 기계 검사)

---

## C_ultraplan_hygiene — /ultraplan 파이프라인 위생 순찰 (2026-04-17 신설)

> 배경: `plan-ultra.md` v3 §Ruler Patrol 동기화. /ultraplan 원격 세션 handoff → Playwright 자동 클릭 → /remote-control 재주입 전 과정의 timeout/인증만료/실패 감지. 사용자 개입 0건 목표의 감시 레이어.

### 감지 항목

| ID | 조건 | 조치 | 이벤트 |
|---|---|---|---|
| U1 | `ultraplan_ready` log 후 > 30min 경과 + 후속 `<ultraplan>` 주입 없음 | Telegram + audit-log flag + handoff 프로세스 확인 | `ultraplan_timeout` |
| U2 | Playwright persistent profile 쿠키 age > 28d (`~/.claude/.playwright-profile` mtime) | 경고 → 사용자 Google 재로그인 요청 | `playwright_auth_expire` |
| U3 | `/remote-control` 재주입 후 pane 에 성공 마커 미감지 (3회 재시도 후) | audit-log + 재시도 큐 | `remote_control_restore_failed` |
| U4 | `ultraplan-handoff.sh` / `ultraplan-watch.js` 프로세스 > 35min 지속 (30min timeout + 5min 버퍼) | 프로세스 kill + orphan 정리 | `handoff_orphan_killed` |

### 검사

- **U1**: `audit-log/YYYY-MM-DD.jsonl` 에 `ultraplan_ready` 이벤트 grep → timestamp + 30min 경과 + 이후 `ultraplan_injected` (또는 동등) 이벤트 부재 판정
- **U2**: `stat -c %Y ~/.claude/.playwright-profile/Default/Cookies` 기준 age 계산
- **U3**: `audit-log` 에 `remote_control_restore_attempt` 후 `remote_control_restore_success` 없이 3회+ attempt
- **U4**: `ps -ef | grep -E 'ultraplan-(handoff|watch)'` 로 elapsed 계산

### 조치 (decisions.jsonl 1줄 append)

- T1 (mtime/timestamp 기계 검사): U1, U2, U4 → 즉시 처리 (`action:"ultraplan_timeout_flag"` / `"playwright_auth_warn"` / `"handoff_orphan_kill"`)
- T2 (규칙 상충 판정): U3 → pending 으로 이동, batch resolver 에서 재시도 전략 결정

### 주의

- Playwright 프로필 직접 삭제 **금지** (사용자 로그인 상태 손실). U2 는 경고만.
- `handoff.sh` / `watch.js` 가 정상 완료한 경우 프로세스 종료 확인 후 skip (false positive 방지).
- U3 재시도 큐는 다음 사이클에서 `ultraplan_watch` 재기동 권장 (수동 개입 전)

### 판정 모드

sonnet-decide (U1/U2/U4) + opus-decide (U3 재시도 전략)

---

## 기준표 동기화 규칙

### A. 상수 리뷰 (기존)

ruler/ruler-batch 가 T1/T2 처리 중 **기준 이벤트** 에 해당하면, 관련 C-check 또는 event-rules.yaml 의 상수를 재검토한다.

**기준 이벤트 정의**:
- 동일 위반 3회+ 반복 (decisions.jsonl `group_by(.check)`)
- grace/window 내 오탐/미탐 발생

**동기화 절차**:
1. 해당 C-check 또는 event-rules.yaml 이벤트 섹션만 offset Read (전문 Read 금지)
2. 관찰 근거 기반 수정안 작성 (decisions.jsonl `action:"constant_review"` 기록)
3. T2 pending → batch resolver 또는 사용자 논의 시 반영

### B. 규칙 내용 변경 → patrol 체크 동기화 (신설)

규칙 파일(`rules/*.md`, `skills/*/skill.md`) 이 T1/T2 로 수정되면, 해당 규칙을 감시하는 patrol 체크(event-rules.yaml, patrol-tier-c.md, patrol-wf-checks.md)도 동기화 필요.

**트리거 조건**:
- decisions.jsonl 에 `file:` 값이 `rules/` 또는 `skills/` 경로인 항목 존재
- 해당 수정이 "감시 기준 변경" (임계값/조건/절차) 에 해당

**동기화 절차**:
1. 수정된 규칙 파일의 변경 영역 Read
2. 해당 규칙을 감시하는 patrol 체크 식별:
   - `grep -l "{규칙파일명}" patrol-tier-c.md patrol-wf-checks.md event-rules.yaml`
3. 관련 체크의 기준/증거 갱신 필요 여부 판정
4. 갱신 필요 시 T2 pending 등록 (decisions.jsonl `action:"rule_patrol_sync"`)
5. batch resolver 에서 일괄 적용

**fallback**: audit-wf Phase Final 에서 추가 검증 (아래 §Phase Final-B 참조)
