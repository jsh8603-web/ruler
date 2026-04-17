#!/usr/bin/env bash
# retrospective-collect.sh — Ruler Retrospective 소스 수집기
# 2026-04-14 Sonnet Migration Phase 1 / role consolidation
#
# patrol.md §사후 Retrospective 소스 카탈로그 10종을 단일 JSON 으로 정규화.
# 사용법:
#   bash retrospective-collect.sh --window 7d --out /tmp/retro-{ts}.json
#
# 출력 JSON 구조:
#   {
#     "window": "7d",
#     "collected_at": "ISO8601",
#     "entries": [ {source, path, cycle, ts, file_affected, payload}, ... ],
#     "external_state": { error:N, warn:N, sonnet:N, escalation:N, unresolved_rate:F,
#                         solution_cache_total:N, solution_cache_stale:N, risk_grep:[...] }
#   }
#
# 모든 섹션 best-effort. 소스 부재 시 entries 누락 허용, 경고 stderr.

set -euo pipefail

WINDOW="7d"
OUT=""
RULER_DIR="${HOME}/.claude/.ruler"
AUDIT_LOG_DIR="${HOME}/.claude/audit-log"
SECRETARY_DIR="D:/projects/button/agent/.secretary"

while [ $# -gt 0 ]; do
  case "$1" in
    --window) WINDOW="$2"; shift 2;;
    --out)    OUT="$2"; shift 2;;
    *) echo "[retrospective-collect] unknown arg: $1" >&2; shift;;
  esac
done

if [ -z "$OUT" ]; then
  OUT="/tmp/retro-$(date +%Y%m%dT%H%M%S).json"
fi

# window → day 환산 (7d → 7)
DAYS="${WINDOW%d}"
[ "$DAYS" = "$WINDOW" ] && DAYS=7

TS_NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# === 임시 파일에 entries 누적 ===
TMP=$(mktemp)
trap 'rm -f "$TMP" "$TMP.ext"' EXIT
echo "[]" > "$TMP"

append_entry() {
  # $1=source $2=path $3=cycle $4=ts $5=file_affected $6=payload_json
  jq --arg s "$1" --arg p "$2" --arg c "$3" --arg t "$4" \
     --arg f "$5" --argjson payload "$6" \
     '. += [{source:$s, path:$p, cycle:$c, ts:$t, file_affected:$f, payload:$payload}]' \
     "$TMP" > "$TMP.new" && mv "$TMP.new" "$TMP"
}

# 1. decisions.jsonl (tail -500 → window filter)
DEC="${RULER_DIR}/decisions.jsonl"
if [ -f "$DEC" ]; then
  tail -500 "$DEC" 2>/dev/null | while IFS= read -r line; do
    [ -z "$line" ] && continue
    echo "$line" | jq -c --arg now "$TS_NOW" --argjson days "$DAYS" \
      'select((.ts // "") != "") |
       {source:"decisions", path:"'"$DEC"'", cycle:(.cycle|tostring), ts:.ts,
        file_affected:(.file // ""), payload:.}' 2>/dev/null || true
  done | jq -s '.' > "$TMP.dec" 2>/dev/null || echo "[]" > "$TMP.dec"
  jq -s '.[0] + .[1]' "$TMP" "$TMP.dec" > "$TMP.new" && mv "$TMP.new" "$TMP"
  rm -f "$TMP.dec"
fi

# 2. log/{date}.md (최근 N일)
if [ -d "${RULER_DIR}/log" ]; then
  find "${RULER_DIR}/log" -name "*.md" -mtime "-${DAYS}" 2>/dev/null | while IFS= read -r f; do
    mt=$(stat -c %y "$f" 2>/dev/null || echo "")
    append_entry "log_daily" "$f" "" "$mt" "" "{}"
  done
fi

# 3. rollback/*.bak (window 내)
if [ -d "${RULER_DIR}/rollback" ]; then
  find "${RULER_DIR}/rollback" -name "*.bak" -mtime "-${DAYS}" 2>/dev/null | while IFS= read -r f; do
    mt=$(stat -c %y "$f" 2>/dev/null || echo "")
    orig=$(basename "$f" | sed 's/-[0-9T]*\.bak$//')
    append_entry "rollback_backup" "$f" "" "$mt" "$orig" "{}"
  done
fi

# 4~6. pending 활성/resolved/dropped
for sub in "" "resolved" "dropped"; do
  dir="${RULER_DIR}/pending${sub:+/$sub}"
  [ -d "$dir" ] || continue
  find "$dir" -maxdepth 1 -name "*.md" 2>/dev/null | while IFS= read -r f; do
    mt=$(stat -c %y "$f" 2>/dev/null || echo "")
    kind="pending_active"
    [ "$sub" = "resolved" ] && kind="pending_resolved"
    [ "$sub" = "dropped" ] && kind="pending_dropped"
    append_entry "$kind" "$f" "" "$mt" "" "{}"
  done
done

# 7. batch-plans/done
if [ -d "${RULER_DIR}/batch-plans/done" ]; then
  find "${RULER_DIR}/batch-plans/done" -name "*.md" -mtime "-${DAYS}" 2>/dev/null | while IFS= read -r f; do
    mt=$(stat -c %y "$f" 2>/dev/null || echo "")
    append_entry "batch_plan_done" "$f" "" "$mt" "" "{}"
  done
fi

# 8. regression 이력 — log/{date}.md 내 grep
if [ -d "${RULER_DIR}/log" ]; then
  grep -l "regression_" "${RULER_DIR}/log/"*.md 2>/dev/null | while IFS= read -r f; do
    append_entry "regression_log" "$f" "" "" "" "{}"
  done
fi

# 9. state.md "Idle Transition" + "Last Cycle Summary"
STATE="${RULER_DIR}/state.md"
if [ -f "$STATE" ]; then
  append_entry "state_history" "$STATE" "" "$(stat -c %y "$STATE" 2>/dev/null)" "" "{}"
fi

# 10. 외부 상태 (비서 5지표) — audit-log tail + solution cache
ERR_COUNT=0; WARN_COUNT=0; SONNET_COUNT=0; ESC_COUNT=0
CACHE_TOTAL=0; CACHE_STALE=0; RISK_HITS=""

if [ -d "$AUDIT_LOG_DIR" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    c=$(grep -c '"type":"ERROR"' "$f" 2>/dev/null || true); ERR_COUNT=$((ERR_COUNT + ${c:-0}))
    c=$(grep -c '"type":"WARN"' "$f" 2>/dev/null || true); WARN_COUNT=$((WARN_COUNT + ${c:-0}))
    c=$(grep -c '"type":"SONNET"' "$f" 2>/dev/null || true); SONNET_COUNT=$((SONNET_COUNT + ${c:-0}))
    c=$(grep -c '"type":"ESCALATION"' "$f" 2>/dev/null || true); ESC_COUNT=$((ESC_COUNT + ${c:-0}))
    hits=$(grep -oE 'force-push|rm -rf|reset --hard|--no-verify' "$f" 2>/dev/null | sort -u | tr '\n' ',' || true)
    [ -n "$hits" ] && RISK_HITS="${RISK_HITS}${hits}"
  done < <(find "$AUDIT_LOG_DIR" -name "*.jsonl" -mtime "-${DAYS}" 2>/dev/null)
fi

CACHE_FILE="${SECRETARY_DIR}/.error-solutions.json"
if [ -f "$CACHE_FILE" ]; then
  CACHE_TOTAL=$(jq 'length' "$CACHE_FILE" 2>/dev/null || echo 0)
  CACHE_STALE=$(jq '[.[] | select(.hit_count == 0 or .hit_count == null)] | length' "$CACHE_FILE" 2>/dev/null || echo 0)
fi

# R11 미해결률 = ESC / (WARN + SONNET)
DENOM=$((WARN_COUNT + SONNET_COUNT))
UNRESOLVED_RATE="0"
if [ "$DENOM" -gt 0 ]; then
  UNRESOLVED_RATE=$(awk -v e="$ESC_COUNT" -v d="$DENOM" 'BEGIN{printf "%.3f", e/d}')
fi

cat > "$TMP.ext" <<JEOF
{
  "error": $ERR_COUNT,
  "warn": $WARN_COUNT,
  "sonnet": $SONNET_COUNT,
  "escalation": $ESC_COUNT,
  "unresolved_rate": $UNRESOLVED_RATE,
  "solution_cache_total": $CACHE_TOTAL,
  "solution_cache_stale": $CACHE_STALE,
  "risk_grep": "$(echo "$RISK_HITS" | sed 's/,$//')"
}
JEOF

# === 최종 JSON 조립 ===
jq -n --arg window "$WINDOW" --arg ts "$TS_NOW" \
      --slurpfile entries "$TMP" \
      --slurpfile ext "$TMP.ext" \
      '{window:$window, collected_at:$ts, entries:$entries[0], external_state:$ext[0]}' \
  > "$OUT"

ENTRY_COUNT=$(jq '.entries | length' "$OUT")
echo "[retrospective-collect] OK entries=${ENTRY_COUNT} ext(err=${ERR_COUNT},esc=${ESC_COUNT},rate=${UNRESOLVED_RATE}) → $OUT" >&2

# R11 임계 힌트 (≥0.5 시 stderr 경고)
awk -v r="$UNRESOLVED_RATE" 'BEGIN{ if (r+0 >= 0.5) exit 1; exit 0 }' || \
  echo "[retrospective-collect] WARN R11 threshold crossed: unresolved_rate=${UNRESOLVED_RATE} ≥ 0.5" >&2

exit 0
