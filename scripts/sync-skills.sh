#!/bin/bash
# sync-skills.sh — G:\ Obsidian 볼트 ↔ ruler repo 3-way 지능형 동기화
#
# 목적: ruler-wf / audit-wf 스킬이 G:\ 볼트 (Google Drive) 와 repo D:\ 양쪽에 존재.
#       어느 쪽에서 편집하든 양쪽이 일관되도록 자동 sync + 충돌 시 abort.
#
# 경로:
#   G:\ (SSOT 초기): G:\내 드라이브\obsidian_logan\00_Claude_Control\skills\{name}\skill.md
#   repo (mirror):   D:\projects\ruler\skills\{name}\skill.md
#
# 판정 로직 (git HEAD 기준 3-way):
#   +---------+---------+-----------------------------------------+
#   | G: vs H | D: vs H | 동작                                    |
#   +---------+---------+-----------------------------------------+
#   | 일치    | 일치    | no-op                                   |
#   | 다름    | 일치    | G: → D:  (정상: 외부 편집 흡수)        |
#   | 일치    | 다름    | D: → G:  (역전파: refine/직접 편집)    |
#   | 다름    | 다름    | ABORT    (양쪽 독립 편집 = 충돌)       |
#   +---------+---------+-----------------------------------------+
#
# 호출:
#   ./sync-skills.sh           # dry-run 요약만
#   ./sync-skills.sh --stage   # 변경 시 git add (pre-commit hook 용)

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VAULT_SKILLS="/g/내 드라이브/obsidian_logan/00_Claude_Control/skills"

declare -a TARGETS=("ruler-wf" "audit-wf")
STAGE_FLAG="${1:-}"

cd "$REPO_ROOT"

changed=0
abort=0

for name in "${TARGETS[@]}"; do
  g_path="$VAULT_SKILLS/$name/skill.md"
  d_path="$REPO_ROOT/skills/$name/skill.md"
  rel="skills/$name/skill.md"

  if [[ ! -f "$g_path" ]]; then
    echo "[sync-skills] ERROR: G: source missing — $g_path" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$d_path")"

  # HEAD 버전 추출 (없으면 빈 파일 = 최초 tracking 전)
  head_tmp="$(mktemp)"
  trap 'rm -f "$head_tmp"' EXIT
  if git cat-file -e "HEAD:$rel" 2>/dev/null; then
    git show "HEAD:$rel" > "$head_tmp"
  else
    : > "$head_tmp"
  fi

  g_vs_head=1
  d_vs_head=1
  cmp -s "$g_path" "$head_tmp" && g_vs_head=0
  [[ -f "$d_path" ]] && cmp -s "$d_path" "$head_tmp" && d_vs_head=0

  if [[ $g_vs_head -eq 0 && $d_vs_head -eq 0 ]]; then
    # both equal HEAD → no-op
    continue
  elif [[ $g_vs_head -ne 0 && $d_vs_head -eq 0 ]]; then
    # G: 새 것, D: HEAD와 일치 → G: → D:
    cp "$g_path" "$d_path"
    echo "[sync-skills] G: → D: ($name/skill.md)"
    changed=1
  elif [[ $g_vs_head -eq 0 && $d_vs_head -ne 0 ]]; then
    # D: 새 것, G: HEAD와 일치 → D: → G:
    cp "$d_path" "$g_path"
    echo "[sync-skills] D: → G: ($name/skill.md) [역전파]"
    changed=1
  else
    # 양쪽 다 HEAD와 다름 → 충돌
    echo "[sync-skills] CONFLICT: $name/skill.md — G:\\ 와 D:\\ 둘 다 HEAD 와 다름" >&2
    echo "              G: $g_path" >&2
    echo "              D: $d_path" >&2
    echo "              수동으로 어느 쪽을 채택할지 결정하고 반대편에 cp 하세요." >&2
    echo "              예) diff '$g_path' '$d_path'" >&2
    abort=1
  fi

  rm -f "$head_tmp"
  trap - EXIT
done

if [[ $abort -eq 1 ]]; then
  echo "[sync-skills] abort — 충돌 해결 후 재시도" >&2
  exit 2
fi

if [[ $changed -eq 1 ]]; then
  if [[ "$STAGE_FLAG" == "--stage" ]]; then
    git add "skills/ruler-wf/skill.md" "skills/audit-wf/skill.md"
    echo "[sync-skills] staged updated skill.md files"
  fi
else
  echo "[sync-skills] no changes (G:\\ 와 repo 일치)"
fi
