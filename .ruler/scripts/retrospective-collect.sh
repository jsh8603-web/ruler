#!/usr/bin/env bash
# retrospective-collect.sh — Ruler Retrospective 소스 수집기
# 2026-04-14 Sonnet Migration Phase 1 / role consolidation
# 2026-04-18 Step 3: Δ 수집 + compute_change_impact() bash 함수 통합 (Python 제거)
#
# patrol.md §사후 Retrospective 소스 카탈로그 10종을 단일 JSON 으로 정규화.
# 사용법:
#   bash retrospective-collect.sh --window 7d --out /tmp/retro-{ts}.json
#
# 출력 JSON 구조:
#   {
#     "window": "7d",
#     "collected_at": "ISO8601",
#     "pre_window":  { "<check>_<file_escaped>": [{decisions.jsonl entry},...] },
#     "post_window": { "<check>_<file_escaped>": [{decisions.jsonl entry},...] },
#     "missing_files": ["<path>", ...],
#     "entries": [ {source, path, cycle, ts, file_affected, payload}, ... ],
#     "external_state": { error:N, warn:N, sonnet:N, escalation:N, unresolved_rate:F,
#                         solution_cache_total:N, solution_cache_stale:N, risk_grep:[...] }
#   }
#
# 모든 섹션 best-effort. 소스 부재 시 entries 누락 허용, 경고 stderr.

set -euo pipefail

# jq PATH 보강 — 시스템 PATH 에 jq 없고 node-jq 경로만 존재하는 Windows 환경 대응
# (msys2 bash 의 PATH 에는 /mingw64/bin, /usr/bin 있으나 jq 미설치)
if ! command -v jq >/dev/null 2>&1; then
  JQ_NODE="/c/Users/jsh86/AppData/Roaming/npm/node_modules/node-jq/bin/jq.exe"
  if [ -x "$JQ_NODE" ]; then
    export PATH="$(dirname "$JQ_NODE"):$PATH"
  else
    echo "[retrospective-collect] FATAL: jq not found in PATH and node-jq missing at $JQ_NODE" >&2
    exit 1
  fi
fi

WINDOW="7d"
OUT=""
RULER_DIR="${HOME}/.claude/.ruler"
AUDIT_LOG_DIR="${HOME}/.claude/audit-log"
SECRETARY_DIR="D:/projects/button/agent/.secretary"
BUTTON_DIR="D:/projects/button"

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
TMPDIR_WORK=$(mktemp -d)
trap 'rm -f "$TMP" "$TMP.ext"; rm -rf "$TMPDIR_WORK"' EXIT
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
# pipefail 환경에서 빈 log 디렉토리 → grep exit 1 → 파이프 실패 방어 ({ ... || true; })
if [ -d "${RULER_DIR}/log" ]; then
  { grep -l "regression_" "${RULER_DIR}/log/"*.md 2>/dev/null || true; } | while IFS= read -r f; do
    [ -z "$f" ] && continue
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

# ===========================================================================
# [Step 3-1] pre-T / post-T 각 3.5일 윈도우 decisions.jsonl 서브셋 추출
# 각 T1/T2 entry 의 ts 기준으로 pre(T-3.5d~T) / post(T~T+3.5d) 분리
# 출력: $TMPDIR_WORK/pre-{check}-{file_escaped}.json, post-{check}-{file_escaped}.json
# ===========================================================================
DEC="${RULER_DIR}/decisions.jsonl"
PRE_WINDOW_JSON="{}"
POST_WINDOW_JSON="{}"

if [ -f "$DEC" ]; then
  # T-point entry 목록 추출 — change event 원천 확장
  # T1 (즉시 수정) + T2_batch_applied (batch 가 실제 적용한 T2) 만 T-point 로 간주.
  # T2_user_direct / T2 (pending 상태) / T0 / archive 는 T-point 아님 (적용 이전 또는 비-change).
  # tier 변종 (T1_user_auth 등) 은 test("^T1") 로 포섭 (substring 아닌 prefix).
  T_ENTRIES_FILE="${TMPDIR_WORK}/t_entries.json"
  jq -c 'select(
    (((.tier // "") | test("^T1")) or ((.tier // "") == "T2_batch_applied"))
    and (.ts != null) and (.ts != "")
  ) | {ts, check: (.check // "unknown"), file: (.file // "unknown")}' \
    "$DEC" 2>/dev/null | jq -s '.' > "$T_ENTRIES_FILE" 2>/dev/null || echo "[]" > "$T_ENTRIES_FILE"

  T_COUNT=$(jq 'length' "$T_ENTRIES_FILE")
  echo "[retrospective-collect] T1/T2 entries for Δ window: ${T_COUNT}" >&2

  if [ "$T_COUNT" -gt 0 ]; then
    # 각 T entry 에 대해 pre/post window decisions 추출
    PRE_MAP_FILE="${TMPDIR_WORK}/pre_map.json"
    POST_MAP_FILE="${TMPDIR_WORK}/post_map.json"
    echo "{}" > "$PRE_MAP_FILE"
    echo "{}" > "$POST_MAP_FILE"

    jq -c '.[]' "$T_ENTRIES_FILE" 2>/dev/null | while IFS= read -r t_entry; do
      T_TS=$(echo "$t_entry" | jq -r '.ts')
      T_CHECK=$(echo "$t_entry" | jq -r '.check')
      T_FILE=$(echo "$t_entry" | jq -r '.file')
      # 파일명 슬래시를 언더스코어로 escape (키 이름용)
      FILE_ESC=$(echo "${T_FILE}" | tr '/' '_' | tr '\\' '_' | tr ':' '_')
      KEY="${T_CHECK}-${FILE_ESC}"

      # pre window: T-3.5d ~ T  (3.5일 = 302400초)
      PRE_FILE="${TMPDIR_WORK}/pre-${KEY}.json"
      POST_FILE="${TMPDIR_WORK}/post-${KEY}.json"

      # 시간 경계: pre = [T-3.5d, T], post = [T, T+3.5d]
      # guide §Phase A: Pre-Δ (T-3.5d ~ T) / Post-Δ (T ~ T+3.5d)
      # date -d 로 offset 계산. 실패 시 단순 이분할로 degrade.
      T_PRE=$(date -u -d "${T_TS} - 3.5 days" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
      T_POST_END=$(date -u -d "${T_TS} + 3.5 days" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")

      if [ -n "$T_PRE" ] && [ -n "$T_POST_END" ]; then
        jq -c --arg t_ts "$T_TS" --arg t_pre "$T_PRE" \
          'select((.ts // "") != "" and .ts >= $t_pre and .ts <= $t_ts)' \
          "$DEC" 2>/dev/null | jq -s '.' > "$PRE_FILE" || echo "[]" > "$PRE_FILE"

        jq -c --arg t_ts "$T_TS" --arg t_end "$T_POST_END" \
          'select((.ts // "") != "" and .ts >= $t_ts and .ts <= $t_end)' \
          "$DEC" 2>/dev/null | jq -s '.' > "$POST_FILE" || echo "[]" > "$POST_FILE"
      else
        # fallback: date 실패 시 이분할 (경계 없음)
        jq -c --arg t_ts "$T_TS" 'select((.ts // "") != "" and .ts <= $t_ts)' \
          "$DEC" 2>/dev/null | jq -s '.' > "$PRE_FILE" || echo "[]" > "$PRE_FILE"
        jq -c --arg t_ts "$T_TS" 'select((.ts // "") != "" and .ts >= $t_ts)' \
          "$DEC" 2>/dev/null | jq -s '.' > "$POST_FILE" || echo "[]" > "$POST_FILE"
      fi

      # 맵에 병합 (동일 KEY 가 여러 T entry 이면 concat)
      jq --arg key "$KEY" --slurpfile new_data "$PRE_FILE" \
        'if has($key) then .[$key] += $new_data[0] else .[$key] = $new_data[0] end' \
        "$PRE_MAP_FILE" > "${PRE_MAP_FILE}.new" && mv "${PRE_MAP_FILE}.new" "$PRE_MAP_FILE" || true

      jq --arg key "$KEY" --slurpfile new_data "$POST_FILE" \
        'if has($key) then .[$key] += $new_data[0] else .[$key] = $new_data[0] end' \
        "$POST_MAP_FILE" > "${POST_MAP_FILE}.new" && mv "${POST_MAP_FILE}.new" "$POST_MAP_FILE" || true
    done

    PRE_WINDOW_JSON=$(cat "$PRE_MAP_FILE" 2>/dev/null || echo "{}")
    POST_WINDOW_JSON=$(cat "$POST_MAP_FILE" 2>/dev/null || echo "{}")
  fi
fi

echo "[retrospective-collect] pre/post window extraction done" >&2

# ===========================================================================
# [Step 3-2] §0.5 누락 감사 — find -mtime -N \ decisions.jsonl 차집합
# 경로 정규화 (realpath), button repo 는 git log --since 교차검증
# 출력: missing-files 배열 → OUT JSON 의 missing_files 키
# ===========================================================================
MISSING_FILES_JSON="[]"
ACTUAL_FILE="${TMPDIR_WORK}/actual.txt"
RECORDED_FILE="${TMPDIR_WORK}/recorded.txt"
MISSING_FILE="${TMPDIR_WORK}/missing.txt"

{
  # 실제 변경 파일 (mtime 기준)
  find "${HOME}/.claude/rules" "${HOME}/.claude/skills" "${HOME}/.claude/docs" \
       "${HOME}/.claude/.ruler" \
       "D:/projects/button/agent/secretary.js" \
       "D:/projects/button/agent/secretary" \
       -type f -mtime "-${DAYS}" 2>/dev/null \
  | while IFS= read -r f; do
      realpath "$f" 2>/dev/null || echo "$f"
    done | sort -u > "$ACTUAL_FILE" || true

  # decisions.jsonl 에 기록된 파일 목록 (경로 정규화)
  if [ -f "$DEC" ]; then
    jq -r 'select(.ts != null) |
      .file // (.files[]? // empty)' \
      "$DEC" 2>/dev/null \
    | while IFS= read -r f; do
        [ -z "$f" ] && continue
        realpath "$f" 2>/dev/null || echo "$f"
      done | sort -u > "$RECORDED_FILE" || true
  else
    echo "" > "$RECORDED_FILE"
  fi

  # 차집합: 실제 변경됐지만 기록 안 된 파일
  comm -23 "$ACTUAL_FILE" "$RECORDED_FILE" 2>/dev/null \
  | while IFS= read -r f; do
      [ -z "$f" ] && continue
      # button repo: git log --since 교차검증 (mtime NTFS 오탐 방어)
      if echo "$f" | grep -qi "projects/button\|projects\\\\button"; then
        git -C "$BUTTON_DIR" log --since="${DAYS}.days" \
          --name-only --pretty=format: -- "$f" 2>/dev/null | grep -q . && echo "$f" || true
      else
        echo "$f"
      fi
    done | grep -v '^$' > "$MISSING_FILE" || true

  MISSING_FILES_JSON=$(jq -Rn '[inputs]' < "$MISSING_FILE" 2>/dev/null || echo "[]")
} 2>/dev/null || true

echo "[retrospective-collect] §0.5 missing audit done ($(jq 'length' <<< "${MISSING_FILES_JSON}") missing)" >&2

# ===========================================================================
# [Step 3-2b] backfill_missing() — missing_files 각 건 decisions.jsonl append
# ts: mtime+09:00, action:"backfill", original_absent:true
# tier: T1 (rules/skills/hooks 매칭) or unknown
# 중복 방지: 동일 file + original_absent:true entry 있으면 skip
# ===========================================================================
backfill_missing() {
  local missing_count
  missing_count=$(jq 'length' <<< "${MISSING_FILES_JSON}" 2>/dev/null || echo 0)
  [ "${missing_count:-0}" -eq 0 ] && return 0

  local backfilled=0 skipped=0
  local mf_list
  mf_list=$(jq -r '.[]' <<< "${MISSING_FILES_JSON}" 2>/dev/null)

  while IFS= read -r mf; do
    [ -z "$mf" ] && continue

    # 중복 감사: 이미 동일 file + original_absent:true entry 가 decisions.jsonl 에 있으면 skip
    if [ -f "$DEC" ]; then
      local dup
      dup=$(jq -c --arg f "$mf" \
        'select((.file // "") == $f and (.original_absent // false) == true) | .ts' \
        "$DEC" 2>/dev/null | head -1)
      if [ -n "$dup" ]; then
        skipped=$((skipped + 1))
        continue
      fi
    fi

    # mtime 확보 (파일이 삭제되었을 수도 있음 → fallback to now)
    local mtime_epoch mtime_iso
    if [ -e "$mf" ]; then
      mtime_epoch=$(stat -c '%Y' "$mf" 2>/dev/null || date +%s)
    else
      mtime_epoch=$(date +%s)
    fi
    mtime_iso=$(date -u -d "@${mtime_epoch}" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)+09:00

    # tier 추정: rules/skills/hooks 매칭 → T1, 외 → unknown
    local tier
    if echo "$mf" | grep -qE '/(rules|skills|hooks)/|\.ruler/'; then
      tier="T1"
    else
      tier="unknown"
    fi

    # decisions.jsonl append
    jq -cn --arg ts "$mtime_iso" \
           --arg session "retrospective-collect" \
           --arg file "$mf" \
           --arg tier "$tier" \
      '{ts: $ts, session: $session, file: $file,
        action: "backfill", reason: "missing_audit_backfill",
        original_absent: true, tier: $tier,
        meta: {inferred_from: "mtime"}}' >> "$DEC"
    backfilled=$((backfilled + 1))
  done <<< "$mf_list"

  echo "[retrospective-collect] backfill_missing done (backfilled=${backfilled} skipped=${skipped})" >&2
}

backfill_missing || echo "[retrospective-collect] WARN backfill_missing failed (best-effort)" >&2

# ===========================================================================
# [Step 3-3] compute_change_impact() — Verdict 계산 + md 표 렌더
# 입력: pre/post window JSON + audit-log + secretary-state
# 출력: .ruler/retrospective/{date}_change-impact.md
#       verdict 분포 JSON (OUT 에 merge)
# ===========================================================================

compute_change_impact() {
  local retro_date
  retro_date=$(date +%Y-%m-%d)
  local retro_dir="${RULER_DIR}/retrospective"
  local impact_md="${retro_dir}/${retro_date}_change-impact.md"
  local state_file="${RULER_DIR}/state.md"

  mkdir -p "$retro_dir"

  # Observation-only 모드 판정
  local enforcement_start
  enforcement_start=$(grep '^change_impact_enforcement_start:' "$state_file" 2>/dev/null \
    | awk '{print $2}' | tr -d '"' || echo "2026-05-16")
  local today_ymd
  today_ymd=$(date +%Y-%m-%d)
  local obs_only=true
  # 날짜 비교: enforcement_start <= today → enforcement 활성
  if [ "$(printf '%s\n' "$enforcement_start" "$today_ymd" | sort | head -1)" = "$enforcement_start" ] \
     && [ "$enforcement_start" != "$today_ymd" ]; then
    obs_only=false
  fi

  # T1/T2 entry 목록 재사용
  local t_entries_file="${TMPDIR_WORK}/t_entries.json"
  [ -f "$t_entries_file" ] || echo "[]" > "$t_entries_file"
  local t_count
  t_count=$(jq 'length' "$t_entries_file")

  # Verdict 집계 카운터
  local cnt_good=0 cnt_neutral=0 cnt_bad=0 cnt_insuf=0

  # md 표 행 임시 파일
  local rows_file="${TMPDIR_WORK}/impact_rows.txt"
  : > "$rows_file"

  # PRE/POST 맵 파일
  local pre_map="${TMPDIR_WORK}/pre_map.json"
  local post_map="${TMPDIR_WORK}/post_map.json"
  [ -f "$pre_map" ] || echo "{}" > "$pre_map"
  [ -f "$post_map" ] || echo "{}" > "$post_map"

  # audit-log 최근 N일 집계 (hook 실패 빈도 기준)
  local audit_err_total=0
  if [ -d "$AUDIT_LOG_DIR" ]; then
    while IFS= read -r af; do
      local c
      c=$(grep -c '"type":"ERROR"' "$af" 2>/dev/null || true)
      audit_err_total=$((audit_err_total + ${c:-0}))
    done < <(find "$AUDIT_LOG_DIR" -name "*.jsonl" -mtime "-${DAYS}" 2>/dev/null)
  fi

  # secretary-state escalation 카운터 (현재 값)
  local sec_state_file="D:/projects/button/agent/.secretary/.secretary-state.json"
  local esc_now=0
  if [ -f "$sec_state_file" ]; then
    esc_now=$(jq '.escalation_count // 0' "$sec_state_file" 2>/dev/null || echo 0)
  fi

  if [ "$t_count" -gt 0 ]; then
    jq -c '.[]' "$t_entries_file" 2>/dev/null | while IFS= read -r t_entry; do
      local t_ts t_check t_file t_action t_tier
      t_ts=$(echo "$t_entry" | jq -r '.ts')
      t_check=$(echo "$t_entry" | jq -r '.check // "unknown"')
      t_file=$(echo "$t_entry" | jq -r '.file // "unknown"')
      t_action=$(echo "$t_entry" | jq -r '.action // "-"')
      t_tier=$(echo "$t_entry" | jq -r '.tier // "T1"')

      local file_esc
      file_esc=$(echo "${t_file}" | tr '/' '_' | tr '\\' '_' | tr ':' '_')
      local key="${t_check}-${file_esc}"

      # pre/post window 에서 동일 check+file 재발동 건수
      # pre_map/post_map 구조: { "key": [entry, entry, ...] } → .[] | .[] 로 flatten
      local pre_count post_count
      pre_count=$(jq --arg f "$t_file" --arg c "$t_check" \
        '[.[] | .[] | select((.file // "") == $f and (.check // "") == $c)] | length' \
        "$pre_map" 2>/dev/null || echo 0)
      post_count=$(jq --arg f "$t_file" --arg c "$t_check" \
        '[.[] | .[] | select((.file // "") == $f and (.check // "") == $c)] | length' \
        "$post_map" 2>/dev/null || echo 0)

      # rollback 건수 (pre/post)
      local pre_rb post_rb
      pre_rb=$(jq --arg f "$t_file" \
        '[.[] | .[] | select((.file // "") == $f and (.action == "retroactive_rollback" or .outcome == "rolled_back"))] | length' \
        "$pre_map" 2>/dev/null || echo 0)
      post_rb=$(jq --arg f "$t_file" \
        '[.[] | .[] | select((.file // "") == $f and (.action == "retroactive_rollback" or .outcome == "rolled_back"))] | length' \
        "$post_map" 2>/dev/null || echo 0)

      # audit-log ts 기반 pre/post ERROR + ESCALATION 카운트 (T_TS ±3.5d window)
      # audit-log 파일은 "YYYY-MM-DD.jsonl" 일별 분리
      local t_epoch t_pre_epoch t_post_epoch
      t_epoch=$(date -u -d "$t_ts" +%s 2>/dev/null || echo 0)
      t_pre_epoch=$((t_epoch - 302400))   # -3.5d (3.5*86400)
      t_post_epoch=$((t_epoch + 302400))  # +3.5d
      local t_pre_iso t_post_iso
      t_pre_iso=$(date -u -d "@${t_pre_epoch}" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "1970-01-01T00:00:00Z")
      t_post_iso=$(date -u -d "@${t_post_epoch}" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "9999-12-31T23:59:59Z")

      local audit_err_pre=0 audit_err_post=0 esc_pre=0 esc_post=0
      if [ -d "$AUDIT_LOG_DIR" ] && [ "$t_epoch" -gt 0 ]; then
        # pre window (t_pre_iso ~ t_ts)
        while IFS= read -r af; do
          [ -z "$af" ] && continue
          local ec
          ec=$(awk -F'"' -v lo="$t_pre_iso" -v hi="$t_ts" '
            /"type":"ERROR"/ {
              ts=""
              for (i=1;i<=NF;i++) if ($i=="ts") { ts=$(i+2); break }
              if (ts >= lo && ts < hi) count++
            }
            END { print count+0 }
          ' "$af" 2>/dev/null || echo 0)
          audit_err_pre=$((audit_err_pre + ${ec:-0}))
          local esc_c
          esc_c=$(awk -F'"' -v lo="$t_pre_iso" -v hi="$t_ts" '
            /"type":"escalation_warned"/ {
              ts=""
              for (i=1;i<=NF;i++) if ($i=="ts") { ts=$(i+2); break }
              if (ts >= lo && ts < hi) count++
            }
            END { print count+0 }
          ' "$af" 2>/dev/null || echo 0)
          esc_pre=$((esc_pre + ${esc_c:-0}))
        done < <(find "$AUDIT_LOG_DIR" -name "*.jsonl" -newermt "@${t_pre_epoch}" ! -newermt "@${t_epoch}" 2>/dev/null)

        # post window (t_ts ~ t_post_iso)
        while IFS= read -r af; do
          [ -z "$af" ] && continue
          local ec
          ec=$(awk -F'"' -v lo="$t_ts" -v hi="$t_post_iso" '
            /"type":"ERROR"/ {
              ts=""
              for (i=1;i<=NF;i++) if ($i=="ts") { ts=$(i+2); break }
              if (ts > lo && ts <= hi) count++
            }
            END { print count+0 }
          ' "$af" 2>/dev/null || echo 0)
          audit_err_post=$((audit_err_post + ${ec:-0}))
          local esc_c
          esc_c=$(awk -F'"' -v lo="$t_ts" -v hi="$t_post_iso" '
            /"type":"escalation_warned"/ {
              ts=""
              for (i=1;i<=NF;i++) if ($i=="ts") { ts=$(i+2); break }
              if (ts > lo && ts <= hi) count++
            }
            END { print count+0 }
          ' "$af" 2>/dev/null || echo 0)
          esc_post=$((esc_post + ${esc_c:-0}))
        done < <(find "$AUDIT_LOG_DIR" -name "*.jsonl" -newermt "@${t_epoch}" ! -newermt "@${t_post_epoch}" 2>/dev/null)
      fi
      local err_delta esc_delta
      err_delta=$((audit_err_post - audit_err_pre))
      esc_delta=$((esc_post - esc_pre))

      # original_absent:true → INSUFFICIENT 강제
      local orig_absent
      orig_absent=$(echo "$t_entry" | jq -r '.original_absent // false')

      local verdict delta_summary
      if [ "$orig_absent" = "true" ]; then
        verdict="INSUFFICIENT"
        delta_summary="original_absent:true — pre/post 계산 불가"
      elif [ "$pre_count" -lt 5 ]; then
        # N<5 기준: Poisson 95% CI 하한 ~1.6. 초기 부트스트랩 기간 (T entry 희소) 에
        # 대부분 INSUFFICIENT 가 되어 obs-only 해제 불가 문제 완화. N=10 → 5 로 낮춤.
        verdict="INSUFFICIENT"
        delta_summary="N=${pre_count} < 5 (Poisson CI 하한 미달)"
      else
        # 변화율 계산 + audit-log delta 반영
        # GOOD: post ↓20%+ AND rollback 0 AND err_delta <= 0 AND esc_delta <= 0
        # BAD:  post ↑20%+ OR rollback 발생 OR err_delta >= +3 OR esc_delta >= +5
        # NEUTRAL: 그 외
        local verdict_code
        verdict_code=$(awk \
          -v pre="$pre_count" -v post="$post_count" \
          -v pre_rb="$pre_rb" -v post_rb="$post_rb" \
          -v err_d="$err_delta" -v esc_d="$esc_delta" \
          'BEGIN {
            if (pre == 0) { print "NEUTRAL"; exit }
            delta = (post - pre) / pre
            # BAD 우선 (하나라도 만족)
            if (post_rb > 0)   { print "BAD"; exit }
            if (delta >= 0.20) { print "BAD"; exit }
            if (err_d >= 3)    { print "BAD"; exit }
            if (esc_d >= 5)    { print "BAD"; exit }
            # GOOD (모두 만족)
            if (delta <= -0.20 && err_d <= 0 && esc_d <= 0) { print "GOOD"; exit }
            print "NEUTRAL"
          }')
        verdict="$verdict_code"
        delta_summary=$(awk \
          -v pre="$pre_count" -v post="$post_count" \
          -v err_d="$err_delta" -v esc_d="$esc_delta" \
          'BEGIN {
            if (pre == 0) { printf "pre=0 post=%d · err Δ%d·esc Δ%d", post, err_d, esc_d }
            else { printf "재발동 pre=%d post=%d (Δ%.0f%%) · err Δ%d·esc Δ%d", pre, post, (post-pre)/pre*100, err_d, esc_d }
          }')

        # BAD 확증: §부록 R1~R11 쿼리 — guide 스펙 "pre 대비 +50% 이상이면 BAD 확정 보조 표기"
        # 방식: R1/R3 는 post ≥ max(임계, pre × 1.5) 일 때만 hit, R2 는 발생 여부만
        if [ "$verdict" = "BAD" ]; then
          local r_hits=""
          # R1: 동일 파일 T1 Edit ≥3회 AND post ≥ pre*1.5
          local r1_pre r1_post
          r1_pre=$(jq -r --arg f "$t_file" \
            '[.[] | .[] | select((.file // "") == $f and (.tier | test("T1")))] | length' \
            "$pre_map" 2>/dev/null || echo 0)
          r1_post=$(jq -r --arg f "$t_file" \
            '[.[] | .[] | select((.file // "") == $f and (.tier | test("T1")))] | length' \
            "$post_map" 2>/dev/null || echo 0)
          local r1_trigger
          r1_trigger=$(awk -v pre="$r1_pre" -v post="$r1_post" \
            'BEGIN { if (post >= 3 && post >= pre * 1.5) print "1"; else print "0" }')
          [ "$r1_trigger" = "1" ] && r_hits="${r_hits}R1 pattern ${r1_post} hits (pre=${r1_pre}) "

          # R2: retroactive_rollback 1건+ → 즉시 확증 (guide "R2 = Sonnet 오판 확정")
          local r2_count
          r2_count=$((pre_rb + post_rb))
          [ "$r2_count" -ge 1 ] && r_hits="${r_hits}R2 pattern ${r2_count} hits "

          # R3: 동일 check 재발동 ≥3 AND post ≥ pre*1.5
          local r3_trigger
          r3_trigger=$(awk -v pre="$pre_count" -v post="$post_count" \
            'BEGIN { if (post >= 3 && post >= pre * 1.5) print "1"; else print "0" }')
          [ "$r3_trigger" = "1" ] && r_hits="${r_hits}R3 pattern ${post_count} hits (pre=${pre_count})"

          # R4: post window 내 동일 파일 pending/dropped ≥5
          local r4_count
          r4_count=$(jq -r --arg f "$t_file" \
            '[.[] | .[] | select((.file // "") == $f and (.action == "pending" or .action == "dropped"))] | length' \
            "$post_map" 2>/dev/null || echo 0)
          [ "$r4_count" -ge 5 ] && r_hits="${r_hits}R4 pattern ${r4_count} hits "

          # R5: audit-log regression_failed post window (t_ts ~ t_post_iso) ≥1
          local r5_count=0
          if [ -d "$AUDIT_LOG_DIR" ] && [ "$t_epoch" -gt 0 ]; then
            while IFS= read -r af; do
              [ -z "$af" ] && continue
              local rc
              rc=$(awk -F'"' -v lo="$t_ts" -v hi="$t_post_iso" '
                /"type":"regression_failed"/ {
                  ts=""
                  for (i=1;i<=NF;i++) if ($i=="ts") { ts=$(i+2); break }
                  if (ts > lo && ts <= hi) count++
                }
                END { print count+0 }
              ' "$af" 2>/dev/null || echo 0)
              r5_count=$((r5_count + ${rc:-0}))
            done < <(find "$AUDIT_LOG_DIR" -name "*.jsonl" -newermt "@${t_epoch}" ! -newermt "@${t_post_epoch}" 2>/dev/null)
          fi
          [ "$r5_count" -ge 1 ] && r_hits="${r_hits}R5 pattern ${r5_count} hits "

          [ -n "$r_hits" ] && delta_summary="${delta_summary} · ${r_hits}"
        fi
      fi

      # 카운터 기록 (파일 기반, subshell 제한 우회)
      echo "$verdict" >> "${TMPDIR_WORK}/verdicts.txt"

      # T 시각 KST 변환 (간략, Z → +09:00 오프셋 추가)
      local t_kst
      t_kst=$(echo "$t_ts" | sed 's/Z$/+09:00/' | sed 's/T/ /' | cut -c1-16)

      # 파일명 축약 (마지막 2 경로 요소)
      local file_short
      file_short=$(echo "$t_file" | awk -F'[/\\\\]' '{print $(NF-1)"/"$NF}' 2>/dev/null || echo "$t_file")

      # 행 기록
      printf "| %-20s | %-15s | %-4s | %-19s | %-11s | %-30s |\n" \
        "$t_kst" "$file_short" "$t_tier" "$t_action" "$verdict" "$delta_summary" \
        >> "$rows_file"
    done
  fi

  # verdicts.txt 에서 집계
  # awk 로 단일 pass 집계 — grep -c 의 Windows MSYS2 newline 섞임 회피
  if [ -f "${TMPDIR_WORK}/verdicts.txt" ]; then
    cnt_good=$(awk '$0=="GOOD"{n++} END{print n+0}' "${TMPDIR_WORK}/verdicts.txt")
    cnt_neutral=$(awk '$0=="NEUTRAL"{n++} END{print n+0}' "${TMPDIR_WORK}/verdicts.txt")
    cnt_bad=$(awk '$0=="BAD"{n++} END{print n+0}' "${TMPDIR_WORK}/verdicts.txt")
    cnt_insuf=$(awk '$0=="INSUFFICIENT"{n++} END{print n+0}' "${TMPDIR_WORK}/verdicts.txt")
  fi

  # md 파일 렌더링
  {
    # Observation-only 배너
    if [ "$obs_only" = "true" ]; then
      echo "> ⚠️ OBSERVATION-ONLY MODE (until ${enforcement_start})"
      echo ""
    fi

    echo "# Change-Impact Verdict — ${retro_date}"
    echo ""
    echo "Window: ${WINDOW} | T1/T2 entries: ${t_count} | GOOD: ${cnt_good} NEUTRAL: ${cnt_neutral} BAD: ${cnt_bad} INSUFFICIENT: ${cnt_insuf}"
    echo ""
    echo "| T                    | file            | tier | action              | verdict     | Δ summary                      |"
    echo "|----------------------|-----------------|------|---------------------|-------------|--------------------------------|"

    if [ -f "$rows_file" ] && [ -s "$rows_file" ]; then
      cat "$rows_file"
    else
      echo "| (no T1/T2 entries in window) | | | | | |"
    fi

    echo ""
    if [ "$obs_only" = "true" ]; then
      echo "> OBSERVATION-ONLY: BAD 판정이 있어도 preflight 승격/pending 생성 하지 않음."
    fi
  } > "$impact_md"

  echo "[retrospective-collect] compute_change_impact done → $impact_md (G=${cnt_good} N=${cnt_neutral} B=${cnt_bad} I=${cnt_insuf})" >&2

  # verdict 분포를 전역 변수 파일로 내보내기 (subshell → main shell)
  cat > "${TMPDIR_WORK}/verdict_dist.json" <<VJEOF
{"good":${cnt_good},"neutral":${cnt_neutral},"bad":${cnt_bad},"insufficient":${cnt_insuf},"impact_md":"${impact_md}"}
VJEOF
}

# compute_change_impact 실행
compute_change_impact || echo "[retrospective-collect] WARN compute_change_impact failed (best-effort)" >&2

# verdict_dist 읽기
VERDICT_DIST="{}"
[ -f "${TMPDIR_WORK}/verdict_dist.json" ] && \
  VERDICT_DIST=$(cat "${TMPDIR_WORK}/verdict_dist.json" 2>/dev/null || echo "{}")

# ===========================================================================
# === 최종 JSON 조립 ===
# ===========================================================================
# pre/post window 맵 읽기
PRE_MAP_FINAL=$(cat "${TMPDIR_WORK}/pre_map.json" 2>/dev/null || echo "{}")
POST_MAP_FINAL=$(cat "${TMPDIR_WORK}/post_map.json" 2>/dev/null || echo "{}")

jq -n --arg window "$WINDOW" --arg ts "$TS_NOW" \
      --slurpfile entries "$TMP" \
      --slurpfile ext "$TMP.ext" \
      --argjson pre_window "$PRE_MAP_FINAL" \
      --argjson post_window "$POST_MAP_FINAL" \
      --argjson missing_files "$MISSING_FILES_JSON" \
      --argjson verdict_dist "$VERDICT_DIST" \
      '{window:$window, collected_at:$ts,
        pre_window:$pre_window, post_window:$post_window,
        missing_files:$missing_files, verdict_dist:$verdict_dist,
        entries:$entries[0], external_state:$ext[0]}' \
  > "$OUT"

ENTRY_COUNT=$(jq '.entries | length' "$OUT")
echo "[retrospective-collect] OK entries=${ENTRY_COUNT} ext(err=${ERR_COUNT},esc=${ESC_COUNT},rate=${UNRESOLVED_RATE}) → $OUT" >&2

# R11 임계 힌트 (≥0.5 시 stderr 경고)
awk -v r="$UNRESOLVED_RATE" 'BEGIN{ if (r+0 >= 0.5) exit 1; exit 0 }' || \
  echo "[retrospective-collect] WARN R11 threshold crossed: unresolved_rate=${UNRESOLVED_RATE} ≥ 0.5" >&2

exit 0
