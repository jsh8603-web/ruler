---
type: ruler-wake-loop
date: 2026-04-15
tags: [ruler, wake, state-machine, load/on-demand]
---

# Ruler Wake Loop — active / idle State Machine

(root: [`~/.claude/.ruler/patrol.md`](~/.claude/.ruler/patrol.md) / [`~/.claude/skills/ruler-wf/skill.md`](~/.claude/skills/ruler-wf/skill.md) §4 에서 참조)

활성화 = **비서 신호 기반 단방향 진입**. Ruler 는 자기 판단으로 `.active` 를 touch 하지 않는다. 비서(`secretary.js` runCycle)가 watched psmux 세션의 `WAITING → WORKING` edge 를 감지해 신호 파일을 drop 한다. wf-start 기반 on-demand touch 는 폐기됨 (2026-04-14 재설계).

## wake.sh 루프

`~/.claude/.ruler/wake.sh` — spawn-session.sh ruler 이 자동 구동.

- **INTERVAL**: 30s short-poll → 실제 순찰은 180s (3분) 주기 (`.last-patrol-ts` 기반)
- **EXIT_PATTERN**: `has-session -t ruler` 부재 시 루프 종료
- **중복 구동 방지**: `.wake-ts` 6분 이내면 재구동 skip
- **Sentinel 종료**: `.wake-stop` 파일 생성 시 graceful exit
- **메시지**: 2-Tier 체크리스트 인라인 (Tier A 매 사이클 + Tier C 10사이클마다) + patrol.md/state.md Read 지시 2중 안전

## 상태 머신

```
[모든 watched 세션 idle] ← Ruler patrol OFF, wake.sh 30s 폴링만 유지
   │
   │ secretary.js: 세션 edge WAITING→WORKING 감지
   │ → ~/.claude/.ruler/.messages/wake-{session}-{ts}.txt drop
   ▼
[wake.sh 감지 → .active touch + .idle-strike 0 리셋 + 신호 파일 consume]
   │
   ▼
[Ruler patrol ON — 3분 사이클]
   │
   │ 매 순찰마다 Tier A: 이벤트 패트롤 → C1/C16/C17/C_idle
   │ 10사이클마다 Tier C: C3~C15 + C18-lite
   │ C_idle_sweep 로 watched 세션 현재 status 확인
   │ 전원 non-WORKING (WAITING|DEAD) 이면 .idle-strike 증가
   │ .idle-strike >= 3 (= 9분 연속 전원 idle) 도달
   ▼
[.active rm → patrol 중단 → 다시 Ruler OFF]
```

## 불변 조건

| 항목 | 규칙 |
|---|---|
| 활성 판정 | **합집합** — watched 세션 중 하나라도 WORKING → ruler ON |
| 해제 판정 | **교집합 × 3회** — watched 세션 전원 non-WORKING 3 사이클 연속 → ruler OFF (`idle_strike_threshold: 3`, 2026-04-16 5→3 복원, T2 배치 스폰 트리거) |
| 진입 신호 | **비서 단방향** — Ruler 는 자기 판단으로 활성화 불가. 오직 `.messages/wake-*.txt` 파일만 신뢰 |
| 제외 세션 (watched 아님) | `worker\|verifier\|healer\|strategic` (harness), `ruler` 본인, `ruler-batch-*` (단수명 Opus), `task\|schedule\|secretary` 접두사, `runner=gemini\|codex` |

## 전환 절차

**idle → active**:
1. `secretary.js` runCycle 이 watched psmux 세션의 `WAITING→WORKING` edge 감지
2. `~/.claude/.ruler/.messages/wake-{session}-{ts}.txt` drop
3. wake.sh 30s poll 이 consume → `.active` touch + `.idle-strike 0`

**active → idle**:
1. patrol 사이클의 `C_idle_sweep` 이 watched 세션 전원 non-WORKING 을 3회 연속 감지
2. `.idle-strike >= 3` → `rm .active` → 다음 poll 부터 순찰 중단 (루프 생존)

## 사이클 진입 절차 (매 사이클 첫 단계)

Ruler 가 3분 자는 사이 `[ruler-reentry]` / `[ruler-wf-end]` 연속 주입이 가능 (레거시 경로). 깨어난 Ruler 는 아래 순서로 처리 (v3 2-Tier 구조 기준):

1. `capture-pane -p -S -200 -t ruler` 로 최근 pane tail 수집
2. `\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\]\[ruler-(reentry|wf-end)\]` 패턴으로 모든 알림 추출
3. TS 필드로 오름차순 정렬 (오래된 것부터)
4. state.md `processed_notifications` 배열과 대조 → 이미 처리된 TS skip
5. 미처리 알림 시간순 처리:
   - `ruler-reentry` → Active WF Contexts 추가
   - `ruler-wf-end` → Active WF Contexts 제거 (비면 `.active` 삭제)
6. 처리된 TS 를 `processed_notifications` 에 append (최근 100개 FIFO)

**TS prefix 없는 레거시 메시지**: "시간 무한대 과거" 취급 → 정렬 시 맨 앞 → 먼저 처리 (하위호환).

> ⚠️ **2026-04-14 재설계 이후**: `[ruler-reentry]` / `[ruler-wf-end]` 는 deprecated 경로. 비서 edge 감지가 주 활성화 경로이고, idle 해제는 C_idle_sweep 담당. 위 절차는 레거시 호환용으로만 유지.

## §2a Active WF Contexts stale sweep (레거시, 매 사이클 필수)

위 알림 처리 **직후**, C 체크리스트 진입 **전**:

1. state.md `## Active WF Contexts` 파싱
2. 다음 조건 하나라도 해당 시 제거:
   - `[unknown]` 또는 `payload truncated` 포함 (parse 실패)
   - `started` 파싱 → 현재 UTC 기준 2시간+ 경과 (stale TTL)
3. Active WF Contexts 가 비면:
   - `rm -f ~/.claude/.ruler/.active` (다음 30s poll 부터 self-wake 중단)
   - state.md `Idle Transition` 섹션 append
   - `.ruler/log/{date}.md` 1줄 기록
4. 사이클 결과 요약에 sweep 건수 반영

## 종료 조건

- Sentinel 파일 `~/.claude/.ruler/.wake-stop` 존재 → wake.sh 루프 종료
- `psmux ls` 에 `ruler` 세션 부재 → 자동 종료 (EXIT_PATTERN `^ruler$`)
- 사용자 명시 `ruler stop` / `psmux kill-session -t ruler` (권장: sentinel 먼저)
