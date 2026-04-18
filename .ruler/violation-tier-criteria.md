# 위반 검증 T1/T2 분류 지침 (draft)

**목적**: 이벤트 패트롤이 위반을 감지했을 때, ruler 순찰 세션(Sonnet)이 즉시 처리할 수 있는 것(T1)과 batch 세션(Opus)에 위임해야 하는 것(T2)을 판정하는 기준.
**작성**: 2026-04-16, ruler-batch-20260416T0122
**상태**: confirmed — patrol.md 런타임 경로 표에 링크 등록, t2-batch-resolver.md §Urgent 기준 연동

> **완화 배경 (2026-04-18)**: retrospective insufficient_rate 해결 위한 T entry 빈도 확보. 기존 T1 기준이 "복구 불가 + 교차 세션 영향 + 복구 비용 > 오탐 비용" 으로 너무 엄격해 7일 window 내 T1 항목 거의 0건 → retrospective 대부분 INSUFFICIENT 로 종결. T1 핵심 의미(가역·저위험·기계적)는 유지하되 **규칙 일관성 보정** 범주를 명시적으로 추가하고, T2 intake 에 "regex-detectable but requiring context review" 케이스를 편입. T3 는 진짜 모호한 인간 판단 영역으로 좁힘. 자율 수정 폭증 방지를 위해 세부 예시만 열거 (범주 확장 금지).

---

## 기존 Gate 와의 관계

기존 T1/T2 Gate (t2-batch-resolver.md) = **파일 수정** 관점.
본 지침 = **위반 감지 → 교정** 관점. 기존 Gate 를 포함하면서 확장.

```
위반 감지
 │
 ├── 교정 = 파일 수정 필요?
 │    └── YES → 기존 Gate 5항목 체크리스트 적용 (T1 or T2)
 │
 ├── 교정 = 통보만? (agent 에게 알려주기)
 │    └── ruler-notify.sh → T1 (통보 자체는 항상 즉시)
 │
 ├── 교정 = 상태 정리? (stale flag rm, registry 갱신 등)
 │    └── 단일 상태 파일 + 가역 → T1
 │
 └── 교정 = 원인 분석 필요? ("왜 이 규칙이 안 지켜졌는가")
      └── T2 (의미 판단 = batch Opus)
```

---

## T1 — 순찰 세션(Sonnet) 즉시 처리

### T1 조건 (모두 충족)

1. **교정 행위가 기계적** — 판단 분기 없이 결정론적으로 수행 가능
2. **단일 파일 이하** — 파일 수정 0~1개
3. **SSOT 연쇄 없음** — "함께 갱신할 파일" 테이블 해당 없음
4. **가역** — 실패 시 원복 가능 (rm, rollback, 재통보)
5. **regression trigger 아님** — secretary.js 등 5개 파일 아님

### T1 = 즉시 수정 + agent 에게 행동 지시

T1 은 "기록하고 통보만" 이 아니라 **"고치고 → agent 에게 다시 하라고 지시"** 까지가 범위.

**절차**:
1. **pane 확인 먼저** — `capture-pane -t {session}` 으로 현재 상태 확인. 이미 지나간 상황(뒷북)이면 통보 skip/조정
2. **즉시 수정** — 상태 정리, format 보정, flag 수정 등
3. **agent 에게 행동 지시** — ruler-notify.sh 경유:
   - `--mode violation`: "규칙 X 다시 Read 해. 위반 내용: Y"
   - `--mode rule-fix --cite {path}`: "규칙 강화됨. {path} 다시 Read 해"
   - 상황별: "이 기능 다시 해봐" / "이 파일 다시 Read 해"
4. decisions.jsonl append + log/{date}.md 기록

### T1 에 해당하는 교정 유형

| 유형 | 예시 | agent 지시 |
|---|---|---|
| **상태 정리 + 지시** | stale flag rm, registry 정리 | "정리했다. 다시 시도해" |
| **format 보정 + 지시** | frontmatter 주입, 마커 수정 | "보정했다. 규칙 다시 Read 해" |
| **파일 속성 + 지시** | session-note attrib +R | "고쳤다. read-only 규칙 지켜" |
| **아카이브 + 알림** | plan→.plan-archive/ 이동 | "아카이브했다. 새 plan 필요하면 만들어" |
| **규칙 위반 통보** | 위반 감지, 수정 불필요 | "규칙 X 위반. 다시 Read 하고 따라" |

### T1 확장 (2026-04-18) — 규칙 일관성 보정 (low risk + high value)

기존 T1 5조건(기계적/단일파일/SSOT 연쇄 없음/가역/non-regression) 을 모두 만족하는 **규칙 일관성 보정** 도 T1 즉시 처리 범위. 세부 예시:

| 서브유형 | 예시 | 조건 |
|---|---|---|
| **frontmatter 필드 누락** | `tags:` 또는 `type:` 필드 부재 → 기본값(폴더명/파일유형) 주입 | ruler 전역 `.md` (archive 제외) + 1파일 단독 |
| **명백한 오탈자/형식** | `##Header` (공백 누락), 끊긴 코드펜스 (```` ``` ```` 쌍 불일치), `--- ` trailing space | 비(非)의미 수정 — 내용 해석 없음 |
| **dead link / broken path** | `](~/.claude/xxx.md)` 가 `test -e` 실패 + `git log --diff-filter=D` 로 삭제 확인 | 대체 경로 명확할 때만 (modify). 모호 → T2 |

**경계**: YAML parse 에러는 파싱 복구가 기계적이면 T1, 구조 추론 필요하면 T2. "명백함" 의 기준 = 수정 후 diff 가 10줄 이내 + semantic 변경 없음.

**자율 수정 상한**: T1 확장 범주는 1사이클(3분) 당 최대 5건까지 자동 처리. 초과분은 T2 pending 으로 이관 (과도한 자율 Edit 방지). decisions.jsonl `action:"t1_ext_apply"` 로 태깅하여 retrospective 에서 빈도·효과 추적.

## T2 — batch 세션(Opus) 위임

### T2 조건 (하나라도 해당)

1. **원인 분석 필요** — "왜 이 규칙을 안 지켰는가" 해석이 필요
2. **규칙 보강** — rules/*.md, CLAUDE.md, patrol.md, skill.md 등 규칙 문서 수정
3. **비서 코드 수정** — secretary.js 또는 11개 모듈 수정 (regression trigger)
4. **hook/settings.json 수정** — 발동 인프라 변경
5. **다파일 SSOT 연쇄** — "함께 갱신할 파일" 2개+
6. **self-edit** — patrol.md / ruler-wf/skill.md 자기 수정
7. **의미 판단** — 대화 로그 해석, plan 내용 해석, task 유형 판단 등 LLM 필요
8. **regex-detectable but requiring context review (2026-04-18)** — 감지는 기계적이나 수정 방향은 맥락 확인 필요. 예: 중복 frontmatter tag 병합 (어느 값이 최신?), 상대경로→절대경로 변환 (대상 경로 선택), `last-edit` 포인터가 여러 후보 중 어느 커밋인지. T3 에서 내려온 경계선 판단 다수가 여기로 편입.

### T2 = 근본 수정은 나중 + 지금은 agent 에게 임시 지침

batch 가 근본 원인을 고치기까지 시간이 걸린다. 그 사이 **agent 에게 즉시 임시 지침**을 준다.

**Critical vs Non-critical 분기**:

```
T2 위반 감지
 │
 ├── Critical? (이대로 두면 계속 망가지는 상황)
 │    ├── YES → agent 에게 "멈춰. 이 작업 중단" (ruler-notify.sh --mode blocker)
 │    │         + urgent 3 안 됐어도 batch 즉시 스폰 ← 신규 트리거
 │    │
 │    └── NO  → agent 에게 "이렇게 해~" 임시 지침 (ruler-notify.sh --mode violation)
 │              + pending 에 수집 → 정상 batch 트리거 대기
 │
 └── 기록: decisions.jsonl + log + pending/{ts}_{topic}.md
```

**Critical 판정 기준** (기존 Urgent 3종 확장):
1. C1 regression 실패 (기존 Urgent)
2. C12 guard 교착 미해소 (기존 Urgent)
3. C16 secretary crash/hang (기존 Urgent)
4. **신규**: hook 미발동으로 agent 가 resume 없이 작업 중 (데이터 유실 진행)
5. **신규**: 규칙 위반이 연쇄 확산 중 (같은 세션 2사이클 내 동일 위반 재발)
6. **신규**: 비서 기능 전면 무효 상태 (registry 미등록 CWD 등)

**Non-critical T2 agent 지시 예시**:
- "모델 라우팅 안 했다. 다음 task 부터 [라우팅] 출력해"
- "progress.md 에 model/wf 빠졌다. 추가해"
- "conventional commit 아니다. 다음 커밋부터 feat/fix/refactor 써"
- "Sonnet-executable 미충족이다. 이 step Opus 로 재분류해"

### T2 에 해당하는 교정 유형 — 전수

| 유형 | 예시 | T2 이유 |
|---|---|---|
| **규칙 보강** | "모델 라우팅 안 했다" → CLAUDE.md §A/§B 규칙 강화 | 규칙 수정 = SSOT 연쇄 + self-edit |
| **비서 기능 수정** | "ctx-warn 넛지 안 보냈다" → ctx-warn.js 임계값/로직 수정 | regression trigger + 코드 해석 |
| **hook 설정 수정** | "routing-context hook 안 발동" → settings.json 수정 | regression trigger + 인프라 |
| **오탐 분석** | "stuck 오탐" → stuck.js 트리거 조건 완화 | 코드 해석 + regression |
| **grace/window 조정** | "memory_ckpt window 300s 가 짧다" → event-rules.yaml 수정 | 관찰 근거 기반 판단 + 기준표 동기화 |
| **신규 이벤트 작성** | coverage-map 미커버 항목 → event-rules.yaml 추가 | YAML 구조 + 연쇄 검증 |
| **대화 패턴 위반** | "사전 동의 없이 Agent 스폰" → 대화 로그 해석 + 규칙 보강 | 의미 판단 |
| **cross-file 수정** | "hook-guard-review.md ↔ settings.json drift" → 양쪽 동기화 | 다파일 SSOT |

---

## 경계 사례 — 판정 지침

### "통보 + 규칙 보강" 혼합

위반 감지 → agent 통보(T1) + 규칙 보강(T2). **분리 처리**:
- T1: 즉시 ruler-notify.sh 로 통보 + decisions.jsonl 기록
- T2: pending 에 규칙 보강 건 수집 → batch 세션

이렇게 하면 agent 는 즉시 알림 받고 (세션 망가지지 않음), 규칙 보강은 batch 에서 안전하게.

### "상태 정리인데 원인이 의문"

flag 가 stale → rm 은 T1. 하지만 "왜 stale 이 됐는가" → 생성 로직 버그면 T2.
**규칙**: 정리 자체는 T1 즉시 수행 + "원인 분석 필요" 판단 시 추가 T2 pending 생성.

### "비서가 안 했는데 이유를 모르겠다"

예: ctx-warn 넛지를 안 보냄. 토큰 80%+ 인데 audit-log 에 ctx_warn 없음.
- 통보: T1 (해당 세션에 "ctx-warn 안 왔다" 알림)
- 원인: T2 (비서 코드 확인 — ctx-warn.js 에 임계값 문제? 레지스트리 누락? 프로세스 hang?)

### "여러 세션에서 같은 위반 반복"

decisions.jsonl `group_by(.check)` 에서 동일 위반 3회+ → **기준표 동기화 규칙** 발동:
- 해당 이벤트 grace/window 재검토 (T2)
- 또는 해당 C-check 기준 재검토 (T2)
- 3회 미만 단발 → T1 통보 + 기록만

---

## 64개 항목 T1/T2 사전 분류 (coverage-map 기반)

### A. 비서 모듈 (28항목)

| ID | 항목 | 감지=T1 | 교정 |
|---|---|---|---|
| A1 | memory_ckpt 누락 | T1 통보 | T1 (통보만) / T2 (window 조정) |
| A2-1 | ctx-warn 미발송 | T1 기록 | T2 (비서 코드) |
| A2-2 | ctx-critical 후 compact 미발생 | T1 통보 | T2 (비서 코드) |
| A2-3 | ctx-clear 미전환 | T1 기록 | T2 (비서 코드) |
| A3-1 | registry 누락 (세션 미등록) | T1 통보 | T2 (registry.js) |
| A3-2 | registry stale (세션 종료 미반영) | T1 정리 | T1 (rm entry) |
| A3-3 | registry model drift (全세션) | T1 기록 | T2 (refreshModels) |
| A4-1 | audit-log 공백 | T1 기록 | T2 (jsonl-audit.js) |
| A5-1 | escalation 오탐 | T1 기록 | T2 (escalation.js) |
| A5-2 | BUG-O 재발 (block 후 escalation) | T1 기록 | T2 (escalation.js) |
| A5-3 | BUG-Q 재발 (단일 사이클 nudge) | T1 기록 | T2 (escalation.js) |
| A6 | commit 미감지 | T1 기록 | T2 (commits.js) |
| A7-1 | presence 오판 | T1 기록 | T2 (presence.js) |
| A7-2 | rate-limit 미감지 | T1 기록 | T2 (presence.js) |
| A8 | guard 교착 미해소 | T1 통보+Urgent | T2 (guard-deadlock.js) |
| A9-1 | progress model drift 넛지 미발송 | T1 기록 | T2 (nudges.js) |
| A9-2 | WF 완료 넛지 미발송 | T1 기록 | T2 (nudges.js) |
| A10-1 | resume 미주입 | T1 통보+Urgent | T2 (resume.js + hook) |
| A10-2 | resume 내용 불완전 | T1 기록 | T2 (resume.js) |
| A10-3 | revival 오탐 | T1 기록 | T2 (resume.js) |
| A11-1 | stuck 오탐 | T1 기록 | T2 (stuck.js) |
| A11-2 | ToolFrozen 오탐 | T1 기록 | T2 (stuck.js) |
| A11-3 | CircularWork 미감지 | T1 기록 | T2 (stuck.js) |

**패턴**: 비서 모듈 위반은 거의 전부 **감지=T1 (기록+통보) + 교정=T2 (코드 수정)**. 순찰 세션이 할 수 있는 건 "발견하고 알리고 기록하는 것"까지.

### B. 규칙 준수 (25항목)

| ID | 항목 | 감지=T1 | 교정 |
|---|---|---|---|
| B1-1 | 라우팅 판정 미수행 | T1 통보 | T2 (규칙 보강 or 넛지 강화) |
| B1-2 | Opus 후 Sonnet 복귀 안 됨 | T1 통보 | T2 (nudges.js) |
| B1-3 | plan 후 progress 미생성 | T1 통보 | T2 (규칙 보강) |
| B1-4 | progress step model/wf 누락 | T1 보정 | T1 (format 보정 가능한 경우) / T2 |
| B2-1 | frontmatter 누락 | T1 보정 | T1 (tags 주입) |
| B2-2 | 파일 배치 오류 | T1 기록 | T2 (이동 + 참조 갱신) |
| B2-3 | 상대경로 링크 | T1 기록 | T2 (다파일 수정) |
| B2-4 | Sonnet-executable 미충족 | T1 기록 | T2 (plan 재분류) |
| B2-5 | MEMORY ckpt 마커 오류 | T1 보정 | T1 (format 수정) |
| B2-6 | plan 완료 미아카이브 | T1 아카이브 | T1 (mv) |
| B3-1 | WF 세션 비서 등록 | T1 통보 | T1 (registry 정리) |
| B3-2 | 리줌 주입 실패 | T1 통보+Urgent | T2 (hook 수정) |
| B3-3 | 회귀 하네스 실패 | T1 Urgent | T2 (코드 롤백) |
| B3-4 | T1/T2 Gate 자기 위반 | T1 기록 | T2 (규칙 보강) |
| B4 | Haiku 위임 판정표 미준수 | T1 기록 | T2 (의미 판단) |
| B5-1 | remote 플래그 미생성 | T1 생성 | T1 (touch) |
| B5-2 | remote EnterPlanMode 미차단 | T1 기록 | T2 (hook 수정) |
| B6 | VaultVoice 규칙 미준수 | T1 기록 | T2 (Pi SSH + 의미 판단) |
| B7-1 | 3파일+ 변경인데 plan 없음 | T1 통보 | T2 (의미 판단) |
| B7-2 | plan 후 progress 없음 | T1 통보 | T2 (규칙 보강) |
| B7-3 | home dir 에 plan 작성 | T1 통보 | T1 (이미 guard 차단) |
| B7-4 | conventional commit 미준수 | T1 기록 | T2 (통보 + 넛지 강화) |
| B8 | psmux Windows 경로 미사용 | T1 기록 | T2 (의미 판단) |
| B9-1 | 사전 동의 없이 대량 스폰 | T1 기록 | T2 (의미 판단) |
| B9-2 | 전역 규칙 무단 편집 | T1 기록 | T2 (의미 판단) |

### C. Hook 발동 (11항목)

| ID | 항목 | 감지=T1 | 교정 |
|---|---|---|---|
| C1-1 | Bash guard 미발동 | T1 기록 | T2 (settings.json + bash-guard.js) |
| C1-2 | WebSearch guard 미발동 | T1 기록 | T2 (settings.json) |
| C1-3 | EnterPlanMode guard 미발동 | T1 기록 | T2 (settings.json) |
| C2 | PermissionRequest guard 미발동 | T1 기록 | T2 (settings.json) |
| C3 | SessionStart hook 미발동 | T1 기록+Urgent | T2 (settings.json + hook 스크립트) |
| C4 | routing-context prompt 미발동 | T1 기록 | T2 (settings.json + routing-context.sh) |
| C5 | routing-context progress 미발동 | T1 기록 | T2 (settings.json + routing-context.sh) |
| C6-1 | PreCompact auto 미발동 | T1 기록 | T2 (settings.json) |
| C6-2 | PreCompact manual 미발동 | T1 기록 | T2 (settings.json) |
| C7-1 | Stop hook 미발동 | 관측 불가 | — |
| C7-2 | Stop 종료 로그 미기록 | 관측 불가 | — |

---

## 요약 — 패턴

| 패턴 | T1 (즉시) | T2 (batch) |
|---|---|---|
| **감지 + 기록** | ✅ 항상 T1 | — |
| **agent 통보** | ✅ 항상 T1 | — |
| **상태 정리** (flag rm, registry 정리) | ✅ T1 | — |
| **format 보정** (frontmatter, 마커) | ✅ T1 | — |
| **규칙 문서 보강** | — | ✅ 항상 T2 |
| **비서 코드 수정** | — | ✅ 항상 T2 |
| **hook/settings.json 수정** | — | ✅ 항상 T2 |
| **원인 분석 ("왜?")** | — | ✅ 항상 T2 |
| **의미 판단 (대화/plan 해석)** | — | ✅ 항상 T2 |
| **grace/window 상수 조정** | — | ✅ 항상 T2 |

**핵심 원칙**: 순찰 세션은 **"발견 → 기록 → 통보 → 상태 정리"** 까지. **"왜 → 어떻게 고칠까"** 는 batch.
