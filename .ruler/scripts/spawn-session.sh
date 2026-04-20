#!/bin/bash
# spawn-session.sh — harness-wf 스펙 완전 구현
# 세션 생성 → wt.exe 창 → Claude 스폰(system-prompt) → 핸드셰이크(ACK) → 역할 주입
#
# Usage:
#   spawn-session.sh <session-name> [role-file]
#   session-name: worker | verifier | healer | strategic | <custom>
#   role-file: 기본값 .harness/<session>-role.md (없으면 역할 주입 생략)
#
# 병렬 실행:
#   bash spawn-session.sh worker &
#   bash spawn-session.sh verifier &
#   bash spawn-session.sh healer &
#   bash spawn-session.sh strategic &
#   wait
#   # → 4세션 동시 기동, 각각 ACK까지 완료 후 리턴

SESSION="$1"
ROLE_ARG="${2:-}"

if [ -z "$SESSION" ]; then
  echo "Usage: spawn-session.sh <session-name> [role-file]" >&2
  exit 1
fi

# ── 경로 설정 ──
SECRETARY_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$SECRETARY_DIR/.sonnet-config.json"

# jq 없으면 grep fallback
if command -v jq &>/dev/null; then
  PSMUX=$(jq -r '.psmux_path' "$CONFIG" 2>/dev/null)
else
  PSMUX=$(grep -o '"psmux_path"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG" | sed 's/.*"psmux_path"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi

if [ -z "$PSMUX" ] || [ ! -f "$PSMUX" ]; then
  echo "[spawn:${SESSION}] ERROR: psmux not found (PSMUX=$PSMUX)" >&2
  exit 1
fi

# SSOT psmux helper (PSMUX_BIN 으로 bridge)
PSMUX_BIN="$PSMUX" source "$HOME/.claude/scripts/lib/psmux-send.sh"

# ruler 세션 단수성 강제: 이미 존재하면 스크립트 자체가 early-exit.
# WF 쪽 재진입 프로토콜 (kill 금지, 컨텍스트만 주입) 과는 별개의 안전망이며,
# 실수로 `spawn-session.sh ruler` 가 두 번 호출돼도 기존 세션이 훼손되지 않도록 보장한다.
if [ "$SESSION" = "ruler" ]; then
  if "$PSMUX" has-session -t ruler 2>/dev/null; then
    echo "[spawn:ruler] SKIP — 기존 ruler 세션 존재. WF 재진입 프로토콜로 컨텍스트만 주입하세요 (kill 금지)." >&2
    echo "[spawn:ruler] reference: ~/.claude/skills/ruler-wf/skill.md §2 재진입 프로토콜" >&2
    exit 0
  fi
fi

# PROJECT_DIR: 기본은 스크립트 상위(=button/agent). 다른 프로젝트에서 호출 시
# PROJECT_DIR_OVERRIDE 환경변수로 덮어쓸 수 있다. (.harness/, .wf-active, cd 대상 경로 모두 영향)
# ruler 세션은 예외: cwd=~/.claude, .harness/ 경로 우회
if [ "$SESSION" = "ruler" ]; then
  PROJECT_DIR="/c/Users/jsh86/.claude"
elif [ -n "${PROJECT_DIR_OVERRIDE:-}" ]; then
  PROJECT_DIR="$(cd "$PROJECT_DIR_OVERRIDE" && pwd)"
else
  PROJECT_DIR="$(cd "$(dirname "$SECRETARY_DIR")" && pwd)"
fi
PROJECT_NAME="$(basename "$PROJECT_DIR")"
WIN_PROJECT_DIR=$(echo "$PROJECT_DIR" | sed 's|^/\([a-z]\)/|\1:/|; s|/|\\\\|g')
WIN_PROJECT_DIR_SLASH=$(echo "$PROJECT_DIR" | sed 's|^/\([a-z]\)/|\1:/|')

# role 파일 (Supervisor가 작성하는 태스크 전용 파일)
if [ -n "$ROLE_ARG" ]; then
  ROLE_FILE="$ROLE_ARG"
else
  ROLE_FILE="$PROJECT_DIR/.harness/${SESSION}-role.md"
fi

# ── 프로토콜 파일 (고정, skills/ 보관) ──
CLAUDE_DIR="/c/Users/jsh86/.claude"
WF_ACTIVE="$PROJECT_DIR/.wf-active"

# WF 타입 감지 (.wf-active → {"type":"lightweight"} 또는 {"type":"harness"})
WF_TYPE="harness"
if [ -f "$WF_ACTIVE" ]; then
  if command -v jq &>/dev/null; then
    WF_TYPE=$(jq -r '.type // "harness"' "$WF_ACTIVE" 2>/dev/null)
  else
    WF_TYPE=$(grep -o '"type"[[:space:]]*:[[:space:]]*"[^"]*"' "$WF_ACTIVE" | sed 's/.*"type"[[:space:]]*:[[:space:]]*"//;s/"$//')
    [ -z "$WF_TYPE" ] && WF_TYPE="harness"
  fi
fi

# 프로토콜 파일 매핑 (역할별, WF 타입별)
case "$SESSION" in
  worker)    PROTOCOL_FILE="$CLAUDE_DIR/skills/${WF_TYPE}-wf/protocols/worker.md";;
  verifier)  PROTOCOL_FILE="$CLAUDE_DIR/skills/harness-wf/protocols/verifier.md";;
  healer)    PROTOCOL_FILE="$CLAUDE_DIR/skills/harness-wf/protocols/healer.md";;
  strategic) PROTOCOL_FILE="$CLAUDE_DIR/skills/harness-wf/protocols/sr.md";;
  *)         PROTOCOL_FILE="";;
esac

# ACK 파일 (공유, 병렬 안전 — append는 atomic)
HARNESS_DIR="$PROJECT_DIR/.harness"
mkdir -p "$HARNESS_DIR"
ACK_FILE="$HARNESS_DIR/acks.txt"

# ── Supervisor 세션명 ──
SUPERVISOR_SESSION=$("$PSMUX" display-message -p '#S' 2>/dev/null || echo "")
if [ -z "$SUPERVISOR_SESSION" ]; then
  # psmux 밖에서 실행 시 fallback
  SUPERVISOR_SESSION="main"
fi

# ── 모델 + wt.exe 배치 ──
# THINK: 24K 는 판단 밀도 높은 세션(debate, SR, ruler)만. 나머지는 settings.json 전역 16K 사용.
case "$SESSION" in
  strategic|debate|judge|ruler) MODEL="opus"; THINK="24000";;
  *) MODEL="sonnet"; THINK="";;
esac

case "$SESSION" in
  worker)    POS="0,0";      SIZE="130,40"; STAGGER=0;;
  verifier)  POS="1280,0";   SIZE="130,40"; STAGGER=1;;
  healer)    POS="0,720";    SIZE="130,40"; STAGGER=2;;
  strategic) POS="1280,720"; SIZE="130,40"; STAGGER=3;;
  debate)    POS="0,0";      SIZE="160,45"; STAGGER=0;;
  judge)     POS="1280,0";   SIZE="160,45"; STAGGER=1;;
  ruler)     POS="320,180";  SIZE="140,45"; STAGGER=0;;
  *)         POS="640,360";  SIZE="130,40"; STAGGER=4;;
esac

TITLE="${SESSION} (${MODEL})"

# ── system-prompt (역할별, common.md 스펙) ──
case "$SESSION" in
  worker)
    SYSTEM_PROMPT="Harness Worker. sessions: worker/${SUPERVISOR_SESSION}/verifier/healer/strategic. Korean. 컨텍스트 압축 시 execution-log.md Read하여 현재 Phase + 마지막 Sub-obj 복원."
    ;;
  verifier)
    SYSTEM_PROMPT="Harness Verifier. sessions: verifier/${SUPERVISOR_SESSION}/worker/healer/strategic. Korean. 컨텍스트 압축 시 execution-log.md Read하여 현재 Phase + 마지막 검증 상태 복원. FAIL 판정 시 ~/.claude/memory/promotion-log.md에 ERROR 기록 필수(상황/원인/해결/방지책 각 20자+)."
    ;;
  healer)
    SYSTEM_PROMPT="Harness Healer. sessions: healer/${SUPERVISOR_SESSION}/verifier/worker. Korean. 컨텍스트 압축 시 execution-log.md Read하여 수정 대기 중인 FAIL Sub-obj 복원."
    ;;
  strategic)
    SYSTEM_PROMPT="Harness Strategic Reviewer. sessions: strategic/${SUPERVISOR_SESSION}. Korean. 컨텍스트 압축 시 execution-log.md Read하여 현재 Phase + 마지막 리뷰 상태 복원. 리서치 결과는 반드시 ~/.claude/docs/archive/research-raw/${PROJECT_NAME}-sr-$(date +%Y-%m-%d).txt에 원본 저장 후 핵심만 지시서에 포함."
    ;;
  ruler)
    SYSTEM_PROMPT="Ruler — 규칙/문서/비서코드 메타 감시 레이어. Korean. cwd=~/.claude. 장수명 세션. 매 사이클 ~/.claude/.ruler/patrol.md + ~/.claude/.ruler/state.md Read하여 13 체크리스트 전수 실행. T1 즉시/T2 24h/T3 pending 자동수정 Gate 엄수. 압축 시 state.md 우선 복원. 상세 규칙: ~/.claude/skills/ruler-wf/skill.md Read."
    ;;
  *)
    SYSTEM_PROMPT="Harness Agent (${SESSION}). sessions: ${SESSION}/${SUPERVISOR_SESSION}. Korean."
    ;;
esac

echo "[spawn:${SESSION}] Session: ${SESSION} | Model: ${MODEL} | Supervisor: ${SUPERVISOR_SESSION}"

# ── 1. 기존 동명 세션 정리 + 생성 ──
if "$PSMUX" has-session -t "$SESSION" 2>/dev/null; then
  echo "[spawn:${SESSION}] Killing existing session"
  "$PSMUX" kill-session -t "$SESSION"
fi

"$PSMUX" new-session -d -s "$SESSION" -x 200 -y 50
if [ $? -ne 0 ]; then
  echo "[spawn:${SESSION}] ERROR: session creation failed" >&2
  exit 1
fi
echo "[spawn:${SESSION}] Session created"

# ── 2. wt.exe 창 (stagger로 병렬 충돌 방지) ──
# wt.exe 는 PATH 에서 'psmux' 를 못 찾으면 0x80070002 (파일 없음) 로 죽는다
# (WinGet 패키지 경로는 PATH 에 없음). 반드시 절대경로 전달.
PSMUX_WIN=$(cygpath -w "$PSMUX" 2>/dev/null || echo "$PSMUX")
sleep "$STAGGER"
powershell.exe -WindowStyle Hidden -Command "Start-Process wt.exe -ArgumentList '--pos','${POS}','--size','${SIZE}','--title','\"${TITLE}\"','${PSMUX_WIN}','attach-session','-t','${SESSION}'" &
sleep 1

# ── 3. cd + Claude 스폰 (system-prompt 포함) ──
# THINK 가 비어있지 않으면 MAX_THINKING_TOKENS override 주입 (Opus 판단 세션 전용 24K)
THINK_ENV=""
if [ -n "$THINK" ]; then
  THINK_ENV="set MAX_THINKING_TOKENS=${THINK} && "
fi
# psmux-raw-ok: bootstrap (cmd.exe pane before Claude launches)
"$PSMUX" send-keys -t "$SESSION" "cd /d ${WIN_PROJECT_DIR}" Enter
# psmux-raw-ok: bootstrap (cmd.exe pane — claude launch command)
"$PSMUX" send-keys -t "$SESSION" "set PSMUX_SESSION=${SESSION} && ${THINK_ENV}claude --dangerously-skip-permissions --model ${MODEL} --system-prompt \"${SYSTEM_PROMPT}\"" Enter

echo "[spawn:${SESSION}] Claude spawning..."

# ── 4. Trust Folder prompt + bypasspermission 통합 폴링 (최대 150초) ──
# 신규 프로젝트 디렉토리에서는 Claude 시작 시 Trust Folder 프롬프트가 먼저 뜨고,
# 선택 후에야 bypass 안내가 나온다. 이미 trust 된 폴더는 바로 bypass로 넘어감.
# 4a/4b 분리 구조는 (1) trust 폴링 타임아웃이 너무 짧으면 trust를 놓치고
# (2) 이어지는 bypass 폴링이 실패한 뒤 handshake 텍스트가 raw pane에 들어가
# trust 메뉴 기본값("No, exit")을 Enter로 선택해버려 Claude 가 종료되는 실패 사슬을 만든다.
# → 단일 루프에서 매 사이클마다 bypass OR trust를 확인하고, trust는 1회만 처리.
READY=false
TRUST_HANDLED=false
for i in $(seq 1 75); do
  sleep 2
  PANE=$("$PSMUX" capture-pane -t "$SESSION" -p -S 0 2>/dev/null)
  # capture-pane 은 터미널 렌더링 셀을 그대로 뽑기 때문에 공백이 사라진 형태로 나올 수
  # 있다 (e.g. "Isthisaprojectyoucreated"). 모든 공백을 제거한 사본을 따로 만들어
  # 두 버전에서 모두 grep 해 안정적으로 감지한다.
  PANE_NS=$(echo "$PANE" | tr -d ' ')

  # bypass 안내가 떴으면 Claude 가 준비된 것 → 루프 종료
  if echo "$PANE_NS" | grep -qi "bypass"; then
    READY=true
    echo "[spawn:${SESSION}] Claude ready after $((i*2))s"
    break
  fi

  # Trust prompt 가 떴고 아직 처리 안 했으면 처리
  if [ "$TRUST_HANDLED" = false ] && echo "$PANE_NS" | grep -qi "trustthisfolder"; then
    # 커서 마커(❯)가 있는 줄에 Yes/No 판별. 없으면 Yes 줄(보통 첫 번째)로 Up fallback.
    # capture-pane 공백 제거 이슈 때문에 PANE_NS 로 grep 한다 ("Yes,Itrust" / "No,exit").
    CURSOR_LINE=$(echo "$PANE_NS" | grep "❯" | head -1)
    if echo "$CURSOR_LINE" | grep -qi "yes"; then
      psmux_send_key "$SESSION" Enter
      echo "[spawn:${SESSION}] Trust folder: cursor on Yes → Enter"
    elif echo "$CURSOR_LINE" | grep -qi "no"; then
      # Yes 줄이 No 줄보다 위/아래 어디에 있는지 계산 → Up/Down 결정
      YES_LINE=$(echo "$PANE_NS" | grep -in "yes,itrust\|yes.*trust" | head -1 | cut -d: -f1)
      NO_LINE=$(echo "$PANE_NS" | grep -in "no,exit\|no.*exit" | head -1 | cut -d: -f1)
      if [ -n "$YES_LINE" ] && [ -n "$NO_LINE" ] && [ "$YES_LINE" -lt "$NO_LINE" ]; then
        psmux_send_key "$SESSION" Up
      else
        psmux_send_key "$SESSION" Down
      fi
      sleep 1
      psmux_send_key "$SESSION" Enter
      echo "[spawn:${SESSION}] Trust folder: cursor on No → moved → Enter"
    else
      # 커서 마커 감지 실패 — 첫 줄이 Yes 인 것이 일반적이므로 Up+Enter
      psmux_send_key "$SESSION" Up
      sleep 1
      psmux_send_key "$SESSION" Enter
      echo "[spawn:${SESSION}] Trust folder: cursor not detected → Up+Enter fallback"
    fi
    TRUST_HANDLED=true
    # trust 수락 후 bypass 준비까지 약간 더 기다리기 위해 sleep 추가
    sleep 2
  fi
done

if [ "$READY" = false ]; then
  echo "[spawn:${SESSION}] WARNING: bypasspermission not detected after 150s" >&2
fi

sleep 2

# ── 6. 핸드셰이크 전송 ──
echo "[spawn:${SESSION}] Sending handshake..."
psmux_send_message "$SESSION" "HANDSHAKE: Bash 도구로 다음 명령 실행: echo '${SESSION}_ACK' >> ${WIN_PROJECT_DIR_SLASH}/.harness/acks.txt"

# ── 7. ACK 폴링 (최대 60초) ──
ACK_OK=false
for i in $(seq 1 12); do
  sleep 5
  if grep -q "${SESSION}_ACK" "$ACK_FILE" 2>/dev/null; then
    ACK_OK=true
    echo "[spawn:${SESSION}] ACK received after $((i*5))s"
    break
  fi
done

if [ "$ACK_OK" = false ]; then
  echo "[spawn:${SESSION}] WARNING: ACK not received after 60s — retry once" >&2
  # 재시도 1회
  psmux_send_message "$SESSION" "HANDSHAKE 재시도: Bash 도구로 실행: echo '${SESSION}_ACK' >> ${WIN_PROJECT_DIR_SLASH}/.harness/acks.txt"
  for i in $(seq 1 6); do
    sleep 5
    if grep -q "${SESSION}_ACK" "$ACK_FILE" 2>/dev/null; then
      ACK_OK=true
      echo "[spawn:${SESSION}] ACK received on retry"
      break
    fi
  done
fi

if [ "$ACK_OK" = false ]; then
  echo "[spawn:${SESSION}] ERROR: ACK failed — manual intervention needed" >&2
  exit 2
fi

# ── 8. 프로토콜 + 태스크 조립 → 역할 주입 ──
ASSEMBLED_FILE="$HARNESS_DIR/${SESSION}-assembled.md"
INJECT_FILE=""

if [ -n "$PROTOCOL_FILE" ] && [ -f "$PROTOCOL_FILE" ]; then
  # 프로토콜 복사 + {SUPERVISOR_SESSION} 치환
  sed "s/{SUPERVISOR_SESSION}/$SUPERVISOR_SESSION/g" "$PROTOCOL_FILE" > "$ASSEMBLED_FILE"

  # 태스크 파일 있으면 append
  if [ -f "$ROLE_FILE" ]; then
    {
      echo ""
      echo "---"
      echo ""
      echo "# Task (Supervisor 지시)"
      echo ""
      cat "$ROLE_FILE"
    } >> "$ASSEMBLED_FILE"
    echo "[spawn:${SESSION}] Assembled: protocol(${WF_TYPE}) + task(${ROLE_FILE})"
  else
    echo "[spawn:${SESSION}] Assembled: protocol only (no task file)"
  fi
  INJECT_FILE="$ASSEMBLED_FILE"
elif [ -f "$ROLE_FILE" ]; then
  # 프로토콜 없으면 기존 방식 (role 파일만)
  INJECT_FILE="$ROLE_FILE"
  echo "[spawn:${SESSION}] Legacy mode: role file only (no protocol)"
fi

if [ -n "$INJECT_FILE" ] && [ -f "$INJECT_FILE" ]; then
  sleep 2
  psmux_send_message "$SESSION" "Read ${INJECT_FILE} and follow all instructions inside. This is your role assignment."
  echo "[spawn:${SESSION}] Role injected: ${INJECT_FILE}"
else
  echo "[spawn:${SESSION}] No role/protocol file — skipping"
fi

# ── 9. Ruler 세션 특수 처리 (post-ACK) ──
#   (a) secretary 레지스트리 등록 (compression/resume 리줌 주입 대상)
#   (b) patrol manifest + state.md 초기 Read 지시 주입
#   (c) wake.sh 백그라운드 구동
if [ "$SESSION" = "ruler" ]; then
  # (a) 레지스트리 등록
  REGISTRY="$SECRETARY_DIR/.session-registry.txt"
  if [ -f "$REGISTRY" ]; then
    # 기존 ruler 행 제거 후 재등록
    grep -v "^ruler|" "$REGISTRY" > "${REGISTRY}.tmp" && mv "${REGISTRY}.tmp" "$REGISTRY"
    TS=$(date -u +%Y-%m-%dT%H:%M:%S+09:00)
    echo "ruler|opus|C:\\Users\\jsh86\\.claude|${TS}|" >> "$REGISTRY"
    echo "[spawn:ruler] Added to secretary registry"
  fi

  # (b) pane 입력 버퍼 클리어 — 이전 핸드셰이크/ACK 이후 남은 입력 잔여물 제거
  # (이 단계 없으면 send-keys 로 넣는 텍스트가 기존 프롬프트 입력에 append 되어 꼬인다)
  sleep 2
  psmux_send_key "$SESSION" Escape
  sleep 1

  # (b-2) /remote-control 먼저 — Claude Code UI 를 Remote Control active 로 전환.
  # SSOT 헬퍼가 내부에서 MSYS_NO_PATHCONV=1 설정 → slash 경로변환 이슈 없음 (promotion-log K73).
  # INIT_MSG 보다 먼저 보내서 Claude Code UI 가 remote-control 상태로 전환된 뒤 초기화 지시가 흘러들어가도록 순서 고정.
  # WF 세션 (worker/verifier/healer/strategic) 은 의도적으로 이 블록을 타지 않는다 —
  # Supervisor 가 harness 컨텍스트를 전담하므로 remote control 등록 불필요.
  psmux_send_slash "$SESSION" '/remote-control'
  echo "[spawn:ruler] /remote-control sent (Remote Control active)"
  sleep 4

  # (b-3) 초기 역할 + 즉시 1 cycle 실행 지시
  INIT_MSG="[ruler-init] Ruler 세션 기동. 즉시 아래 순서로 실행:
1. Read ~/.claude/skills/ruler-wf/skill.md — 전체 역할 정의
2. Read ~/.claude/.ruler/patrol.md — 13 체크리스트 SSOT
3. Read ~/.claude/.ruler/state.md — 영속 상태
4. 즉시 1 사이클 실행 — 13 체크리스트 전수 순회하여 cycle=1 로 초기화
5. state.md 갱신 (cycle=1, updated=now, 이번 사이클 결과 요약, Active WF Contexts=비어있음, Open Issues 정리)
6. log/\$(date +%Y-%m-%d).md 에 초기 사이클 기록 append
7. 초기화 완료 후 대기 — .active 플래그가 없으면 wake.sh 가 패트롤 메시지를 보내지 않는다 (idle 모드). WF skill 이 .active 를 생성할 때까지 메시지 수신 없이 대기."
  psmux_send_message "$SESSION" "$INIT_MSG"

  # (c) wake.sh 백그라운드 구동 (disown 으로 부모 독립)
  if [ -x "/c/Users/jsh86/.claude/.ruler/wake.sh" ]; then
    nohup bash "/c/Users/jsh86/.claude/.ruler/wake.sh" > "/c/Users/jsh86/.claude/.ruler/log/wake-stdout.log" 2>&1 &
    disown 2>/dev/null || true
    echo "[spawn:ruler] wake.sh started (3min Self-Wake loop)"
  else
    echo "[spawn:ruler] WARNING: wake.sh not found or not executable" >&2
  fi
fi

echo "[spawn:${SESSION}] DONE (session=${SESSION}, model=${MODEL}, wf=${WF_TYPE}, ack=OK)"
