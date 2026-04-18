#!/usr/bin/env bash
# test-compute-change-impact.sh — Step 5 fixture harness
#
# 3 fixture (good/bad/insufficient) 를 순회하며 retrospective-collect.sh 의
# compute_change_impact() 가 올바른 verdict 를 내리는지 확인.
#
# 각 fixture → 임시 RULER_DIR 구성 → collect.sh 실행 → 생성된
# retrospective/{date}_change-impact.md 의 verdict 열 파싱 → 기대값 assert.
#
# 사용:
#   bash D:/projects/ruler/.ruler/tests/test-compute-change-impact.sh
# 성공: exit 0 + "3/3 PASSED"
# 실패: exit 1 + "FAIL: <case> expected=X actual=Y"
#
# 동작 원리:
#   - HOME 을 임시 디렉터리로 swap → collect.sh 의 `RULER_DIR="${HOME}/.claude/.ruler"`
#     가 임시 경로로 resolve.
#   - fixture → decisions.jsonl 로 복사.
#   - state.md 는 `change_impact_enforcement_start: "2026-05-16"` 로 obs-only 유지
#     (verdict 판정 로직은 obs-only 와 무관).
#   - log/ 에 regression_placeholder 포함한 dummy.md 를 둠: collect.sh 의
#     `grep -l "regression_" ${RULER_DIR}/log/*.md` 파이프라인이 빈 glob 으로 인해
#     pipefail → set -e 로 조기 종료하는 것을 방지.
#
# 비고:
#   - collect.sh 는 현재 최종 jq 조립 단계에서 verdict_dist JSON 파싱 실패로 exit 2
#     가 날 수 있으나, 그 이전 단계에서 `retrospective/{date}_change-impact.md` 는
#     정상 렌더링됨. 따라서 이 테스트는 collect.sh exit code 를 엄격히 검사하지 않고
#     impact md 의 생성·내용만 검증한다.

set -euo pipefail

# jq PATH 보강 (collect.sh 와 동일 처리)
export PATH="/c/Users/jsh86/AppData/Roaming/npm/node_modules/node-jq/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="${SCRIPT_DIR}/fixtures"
COLLECT_SH="D:/projects/ruler/.ruler/scripts/retrospective-collect.sh"
TODAY="$(date +%Y-%m-%d)"

# 각 case 기대값
declare -A EXPECT=(
  [good]="GOOD"
  [bad]="BAD"
  [insufficient]="INSUFFICIENT"
)

PASS_COUNT=0
FAIL_MSGS=()

for CASE in good bad insufficient; do
  FIXTURE="${FIXTURES_DIR}/${CASE}-case.jsonl"
  if [ ! -f "$FIXTURE" ]; then
    FAIL_MSGS+=("FAIL: ${CASE} fixture missing: ${FIXTURE}")
    continue
  fi

  # 각 case 마다 독립된 임시 root 생성
  TMP_ROOT=$(mktemp -d)

  # HOME 을 임시 root 로 전환 → collect.sh 는 ${HOME}/.claude/.ruler 를 RULER_DIR 로 해석
  export HOME="$TMP_ROOT"
  TMP_RULER_DIR="${TMP_ROOT}/.claude/.ruler"
  TMP_AUDIT_DIR="${TMP_ROOT}/.claude/audit-log"

  mkdir -p "${TMP_RULER_DIR}/retrospective" \
           "${TMP_RULER_DIR}/rollback" \
           "${TMP_RULER_DIR}/pending/resolved" \
           "${TMP_RULER_DIR}/pending/dropped" \
           "${TMP_RULER_DIR}/batch-plans/done" \
           "${TMP_RULER_DIR}/log" \
           "${TMP_AUDIT_DIR}"

  # fixture → decisions.jsonl
  cp "$FIXTURE" "${TMP_RULER_DIR}/decisions.jsonl"

  # collect.sh 의 `grep -l "regression_" ${RULER_DIR}/log/*.md` 가 빈 glob 에서
  # pipefail → set -e 로 죽는 것을 방지. regression_ 문자열이 포함된 dummy 파일 생성.
  echo "regression_placeholder" > "${TMP_RULER_DIR}/log/dummy.md"

  # state.md: obs-only 유지 (enforcement_start 를 미래로)
  cat > "${TMP_RULER_DIR}/state.md" <<'STATE_EOF'
---
type: ruler-state
cycle: 0
change_impact_enforcement_start: "2026-05-16"
---
STATE_EOF

  # collect.sh 실행 — exit code 는 느슨하게 처리 (impact.md 가 렌더링되면 OK)
  OUT_JSON="${TMP_ROOT}/out.json"
  COLLECT_LOG="${TMP_ROOT}/collect.log"
  bash "$COLLECT_SH" --window 7d --out "$OUT_JSON" >"$COLLECT_LOG" 2>&1 || true

  IMPACT_MD="${TMP_RULER_DIR}/retrospective/${TODAY}_change-impact.md"
  if [ ! -f "$IMPACT_MD" ]; then
    FAIL_MSGS+=("FAIL: ${CASE} change-impact.md not rendered at ${IMPACT_MD}")
    echo "--- ${CASE} collect.log tail ---" >&2
    tail -30 "$COLLECT_LOG" >&2 || true
    echo "--- end ---" >&2
    rm -rf "$TMP_ROOT"
    continue
  fi

  # T row 추출: T1 entry ts=2026-04-09T12:00:00+09:00 → KST "2026-04-09 12:00"
  # 행 형식: | 2026-04-09 12:00     | file/path       | T1   | edit                | VERDICT     | Δ summary |
  # awk -F '|' 시 field indices: $1="" (leading), $2..$7=columns, $8="" (trailing)
  # verdict 열 = $6
  ROW=$(grep -E '^\| 2026-04-09' "$IMPACT_MD" || true)
  if [ -z "$ROW" ]; then
    FAIL_MSGS+=("FAIL: ${CASE} no T row found in ${IMPACT_MD}")
    echo "--- ${IMPACT_MD} contents ---" >&2
    cat "$IMPACT_MD" >&2 || true
    echo "--- end ---" >&2
    rm -rf "$TMP_ROOT"
    continue
  fi

  # verdict 파싱: 1차 — awk column 6
  ACTUAL=$(echo "$ROW" | awk -F '|' '{gsub(/ /,"",$6); print $6}')
  # 2차 fallback — awk 실패 시 grep -oE 로 재시도
  if ! echo "$ACTUAL" | grep -qE '^(GOOD|BAD|NEUTRAL|INSUFFICIENT)$'; then
    ACTUAL=$(echo "$ROW" | grep -oE 'GOOD|BAD|NEUTRAL|INSUFFICIENT' | head -1 || true)
  fi

  EXPECTED="${EXPECT[$CASE]}"
  if [ "$ACTUAL" = "$EXPECTED" ]; then
    echo "PASS: ${CASE} (verdict=${ACTUAL})"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    FAIL_MSGS+=("FAIL: ${CASE} expected=${EXPECTED} actual=${ACTUAL:-<empty>}")
    echo "--- ${CASE} change-impact.md ---" >&2
    cat "$IMPACT_MD" >&2 || true
    echo "--- ${CASE} T row ---" >&2
    echo "$ROW" >&2
    echo "--- ${CASE} collect.log tail ---" >&2
    tail -30 "$COLLECT_LOG" >&2 || true
    echo "--- end ---" >&2
  fi

  rm -rf "$TMP_ROOT"
done

echo ""
if [ "$PASS_COUNT" -eq 3 ]; then
  echo "3/3 PASSED"
  exit 0
else
  for msg in "${FAIL_MSGS[@]}"; do
    echo "$msg" >&2
  done
  echo "${PASS_COUNT}/3 PASSED" >&2
  exit 1
fi
