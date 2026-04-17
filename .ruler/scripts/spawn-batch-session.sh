#!/bin/bash
# spawn-batch-session.sh — Ruler T2 Batch Resolver 세션 스폰 헬퍼
#
# 목적: ruler-batch-{ts} 단수명 세션 1회 스폰.
#       Enter 누락 방지 위한 send-keys 표준화 + opus 모델 고정 + cwd=~/.claude 고정.
#
# Usage:
#   spawn-batch-session.sh <plan-file-absolute-path>
#   spawn-batch-session.sh /c/Users/jsh86/.claude/.ruler/batch-plans/20260417T1022_xxx.md
#
# 특징:
#   - 세션명 = ruler-batch-$(date +%Y%m%dT%H%M%S) 자동 생성
#   - 모델 = opus 고정 (retrospective-guide.md §19 요구사항)
#   - cwd = /c/Users/jsh86/.claude 고정 (button 레포 등 엉뚱한 곳에 박히는 사고 방지)
#   - self-target 금지: ruler 세션 자신에게 스폰 금지
#   - 초기 프롬프트 = plan 파일 Read + t2-batch-resolver 6-Step 실행 + self-terminate 지시
#   - send-keys 는 전부 'Enter' 분리 호출 → 프롬프트창에 미입력 잔류 방지
#
# Exit codes:
#   0  성공
#   1  plan 파일 누락/존재하지 않음
#   2  self-target 시도
#   3  동명 세션 이미 존재 (극히 드문 타이밍 충돌)
#   4  psmux new-session 실패
#   5  Claude bypass 미감지 (timeout)

set -u

PLAN_FILE="${1:-}"

if [ -z "$PLAN_FILE" ]; then
  echo "Usage: spawn-batch-session.sh <plan-file-absolute-path>" >&2
  exit 1
fi

if [ ! -f "$PLAN_FILE" ]; then
  echo "[batch-spawn] ERROR: plan file not found: $PLAN_FILE" >&2
  exit 1
fi

# ── 세션명 생성 ──
TS=$(date +%Y%m%dT%H%M%S)
SESSION="ruler-batch-${TS}"

# ── psmux 경로 ──
PSMUX="/c/Users/jsh86/AppData/Local/Microsoft/WinGet/Packages/marlocarlo.psmux_Microsoft.Winget.Source_8wekyb3d8bbwe/psmux.exe"
if [ ! -f "$PSMUX" ]; then
  # fallback: PATH 에서 찾기
  PSMUX=$(command -v psmux || echo "")
  if [ -z "$PSMUX" ]; then
    echo "[batch-spawn] ERROR: psmux not found" >&2
    exit 1
  fi
fi

# ── self-target 방지 ──
CURRENT_SESSION="${PSMUX_SESSION:-}"
if [ "$CURRENT_SESSION" = "$SESSION" ]; then
  echo "[batch-spawn] ERROR: self-target forbidden (current=$CURRENT_SESSION)" >&2
  exit 2
fi

# ── 중복 세션 확인 ──
if "$PSMUX" has-session -t "$SESSION" 2>/dev/null; then
  echo "[batch-spawn] ERROR: session already exists: $SESSION" >&2
  exit 3
fi

# ── plan 파일 절대경로 정규화 ──
# Windows 경로로 들어온 경우 MSYS 경로로 통일
if [[ "$PLAN_FILE" =~ ^[A-Za-z]:[\\/] ]]; then
  PLAN_FILE_MSYS=$(echo "$PLAN_FILE" | sed 's|^\([A-Za-z]\):|/\L\1|; s|\\|/|g')
else
  PLAN_FILE_MSYS="$PLAN_FILE"
fi

# ── cwd 고정 (Windows 형식) ──
WIN_CWD="C:\\Users\\jsh86\\.claude"

echo "[batch-spawn] Session: $SESSION"
echo "[batch-spawn] Plan:    $PLAN_FILE_MSYS"
echo "[batch-spawn] Model:   opus"
echo "[batch-spawn] Cwd:     $WIN_CWD"

# ── 1. 세션 생성 ──
"$PSMUX" new-session -d -s "$SESSION" -x 200 -y 50
if [ $? -ne 0 ]; then
  echo "[batch-spawn] ERROR: session creation failed" >&2
  exit 4
fi
echo "[batch-spawn] Session created"

# ── 2. wt.exe 창 ──
PSMUX_WIN=$(cygpath -w "$PSMUX" 2>/dev/null || echo "$PSMUX")
TITLE="${SESSION} (opus)"
powershell.exe -WindowStyle Hidden -Command "Start-Process wt.exe -ArgumentList '--pos','320,180','--size','140,45','--title','\"${TITLE}\"','${PSMUX_WIN}','attach-session','-t','${SESSION}'" &
sleep 2

# ── 3. cd + Claude 스폰 ──
SYSTEM_PROMPT="Ruler Batch Session. 단수명 (작업 1회 후 self-terminate). cwd=~/.claude. 모델=opus. 먼저 plan 파일 frontmatter 의 mode 필드 확인 → mode=retrospective 면 SSOT=~/.claude/.ruler/retrospective-guide.md §Phase 3 (Phase A→B→Final→C), 그 외 / 필드 없음이면 SSOT=~/.claude/.ruler/t2-batch-resolver.md §Batch Resolver 6-Step. patrol 본체(ruler-wf/skill.md) 읽지 않음. 작업 완료 = psmux kill-session 으로 즉시 self-terminate."

"$PSMUX" send-keys -t "$SESSION" "cd /d ${WIN_CWD}" Enter
sleep 1
"$PSMUX" send-keys -t "$SESSION" "set PSMUX_SESSION=${SESSION} && set MAX_THINKING_TOKENS=24000 && claude --dangerously-skip-permissions --model claude-opus-4-7[1m] --system-prompt \"${SYSTEM_PROMPT}\"" Enter
echo "[batch-spawn] Claude spawning..."

# ── 4. bypass/trust 통합 폴링 (최대 150초) ──
READY=false
TRUST_HANDLED=false
for i in $(seq 1 75); do
  sleep 2
  PANE=$("$PSMUX" capture-pane -t "$SESSION" -p -S 0 2>/dev/null)
  PANE_NS=$(echo "$PANE" | tr -d ' ')

  if echo "$PANE_NS" | grep -qi "bypass"; then
    READY=true
    echo "[batch-spawn] Claude ready after $((i*2))s"
    break
  fi

  if [ "$TRUST_HANDLED" = false ] && echo "$PANE_NS" | grep -qi "trustthisfolder"; then
    CURSOR_LINE=$(echo "$PANE_NS" | grep "❯" | head -1)
    if echo "$CURSOR_LINE" | grep -qi "yes"; then
      "$PSMUX" send-keys -t "$SESSION" Enter
    elif echo "$CURSOR_LINE" | grep -qi "no"; then
      YES_LINE=$(echo "$PANE_NS" | grep -in "yes,itrust\|yes.*trust" | head -1 | cut -d: -f1)
      NO_LINE=$(echo "$PANE_NS" | grep -in "no,exit\|no.*exit" | head -1 | cut -d: -f1)
      if [ -n "$YES_LINE" ] && [ -n "$NO_LINE" ] && [ "$YES_LINE" -lt "$NO_LINE" ]; then
        "$PSMUX" send-keys -t "$SESSION" Up
      else
        "$PSMUX" send-keys -t "$SESSION" Down
      fi
      sleep 1
      "$PSMUX" send-keys -t "$SESSION" Enter
    else
      "$PSMUX" send-keys -t "$SESSION" Up
      sleep 1
      "$PSMUX" send-keys -t "$SESSION" Enter
    fi
    TRUST_HANDLED=true
    sleep 2
  fi
done

if [ "$READY" = false ]; then
  echo "[batch-spawn] WARNING: bypass not detected after 150s — continuing anyway" >&2
fi

sleep 2

# ── 5. /remote-control (UI 상태 전환) ──
# MSYS_NO_PATHCONV=1 필수 — MSYS2 가 '/remote-control' 을 경로로 변환하지 않도록.
MSYS_NO_PATHCONV=1 "$PSMUX" send-keys -t "$SESSION" '/remote-control' Enter
echo "[batch-spawn] /remote-control sent"
sleep 4

# ── 6. 초기 프롬프트 송신 (psmux-safe-send.sh 래퍼 경유) ──
# 직접 send-keys 로 multi-line 변수 전달하면 첫 줄에서 submit 되는 버그가 있다
# (promotion-log 2026-04-17 "INIT_MSG multi-line 첫줄만 submit").
# 래퍼: newline→space + 400자 truncate + Enter 분리 + verify-retry 2회.
# plan 파일은 --file 옵션으로 append → 래퍼가 "-- Read ${PLAN_FILE_MSYS}" 추가.
# 상세 6-Step 프로토콜은 세션이 t2-batch-resolver.md 를 Read 해서 로드.
SAFE_SEND="/d/projects/button/agent/.secretary/.scripts/psmux-safe-send.sh"
INIT_MSG="[batch-init] plan 파일 먼저 Read → frontmatter mode 확인. mode=retrospective → retrospective-guide.md §Phase 3 (Phase A→B→Final→C) 실행. 그 외 → t2-batch-resolver.md §Batch Resolver 6-Step. 완료 후 [ruler-wf-end] ruler 에 송신 + self-terminate (kill-session ${SESSION})."

if [ -x "$SAFE_SEND" ]; then
  bash "$SAFE_SEND" "$SESSION" "$INIT_MSG" --file "$PLAN_FILE_MSYS"
  echo "[batch-spawn] Init prompt sent via psmux-safe-send.sh"
else
  # fallback: 래퍼 없으면 단일 라인으로 압축 + 분리 송신
  echo "[batch-spawn] WARNING: psmux-safe-send.sh not found, using fallback" >&2
  COMPACT_MSG="${INIT_MSG} -- Read ${PLAN_FILE_MSYS}"
  "$PSMUX" send-keys -t "$SESSION" "$COMPACT_MSG"
  sleep 1
  "$PSMUX" send-keys -t "$SESSION" Enter
fi

echo "[batch-spawn] DONE (session=${SESSION}, plan=${PLAN_FILE_MSYS}, model=opus)"
echo "$SESSION"
