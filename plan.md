---
type: plan
scope: ruler-session-monitoring
session: btn-ruler
model: opus
created: 2026-04-20
tags: [ruler, monitoring, self-wake, checklist, design-drift]
---

# 세션 운영 plan — ruler/활성 세션 모니터링 + 설계 이탈 자동 교정

## 배경

btn-ruler 세션(opus, cwd=D:\projects\ruler)이 다음 역할을 **상주** 수행:

1. **3분 주기 self-wake** — `D:\projects\button\checklist.md` 5 체크 항목 순찰 (Lite 단계).
2. **설계 이탈 자동 교정** — secretary / wake.sh / ruler patrol 3 주체 중 설계와 다르게 동작하는 현상 발견 시 즉시 수정.
3. **지속 기록 의무** — 모든 교정을 `D:\projects\ruler\.ruler\decisions.jsonl` 에 append (§0.5 3단 기록).

## 이 세션에서 수립된 지침 (시간순)

| # | 시각 (KST) | 지시 | 조치 |
|---|---|---|---|
| D1 | 10:36 | 3분 self-wake 스킬로 타이머 켜고 checklist.md 내용대로 룰러/활성 세션 모니터링 시작 | self-wake Lite 구동 (bg task `b0rt74gmd`) — **첫 180s sleep 내 exit 확인** → nohup 방식으로 재구동 필요 |
| D2 | 10:44 | 이미지의 patrol OFF(cycle 677) 포함 진단 4건 전부 수정 + 정상화 | Step 1-6 착수 |
| D3 | 10:49 | 계속 지켜보면서 설계와 다르게 움직이는건 수정하고 ruler decisions 지속 기록 | 상주 미션으로 등록 — 매 wake 후 설계 이탈 발견 시 `decisions.jsonl` append |
| D4 | 10:50 | plan.md 에 3분 wake 부터 지금 세션에서 지시받은 것 기록 | 본 문서 |

## 발견된 설계 이탈 (2026-04-20 오전 진단 — 상세)

### I1 — secretary `.wake-stop` 무조건 touch (BLOCKER)
- **위치**: `D:/projects/button/agent/secretary.js` L1594-L1595
- **현상**: `idleStrikeCount >= 3` 도달 시 pending 수 무관하게 `.wake-stop` 찍음. pending < threshold(10) 이면 batch 도 안 뜨는데 wake.sh 만 끄는 꼴.
- **감지 증거**: `audit-log/2026-04-20.jsonl` 에 `idle_strike_threshold pending=5` 가 5-6분 주기로 11회 (00:33–01:23 UTC).
- **설계 의도** (L1486-L1491 comment): "idle-strike 3회 → **batch spawn + wake-stop**". 즉 batch 와 세트여야 함.
- **교정 방향**: wake-stop/`.active` 삭제/`idle_strike_threshold` log 를 `pendingFiles.length >= threshold && !liveBatchExists` 조건 안으로 이동. `idleStrikeCount = 0` 리셋은 무조건 유지 (무한 누적 방지).

### I2 — checklist.md ④ 지표 고장
- **위치**: `D:/projects/button/checklist.md` L47-L50
- **현상**: 비서 생존 지표로 `.secretary/.debug-ctx.log` mtime 90s 이내를 보는데, 이 파일은 2026-04-18 22:40 이후 48h+ stale. 비서는 실제 살아있음 (`audit-log/2026-04-20.jsonl` cycle_60s 10:34:48 기록).
- **교정 방향**: `audit-log/{YYYY-MM-DD}.jsonl` mtime 임계 120s (60s cycle 2회 여유).

### I3 — wake.sh 재자살 loop (부분 수정됨)
- **위치**: `D:/projects/ruler/.ruler/wake.sh`
- **기존 수정** (07aec4a): start 시점 stale `.wake-stop` 청소 추가.
- **잔여 문제**: 런타임 중 secretary 또는 ruler patrol 이 새로 찍는 `.wake-stop` 은 여전히 유효 → 30s 내 sentinel stop. **근본 해결은 I1, I4**.

### I4 — ruler patrol + secretary 이중 `.wake-stop` 경로
- **ruler patrol 쪽**: `patrol-tier-a.md` L112 — strike 3 도달 시 `touch .wake-stop` + patrol OFF. (이미지 cycle 677)
- **secretary 쪽**: L1595 — 별도 idleStrikeCount 로 같은 sentinel.
- **설계 의도**: 둘 중 어느 쪽이 SSOT? 주석상 `idle_strike_threshold=3 SSOT: wake.sh + patrol-tier-a.md C_idle_sweep` 로 patrol 이 SSOT.
- **교정 방향**: secretary 쪽은 batch spawn 시만 wake-stop (I1 수정에 포함). ruler patrol 쪽은 SSOT 유지. 단, pending<threshold 면 patrol 도 자살 전에 체크해야 → 추후 논의.

### I5 — self-wake Claude Bash bg task 조기 종료
- **현상**: `run_in_background=true` 로 돌린 self-wake 루프 (b0rt74gmd) 가 첫 180s sleep 도 못 돌고 exit 0 완료. `.self-wake-checklist-ts` 파일 미생성 = 루프 첫 iteration 진입 못 함.
- **교정 방향**: `nohup bash -c '...' > /tmp/... 2>&1 &` 방식으로 detached 실행 (wake.sh 재기동 성공 사례 참조).

## 교정 Step

- [ ] **Step 1** — secretary.js L1547-L1606 수정 (wake-stop 조건부) (model: opus)
- [ ] **Step 2** — checklist.md ④ 지표 변경 (model: sonnet)
- [ ] **Step 3** — self-wake 루프 nohup 재구동 + 첫 wake 도달 검증
- [ ] **Step 4** — `.wake-stop` 제거 + wake.sh 수동 재기동
- [ ] **Step 5** — state.md idle_strike_count 0 반영 + last_cycle_report 정정
- [ ] **Step 6** — decisions.jsonl 각 교정 append (I1/I2/I3/I4 별 entry + Step 5 state 정정)
- [ ] **Step 7** — 비서 재시작 (사용자 수동 — server.js pid kill + 재구동)
- [ ] **Step 8** — 상주 감시 (D3 지시 이행) — 매 wake 후 설계 이탈 판정

## 상주 감시 루틴 (D3 이행)

self-wake 매 tick 마다:
1. checklist.md 5 항목 실행
2. 이상 감지 시 분류:
   - **설계 이탈** (설계 문서와 코드 거동 불일치) → 즉시 교정 착수 + decisions.jsonl append `{tier:"T1_design_drift", ...}`
   - **단순 health issue** → 3줄 이내 보고 후 사용자 결정 대기
   - **정상** → `[순찰-HHMMSS] OK` 1줄
3. 신규 Step 추가 시 progress.md + 본 plan.md §교정 Step append

## 완료 조건

- [ ] Step 1-6 완료 + 커밋
- [ ] self-wake 루프 180s 이상 생존 + 첫 tick 순찰 메시지 수신 확인
- [ ] ruler wake.sh 10분+ 생존 (sentinel stop 없이)
- [ ] audit-log 에 `idle_strike_no_action` (신규 이벤트명) 확인 — pending 미달 시
- [ ] decisions.jsonl 에 I1-I4 교정 entry 4건 이상 append

## 아카이브

Step 1-8 모두 완료 후 file-standards §self-archive 따라 `.plan-archive/plan-{date}-session-monitoring.md` 이동. 본 plan.md 는 **상주 성격** (D3) 이라 마지막 Step 이 없음 → 사용자가 "종료해" 지시 시 아카이브.
