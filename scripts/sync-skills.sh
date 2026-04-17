#!/bin/bash
# sync-skills.sh — G:\ Obsidian 볼트 skill.md → ruler repo 단방향 동기화
#
# 목적: ruler-wf / audit-wf 스킬은 Obsidian G:\ 볼트 (Google Drive) 에 물리적으로 존재.
#       reparse point 미지원으로 symlink 불가 → 커밋 직전 repo 쪽으로 copy 강제.
#
# SSOT: G:\내 드라이브\obsidian_logan\00_Claude_Control\skills\{ruler-wf,audit-wf}\skill.md
# mirror: D:\projects\ruler\skills\{ruler-wf,audit-wf}\skill.md
#
# 방향: G:\ → repo (단방향). repo 쪽 수정은 수동으로 G:\ 에 반영 필요 (refine 결과 등).
#
# 호출: .git/hooks/pre-commit 이 자동 실행. 수동 실행도 안전 (idempotent).

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VAULT_SKILLS="/g/내 드라이브/obsidian_logan/00_Claude_Control/skills"

declare -a TARGETS=("ruler-wf" "audit-wf")

changed=0
for name in "${TARGETS[@]}"; do
  src="$VAULT_SKILLS/$name/skill.md"
  dst="$REPO_ROOT/skills/$name/skill.md"

  if [[ ! -f "$src" ]]; then
    echo "[sync-skills] ERROR: source missing — $src" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$dst")"

  if [[ ! -f "$dst" ]] || ! cmp -s "$src" "$dst"; then
    cp "$src" "$dst"
    echo "[sync-skills] synced: $name/skill.md"
    changed=1
  fi
done

if [[ $changed -eq 1 ]]; then
  # pre-commit 호출 시 변경분 자동 스테이징
  if [[ "${1:-}" == "--stage" ]]; then
    cd "$REPO_ROOT"
    git add skills/ruler-wf/skill.md skills/audit-wf/skill.md
    echo "[sync-skills] staged updated skill.md files"
  fi
else
  echo "[sync-skills] no changes (G:\\ 와 repo 일치)"
fi
