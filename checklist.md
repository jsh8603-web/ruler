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
