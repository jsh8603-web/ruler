# 세션·룰러 모니터링 체크리스트 (3분 self-wake)

**목표**: btn-button 세션이 3분마다 깨어나 활성 psmux 세션 + 룰러 health 관찰. 이상 발견 시 1줄 보고.

**간섭 금지 원칙**: ruler patrol 세션은 자체 3분 wake 루프 보유 + 자체 순찰 수행 중. 이 체크리스트는 **중복 순찰 금지**, health 수준만.

---

## 매 wake 실행 절차 (순서대로)

### ① Agent health
```bash
curl -s http://localhost:9876/health
```
- 기대: `{"status":"online", ...}`
- 실패 시: Agent 재구동 필요 보고

### ② psmux 활성 세션 목록
```bash
PSMUX="/c/Users/jsh86/AppData/Local/Microsoft/WinGet/Packages/marlocarlo.psmux_Microsoft.Winget.Source_8wekyb3d8bbwe/psmux.exe"
"$PSMUX" list-sessions 2>&1
```

**예상 세션** (현재 알려진):
- `ruler` — patrol (Sonnet, 장수명)
- `btn-button` — 본인
- `btn-babyplace` / `btn-Codlearn` / `btn-Obsidian` — 사용자 작업 세션
- `btn-ruler` — D:\projects\ruler 작업 세션 (신규)
- `ruler-batch-*` — 일시 존재 (batch 실행 중에만)

**보고 대상**:
- `ruler` 부재 → ⚠️ 메타 감시 정지 (즉시 경고)
- 신규/제거 세션 → 변동 1줄 보고

### ③ 룰러 health (존재 시만, 순찰 금지)
```bash
cat /d/projects/ruler/.ruler/.cycle 2>/dev/null
cat /d/projects/ruler/.ruler/.idle-strike 2>/dev/null
stat -c '%Y' /d/projects/ruler/.ruler/.last-patrol-ts 2>/dev/null
stat -c '%Y' /d/projects/ruler/.ruler/.wake-ts 2>/dev/null
ls /d/projects/ruler/.ruler/.wake-stop 2>/dev/null
date +%s
```
- `.idle-strike ≥ 3`: ⚠️ all-idle sweep 반복 중 (룰러가 다른 세션 깨우지 못함)
- 현재시각 - `.last-patrol-ts` > 600초: ⚠️ 룰러 10분+ 정지
- 현재시각 - `.wake-ts` > 90초 또는 `.wake-ts` 부재: ⚠️ wake.sh 프로세스 죽음 (설계 원안: wake.sh L92 가 30s 주기 무조건 갱신, 2회+ 누락 = 이상)
- `.wake-stop` 존재 + 60초+ 유지: ⚠️ sentinel 잔존 — wake.sh 재기동 차단 중 (I3 유사 재발 신호)
- 정상 범위 내면 **보고 생략** (간섭 금지)

### ④ 비서 루프 생존
```bash
stat -c '%Y' ~/.claude/audit-log/$(date +%Y-%m-%d).jsonl 2>/dev/null
date +%s
```
- 차이 > 120초: ⚠️ 비서 runCycle 정지 의심 (설계 원안: secretary.js L1610 `cycle_60s` 가 60s 주기 무조건 append, 2회+ 누락 = 정지)
- **참고 (2026-04-20 I2 fix)**: 기존 지표 `.debug-ctx.log` 는 조건부 디버그 로그 (context 판정 엣지 케이스 only, secretary.js L1076) — 주기 지표로 부적합. audit-log cycle_60s 를 SSOT 로 삼음.

### ⑤ 최근 ERROR / 에스컬레이션 (30분 이내)
```bash
ls -1t ~/.claude/audit-log/*.jsonl 2>/dev/null | head -1 | xargs tail -50 \
  | grep -E '"type":"(escalation_escalated|stuck|guard_deadlock|rate_limit)"' | tail -3
```
- 결과 있으면 1-2줄로 요약
- 없으면 보고 생략

### ⑥ idle_strike × audit-log 이벤트 매핑 검증 (2026-04-20 I6 fix, 2단계 threshold)
설계 원안: strike 1-2=정상 wake / **strike 3=batch 소환 시도** / strike 4=정상 wake / **strike 5=wake-stop sentinel + .active 삭제** / **strike 6+=비서 wake signal 미송신 (자연 정지)**. 이탈 시 T1_design_drift.
```bash
# 오늘 audit-log 내 strike 별 이벤트 매핑
AL=~/.claude/audit-log/$(date +%Y-%m-%d).jsonl
echo "--- strike 3 시점 (batch 시도 있어야) ---"
grep -E '"strike":3|"strike":"3"' "$AL" 2>/dev/null | grep -E '"type":"(batch_spawn_initiated|batch_spawn_skipped|idle_strike_no_action)"' | tail -3
echo "--- strike 5 시점 (wake-stop 찍혀야) ---"
grep -E '"strike":5' "$AL" 2>/dev/null | grep -E '"type":"(idle_strike_wake_stop|ruler_idle_wake|ruler_idle_wake_stopped)"' | tail -3
echo "--- strike 6+ (wake signal 없어야, ruler_idle_wake_stopped 만) ---"
grep -E '"strike":[6-9]|"strike":1[0-9]' "$AL" 2>/dev/null | grep -E '"type":"(ruler_idle_wake|ruler_idle_wake_stopped)"' | tail -3
```
- strike 3 시점에 `batch_spawn_initiated|_skipped|idle_strike_no_action` 셋 중 하나 없음: ⚠️ strike 3 로직 이탈
- strike 5 시점에 `idle_strike_wake_stop` 없음: ⚠️ wake-stop sentinel 미작동
- strike 6+ 시점에 `ruler_idle_wake` (미발사 설계인데 발사됨): ⚠️ counter autofill drift 재발
- 위 3건 전부 설계대로 → 보고 생략

---

## 보고 양식

**정상 (생략 허용)**:
```
[순찰-HHMMSS] OK
```

**1줄 보고**:
```
[순찰-HHMMSS] Agent:OK | psmux:6 | ruler cycle=570 strike=0 | alerts:0
```

**이상 발견** (해당 항목만, 3줄 이내):
```
[순찰-HHMMSS] ⚠ ruler 부재 — spawn-session.sh 수동 스폰 필요
[순찰-HHMMSS] ⚠ btn-babyplace escalation_escalated — stuck 주의
```

---

## 정지 조건

- `.watchdog-stop-checklist` 파일 touch → 다음 사이클에서 graceful exit
- btn-button 세션 종료 → 루프 자동 종료 (EXIT_PATTERN 매칭)
- 동일 경고 3회 연속 → 보고 생략 (스팸 방지)

## 관련 파일
- self-wake 패턴: `~/.claude/skills/self-wake/skill.md`
- 룰러 운영: `D:\projects\ruler\.ruler\patrol.md` (patrol 자체 순찰)
- 비서: `D:\projects\button\agent\secretary.js`
- wake 타임스탬프: `D:\projects\button\.self-wake-checklist-ts` (본 루프 전용)

---

## 심층 기능 검증 (주간 또는 수동 트리거)

> **복원 배경** (2026-04-20): 이 체크리스트는 원래 "**ruler patrol 이 정상 작동하는지 감시**" 목적의 V3 (2026-04-16, 135줄) 이었는데 어떤 agent 가 self-wake 용으로 덮어쓰면서 감시 항목이 유실됨. V3 내용을 아래 섹션으로 복원하여 self-wake health(①~⑥) + 심층 기능 검증(아래) 을 병존.
>
> **실행 시점**: 3분 self-wake 루프에는 포함하지 않음 (무거움). **주간 또는 사용자가 "심층 검증해" 트리거 시** 별도 실행. 결과 항목 중 FAIL 발견 시 decisions.jsonl append (tier: T1_design_drift 또는 T2_pending).

### 1. 이벤트 감시 시스템 (event-rules.yaml v6)

#### 1-1. audit-log 이벤트 정상 emit 확인
- [ ] `cat ~/.claude/audit-log/$(date +%Y-%m-%d).jsonl | grep -o '"type":"[^"]*"' | sort -u | wc -l` → 15종+ 이벤트 타입 존재
- [ ] `grep '"type":"cycle_60s"' ~/.claude/audit-log/$(date +%Y-%m-%d).jsonl | tail -1` → 최근 5분 이내 타임스탬프
- [ ] `grep '"type":"jsonl_audit"' ~/.claude/audit-log/$(date +%Y-%m-%d).jsonl | tail -1` → session 필드 + context 필드 존재

#### 1-2. 트리거 이벤트 타입 정합성
- [ ] `grep '"type":"work_complete"' ~/.claude/audit-log/$(date +%Y-%m-%d).jsonl | head -1` → 존재 확인 (event #28 트리거)
- [ ] `grep '"type":"consecutive errors"' ~/.claude/audit-log/$(date +%Y-%m-%d).jsonl | head -1` → count 필드 존재 (event #26 트리거)
- [ ] `grep '"type":"registry_model_refresh"' ~/.claude/audit-log/$(date +%Y-%m-%d).jsonl | head -1` → session 필드 존재 (event #11, #33 트리거)
- [ ] `grep '"type":"ctx_warn_jsonl"' ~/.claude/audit-log/$(date +%Y-%m-%d).jsonl | head -1` → stage 필드 존재 (event #1, #6, #24 트리거)

#### 1-3. WF 완료 감지 (v6 fix)
- [ ] `grep "wf_complete" D:/projects/button/agent/secretary/nudges.js` → `log_event('wf_complete'` 존재
- [ ] `.wf-active` 파일 비존재 시: 정상 (WF 미활성)
- [ ] `.wf-active` 파일 존재 시: `stat D:/projects/button/.wf-active` → mtime 확인, WF 활성 상태

#### 1-4. stuck 모듈 이벤트 (15s 사이클)
- [ ] `grep -oP '"type":"(stuck|tool_frozen|agent_pending|read_only_loop|circular_work)"' ~/.claude/audit-log/$(date +%Y-%m-%d).jsonl | sort -u` → 해당 이벤트 존재 (활성 세션 있을 때)
- [ ] `grep '"type":"circular_work"' ~/.claude/audit-log/$(date +%Y-%m-%d).jsonl | tail -1` → session 필드 존재

#### 1-5. escalation 이벤트 체인 (60s 사이클)
- [ ] `grep -oP '"type":"(escalation_warned|escalation_escalated|struggle)"' ~/.claude/audit-log/$(date +%Y-%m-%d).jsonl | sort -u` → FSM 이벤트 존재 (에러 발생 세션 있을 때)

#### 1-6. event-patrol 비서 편입 (300s 사이클)
- [ ] `grep '"type":"event_patrol_candidates"' ~/.claude/audit-log/$(date +%Y-%m-%d).jsonl | tail -1` → count + events 필드 존재
- [ ] `test -f ~/.claude/.ruler/scripts/event-patrol.py` → 스크립트 존재
- [ ] `grep "runEventPatrol" D:/projects/button/agent/secretary.js` → 300s 사이클에 호출 존재

### 2. 비서 모듈 정상 작동

#### 2-1. registry 동기화
- [ ] `cat D:/projects/button/agent/.secretary/.session-registry.txt` → 현재 psmux 세션과 일치
- [ ] `psmux ls` 출력의 btn-* 세션이 registry에 모두 등록되어 있는지 대조

#### 2-2. 비서 heartbeat (15s/60s/300s 사이클)
- [ ] `grep cycle_60s ~/.claude/audit-log/$(date +%Y-%m-%d).jsonl | wc -l` → 1시간 기준 ~60건
- [ ] 최근 cycle_60s 타임스탬프와 현재 시각 차이 < 120s
- [ ] `grep '"type":"jsonl_audit"' ~/.claude/audit-log/$(date +%Y-%m-%d).jsonl | wc -l` → 300s 사이클 증거 (1시간 ~12건)

#### 2-3. ctx-warn 정상 발동
- [ ] 토큰 80k+ 세션이 있을 때 `ctx_warn_jsonl` 이벤트 존재 확인
- [ ] ctx_warn 후 MEMORY.md에 ckpt 마커 존재 확인: `tail -5 ~/.claude/projects/*/memory/MEMORY.md | grep ckpt`
- [ ] `.warn` flag stale 확인: `find D:/projects/button/agent/.secretary/.ctx-warn-ts -name "*.warn" -mmin +60` → 1시간+ stale 없어야 정상 (BUG-U fix)

#### 2-4. resume 모듈 — 세션 부활/압축 주입
- [ ] `grep '"type":"compression_resume_injected"' ~/.claude/audit-log/$(date +%Y-%m-%d).jsonl | head -3` → via 필드 (flag/pending) 존재
- [ ] `grep '"type":"session_revived"' ~/.claude/audit-log/$(date +%Y-%m-%d).jsonl | head -3` → 부활 이벤트 확인 (세션 death 있을 때)

#### 2-5. guard-deadlock 감지
- [ ] `grep '"type":"guard_deadlock"' ~/.claude/audit-log/$(date +%Y-%m-%d).jsonl | head -3` → 교착 감지 시 이벤트 존재
- [ ] `grep "guardDetectedAt" D:/projects/button/agent/secretary/guard-deadlock.js` → 상태 관리 코드 존재

#### 2-6. commits 모듈 — work_complete + diff_broadcast
- [ ] `grep '"type":"work_complete"' ~/.claude/audit-log/$(date +%Y-%m-%d).jsonl | wc -l` → 커밋 있으면 1건+
- [ ] `grep "diff_broadcast\|simplify_reminder" D:/projects/button/agent/secretary/commits.js` → 함수 존재

#### 2-7. nudges 모듈 — progress/promo 넛지
- [ ] `grep '"type":"promo_nudge"' ~/.claude/audit-log/$(date +%Y-%m-%d).jsonl | grep -oP '"trigger":"[^"]*"' | sort -u` → 트리거 종류 확인
- [ ] `grep "checkProgressModelDrift" D:/projects/button/agent/secretary/nudges.js` → §B 복귀 드리프트 감지 함수 존재

#### 2-8. presence 모듈 — idle/rate-limit
- [ ] `grep -oP '"type":"(user_absent|user_returned|rate_limit|file_conflict)"' ~/.claude/audit-log/$(date +%Y-%m-%d).jsonl | sort -u` → 이벤트 존재 (해당 상황 발생 시)

### 3. 파일 무결성

#### 3-1. event-rules.yaml
- [ ] `head -7 ~/.claude/.ruler/event-rules.yaml | grep "v6"` → v6 버전 확인
- [ ] `grep "^  [a-z_]*:" ~/.claude/.ruler/event-rules.yaml | wc -l` → 33개 이벤트 ID

#### 3-2. patrol 문서 체계
- [ ] `test -f ~/.claude/.ruler/patrol.md` → 존재
- [ ] `test -f ~/.claude/.ruler/patrol-tier-a.md` → 존재
- [ ] `test -f ~/.claude/.ruler/patrol-tier-c.md` → 존재
- [ ] `test -f ~/.claude/.ruler/patrol-wf-checks.md` → 존재

#### 3-3. C-check 목록 일관성
- [ ] `grep "^## C" ~/.claude/.ruler/patrol-tier-c.md | wc -l` → C-check 개수 (C3~C33, 약 22개)
- [ ] `grep "VaultVoice" ~/.claude/.ruler/patrol-tier-c.md` → C8 + C28에 VaultVoice 검증 존재

#### 3-4. secretary 모듈 12종 존재
- [ ] 아래 실행 → 전부 OK:
```bash
for f in commits.js ctx-warn.js escalation.js guard-deadlock.js jsonl-audit.js \
  memory-nudge.js nudges.js presence.js registry.js resume.js stuck.js psmux-send-helper.js; do
  test -f "D:/projects/button/agent/secretary/$f" && echo "OK: $f" || echo "MISSING: $f"
done
```

#### 3-5. wake.sh + event-patrol 연동
- [ ] `grep "event-patrol" ~/.claude/.ruler/wake.sh` → 이벤트 판정 지시 존재 (wake 메시지에 포함)
- [ ] `grep "runEventPatrol" D:/projects/button/agent/secretary.js` → 비서 300s 사이클 편입 확인

### 4. 회귀 테스트

#### 4-1. secretary 통합 회귀
- [ ] `bash ~/.claude/docs/verification/secretary-regression/run-all.sh 2>&1 | tail -5` → "TOTAL: 4/4 suites PASS"

#### 4-2. secretary 11모듈 require 검증
- [ ] 아래 실행 → 전부 OK:
```bash
"/c/Program Files/nodejs/node.exe" -e "
['commits','ctx-warn','escalation','guard-deadlock','jsonl-audit',
 'memory-nudge','nudges','presence','registry','resume','stuck'].forEach(m => {
  try { require('D:/projects/button/agent/secretary/' + m + '.js'); process.stdout.write('OK: ' + m + '\n'); }
  catch(e) { process.stdout.write('FAIL: ' + m + ' - ' + e.message + '\n'); }
});
"
```

### 5. ruler SSOT 문서 연결

- [ ] `grep "v6" ~/.claude/skills/ruler-wf/skill.md` → 이벤트 수 33개 반영 확인
- [ ] `grep "v6" ~/.claude/rules/secretary-system.md` → §7 갱신 확인
- [ ] `grep "33" ~/.claude/.ruler/event-rules.yaml` → #33 direct_model_switch_detected 존재
- [ ] `wc -l < D:/projects/button/agent/secretary.js` → secretary-system.md 표 줄 수와 ±50 이내

### 심층 검증 실행 가이드

```bash
# 전체 자동 실행 (bash one-liner, 핵심 항목만)
echo "=== 1-1: event types ===" && cat ~/.claude/audit-log/$(date +%Y-%m-%d).jsonl | grep -o '"type":"[^"]*"' | sort -u | wc -l && \
echo "=== 1-6: event_patrol ===" && grep '"type":"event_patrol"' ~/.claude/audit-log/$(date +%Y-%m-%d).jsonl | wc -l && \
echo "=== 2-1: registry ===" && wc -l D:/projects/button/agent/.secretary/.session-registry.txt && \
echo "=== 2-3: stale .warn ===" && find D:/projects/button/agent/.secretary/.ctx-warn-ts -name "*.warn" -mmin +60 2>/dev/null | wc -l && \
echo "=== 3-1: v6 ===" && head -7 ~/.claude/.ruler/event-rules.yaml | grep v6 && \
echo "=== 3-4: modules ===" && ls D:/projects/button/agent/secretary/*.js | wc -l && \
echo "=== 4-1: regression ===" && bash ~/.claude/docs/verification/secretary-regression/run-all.sh 2>&1 | tail -3
```

---

## Retro. (주간 retrospective 모니터링)

Ruler retrospective 가 주 1회 자동 돌지만, 사용자 side 에서 정상 가동을 확인하는 체크리스트. 2026-04-18 plan (retrospective 완성도 보완) 의 최종 구현 반영.

### A. 주간 retrospective 가동

- [ ] 최근 retrospective 실행 ts 확인 (`ls -lt D:/projects/ruler/.ruler/retrospective/*.md | head -1`) — 7일 이내인가
- [ ] 가장 최근 `change-impact.md` 에서 `BAD:` 카운트 0 인가 (아니면 pending 검토)
- [ ] `D:/projects/ruler/.ruler/external-skill-checksums.md` 의 ruler-wf / audit-wf 해시가 실제 skill.md 해시와 일치하는가 (drift 없음)
- [ ] 가장 최근 collect 결과의 `missing_files` 길이 0 (backfill 된 건은 decisions.jsonl 에 `original_absent:true` 로 남음)
- [ ] obs-only 해제 여부 (`grep 'change_impact_enforcement_start' D:/projects/ruler/.ruler/state.md`) — 오늘 이전이면 enforcement 활성, 이후이면 obs-only

### B. 소스 기록 건전성 (Step 11-13, 감사 gap 조치)

- [ ] 비서 audit-log 에 `type:"ERROR"` 또는 `type:"error_detected"` 이벤트 쌓이는지 (`grep -c '"type":"ERROR"\|"type":"error_detected"' ~/.claude/audit-log/*.jsonl | tail -1`) — 비서 재시작 후 1건 이상
- [ ] `.secretary-state.json` 에 `escalation_count` 필드 존재 (`jq '.escalation_count' D:/projects/button/agent/.secretary/.secretary-state.json`) — null 아님
- [ ] audit-log `type:"regression_failed"` 기록 가능 (`grep -c 'regression_failed' D:/projects/ruler/.ruler/scripts/t1-gate.sh` ≥ 1)
- [ ] Phase C 종료 시 `log/{YYYY-MM-DD}.md` 에 batch 블록 append 되는지 (최근 batch 3개 기준)
- [ ] `decisions.jsonl` tier 값 표준 준수 (`t1-gate.sh --validate-entry` regex `^(T[0-3](_[a-z_]+)?|archive|observe)$` 통과)

### C. 자동화 hook/gate 작동 (Step 14, 16)

- [ ] `~/.claude/hooks/ruler-decisions-autolog.sh` 존재 + 실행권한 + settings.json 등록
- [ ] Ruler 전역 파일 (`.ruler/*.md`, `rules/*.md`) 편집 시 decisions.jsonl 에 `tier:"T0_autolog"` entry 자동 append (최근 24h 기준)
- [ ] retrospective-collect.sh T-point 추출 범위: `T1` prefix + `T2_batch_applied` (`test("^T1")` 매칭)
- [ ] Poisson CI 임계값 `N<5` 적용 (초기 부트스트랩 완화, `grep 'pre_count.*-lt 5' D:/projects/ruler/.ruler/scripts/retrospective-collect.sh`)
- [ ] 통합 smoke 3/3 PASS (`bash D:/projects/ruler/.ruler/tests/test-compute-change-impact.sh`)
