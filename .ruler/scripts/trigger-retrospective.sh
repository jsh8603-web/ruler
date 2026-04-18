#!/usr/bin/env bash
# trigger-retrospective.sh — retrospective 3-step 원자 실행 래퍼
#
# Flow:
#   Step 1/3: retrospective-collect.sh --window 7d --out <OUT>
#   Step 2/3: batch plan 파일 heredoc 작성 (guide.md 템플릿)
#   Step 3/3: spawn-batch-session.sh <PLAN>
#
# Usage:
#   bash trigger-retrospective.sh              # 실제 실행
#   bash trigger-retrospective.sh --help       # 3-step 개요 출력 후 종료
#   bash trigger-retrospective.sh --dry-run    # 3-step 개요 출력 후 종료 (--help 와 동일)
#
# CLAUDE.md Auto Triggers 주간리뷰 줄이 이 스크립트 한 줄 호출로 단순화됨.

set -euo pipefail

TS=$(date +%Y%m%dT%H%M%S)
OUT="/tmp/retro-${TS}.json"
PLAN="/c/Users/jsh86/.claude/.ruler/batch-plans/${TS}_retrospective.md"

# --help / --dry-run: 3-step 개요만 출력하고 종료 (exit 0)
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--dry-run" ]; then
  echo "[trigger] Step 1/3: retrospective-collect.sh --window 7d --out ${OUT}"
  echo "[trigger] Step 2/3: plan file heredoc → ${PLAN}"
  echo "[trigger] Step 3/3: spawn-batch-session.sh ${PLAN}"
  exit 0
fi

mkdir -p "$(dirname "$PLAN")"

echo "[trigger] Step 1/3: retrospective-collect.sh"
bash ~/.claude/.ruler/scripts/retrospective-collect.sh --window 7d --out "$OUT"

echo "[trigger] Step 2/3: plan file"
cat > "$PLAN" <<EOF
---
type: t2-batch-plan
mode: retrospective
input: $OUT
created: $(date -Iseconds)
---
# Retrospective ${TS}

Input=\`$OUT\`. Phase A → B → C → Final → Terminal per retrospective-guide.md.
EOF

echo "[trigger] Step 3/3: spawn-batch-session.sh"
bash ~/.claude/.ruler/scripts/spawn-batch-session.sh "$PLAN"
