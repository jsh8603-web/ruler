#!/bin/bash
# t1-gate.sh — Ruler T1 자동 수정 Gate (결정론적 판정)
#
# Ruler 가 자기 판단으로 T1 Edit 실행 전 반드시 호출.
# FAIL 시 Ruler 는 해당 수정을 T3 pending 으로 강제 전환해야 한다.
# 사용자 명시 승인 시 --authorized-by <who> 플래그로 override 가능
# (경고만, decisions.jsonl 에 tier=T1_user_auth 로 기록 필수).
#
# Usage:
#   t1-gate.sh <file> <new-content-path> [--authorized-by <who>]
#
# Exit codes:
#   0 = PASS      (T1 즉시 적용 가능)
#   1 = FAIL      (T3 pending 전환 필수)
#   2 = OVERRIDE  (--authorized-by 있음, 경고만. decisions.jsonl 기록 의무)

set -u

FILE="${1:-}"
NEW="${2:-}"
shift 2 2>/dev/null || true

AUTH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --authorized-by) AUTH="${2:-}"; shift 2;;
    *) shift;;
  esac
done

if [ -z "$FILE" ] || [ -z "$NEW" ]; then
  echo "Usage: t1-gate.sh <file> <new-content-path> [--authorized-by <who>]" >&2
  exit 1
fi
if [ ! -f "$FILE" ] || [ ! -f "$NEW" ]; then
  echo "[t1-gate] FAIL file-not-found FILE=$FILE NEW=$NEW" >&2
  exit 1
fi

MAX_LINES=5
EXT="${FILE##*.}"
BASENAME="$(basename "$FILE")"
REASONS=()

# ── (0) Phase 1 Sonnet Migration — opus_only_files hard-block ──
# state.md 의 opus_only_files YAML 리스트에 매칭되는 파일은 T1 경로 불가.
# Sonnet patrol 이 실수로 secretary.js 등을 T1 로 편집하는 것을 차단.
# 글롭 지원 (예: D:/projects/button/agent/secretary/*.js).
STATE_MD="$HOME/.claude/.ruler/state.md"
if [ -f "$STATE_MD" ]; then
  # FILE 을 절대경로로 정규화 (~ 전개 포함)
  FILE_ABS="${FILE/#\~/$HOME}"
  case "$FILE_ABS" in
    /*|?:*) ;;  # 이미 절대경로
    *) FILE_ABS="$(cd "$(dirname "$FILE_ABS")" 2>/dev/null && pwd)/$(basename "$FILE_ABS")" ;;
  esac

  # opus_only_files 블록 추출 (`opus_only_files:` 부터 다음 non-`  - ` 줄까지)
  OPUS_LIST=$(awk '
    /^opus_only_files:/ { in_block=1; next }
    in_block && /^[[:space:]]*-[[:space:]]/ { sub(/^[[:space:]]*-[[:space:]]/,""); print; next }
    in_block && !/^[[:space:]]*-/ { in_block=0 }
  ' "$STATE_MD")

  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    # ~ 전개
    pattern="${pattern/#\~/$HOME}"
    # 글롭 매칭 (case + shopt)
    case "$FILE_ABS" in
      $pattern)
        REASONS+=("opus_only_file: $pattern")
        break
        ;;
    esac
  done <<< "$OPUS_LIST"
fi

# ── (0b) ruler self-edit hard-block ──
# 장수명 ruler 순찰 세션 ($PSMUX_SESSION=ruler) 이 .t2-locked-files 에
# 등록된 파일을 직접 Edit 하려 하면 hard-block. 유일한 적용 경로는
# ruler-batch-{ts} 스폰 위임. --authorized-by override 는 여전히 허용.
# 근거: patrol "내가 Opus 니까 그냥 해도 된다" 합리화 차단 (2026-04-14 재발).
LOCKED_LIST="$HOME/.claude/.ruler/.t2-locked-files"
if [ -f "$LOCKED_LIST" ] && [[ "${PSMUX_SESSION:-}" =~ ^ruler[[:space:]]*$ ]]; then
  FILE_ABS2="${FILE/#\~/$HOME}"
  case "$FILE_ABS2" in
    /*|?:*) ;;
    *) FILE_ABS2="$(cd "$(dirname "$FILE_ABS2")" 2>/dev/null && pwd)/$(basename "$FILE_ABS2")" ;;
  esac
  while IFS= read -r lpat; do
    # comment / blank skip
    case "$lpat" in ''|'#'*) continue;; esac
    lpat="${lpat/#\~/$HOME}"
    case "$FILE_ABS2" in
      $lpat)
        REASONS+=("ruler-self-edit-blocked: $lpat")
        break
        ;;
    esac
  done < "$LOCKED_LIST"
fi

# ── (a) diff 라인 수 cap ──
DIFF_LINES=$(diff "$FILE" "$NEW" 2>/dev/null | grep -cE '^[<>]' || echo 0)
if [ "${DIFF_LINES:-0}" -gt "$MAX_LINES" ]; then
  REASONS+=("diff-lines=${DIFF_LINES}>${MAX_LINES}")
fi

# ── (b) 추가된 라인만 추출 (실제 새로 들어가는 코드) ──
ADDED=$(diff "$FILE" "$NEW" 2>/dev/null | grep -E '^>' | sed 's/^> //' || true)

# ── (c) secretary.js strict whitelist (⑤) ──
# 허용: 주석(// /* *), 대문자 상수 선언, 따옴표 문자열 리터럴, 경로 리터럴
# 금지: function 선언, 화살표 함수, if/else/while/for/return/switch/try/catch,
#       new RegExp, 정규식 literal
if [ "$BASENAME" = "secretary.js" ] && [ -n "$ADDED" ]; then
  DISALLOWED=$(echo "$ADDED" | grep -nE '^(function\b|[[:space:]]*(if|else|while|for|return|switch|case|try|catch)\b)|=>|new RegExp|^[[:space:]]*/[^/*][^/]*/' || true)
  if [ -n "$DISALLOWED" ]; then
    FIRST=$(echo "$DISALLOWED" | head -1 | cut -c1-80)
    REASONS+=("secretary.js-strict-violation: ${FIRST}")
  fi
fi

# ── (d) syntax check ──
case "$EXT" in
  js)
    if command -v node >/dev/null 2>&1; then
      node --check "$NEW" 2>/dev/null || REASONS+=("node-check-failed")
    fi
    ;;
  sh|bash)
    bash -n "$NEW" 2>/dev/null || REASONS+=("bash-n-failed")
    ;;
esac

# ── 판정 ──
if [ ${#REASONS[@]} -eq 0 ]; then
  echo "[t1-gate] PASS file=${BASENAME} diff=${DIFF_LINES}" >&2
  exit 0
fi

REASON_STR=$(IFS='; '; echo "${REASONS[*]}")

if [ -n "$AUTH" ]; then
  echo "[t1-gate] OVERRIDE authorized-by=${AUTH} reasons=${REASON_STR}" >&2
  exit 2
fi

echo "[t1-gate] FAIL reasons=${REASON_STR}" >&2
exit 1
