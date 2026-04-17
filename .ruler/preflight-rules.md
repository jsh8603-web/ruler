---
type: ruler-preflight-rules
tags:
  - ruler
  - preflight
  - auto-generated
version: 1
created: 2026-04-14
updated: 2026-04-14
description: |
  Ruler retrospective (Phase A) 가 decisions.jsonl + 재수정 패턴 분석으로
  추출한 자동 Pre-flight 규칙. t1-gate.sh 가 Edit 직전 매칭 검사.
  사용자 수기 작성 금지 — ruler-batch-{ts} 가 자동 관리.
---

# Ruler Pre-flight Rules (자동 생성 SSOT)

본 파일은 ruler retrospective 가 주간 분석을 통해 추출한 **자동 차단 규칙** 의 단일 진실원이다. `t1-gate.sh` 가 Edit 직전 본 파일의 각 rule 을 파싱하여 `forbidden_change` 패턴이 diff 에 등장하면 즉시 T2 강제 + `decisions.jsonl gate:"preflight_block"` 기록.

## 포맷 규격

각 rule 은 `## rule_id: preflight-NNN` 헤더로 시작하며 아래 5 필드를 포함한다:

```markdown
## rule_id: preflight-001
- target: {파일 경로 pattern — glob 또는 정규식}
- forbidden_change: {diff 내 차단 패턴}
- reason: {근거 — retrospective 분석에서 도출한 semantic reason}
- source: retrospective-{YYYY-MM-DD}
- ttl: 30d  # 마지막 매칭으로부터
- last_matched: null  # t1-gate 가 매칭 시 갱신
```

## TTL 만료 정책

- 매 retrospective 사이클마다 `last_matched` 검사
- `last_matched` 가 30일 이상 과거거나 `null` 이고 `source` 로부터 30일 초과 → 자동 archive (`~/.claude/.ruler/preflight-rules.md/archive/` 이동)
- 만료 archive 도 retrospective 이력 보존용으로 유지 (삭제 금지)

## 규칙 충돌 감지

같은 `target` 에 서로 다른 `forbidden_change` 가 2개 이상 등록되면 retrospective 가 Opus 재판정 task 로 큐잉 (R10 기준).

---

## 규칙 목록

<!-- 초기 상태: 비어있음. 첫 retrospective 실행 시 ruler-batch 가 append. -->

(아직 추출된 규칙 없음. 첫 주간 retrospective 실행 대기 중.)

---

## 운영 로그

- 2026-04-14: 초기 파일 생성 (Phase 1 Sonnet Migration). 첫 retrospective 발동 대기.
