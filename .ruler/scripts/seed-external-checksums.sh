#!/usr/bin/env bash
# seed-external-checksums.sh — C_external baseline 생성
# 용도: ruler Tier C C_external drift 감지용 sha256 기준값 baseline 생성 (G7)
set -euo pipefail

RULER_SKILL="$HOME/.claude/skills/ruler-wf/skill.md"
AUDIT_SKILL="$HOME/.claude/skills/audit-wf/skill.md"
OUT="$HOME/.claude/.ruler/external-skill-checksums.md"

[ -f "$RULER_SKILL" ] || { echo "ERR: $RULER_SKILL missing" >&2; exit 1; }
[ -f "$AUDIT_SKILL" ] || { echo "ERR: $AUDIT_SKILL missing" >&2; exit 1; }

R_HASH=$(sha256sum "$RULER_SKILL" | cut -d' ' -f1)
A_HASH=$(sha256sum "$AUDIT_SKILL" | cut -d' ' -f1)

TODAY=$(date +%Y-%m-%d)

cat > "$OUT" <<EOF
# External Skill Checksums (baseline)
date: ${TODAY}

ruler-wf/skill.md: ${R_HASH}
audit-wf/skill.md: ${A_HASH}
EOF

echo "[seed] ${OUT} created"
echo "ruler-wf:  ${R_HASH}"
echo "audit-wf:  ${A_HASH}"
