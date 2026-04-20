#!/bin/bash
# ruler-notify.sh — ruler → agent 세션 통보 (v0.2)
#
# plan: ~/.claude/.ruler/batch-plans/202604151600-event-driven-patrol/plan.md
# spec: sendWithFile(sessionName, summary, fileContent) 경량 복제
#       - 방안 B (ruler 자체 구현, secretary.js export 불필요)
# version: v0.2 (2026-04-16 ruler-batch-20260416T0122 Step 4)
#
# 사용법
# ------
#   ruler-notify.sh --target <session> --summary "<msg>" [--mode <mode>] [--cite <path>]
#   ruler-notify.sh --target <session> --summary "<msg>" --body-file <path>
#   ruler-notify.sh --target <session> --summary "<msg>" --body-stdin
#
# 모드 (--mode)
# -------------
#   violation  (기본) — 위반 사실 통보. 규칙 준수 요청.
#   blocker    — "기능 X 수리 중, 대기". blocker 상태 파일 생성.
#   unblock    — "수리 완료, 재개 OK". blocker 상태 파일 제거.
#   rule-fix   — "규칙 강화됨, 다시 Read". --cite 로 강화된 규칙 경로 전달.
#
# 종료 코드
# ---------
#   0  = 성공 (send-keys 완료)
#   1  = 인자 오류
#   2  = 대상 세션 부재 (psmux has-session 실패)
#   3  = compacting/init-lock 가드로 skip (log_event 기록 후 정상 종료 아님)
#   4  = Temp 파일 Write 실패
#   5  = psmux send-keys 실패
#   6  = 동시 호출 lock 획득 실패 (이미 다른 notify 진행중)
#
# 가드 복제 범위
# --------------
#   ✔ compacting 근사: .secretary/.post-compact-flag/{target} 존재 + mtime < 10min → defer
#   ✔ 대상 세션 존재 확인: psmux has-session
#   ✔ 동시 호출 방지: mkdir atomic lock per-target (ttl 30s)
#   ✘ init-lock: ruler 외부에서 확인 불가 — skip (secretary 가 대신 drop)
#   ✘ hooks-running: 외부 관측 경로 없음 — skip
#
# 의존성: bash, psmux, date, mkdir, cat
#
set -u
set -o pipefail

SCRIPT_NAME="ruler-notify.sh"

# SSOT psmux helper
source "$HOME/.claude/scripts/lib/psmux-send.sh"

FLAG_DIR="/d/projects/button/agent/.secretary/.post-compact-flag"
TMP_DIR_WIN="C:/Users/jsh86/AppData/Local/Temp"
TMP_DIR_MSYS="/c/Users/jsh86/AppData/Local/Temp"
LOCK_ROOT="${TMPDIR:-/tmp}/ruler-notify-locks"
BLOCKER_DIR="$HOME/.claude/.ruler/state/blockers"
AUDIT_LOG="$HOME/.claude/audit-log/$(date +%Y-%m-%d).jsonl"
LOCK_TTL_SEC=30
COMPACT_GUARD_MAX_AGE=600  # 10 min

# ─────────────────────────────────────────────────────────────
# 로그 (stderr) + audit-log emit
# ─────────────────────────────────────────────────────────────
log_stderr() {
  echo "[$(date +%Y-%m-%dT%H:%M:%S%z)] [$SCRIPT_NAME] $*" >&2
}

emit_audit() {
  local type="$1"
  local session="$2"
  local summary="$3"
  local extra="${4:-}"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
  mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true
  # 단순 JSON (jq 없이). summary 이스케이프는 " → \" 만 처리.
  local summary_esc="${summary//\"/\\\"}"
  local line
  line=$(printf '{"ts":"%s","type":"%s","session":"%s","summary":"%s"%s}' \
         "$ts" "$type" "$session" "$summary_esc" "$extra")
  echo "$line" >> "$AUDIT_LOG" 2>/dev/null || true
}

# ─────────────────────────────────────────────────────────────
# 인자 파싱
# ─────────────────────────────────────────────────────────────
TARGET=""
SUMMARY=""
BODY_FILE=""
BODY_STDIN=0
MODE="violation"
CITE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --summary) SUMMARY="$2"; shift 2 ;;
    --body-file) BODY_FILE="$2"; shift 2 ;;
    --body-stdin) BODY_STDIN=1; shift ;;
    --mode) MODE="$2"; shift 2 ;;
    --cite) CITE="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,50p' "$0"; exit 0 ;;
    *)
      log_stderr "ERROR: unknown arg: $1"
      exit 1 ;;
  esac
done

if [ -z "$TARGET" ] || [ -z "$SUMMARY" ]; then
  log_stderr "ERROR: --target and --summary are required"
  exit 1
fi

case "$MODE" in
  violation|blocker|unblock|rule-fix) ;;
  *)
    log_stderr "ERROR: unknown mode: $MODE (use violation|blocker|unblock|rule-fix)"
    exit 1 ;;
esac

# 세션 안전성 체크 (secretary.js assertSafeSession 과 동일 정신)
case "$TARGET" in
  worker|verifier|healer|strategic)
    log_stderr "REFUSE: WF session name blocked ($TARGET) — secretary-system.md rule 3"
    emit_audit "ruler_notify_refused_wf_session" "$TARGET" "$SUMMARY"
    exit 1
    ;;
  *[!a-zA-Z0-9_-]*)
    log_stderr "ERROR: invalid session name: $TARGET"
    exit 1
    ;;
esac

# ─────────────────────────────────────────────────────────────
# 1) 대상 세션 존재 확인
# ─────────────────────────────────────────────────────────────
if ! psmux has-session -t "$TARGET" 2>/dev/null; then
  log_stderr "ABORT: session not found: $TARGET"
  emit_audit "ruler_notify_no_session" "$TARGET" "$SUMMARY"
  exit 2
fi

# ─────────────────────────────────────────────────────────────
# 2) compacting 가드 근사 (.post-compact-flag mtime)
# ─────────────────────────────────────────────────────────────
FLAG_PATH="$FLAG_DIR/$TARGET"
if [ -f "$FLAG_PATH" ]; then
  flag_mtime=$(stat -c %Y "$FLAG_PATH" 2>/dev/null || echo 0)
  now=$(date +%s)
  age=$((now - flag_mtime))
  if [ "$age" -lt "$COMPACT_GUARD_MAX_AGE" ]; then
    log_stderr "DEFER: $TARGET is compacting (flag age=${age}s < ${COMPACT_GUARD_MAX_AGE}s)"
    emit_audit "ruler_notify_skipped_compacting" "$TARGET" "$SUMMARY" ",\"flag_age_sec\":$age"
    exit 3
  fi
fi

# ─────────────────────────────────────────────────────────────
# 3) 동시 호출 방지 (mkdir atomic lock, ttl 30s)
# ─────────────────────────────────────────────────────────────
mkdir -p "$LOCK_ROOT" 2>/dev/null || true
LOCK_DIR="$LOCK_ROOT/$TARGET.lock"

# stale lock cleanup
if [ -d "$LOCK_DIR" ]; then
  lock_mtime=$(stat -c %Y "$LOCK_DIR" 2>/dev/null || echo 0)
  now=$(date +%s)
  if [ $((now - lock_mtime)) -gt "$LOCK_TTL_SEC" ]; then
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
fi

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  log_stderr "ABORT: another notify in progress for $TARGET"
  emit_audit "ruler_notify_lock_busy" "$TARGET" "$SUMMARY"
  exit 6
fi

# cleanup trap
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

# ─────────────────────────────────────────────────────────────
# 4) body 있으면 Temp 파일 Write (secretary 와 동일 경로체계)
# ─────────────────────────────────────────────────────────────
TMP_WIN=""
TMP_MSYS=""
if [ -n "$BODY_FILE" ] && [ "$BODY_STDIN" -eq 1 ]; then
  log_stderr "ERROR: --body-file and --body-stdin are mutually exclusive"
  exit 1
fi

if [ -n "$BODY_FILE" ] || [ "$BODY_STDIN" -eq 1 ]; then
  now_epoch_ms=$(date +%s%3N)
  fname="ruler-notify-${TARGET}-${now_epoch_ms}.txt"
  TMP_WIN="$TMP_DIR_WIN/$fname"
  TMP_MSYS="$TMP_DIR_MSYS/$fname"
  mkdir -p "$TMP_DIR_MSYS" 2>/dev/null || true
  if [ "$BODY_STDIN" -eq 1 ]; then
    if ! cat > "$TMP_MSYS"; then
      log_stderr "ERROR: tmp write failed: $TMP_MSYS"
      exit 4
    fi
  else
    if ! cp "$BODY_FILE" "$TMP_MSYS"; then
      log_stderr "ERROR: body file copy failed: $BODY_FILE"
      exit 4
    fi
  fi
  # 5분 후 cleanup (background)
  ( sleep 300; rm -f "$TMP_MSYS" 2>/dev/null ) &
  disown 2>/dev/null || true
fi

# ─────────────────────────────────────────────────────────────
# 5) mode 별 메시지 조립 + blocker 상태 관리
# ─────────────────────────────────────────────────────────────
mkdir -p "$BLOCKER_DIR" 2>/dev/null || true

case "$MODE" in
  violation)
    PREFIX="[VIOLATION]"
    ;;
  blocker)
    PREFIX="[BLOCKER] 수리 중. 대기."
    # blocker 상태 파일 생성 (feature = summary의 첫 단어)
    blocker_key=$(echo "$SUMMARY" | tr ' ' '_' | head -c 60)
    blocker_file="$BLOCKER_DIR/${TARGET}-${blocker_key}.blocker"
    echo "{\"target\":\"$TARGET\",\"summary\":\"$SUMMARY\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > "$blocker_file"
    log_stderr "BLOCKER created: $blocker_file"
    ;;
  unblock)
    PREFIX="[UNBLOCK] 수리 완료. 재개 OK."
    # blocker 상태 파일 제거 (해당 target 의 모든 blocker)
    for bf in "$BLOCKER_DIR"/${TARGET}-*.blocker; do
      [ -f "$bf" ] || continue
      rm -f "$bf" && log_stderr "BLOCKER removed: $bf"
    done
    ;;
  rule-fix)
    if [ -n "$CITE" ]; then
      PREFIX="[RULE-FIX] 규칙 강화됨. 다시 Read: $CITE"
    else
      PREFIX="[RULE-FIX] 규칙 강화됨."
    fi
    ;;
esac

FULL_SUMMARY="$PREFIX $SUMMARY"

# 길이 제한
SUMMARY_MAXLEN=400
if [ "${#FULL_SUMMARY}" -gt "$SUMMARY_MAXLEN" ]; then
  FULL_SUMMARY="${FULL_SUMMARY:0:$SUMMARY_MAXLEN}"
fi

if [ -n "$TMP_WIN" ]; then
  MSG="$FULL_SUMMARY -- Read $TMP_WIN"
else
  MSG="$FULL_SUMMARY"
fi

if ! psmux_send_message "$TARGET" "$MSG" 2>/dev/null; then
  log_stderr "ERROR: psmux send-keys failed to $TARGET"
  emit_audit "ruler_notify_send_failed" "$TARGET" "$SUMMARY"
  exit 5
fi

# ─────────────────────────────────────────────────────────────
# 6) audit-log success
# ─────────────────────────────────────────────────────────────
extra=",\"mode\":\"$MODE\""
if [ -n "$TMP_WIN" ]; then
  extra="$extra,\"file\":\"${TMP_WIN//\\/\\\\}\""
fi
if [ -n "$CITE" ]; then
  extra="$extra,\"cite\":\"$CITE\""
fi
emit_audit "ruler_notify_sent" "$TARGET" "$FULL_SUMMARY" "$extra"
log_stderr "SENT ($MODE): $TARGET ← $FULL_SUMMARY${TMP_WIN:+ (+file)}"

exit 0
