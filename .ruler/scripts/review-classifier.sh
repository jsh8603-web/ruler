#!/usr/bin/env bash
# review-classifier.sh — Phase 3 dry-run classifier self-learning
# SSOT: D:/projects/button/plan.md §Step 9
#
# Scans classifier-audit jsonl, groups unknown:* prefixes, proposes regex additions.
# Dry-run by default: writes decisions.jsonl outcome="dry-run", NEVER edits secretary.js.
# Live gate: CLASSIFIER_LIVE=1 env OR (phase2 commit + agent uptime 7d + audit 200 entries).
#
# Exit codes:
#   0 = success (dry-run or live)
#   1 = bash/env error
#   2 = cooldown active (24h)
#   3 = no audit data

set -uo pipefail

RULER_DIR="$HOME/.claude/.ruler"
DECISIONS="$RULER_DIR/decisions.jsonl"
COOLDOWN_FILE="$RULER_DIR/.last-classifier-review"
AUDIT_DIR="D:/projects/button/agent/.secretary/.classifier-audit"
SECRETARY_JS="D:/projects/button/agent/secretary.js"

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
CHECK="C14"
TIER="T0"

# ── 1. 24h cooldown check ─────────────────────────────────────────
if [[ -f "$COOLDOWN_FILE" ]]; then
  now=$(date +%s)
  last=$(stat -c %Y "$COOLDOWN_FILE" 2>/dev/null || stat -f %m "$COOLDOWN_FILE" 2>/dev/null || echo 0)
  age=$(( now - last ))
  if (( age < 86400 )); then
    echo "[review-classifier] cooldown active: ${age}s / 86400s — skip"
    exit 2
  fi
fi

# ── 2. Live gate self-check ───────────────────────────────────────
live_mode=0
if [[ "${CLASSIFIER_LIVE:-0}" == "1" ]]; then
  live_mode=1
  gate_reason="env CLASSIFIER_LIVE=1"
else
  phase2_commit=""
  if [[ -d D:/projects/button/.git ]]; then
    phase2_commit=$(git -C D:/projects/button log --oneline --grep="phase 2 error-detect-loop" -1 2>/dev/null || true)
  fi
  audit_total=0
  if [[ -d "$AUDIT_DIR" ]]; then
    audit_total=$(cat "$AUDIT_DIR"/classifier-*.jsonl 2>/dev/null | wc -l)
  fi
  agent_uptime_days=0
  if [[ -f D:/projects/button/agent/.secretary/.session-registry.txt ]]; then
    reg_age=$(( ( $(date +%s) - $(stat -c %Y D:/projects/button/agent/.secretary/.session-registry.txt 2>/dev/null || echo 0) ) / 86400 ))
    agent_uptime_days=$reg_age
  fi
  if [[ -n "$phase2_commit" ]] && (( agent_uptime_days >= 7 )) && (( audit_total >= 200 )); then
    live_mode=1
    gate_reason="self-check: phase2+uptime=${agent_uptime_days}d+audit=${audit_total}"
  else
    gate_reason="dry-run (phase2=${phase2_commit:+yes}${phase2_commit:-no}, uptime=${agent_uptime_days}d, audit=${audit_total})"
  fi
fi

# ── 3. Scan audit for unknown:* clusters ──────────────────────────
if [[ ! -d "$AUDIT_DIR" ]]; then
  echo "[review-classifier] no audit dir: $AUDIT_DIR"
  exit 3
fi

TMP_UNK=$(mktemp)
trap 'rm -f "$TMP_UNK"' EXIT

# Extract unknown:* categories with timestamps
"/c/Program Files/nodejs/node.exe" -e '
const fs=require("fs"),path=require("path");
const dir=process.argv[1];
const files=fs.readdirSync(dir).filter(f=>f.startsWith("classifier-")&&f.endsWith(".jsonl"));
const groups={};
for(const f of files){
  const lines=fs.readFileSync(path.join(dir,f),"utf8").split("\n");
  for(const ln of lines){
    if(!ln.trim())continue;
    try{
      const d=JSON.parse(ln);
      if(d.matched===false && d.category && d.category.startsWith("unknown:")){
        const prefix=d.category.slice(8).split(/\s+/).slice(0,3).join(" ").toLowerCase().replace(/[^a-z0-9 :<>_-]/g,"");
        if(!prefix)continue;
        if(!groups[prefix])groups[prefix]={count:0,ts:[],sample:""};
        groups[prefix].count++;
        groups[prefix].ts.push(d.ts||"");
        if(!groups[prefix].sample)groups[prefix].sample=(d.raw||"").slice(0,80);
      }
    }catch(e){}
  }
}
for(const [prefix,g] of Object.entries(groups)){
  const days=new Set(g.ts.map(t=>t.slice(0,10))).size;
  if(g.count>=5 && days>=2){
    console.log(JSON.stringify({prefix,count:g.count,days,sample:g.sample}));
  }
}
' "$AUDIT_DIR" > "$TMP_UNK" 2>/dev/null || true

proposal_count=$(wc -l < "$TMP_UNK")

echo "[review-classifier] mode=$([[ $live_mode -eq 1 ]] && echo live || echo dry-run) gate=\"$gate_reason\" proposals=$proposal_count"

# ── 4. Emit proposals ─────────────────────────────────────────────
if (( proposal_count > 0 )); then
  while IFS= read -r line; do
    prefix=$(echo "$line" | "/c/Program Files/nodejs/node.exe" -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{const j=JSON.parse(d);console.log(j.prefix)})')
    count=$(echo "$line" | "/c/Program Files/nodejs/node.exe" -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{const j=JSON.parse(d);console.log(j.count)})')
    days=$(echo "$line" | "/c/Program Files/nodejs/node.exe" -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{const j=JSON.parse(d);console.log(j.days)})')
    category=$(echo "$prefix" | tr ' <>' '___' | head -c 30)
    regex="/$(echo "$prefix" | sed 's/[][\.*+?^$(){}|/]/\\&/g')/i"
    echo "[dry-run] 제안: ${category} ← ${regex} (근거: unknown:${prefix} 발생 ${count}회, ${days}일)"
  done < "$TMP_UNK"
fi

# ── 5. Append decisions.jsonl ─────────────────────────────────────
outcome="dry-run"
if (( live_mode == 1 )); then
  outcome="live-skipped-no-edit-yet"
fi
diff_hash="none"
if (( proposal_count > 0 )); then
  diff_hash=$("/c/Program Files/nodejs/node.exe" -e 'const c=require("crypto");let d="";process.stdin.on("data",x=>d+=x).on("end",()=>{console.log("sha256:"+c.createHash("sha256").update(d).digest("hex").slice(0,16))})' < "$TMP_UNK")
fi

entry=$("/c/Program Files/nodejs/node.exe" -e '
const [ts,check,tier,file,diff,outcome,gate,pcount]=process.argv.slice(1);
console.log(JSON.stringify({ts,cycle:0,check,tier,file,diff_hash:diff,backup:"none",regression:"n/a",outcome,gate,proposal_count:Number(pcount)}));
' "$TS" "$CHECK" "$TIER" "$SECRETARY_JS" "$diff_hash" "$outcome" "$gate_reason" "$proposal_count")

echo "$entry" >> "$DECISIONS"

# ── 6. Boundary assertion — secretary.js must NOT be touched ──────
if [[ $live_mode -eq 0 ]]; then
  echo "[review-classifier] boundary: secretary.js unchanged (dry-run)"
fi

# ── 7. Update cooldown timestamp ──────────────────────────────────
touch "$COOLDOWN_FILE"

echo "[review-classifier] done outcome=$outcome decisions_append=1"
exit 0
