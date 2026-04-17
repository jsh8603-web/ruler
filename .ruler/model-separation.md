---
type: ruler-model-separation
date: 2026-04-15
tags: [ruler, sonnet, opus, model-routing, load/on-demand]
---

# Ruler 모델 분리 정책 (2026-04-14 Sonnet Migration Phase 1)

(root: [`~/.claude/.ruler/patrol.md`](~/.claude/.ruler/patrol.md) §모델 분리 / [`~/.claude/skills/ruler-wf/skill.md`](~/.claude/skills/ruler-wf/skill.md) §5a 에서 참조)

**프레임**: 순찰 세션 = **Sonnet** (1차 반응, 빠른/싼 감지+T1 기계적 적용). batch 세션 = **Opus** (2차 사후 Supervisor, 의존성 묶음 + Step 0 소급 review + rollback 판정).

**근거**: decisions.jsonl + rollback/*.bak + log/{date}.md 3중 기록이 있으므로 Sonnet 순찰이 잘못 판정한 T1 은 다음 batch Step 0 에서 소급 rollback 가능. 순찰 패스를 Sonnet 으로 내리면 월 토큰 350만→100만 (70% 절감) 추정.

## 역할 매핑

| 세션 | 모델 | 책임 | 판단 한계 |
|---|---|---|---|
| `ruler` (장수명 순찰) | **sonnet** | C1~C18 전수 순회 / T1 기계적 수정 / pending 수집 / §2a sweep / idle 전환 | 의존성 그래프 분해·semantic 판정 금지 → 즉시 pending 으로 넘김 |
| `ruler-batch-{ts}` (단수명) | **opus** | Step 0 사후 review / 의존성 그래프 / 그룹 실행 / rollback 판정 / urgent 승격 질의 | — |

## `opus_only_files` — T1 경로 hard-block

patrol(Sonnet) T1 경로에서 Edit 차단되는 파일. 항상 Opus batch 경유. `t1-gate.sh` §(0) 가 파일 경로로 hard-block 한다. Sonnet 이 실수로 Edit 시도해도 exit 1 + T2 강제 전환.

- `D:/projects/button/agent/secretary.js`
- `D:/projects/button/agent/secretary/*.js` (11개 factory)
- `D:/projects/button/agent/.secretary/.scripts/revive.sh`
- `D:/projects/button/agent/.secretary/.scripts/generate-session-resume.sh`
- `D:/projects/button/agent/.secretary/.scripts/bash-guard.js`
- `~/.claude/settings.json`
- `~/.claude/memory/promotion-log.md` (append 포함 — E{n} 번호 충돌 semantic 판정 필요)
- `~/.claude/.ruler/patrol.md` (자기수정)
- `~/.claude/skills/ruler-wf/skill.md` (자기수정)

## Sonnet 판정 한계 — 즉시 pending escalate

- **C3** Symmetric fix propagation — diff semantic 판정
- **C9** promotion-log ERROR 4필드 완결성 — 필드 의미 해석 필요
- **C12** guard 교착 원인 분기 — 2차 batch 판정
- **C14** plan/progress 아카이브 Tier 2 (Abandoned 의심) — target grep escalate
- **t1-gate.sh FAIL** — 이유 불문 T2

## Sonnet → Opus 사이클 중간 escalation

사이클 중 아래 조건 발견 시 Sonnet 순찰이 해당 사이클 나머지 C-check 를 skip + idle 전환 + batch 스폰 우선화:

- **C1** regression suite FAIL (Urgent)
- **C16** heartbeat crashed (Urgent)
- rollback 예산 >15% 초과 (`force_opus_fallback: true`)

중간 escalation 시 state.md `escalation_reason` 필드 기록.

## 첫 1일 보수 모드 (자동)

Sonnet Phase 1 런칭 후 첫 24시간 `batch_threshold: 1` 강제. 매 사이클 §2a sweep 직후 자동 검사:

```
(now >= batch_threshold_restore_ts) AND (rollback_count_since_cycle52 == 0)
```

→ 즉시 `batch_threshold: 10` 로 승격 + state.md 갱신 + decisions.jsonl `action:"threshold_auto_restored"` 기록. **사용자 액션 0건**.

## 모델 전환 자동 트리거

- **Sonnet 진입**: cycle 52 완료 후 state.md `sonnet_switch_pending: true` 설정 → 다음 ruler 세션 wake 시 wake.sh 가 플래그 감지 → `model-switch-and-send.sh ruler sonnet '{handoff-note}'` 호출 (self-target 시 스크립트가 자동 background self-reinvoke, 호출 측 특별 조치 불필요) → 성공 시 플래그 clear + decisions.jsonl `action:"sonnet_transition_auto"` 기록.
- **Opus 복귀**: Sonnet 패스 rollback >15% 감지 → `force_opus_fallback: true` 설정 → 다음 사이클 wake 시 동일 자동 메커니즘으로 `model-switch-and-send.sh ruler opus 'rollback budget exceeded'` 호출.

수동 `/ruler opus` 지시 제거 — 사용자 개입 완전 배제.

## Rollback 예산 auto-throttling

Sonnet 순찰의 오판률을 결정론적으로 모니터링해 임계 초과 시 자동으로 Opus fallback.

**계산식**: `rate = rolled_back_count / total_t1_count` (최근 50건 window)

```bash
total=$(tail -50 ~/.claude/.ruler/decisions.jsonl | jq -s '[.[] | select(.tier=="T1")] | length')
rb=$(tail -50 ~/.claude/.ruler/decisions.jsonl | jq -s '[.[] | select(.action=="retroactive_rollback" or .outcome=="rolled_back")] | length')
rate=$(awk -v t=$total -v r=$rb 'BEGIN{if(t==0)print 0; else printf "%.3f", r/t}')
```

**임계값 2단계**:

| 임계 | 플래그 | 조치 |
|---|---|---|
| `rate >= 0.05` (5%) | `rollback_budget_warn: true` | `.ruler/log/{date}.md` 경고 블록 + 다음 사이클 시작 시 사용자 알림 (1회) |
| `rate >= 0.15` (15%) | `force_opus_fallback: true` | 다음 사이클부터 순찰 세션도 Opus 강제 전환 (`model-switch-and-send.sh ruler opus 'rollback budget exceeded'`) + 긴급 알림 |

**해제 조건**: 새로운 50건 window 에서 rate 가 임계 아래로 자동 clear. `force_opus_fallback` 은 30 사이클 연속 0 rollback 관측 시 자동 해제.

**측정 주기**: 매 사이클 §2a sweep 직후.

**False positive 방지**: 초기 1~2 사이클 total < 5 면 rate 계산 skip (`rate=0` 강제). 데이터 부족 시 throttling 무의미.

**기록**:
- `.ruler/log/{date}.md` 매 측정 `rollback_rate: {N/M = rate}` 1줄
- decisions.jsonl 는 임계 돌파 시점만 `{action:"budget_threshold_crossed", level:"warn|force"}` append
