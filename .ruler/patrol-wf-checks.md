---
tags: [type/patrol, domain/wf]
date: 2026-04-16
description: WF 실행 중 ruler가 읽는 절차 준수 체크리스트. .wf-active 존재 시에만 활성.
---

# WF Patrol Checklist — Ruler 순찰용

> **활성화 조건**: `.wf-active` 파일 존재 시에만 이 문서 Read.
> **판정 방법**: ruler LLM이 execution-log / harness.md / progress.md / 파일시스템 상태를 grep/Read 하여 pass/fail 판정.
> **WF 타입 분기**: `.wf-active` 내 `type=` 값으로 해당 섹션만 체크.

---

## §1. 공통 체크 (모든 WF 타입)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| COM-1 | `.wf-active` 파일 존재 + type 필드 | `cat .wf-active` | type ∈ {harness, coding, lightweight, planning} |
| COM-2 | progress.md 존재 | `stat progress.md` | 프로젝트 디렉토리에 위치 |
| COM-3 | step에 model/wf 정확히 하나 | `grep -c 'model:\|wf:' progress.md` | 각 step 당 1개 |
| COM-4 | 사용자 승인 기록 | execution-log 또는 대화 이력 | 승인 없이 실행 시 blocker |
| COM-5 | session-notes 정리 금지 | `.session-notes/` 파일 존재 확인 | 삭제 시도 = 즉시 T1 위반 |

---

## §2. Harness WF (type=harness) — 97항목

### 2.1 진입 (E-1~E-10)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| E-1 | `.wf-active type=harness` 존재 | `cat .wf-active` | type=harness |
| E-2 | progress.md 존재 | `stat` | 프로젝트 디렉토리 |
| E-3 | harness.md 존재 + Phase 헤더 | `head -20 .harness/harness.md` | `## Phase` 구조 |
| E-4 | execution-log.md 헤더 존재 | `head -5 .harness/execution-log.md` | 4필드 헤더 |
| E-5 | Supervisor 승인 기록 | execution-log | 사용자 승인 라인 존재 |
| E-6 | 4세션 존재 (Worker/Verifier/Healer/SR) | `psmux ls` | 4개 세션 alive |
| E-7 | ACK 핸드셰이크 완료 | `.harness/acks.txt` | 4개 ACK 기록 |
| E-8 | spawn-session.sh 경유 | audit-log | spawn-session 호출 기록 |
| E-9 | 역할 파일 분리 (200자+ send-keys 금지) | 역할 .md 파일 존재 | `role-assembled.md` 등 |
| E-10 | progress.md 포맷 검증 (model XOR wf, haiku path) | `grep` progress.md | 각 step 문법 정확 |

### 2.2 세션 스폰+핸드셰이크 (S-1~S-6)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| S-1 | 4세션 생존 확인 | `psmux ls` grep | blocker: 소멸 시 즉시 재스폰 |
| S-2 | ACK 4개 완료 | `.harness/acks.txt` line count | 4줄 |
| S-3 | spawn-session.sh 경유 스폰 | audit-log 또는 bash history | 직접 `claude` 실행 금지 |
| S-4 | 역할별 파일 기반 주입 | `.harness/` 내 역할 파일 | send-keys 200자 초과 금지 |
| S-5 | SR = Opus 모델 | registry 또는 spawn 인자 | strategic-review = opus |
| S-6 | ACK 2회 실패 시 exit 2 + 재스폰 기록 | execution-log | 실패 시 판단 기록 존재 |

### 2.3 Self-Wake+워치독 (W-1~W-5)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| W-1 | Self-Wake 루프 구동 | `pgrep -f wake` 또는 pid 파일 | blocker: 사망 시 즉시 재기동 |
| W-2 | 워치독 기록 갱신 | execution-log 워치독 타임스탬프 | 최근 5분 이내 |
| W-3 | guard 3중 플래그 갱신 (TTL 4분) | `.harness/` 플래그 mtime | 4분 이내 |
| W-4 | secretary-alive 확인 | 비서 PID 체크 | alive |
| W-5 | IDLE 즉시 실행 (대기 금지) | execution-log 타임스탬프 갭 | >10분 갭 = 경고 |
| W-6 | `.wf-active` 생성 시점 = 핸드셰이크 후, Self-Wake 전 | mtime 순서 | acks.txt mtime < .wf-active mtime < wake pid |

### 2.4 Worker 기록 (R-1~R-7)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| R-1 | 시작 알림 기록 | execution-log | "시작" 또는 "착수" 키워드 |
| R-2 | 완료 4필드 (변경/핵심/발견/막힘) | execution-log 완료 블록 | 4필드 모두 존재 |
| R-3 | 📐 DesignDecision 기록 | execution-log | 설계 판단 시 기록 존재 |
| R-4 | Verifier 통보 (완료 신호) | 통보 파일 또는 send-keys | 완료 후 Verifier 에게 전달 |
| R-5 | Bash 도구 사용 기록 | execution-log | 도구 호출 기록 |
| R-6 | 인수인계 키 4필드 기록 | execution-log | 컨텍스트 임계 시 |
| R-7 | 컨텍스트 10% 이하 시 배포 금지 | execution-log | 임계 도달 시 중단 기록 |

### 2.5 Verifier 검증 (V-1~V-6)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| V-1 | 체크박스 갱신 | harness.md | PASS/FAIL 마킹 |
| V-2 | FAIL → Healer 라우팅 + promotion-log ERROR | harness.md + promotion-log | FAIL 시 둘 다 기록 |
| V-3 | EVT 베이스라인 준수 | 검증 기준 파일 | 기준 대비 |
| V-4 | specialist 라우팅 (security/quality/performance) | agent 스폰 로그 | 해당 시 specialist 호출 |
| V-5 | Phase 종합 판정 | harness.md Phase 끝 | PASS/FAIL 명시 |
| V-6 | FAIL 시 promotion-log ERROR append 확인 | `grep ERROR promotion-log.md` | FAIL마다 1건 이상 |

### 2.6 Healer 수정 (H-1~H-7)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| H-1 | FixComplete 4필드 기록 | execution-log | 4필드 완전 |
| H-2 | Fix 패턴 기록 | execution-log | `💡 Fix 패턴:` 존재 |
| H-3 | 파일 충돌 방지 | git diff | Worker 작업 파일과 비충돌 |
| H-4 | 재검증 신호 전송 | Verifier 통보 | 수정 후 재검증 요청 |
| H-5 | DesignFAIL 금지 (설계 변경 불가) | execution-log | 설계 변경 시도 없음 |
| H-6 | WARNING 미수정 (ERROR만 수정) | execution-log | WARNING = 방치 |
| H-7 | Fix 패턴 promotion-log KNOWLEDGE 승격 | promotion-log | 반복 Fix 시 승격 기록 |

### 2.7 SR Pre-Review (SR-1~SR-8)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| SR-1 | PreReview 실행 기록 | execution-log | SR 작동 흔적 |
| SR-2 | 3세트 리서치 수행 | execution-log | 리서치 기록 3건+ |
| SR-3 | 3가정 (assumptions) 기록 | execution-log | 가정 명시 3건+ |
| SR-4 | TypeA (규칙 존재 + 미준수) 판정 | execution-log | 유형 분류 기록 |
| SR-5 | TypeB (규칙 부재 + 신규 필요) 판정 | execution-log | 유형 분류 기록 |
| SR-6 | 렌즈 2+ 사용 | execution-log | 2개 이상 관점 |
| SR-7 | 이벤트 기반 행동 기록 | execution-log | 관찰 → 행동 연결 |
| SR-8 | 대기 중 자율 행동 = deferred-ideas 재검토만 허용 | execution-log | Supervisor 전송 금지 |

### 2.8 Phase 전환 (P-1~P-10)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| P-1 | Healer 대기 확인 후 전환 | harness.md | Healer 완료 대기 |
| P-2 | GateReview 3-agent 참여 | harness.md | Worker+Verifier+SR 참여 |
| P-3 | SR Gate G1-G4 기준 충족 | harness.md | 4개 Gate 항목 |
| P-4 | PostReview 기록 | harness.md | Phase 전환 후 기록 |
| P-5 | Sufficiency 판정 | harness.md | 충분성 평가 |
| P-6 | 스냅샷 기록 | harness.md | Phase 시작 상태 |
| P-7 | 헤더 갱신 (Phase N → N+1) | harness.md | 헤더 업데이트 |
| P-8 | 에스컬레이션 4단계 | harness.md | 단계별 기록 |
| P-9 | SR 트리거 T1-T4 | execution-log | SR 트리거 조건 |
| P-10 | Healer 파일 소유권 Active 잔존 시 전환 금지 | harness.md | Active=0 확인 |

### 2.9 종료 (C-1~C-21)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| C-1 | RC-1 최종 빌드 통과 | harness.md | RC 체크 |
| C-2 | RC-2 테스트 통과 | harness.md | RC 체크 |
| C-3 | RC-3 코드 품질 | harness.md | RC 체크 |
| C-4 | RC-4 보안 검토 | harness.md | RC 체크 |
| C-5 | RC-5 문서화 | harness.md | RC 체크 |
| C-6 | RC-5.5 회귀 확인 | harness.md | RC 체크 |
| C-7 | RC 미완료 시 kill 금지 | harness.md RC 체크박스 | blocker: RC-1~5.5 전부 체크 전 kill 불가 |
| C-8 | SessionNote 작성 | `.session-notes/` | 파일 생성 확인 |
| C-9 | SelfWake 종료 (sentinel) | pid 파일 또는 프로세스 | graceful 종료 |
| C-10 | pkill 금지 | bash history | pkill/kill -9 사용 금지 |
| C-11 | .wf-active 삭제 | `stat .wf-active` | blocker: 잔존 시 즉시 삭제 |
| C-12 | 4세션 종료 | `psmux ls` | WF 세션 전부 종료 |
| C-13 | Ruler 종료 통보 | `[ruler-wf-end]` 메시지 | ruler 세션 존재 시 통보 |
| C-14 | 아카이브 (삭제 아님) | `.plan-archive/` | plan/progress 이동 |
| C-15 | 정리 금지 목록 준수 | `.session-notes/`, promotion-log | 절대 삭제 불가 목록 |
| C-16 | SessionNote frontmatter 7필드 | session-note 파일 | 7필드 존재 |
| C-17 | error_count > 0 시 실질 내용 | session-note | ERROR 시 설명 포함 |
| C-18 | read-only 설정 | `attrib +R` 또는 `IsReadOnly` | session-note 보호 |

### 2.10 소통/통신 (T-1~T-4)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| T-1 | 한국어 보고 | execution-log | 한국어 사용 |
| T-2 | 자율 실행 (사용자 질문 최소화) | 대화 이력 | 불필요한 질문 0 |
| T-3 | Liveness 확인 | 워치독 | 세션 alive |
| T-4 | psmux 전용 통신 | bash history | psmux send-keys 사용 |

### 2.11 규칙 자율 개선 (I-1~I-2)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| I-1 | 동일 문제 2회 → 규칙 수정 | decisions.jsonl | 반복 시 규칙 개선 |
| I-2 | 목표 수정 금지 | harness.md | 원래 목표 유지 |

### 2.12 2회차 보완 (X-1~X-10)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| X-1 | Sub4 원칙 (4세션 유지) | `psmux ls` | 항상 4세션 |
| X-2 | Additive Overlay | harness.md | 덧씌우기 방식 |
| X-3 | Sacred Goal 보존 | harness.md | 원래 목표 |
| X-4 | Gate PASS 확인 | harness.md | Gate 통과 기록 |
| X-5 | 컨텍스트 복원 | execution-log | 압축 후 복원 |
| X-6 | ReRead 의무 | execution-log | 재읽기 기록 |
| X-7 | 자산화 블록 | execution-log | 자산화 후보 |
| X-8 | WARNING 미수정 | execution-log | WARNING 방치 |
| X-9 | SparkIgnite | execution-log | SR 트리거 |
| X-10 | Model Escalation | execution-log | 모델 전환 기록 |

---

## §3. Coding WF (type=coding) — 56항목

### 3.1 진입 (A-1~A13)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| A-1 | plan.md 존재 | `stat plan.md` | 프로젝트 디렉토리 |
| A-2 | Sonnet-executable 검증 통과 | plan.md 내용 | 5항목 체크 |
| A-3 | progress.md 존재 | `stat progress.md` | step model/wf 포함 |
| A-4 | step에 model/wf 정확히 하나 | `grep` progress.md | 1개씩 |
| A-5 | 규모 판정 S/M/L | progress.md 또는 plan.md | 규모 명시 |
| A-6 | 사용자 승인 | 대화 이력 | 승인 기록 |
| A-7 | §B③ 통과 (3+ 독립 모듈) | plan.md | 3개+ 병렬 대상 |
| A-8 | 경량화 키워드 미매칭 | plan.md grep | 키워드 0건 |
| A-9 | bulk-skip 실행 (guard 차단 방지) | audit-log | promotion-signal bulk-skip |
| A-10 | model-switch 경유 진입 | bash history | model-switch-and-send.sh |
| A-11 | 5분 미만 wf spawn 금지 | progress.md | 소요 예상 ≥ 5분 |
| A-12 | bulk-skip promotion-signal 선행 | audit-log | Coder 스폰 전 실행 |
| A-13 | 장수명 모드 경고 (압축 3회+) | execution-log | harness 격상 권장 |

### 3.2 S-scale 실행 (B-1~B8)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| B-1 | Sonnet 직접 수행 | 모델 확인 | model=sonnet |
| B-2 | Guardian 키워드 grep 기반 | grep 실행 기록 | 키워드 검색 수행 |
| B-3 | Guardian 형식 준수 | 검증 결과 | 포맷 맞음 |
| B-4 | 키워드 0건 = Guardian 생략 | grep 결과 | 0건이면 skip |
| B-5 | 빌드만 Tester 대체 금지 | execution-log | Tester 별도 |
| B-6 | 3회 재투입 한도 | execution-log | 최대 3회 |
| B-7 | simplify 실행 | git diff | simplify 수행 |
| B-8 | 아카이브 | `.plan-archive/` | 이동 완료 |

### 3.3 M/L-scale 실행 (C-1~C22)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| C-1 | Opus Planner 사용 | 모델 확인 | Planner = opus |
| C-2 | Sonnet 오케스트레이션 | 모델 확인 | orchestrator = sonnet |
| C-3 | Coder = Sonnet | Agent 스폰 model | model:"sonnet" |
| C-4 | Guardian = Sonnet | Agent 스폰 model | model:"sonnet" |
| C-5 | Tester = Haiku + 수량 (M:2, L:3) | Agent 스폰 | model:"haiku" + count |
| C-6 | Planner 6항목 출력 | plan 산출물 | 6개 섹션 |
| C-7 | 의존성 그룹 분리 | plan 산출물 | 독립/의존 분류 |
| C-8 | 격리 방식 (worktree 등) | Agent 스폰 | isolation 명시 |
| C-9 | PATH 명시 | Coder 프롬프트 | 파일 경로 포함 |
| C-10 | 파일 충돌 방지 | plan 산출물 | 파일 배타적 할당 |
| C-11 | Guardian 키워드 검사 | grep 실행 | 키워드 grep |
| C-12 | Tester 빌드 금지 (테스트 전용) | Tester 프롬프트 | 빌드 코드 없음 |
| C-13 | 재투입 2회 한도 | execution-log | 최대 2회 |
| C-14 | Planner 재호출 (Guardian 3+ 이슈) | 모델 전환 기록 | opus 재호출 |
| C-15 | 힐러 3단계 | execution-log | 3단계 에스컬레이션 |
| C-16 | 테스트 3회 한도 | execution-log | 최대 3회 |
| C-17 | Worktree merge 순서 (의존성 그룹 순) | git log | 독립→의존 순서 |
| C-18 | Worktree 정리 (remove) | `git worktree list` | 잔존 worktree 0 |
| C-19 | batch 10+ 파일 시 분할 | plan 산출물 | 10개+ 시 배치 분리 |
| C-20 | Write 실패 시 재Read 재시도 지시 | Coder 프롬프트 | 지시 포함 |
| C-21 | Worktree merge 순서 = 의존성 그룹 순 확인 | git log merge | 순서 정확 |
| C-22 | Worktree conflict 시 Opus resolve | execution-log | Sonnet 임의 resolve 금지 |

### 3.4 모델 배정 (D-1~D6)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| D-1 | orchestrator = Sonnet | 모델 확인 | sonnet |
| D-2 | Opus 전환 후 복귀 | 모델 이력 | opus → sonnet 복귀 |
| D-3 | Guardian 재계획 시만 Opus | 전환 기록 | 3+ 이슈일 때만 |
| D-4 | /model 직접 금지 | bash history | /model 사용 0 |
| D-5 | Agent 스폰 model:"sonnet" 명시 | Agent 호출 | 기본 sonnet |
| D-6 | Planner 재호출 시 model-switch 경유 | bash history | 헬퍼 경유 |

### 3.5 코드 품질 (E-1~E5)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| E-1 | 함수 50줄 제한 | `wc -l` 대상 함수 | ≤ 50줄 |
| E-2 | 중첩 3단계 제한 | 코드 검사 | ≤ 3단계 |
| E-3 | 5파일+ 시 simplify | git diff --stat | 5개+ 파일 변경 시 simplify |
| E-4 | 10파일+ 시 batch 분할 | plan 산출물 | 10개+ 시 배치 |
| E-5 | ccusage 실행 | 실행 기록 | 토큰 사용량 확인 |

### 3.6 종료 (F-1~F8)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| F-1 | simplify 3병렬 | git log | simplify 실행 |
| F-2 | 아카이브 | `.plan-archive/` | plan/progress 이동 |
| F-3 | 명명 규칙 | 아카이브 파일명 | kebab-case + date |
| F-4 | 보고 포맷 | 사용자 보고 | 템플릿 준수 |
| F-5 | Worktree 정리 | `git worktree list` | 잔존 0 |
| F-6 | SessionNote | `.session-notes/` | 파일 생성 |
| F-7 | readOnly 설정 | `attrib` | session-note 보호 |
| F-8 | .wf-active 삭제 | `stat .wf-active` | 파일 없음 |

### 3.7 금지 규칙 (G-1~G7)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| G-1 | 판정표 통과 확인 (§B③ 경유) | progress.md | wf:coding 기록 |
| G-2 | 경량화 키워드 침입 금지 | plan.md grep | 키워드 0건 |
| G-3 | EnterPlanMode 스킵 금지 | 도구 호출 기록 | 계획 수립 |
| G-4 | Excel 제외 | plan.md | MCP 작업 아님 |
| G-5 | wf 재시작 금지 (이어서 수행) | execution-log | 재시작 기록 없음 |
| G-6 | 장수명 경고 (3회+ 압축) | execution-log | 경고 기록 |
| G-7 | §B 우회 금지 | progress.md | 판정표 경유 |

### 3.8 서브에이전트 (H-1~H6)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| H-1 | agents/ 정의 파일 사용 | Agent 스폰 | subagent_type 지정 |
| H-2 | security 읽기 전용 | Agent 결과 | 수정 없음 |
| H-3 | quality 읽기 전용 | Agent 결과 | 수정 없음 |
| H-4 | healer 최소 수정 | git diff | 최소 변경 |
| H-5 | healer 3회 한도 | execution-log | ≤ 3회 |
| H-6 | 핵심 foreground (background 금지) | Agent 호출 | run_in_background=false |

---

## §4. Lightweight WF (type=lightweight) — 61항목

### 4.1 진입 (E-1~E11)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| E-1 | `.wf-active type=lightweight` 존재 | `cat .wf-active` | type=lightweight |
| E-2 | Supervisor = Opus | 모델 확인 | opus 고정 |
| E-3 | progress.md 존재 | `stat` | 프로젝트 디렉토리 |
| E-4 | step에 model/wf 정확히 하나 | `grep` progress.md | 1개씩 |
| E-5 | model:haiku step에 haikuplan 경로 병기 | progress.md | 경로 존재 |
| E-6 | Sonnet-executable 5항목 검증 | plan.md | 체크리스트 충족 |
| E-7 | plan/progress 프로젝트 디렉토리 위치 | `pwd` + `stat` | home dir 아님 |
| E-8 | `.harness/` + `acks.txt` 생성 | `stat .harness/acks.txt` | 존재 |
| E-9 | Worker spawn-session.sh 경유 | audit-log | 스폰 기록 |
| E-10 | Supervisor = 기존 메인 세션 (새 세션 생성 금지) | `psmux ls` | 추가 세션 없음 |
| E-11 | Worker 코딩wf 발동 권한 확인 | plan.md | 3+ 파일 복잡 변경 시 |

### 4.2 Worker 행동 (W-1~W10)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| W-1 | execution-log 4필드 기록 | execution-log | 변경/핵심/발견/막힘 |
| W-2 | Step 완료 fire-and-forget | execution-log | 승인 대기 금지 |
| W-3 | 막힘 시 🔧 시그널 + 카테고리 + sleep/Enter 분리 | execution-log | 시그널 전송 기록 |
| W-4 | 📐 Design Decision 기록 | execution-log | 설계 판단 시 |
| W-5 | 자산화 후보 분류 | execution-log | 후보 기록 |
| W-6 | 전역 파일 직접 수정 금지 | git diff | `~/.claude/` 수정 없음 |
| W-7 | 금지 스킬 미사용 | 도구 호출 | cross-verify, code-review-team 금지 |
| W-8 | Reflection 2-track 응답 | execution-log | 2-track 형식 |
| W-9 | per-task Haiku 위임 판정 | haiku-delegation.md 경유 | 판정표 실행 |
| W-10 | 전역 파일 수정 시 guard 시그널 경유 | execution-log | 시그널 기록 |

### 4.3 Supervisor 행동 (S-1~S10)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| S-1 | Self-Wake 루프 구동 | pid 또는 프로세스 | alive |
| S-2 | 워치독 3중 guard (TTL 4분) | 플래그 mtime | 4분 이내 |
| S-3 | Worker 역할 주입 파일 기반 (200자+ send-keys 금지) | `.harness/` 역할 파일 | 파일 존재 |
| S-4 | 프로토콜 복사 금지 | Worker 프롬프트 | 프로토콜 인라인 아님 |
| S-5 | review-checklist 매 step 작성 | `.harness/` | 체크리스트 파일 |
| S-6 | 직접 수정 (Worker 재위임 안 함) | git diff author | Supervisor 직접 |
| S-7 | 5 Step+ 시 상태 요약 | execution-log | 요약 기록 |
| S-8 | Worker 대기 중 병렬 작업 (pre-scout/external-check/progress-test/review-checklist) | `.harness/` 파일 | 4개 산출물 |
| S-9 | 장수명 모드 — 압축 3회+ 시 guide.md + snapshot | guide.md 존재 | 장수명 진입 시 |
| S-10 | Worker 대기 중 ⑤~⑧ 4개 병렬 산출물 | `.harness/` | pre-scout/external-check/test-scenarios/review-checklist |

### 4.4 종료 (T-1~T19)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| T-1 | Supervisor 검수 블록 기록 | execution-log | 검수 결과 |
| T-2 | Reflection 실행 (스킵 불가) | execution-log | Reflection 기록 |
| T-3 | Reflection 4필드 완전성 | execution-log | 4필드 모두 |
| T-4 | promotion-log 기록 | promotion-log.md | 기록 존재 |
| T-5 | ERROR 항목 자산화 블록 | execution-log | ERROR → 자산화 |
| T-6 | Session-Note + read-only | `.session-notes/` + `attrib` | 존재 + 보호 |
| T-7 | Session-Note frontmatter 7필드 | session-note | 7필드 완전 |
| T-8 | error_count > 0 실질 내용 | session-note | ERROR 시 설명 |
| T-9 | Self-Wake graceful 종료 (sentinel) | pid 파일 | 정상 종료 |
| T-10 | Worker 세션 종료 | `psmux ls` | Worker 없음 |
| T-11 | 플래그 파일 정리 | `.harness/` | 불필요 파일 제거 |
| T-12 | .wf-active 삭제 | `stat .wf-active` | 파일 없음 |
| T-13 | Ruler 종료 알림 | `[ruler-wf-end]` 메시지 | 통보 |
| T-14 | Ruler 세션 kill 금지 | bash history | kill 사용 0 |
| T-15 | Supervisor 복귀 = Sonnet | 모델 확인 | sonnet 복귀 |
| T-16 | 사용자 보고 템플릿 | 사용자 메시지 | 포맷 준수 |
| T-17 | plan/progress 아카이브 | `.plan-archive/` | 이동 완료 |
| T-18 | 정리 금지 목록 준수 | session-notes 등 | 삭제 없음 |
| T-19 | Reflection 개선 제안 적용 절차 (전체/일부/보류 3분기) | execution-log | 사용자 승인 후 적용 |

### 4.5 실행 중 순찰 (R-1~R6)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| R-1 | Worker 세션 생존 | `psmux ls` | alive |
| R-2 | Worker idle 감지 (10분+) | execution-log 타임스탬프 | 갭 < 10분 |
| R-3 | Guard 차단 미해소 | `.harness/` 플래그 | 해소됨 |
| R-4 | Self-Wake 루프 생존 | pid 또는 프로세스 | alive |
| R-5 | execution-log 기록 순서 | execution-log | 시간순 |
| R-6 | Worker 압축 후 execution-log Read 복원 | execution-log | 복원 기록 |

### 4.6 교차 검증 (X-1~X5)

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| X-1 | Supervisor = Opus 고정 | 모델 확인 | opus |
| X-2 | Worker = Sonnet | 모델 확인 | sonnet |
| X-3 | 5분 미만 작업 wf spawn 금지 | progress.md | 소요 ≥ 5분 |
| X-4 | model-switch-and-send.sh 경유 | bash history | 헬퍼 사용 |
| X-5 | session-notes 정리 금지 | `.session-notes/` | 존재 유지 |

---

## §5. Planning WF (type=planning) — 3항목

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| PL-1 | Supervisor = Opus | 모델 확인 | opus |
| PL-2 | plan.md 산출물 생성 | `stat plan.md` | 존재 |
| PL-3 | .wf-active 종료 시 삭제 | `stat .wf-active` | 파일 없음 |

---

## §6. Handoff-Plan (장수명 릴레이, 모든 WF/세션과 혼용) — 7항목

> **감지**: `guide.md` 존재 (plan 폴더). handoff-plan-wf 는 ruler-batch 전용이 아님 —
> CLAUDE.md §Model Routing 에 명시된 대로 **모든 WF/direct 세션에 장수명 수식어로 얹을 수 있음**.
> 압축 3회+ 예상 시 §A·§B 모든 경로에 적용 가능 (코딩WF만 제외).

| ID | 항목 | 증거 | 기준 |
|---|---|---|---|
| HO-1 | guide.md 존재 (plan 디렉토리) | `stat guide.md` | plan.md 와 같은 폴더 |
| HO-2 | guide.md ≤ 1k 토큰 (~50줄) | `wc -l guide.md` | 비대화 방지 |
| HO-3 | progress.md §진입 스냅샷 존재 | `grep '진입 스냅샷' progress.md` | 섹션 존재 |
| HO-4 | plan.md 상단 포인터 삽입 | `head -3 plan.md` | `⚡ 새 세션 진입` 라인 |
| HO-5 | MEMORY.md ckpt append | `grep 'guide.md' MEMORY.md` | ckpt 라인 존재 |
| HO-6 | 세션 종료/압축 시 §진입 스냅샷 갱신 | progress.md mtime | 최근 갱신 |
| HO-7 | 실행 세션 모델 = progress.md step 기대값 | registry model | 일치 |

---

## §7. Ruler 순찰 통합 방법

1. **Tier A 사이클 시작**: `.wf-active` 존재 확인
2. 존재 시 `type=` 값 Read → 해당 §섹션만 offset Read
3. `.wf-active` 없어도 `guide.md` + `ruler-batch-*` 활성 → §6 Handoff 체크
4. 해당 WF 타입의 **blocker** 항목 (COM-1, S-1, W-1, C-7, C-11 등) 우선 체크
5. 비-blocker 항목은 Tier C (30분) 사이클에서 샘플링 체크 (전수 불필요)
6. 위반 발견 시 `ruler-notify.sh violation` 으로 해당 Supervisor 에게 통보
