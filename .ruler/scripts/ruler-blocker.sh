#!/bin/bash
# ruler-blocker.sh — agent 대기/재개 프로토콜 프로토타입 (Step 6)
#
# plan: ~/.claude/.ruler/batch-plans/202604151600-event-driven-patrol/plan.md §Step 6
# version: v0.1 (2026-04-15 ruler-batch-20260415T2308 Step 6 prototype)
#
# 사용법
# ------
#   ruler-blocker.sh block   --target <sess> --reason "<text>" [--eta <sec>] [--session <ruler-session>]
#   ruler-blocker.sh unblock --target <sess> [--message "<text>"] [--session <ruler-session>]
#   ruler-blocker.sh status  --target <sess>
#   ruler-blocker.sh list
#   ruler-blocker.sh orphan-scan                   # stale blocker (mtime>30min) 경고
#
# state 파일
# ----------
#   ~/.claude/.ruler/.blockers/{target}.json
#   {
#     "target": "btn-button",
#     "reason": "event-patrol.py v0.1 loader 경로 불일치",
#     "eta_sec": 300,
#     "blocked_by_ts": "2026-04-15T23:40:00+09:00",
#     "blocker_session": "ruler-batch-20260415T2308",
#     "status": "waiting",
#     "unblock_ts": null,
#     "unblock_msg": null
#   }
#
# 원자성
# ------
#   - block 생성: mkdir sentinel 로 race 방어 + 파일 tmp→mv
#   - unblock: ownership 검증 (blocker_session 매칭)
#   - 동일 target 에 활성 blocker 존재 시 block 거부 (exit 7)
#
# 종료 코드
# ---------
#   0 = 성공
#   1 = 인자 오류
#   2 = 대상 세션 부재 (psmux has-session)
#   3 = state 파일 read/write 실패
#   6 = 이미 활성 blocker 존재 (block 중복)
#   7 = ownership 위반 (다른 세션이 건 blocker 에 unblock 시도)
#   8 = blocker 부재 (unblock 대상 없음)
#
set -u
set -o pipefail

SCRIPT_NAME="ruler-blocker.sh"
BLOCKER_DIR="$HOME/.claude/.ruler/.blockers"
NOTIFY_SH="$HOME/.claude/.ruler/scripts/ruler-notify.sh"
AUDIT_LOG="$HOME/.claude/audit-log/$(date +%Y-%m-%d).jsonl"
STALE_THRESHOLD_SEC=1800  # 30 min

mkdir -p "$BLOCKER_DIR" 2>/dev/null || true

log_stderr() {
  echo "[$(date +%Y-%m-%dT%H:%M:%S%z)] [$SCRIPT_NAME] $*" >&2
}

emit_audit() {
  local type="$1"
  local target="$2"
  local extra="${3:-}"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
  mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true
  local line
  line=$(printf '{"ts":"%s","type":"%s","target":"%s"%s}' "$ts" "$type" "$target" "$extra")
  echo "$line" >> "$AUDIT_LOG" 2>/dev/null || true
}

# ─────────────────────────────────────────────────────────────
# JSON 원시 유틸 (jq 의존 제거 — 필드 개수 제한)
# ─────────────────────────────────────────────────────────────
json_escape() {
  # " → \", \ → \\ 만 처리. v0.1 단순.
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  # 개행 제거 (single-line JSON 유지)
  s="${s//$'\n'/ }"
  printf '%s' "$s"
}

json_get() {
  # $1 = file, $2 = key. 간단 grep 기반. 값에 `"` 없다고 가정.
  local file="$1" key="$2"
  [ -f "$file" ] || return 1
  grep -oE "\"$key\"[[:space:]]*:[[:space:]]*(\"[^\"]*\"|null|[0-9]+)" "$file" \
    | head -1 \
    | sed -E "s/\"$key\"[[:space:]]*:[[:space:]]*//;s/^\"//;s/\"$//"
}

write_state_atomic() {
  local target="$1" body="$2"
  local final="$BLOCKER_DIR/$target.json"
  local tmp="$BLOCKER_DIR/.$target.json.tmp.$$"
  printf '%s\n' "$body" > "$tmp" || return 3
  mv -f "$tmp" "$final" || return 3
  return 0
}

# ─────────────────────────────────────────────────────────────
# 서브커맨드
# ─────────────────────────────────────────────────────────────
CMD="${1:-}"
if [ -z "$CMD" ]; then
  sed -n '2,30p' "$0"; exit 1
fi
shift || true

TARGET=""
REASON=""
ETA_SEC=0
MSG=""
BLOCKER_SESS="${PSMUX_SESSION:-unknown-ruler}"

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --reason) REASON="$2"; shift 2 ;;
    --eta) ETA_SEC="$2"; shift 2 ;;
    --message) MSG="$2"; shift 2 ;;
    --session) BLOCKER_SESS="$2"; shift 2 ;;
    *) log_stderr "ERROR: unknown arg: $1"; exit 1 ;;
  esac
done

# ─────────────────────────────────────────────────────────────
cmd_block() {
  [ -n "$TARGET" ] || { log_stderr "ERROR: --target required"; exit 1; }
  [ -n "$REASON" ] || { log_stderr "ERROR: --reason required"; exit 1; }

  # 세션 존재 확인
  if ! psmux has-session -t "$TARGET" 2>/dev/null; then
    log_stderr "ABORT: session not found: $TARGET"
    emit_audit "ruler_blocker_no_session" "$TARGET"
    exit 2
  fi

  local state_path="$BLOCKER_DIR/$TARGET.json"

  # 이미 활성 blocker 존재 여부
  if [ -f "$state_path" ]; then
    local existing_status
    existing_status=$(json_get "$state_path" "status")
    if [ "$existing_status" = "waiting" ] || [ "$existing_status" = "repairing" ]; then
      local existing_owner
      existing_owner=$(json_get "$state_path" "blocker_session")
      log_stderr "REFUSE: active blocker exists (status=$existing_status, owner=$existing_owner)"
      emit_audit "ruler_blocker_conflict" "$TARGET" ",\"existing_owner\":\"$existing_owner\",\"existing_status\":\"$existing_status\""
      exit 6
    fi
    # unblocked 상태라면 덮어쓰기 허용
  fi

  local ts
  ts=$(date +%Y-%m-%dT%H:%M:%S%z)
  local reason_esc
  reason_esc=$(json_escape "$REASON")
  local body
  body=$(cat <<JSON
{"target":"$TARGET","reason":"$reason_esc","eta_sec":$ETA_SEC,"blocked_by_ts":"$ts","blocker_session":"$BLOCKER_SESS","status":"waiting","unblock_ts":null,"unblock_msg":null}
JSON
)

  if ! write_state_atomic "$TARGET" "$body"; then
    log_stderr "ERROR: state write failed: $state_path"
    exit 3
  fi

  # ruler-notify.sh 경유 메시지 전송
  local summary="⏸ BLOCKER: $REASON"
  if [ "$ETA_SEC" -gt 0 ]; then
    summary="$summary (ETA ${ETA_SEC}s)"
  fi
  summary="$summary. 현 step 마무리 후 대기. ruler 가 수정 중, unblock 메시지까지 추가 tool 호출 자제."

  # body: state 파일 경로 전달 (agent 가 Read)
  local state_path_win="C:/Users/jsh86/.claude/.ruler/.blockers/$TARGET.json"
  local notify_body="BLOCKER state: $state_path_win

reason: $REASON
eta_sec: $ETA_SEC
blocker_session: $BLOCKER_SESS
blocked_at: $ts

대기 동안:
- 현 step 의 파일 저장/3단 기록은 완결
- 새 tool 호출 (Edit/Write/Bash) 자제
- 압축/컨텍스트 체크포인트 저장은 허용
- unblock 메시지 도착 시 작업 재개"

  if [ -x "$NOTIFY_SH" ]; then
    echo "$notify_body" | bash "$NOTIFY_SH" --target "$TARGET" --summary "$summary" --body-stdin || \
      log_stderr "WARN: ruler-notify.sh send failed — state 파일은 생성됨 ($state_path)"
  else
    log_stderr "WARN: notify script not found/executable: $NOTIFY_SH"
  fi

  emit_audit "ruler_blocker_created" "$TARGET" ",\"reason\":\"$reason_esc\",\"eta_sec\":$ETA_SEC,\"owner\":\"$BLOCKER_SESS\""
  log_stderr "BLOCKED: $TARGET ← $REASON (owner=$BLOCKER_SESS)"
  exit 0
}

cmd_unblock() {
  [ -n "$TARGET" ] || { log_stderr "ERROR: --target required"; exit 1; }
  local state_path="$BLOCKER_DIR/$TARGET.json"

  if [ ! -f "$state_path" ]; then
    log_stderr "ABORT: no blocker state: $TARGET"
    emit_audit "ruler_blocker_unblock_missing" "$TARGET"
    exit 8
  fi

  local existing_owner existing_status
  existing_owner=$(json_get "$state_path" "blocker_session")
  existing_status=$(json_get "$state_path" "status")

  if [ "$existing_status" = "unblocked" ]; then
    log_stderr "NOOP: already unblocked: $TARGET"
    exit 0
  fi

  # ownership: 동일 세션만 허용 (override flag 는 v0.2)
  if [ "$existing_owner" != "$BLOCKER_SESS" ]; then
    log_stderr "REFUSE: ownership violation (owner=$existing_owner, caller=$BLOCKER_SESS)"
    emit_audit "ruler_blocker_ownership_violation" "$TARGET" ",\"owner\":\"$existing_owner\",\"caller\":\"$BLOCKER_SESS\""
    exit 7
  fi

  local reason eta blocked_ts
  reason=$(json_get "$state_path" "reason")
  eta=$(json_get "$state_path" "eta_sec")
  blocked_ts=$(json_get "$state_path" "blocked_by_ts")

  local ts
  ts=$(date +%Y-%m-%dT%H:%M:%S%z)
  local msg_esc
  msg_esc=$(json_escape "${MSG:-repair complete}")
  local reason_esc
  reason_esc=$(json_escape "$reason")
  local body
  body=$(cat <<JSON
{"target":"$TARGET","reason":"$reason_esc","eta_sec":$eta,"blocked_by_ts":"$blocked_ts","blocker_session":"$BLOCKER_SESS","status":"unblocked","unblock_ts":"$ts","unblock_msg":"$msg_esc"}
JSON
)

  if ! write_state_atomic "$TARGET" "$body"; then
    log_stderr "ERROR: state write failed"
    exit 3
  fi

  # notify
  local summary="▶ UNBLOCK: 수정 완료, 작업 재개 가능. ${MSG:-}"
  local notify_body="UNBLOCK $TARGET

original_reason: $reason
blocked_at: $blocked_ts
unblocked_at: $ts
unblock_msg: ${MSG:-repair complete}

재개 절차:
- 중단 시점의 step 확인
- unblock 메시지 이후 정상 작업 흐름 복귀
- 필요 시 blocker 근본 원인 retrospective 작성"

  if [ -x "$NOTIFY_SH" ]; then
    echo "$notify_body" | bash "$NOTIFY_SH" --target "$TARGET" --summary "$summary" --body-stdin || \
      log_stderr "WARN: ruler-notify.sh send failed — state 는 갱신됨"
  fi

  emit_audit "ruler_blocker_unblocked" "$TARGET" ",\"owner\":\"$BLOCKER_SESS\",\"unblock_msg\":\"$msg_esc\""
  log_stderr "UNBLOCKED: $TARGET"
  exit 0
}

cmd_status() {
  [ -n "$TARGET" ] || { log_stderr "ERROR: --target required"; exit 1; }
  local state_path="$BLOCKER_DIR/$TARGET.json"
  if [ ! -f "$state_path" ]; then
    echo '{"target":"'"$TARGET"'","status":"none"}'
    exit 0
  fi
  cat "$state_path"
  exit 0
}

cmd_list() {
  shopt -s nullglob
  local any=0
  for f in "$BLOCKER_DIR"/*.json; do
    any=1
    cat "$f"; echo
  done
  if [ "$any" -eq 0 ]; then
    echo '{"blockers":[]}'
  fi
  exit 0
}

cmd_orphan_scan() {
  local now
  now=$(date +%s)
  shopt -s nullglob
  local orphans=0
  for f in "$BLOCKER_DIR"/*.json; do
    local status
    status=$(json_get "$f" "status")
    [ "$status" = "unblocked" ] && continue
    local mtime
    mtime=$(stat -c %Y "$f" 2>/dev/null || echo 0)
    local age=$((now - mtime))
    if [ "$age" -gt "$STALE_THRESHOLD_SEC" ]; then
      log_stderr "ORPHAN: $f (age=${age}s, status=$status)"
      local tgt
      tgt=$(basename "$f" .json)
      emit_audit "ruler_blocker_orphan" "$tgt" ",\"age_sec\":$age,\"status\":\"$status\""
      orphans=$((orphans + 1))
    fi
  done
  log_stderr "orphan-scan: $orphans found"
  exit 0
}

case "$CMD" in
  block)        cmd_block ;;
  unblock)      cmd_unblock ;;
  status)       cmd_status ;;
  list)         cmd_list ;;
  orphan-scan)  cmd_orphan_scan ;;
  *) log_stderr "ERROR: unknown subcommand: $CMD"; exit 1 ;;
esac
