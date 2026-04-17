#!/bin/bash
# ruler wake.sh — 3분 Self-Wake 루프
# 구동: bash ~/.claude/.ruler/wake.sh (spawn-session.sh ruler 에서 background 호출)
# 종료: .wake-stop sentinel 또는 ruler 세션 부재

PSMUX="/c/Users/jsh86/AppData/Local/Microsoft/WinGet/Packages/marlocarlo.psmux_Microsoft.Winget.Source_8wekyb3d8bbwe/psmux.exe"
SESSION="ruler"
RULER_DIR="$HOME/.claude/.ruler"
cd "$RULER_DIR" || exit 1
mkdir -p .messages log

# 중복 구동 방지 — .wake-ts mtime 기반 (MSYS2 PID ≠ Windows PID 이므로 kill -0 불가)
# .wake-ts 가 60s 이내 갱신됐으면 기존 인스턴스 활성 → 즉시 exit
if [ -f .wake-ts ]; then
  _MTIME=$(stat -c %Y .wake-ts 2>/dev/null || echo 0)
  _NOW=$(date +%s)
  _AGE=$((_NOW - _MTIME))
  if [ "$_AGE" -lt 60 ]; then
    echo "[ruler-wake] already running (.wake-ts ${_AGE}s fresh)"
    exit 0
  fi
fi

echo "$(date +%s%3N)" > .wake-ts
echo $$ > .wake-pid
trap 'rm -f .wake-pid .wake-ts' EXIT
echo "[ruler-wake] started at $(date) pid=$$" >> log/$(date +%Y-%m-%d).md

# === Phase 1 Sonnet Migration — batch_threshold 자동 복귀 ===
# state.md 의 batch_threshold_restore_ts 도달 + 그간 rollback 0건 이면 batch_threshold 를 10 으로 승격.
RESTORE_TS=$(grep -oP '^batch_threshold_restore_ts:\s*\K[0-9T:Z\-]+' state.md 2>/dev/null || echo "")
CURRENT_BT=$(grep -oP '^batch_threshold:\s*\K[0-9]+' state.md 2>/dev/null || echo "10")
if [ -n "$RESTORE_TS" ] && [ "$CURRENT_BT" = "1" ]; then
  NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  if [ "$NOW_ISO" \> "$RESTORE_TS" ]; then
    # rollback 카운트 — decisions.jsonl 에서 그 동안의 rolled_back 개수
    RB_COUNT=$(grep -c 'rolled_back\|retroactive_rollback' decisions.jsonl 2>/dev/null || echo "0")
    if [ "$RB_COUNT" = "0" ]; then
      sed -i 's/^batch_threshold: 1.*/batch_threshold: 10  # 24h + 0 rollback 자동 복귀 (wake.sh)/' state.md
      echo "[ruler-wake] batch_threshold 1→10 auto-restored at $(date) (rb_count=0)" >> log/$(date +%Y-%m-%d).md
    fi
  fi
fi

while true; do
  # 짧은 체크 주기: 30s 마다 .active 플래그 감지 → 순찰 여부 판단
  sleep 30

  # Sentinel 종료
  if [ -f .wake-stop ]; then
    rm -f .wake-ts .wake-pid .wake-stop
    echo "[ruler-wake] sentinel stop at $(date)" >> log/$(date +%Y-%m-%d).md
    exit 0
  fi

  # ruler 세션 생존 확인 (psmux has-session)
  # 2026-04-16 (BUG-U): ruler 부재 + wake signal 있으면 auto-spawn → loop 유지.
  # 신호 없으면 종전대로 exit (agent restart 시 재구동). 사유: 신호 자체가 소환
  # 요청이므로 ruler 가 죽어도 신호 queue 만 쌓이고 consume 안 되는 dead state
  # 방지. spawn 실패 시 .spawn-failed sentinel 쓰고 exit (무한 루프 방지).
  if ! "$PSMUX" has-session -t ruler 2>/dev/null; then
    shopt -s nullglob
    _pending=(.messages/wake-*.txt)
    _pending_queue=(pending/*.md)
    shopt -u nullglob
    # 2026-04-17: auto-spawn 트리거 확장 — signal OR pending 디렉토리 overflow (>=15).
    # 사유: babyplace 같은 장시간 active 세션이 있으면 secretary 가 all-idle 조건을
    # 못 만족해서 wake signal 을 drop 하지 않음 → ruler 부재 + signal 0 으로 wake.sh
    # 가 영구 exit. pending 이 쌓이고 있다는 건 ruler 소환이 필요한 상태이므로 signal
    # 없이도 auto-spawn 해야 한다.
    _PENDING_OVERFLOW_THRESHOLD=15
    if { [ ${#_pending[@]} -gt 0 ] || [ ${#_pending_queue[@]} -ge "$_PENDING_OVERFLOW_THRESHOLD" ]; } && [ ! -f .spawn-failed ]; then
      echo "[ruler-wake] ruler absent + signals=${#_pending[@]} pending-queue=${#_pending_queue[@]} → auto-spawn at $(date)" >> log/$(date +%Y-%m-%d).md
      ( bash /d/projects/button/agent/.secretary/.scripts/spawn-session.sh ruler >> log/$(date +%Y-%m-%d).md 2>&1 & )
      sleep 10
      if ! "$PSMUX" has-session -t ruler 2>/dev/null; then
        echo "[ruler-wake] auto-spawn failed — sentinel + exit at $(date)" >> log/$(date +%Y-%m-%d).md
        touch .spawn-failed
        rm -f .wake-ts
        exit 1
      fi
      echo "[ruler-wake] auto-spawn success — loop continues at $(date)" >> log/$(date +%Y-%m-%d).md
      rm -f .spawn-failed
    else
      rm -f .wake-ts
      echo "[ruler-wake] ruler session gone, signals=${#_pending[@]} pending-queue=${#_pending_queue[@]}, exit at $(date)" >> log/$(date +%Y-%m-%d).md
      exit 0
    fi
  fi

  # 루프 생존 타임스탬프 갱신 (중복 구동 방지용)
  echo "$(date +%s%3N)" > .wake-ts

  # .messages/wake-*.txt 감지 → .active touch + consume
  # 2026-04-14: 활성화 모델 재설계. 비서가 watched 세션의 WAITING→WORKING edge 를
  # 감지해 신호 파일을 drop 하면, 여기서 consume 하고 ruler patrol 을 재개한다.
  # 근거: plan.md Step 2 (D:\projects\ruler\plan.md)
  _just_consumed=0
  shopt -s nullglob
  _signals=(.messages/wake-*.txt)
  shopt -u nullglob
  if [ ${#_signals[@]} -gt 0 ]; then
    touch .active
    for _sig in "${_signals[@]}"; do rm -f "$_sig"; done
    # strike 리셋은 여기서 안 함 — idle-skip 의 WORKING 재감지(L174)에서만 리셋.
    # signal consume 은 .active 활성화 + patrol 즉발 목적만.
    _just_consumed=1
    echo "[ruler-wake] wake signal consumed (${#_signals[@]} files) at $(date)" >> log/$(date +%Y-%m-%d).md
  fi

  # stale 4h failsafe 제거 (2026-04-14): idle 해제는 이제 patrol 의 C_idle_sweep 이
  # 3회 연속 전원 non-WORKING 감지로 담당. wake.sh 는 단순 신호 파일 폴링만.

  # 2026-04-15: Level-trigger fallback — edge 놓친 recovery.
  # secretary.js L1180 edge 조건은 prevStatus!==undefined 필요 → agent 재시작 후
  # 이미 WORKING 이던 세션은 첫 관측이 set-only 로 끝나 wake signal 영영 미발사.
  # .active 없음 + watched WORKING 1개 이상 감지 시 level 로 .active 생성.
  if [ ! -f .active ] && [ "$_just_consumed" -eq 0 ]; then
    for _S in $("$PSMUX" ls 2>/dev/null | cut -d: -f1); do
      case "$_S" in ruler|ruler-batch-*|task|schedule|secretary|worker|verifier|healer|strategic|btn-button) continue;; esac
      _CAP=$("$PSMUX" capture-pane -p -S -5 -t "$_S" 2>/dev/null)
      if echo "$_CAP" | grep -qE 'esc to interrupt|✽|Running…|Running\.\.\.|tokens.*esc'; then
        touch .active
        _just_consumed=1
        echo 0 > .idle-strike
        echo "[ruler-wake] level-trigger activate at $(date) — $_S WORKING (edge 놓침 recovery)" >> log/$(date +%Y-%m-%d).md
        break
      fi
    done
  fi

  # .active 플래그 없으면 idle 모드 — 순찰 메시지 보내지 않고 다음 체크로
  if [ ! -f .active ]; then
    continue
  fi

  # 마지막 순찰으로부터 180s+ 경과 여부 확인 (3분 주기 유지)
  # 2026-04-15 bugfix: 방금 signal consume 한 iteration 은 DIFF 체크 우회.
  # edge 는 즉발 사유이므로 180s 쿨다운과 무관하게 즉시 fire 해야 함.
  LAST=$(cat .last-patrol-ts 2>/dev/null || echo 0)
  NOW=$(date +%s%3N)
  DIFF=$(( (NOW - LAST) / 1000 ))
  if [ "$DIFF" -lt 180 ] && [ "$_just_consumed" -eq 0 ]; then
    continue
  fi

  # idle-skip 블록 제거 (2026-04-17): idle-strike 카운팅은 ruler C_idle_sweep 전담.
  # wake.sh 는 비서 wake signal 있는 한 patrol 메시지를 무조건 전달하는 중계 역할.
  # 비서 idleWakeCounter(5회)가 자연 소진되면 signal 고갈 → patrol 자동 중단.
  # ruler 가 C_idle_sweep 에서 idle-strike 3 도달 시 batch spawn + .wake-stop 생성.

  # 사이클 번호 증가 + 순찰 시각 기록
  CYCLE=$(cat .cycle 2>/dev/null || echo 0)
  CYCLE=$((CYCLE+1))
  echo $CYCLE > .cycle
  echo "$NOW" > .last-patrol-ts

  # 패트롤 메시지 (체크리스트 인라인 + patrol.md Read 지시, 2중 안전)
  # 2026-04-16: 이벤트 패트롤은 비서(secretary.js 300s 사이클)가 기계적 실행.
  # ruler는 candidate 판정만 담당. wake signal에 candidate 목록 포함되면 판정.
  MSG="[ruler-patrol cycle=${CYCLE}] 3분 순찰 시작.
1. Read ~/.claude/.ruler/patrol.md — 체크리스트 SSOT
2. Read ~/.claude/.ruler/state.md — 이전 사이클 상태 복원 (cycle ${CYCLE} 증가 반영)
3. 이벤트 판정: ~/.claude/.ruler/.messages/wake-event-patrol-*.txt 존재 시:
   a. candidate 각각 판정 (violation / false_positive / deferred)
   b. 판정 후 반드시 ~/.claude/.ruler/event-patrol-feedback.jsonl 에 1줄 append:
      {\"ts\":\"ISO\",\"event\":\"이벤트명\",\"verdict\":\"violation|false_positive|deferred\",\"reason\":\"판정근거 1줄\"}
   c. violation 시 통보, false_positive 시 skip, deferred 시 T2 pending
   d. 파일 없으면 이벤트 판정 skip.
4. C-check: C1(트리거시) → C16 heartbeat → C17 모델 → C_idle
   (10사이클마다 Tier C: C3~C15 + C18-lite + C_memory)
5. 자동수정 Gate: T1 즉시 적용, T2 pending 24h
6. state.md 갱신 + log append
7. 자기감시: patrol.md/skill.md 자기수정 금지 또는 T3 강제"

  "$PSMUX" send-keys -t "$SESSION" "$MSG"
  sleep 1
  "$PSMUX" send-keys -t "$SESSION" Enter
done
