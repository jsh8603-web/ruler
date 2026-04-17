#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Windows: "C:\Users\jsh86\AppData\Local\Programs\Python\Python312\python.exe" 로 직접 호출 권장
# (python3 = Windows Store stub 가능성 → pyyaml import 실패)
"""
event-patrol.py — event-rules.yaml loader

plan: ~/.claude/.ruler/batch-plans/202604151600-event-driven-patrol/plan.md
rules: ~/.claude/.ruler/event-rules.yaml
called-by: patrol.md §이벤트 패트롤
version: v0.2 (2026-04-16 ruler-batch-20260416T0122 Step 3)

v0.1 → v0.2 변경:
  - glob 지원 (D:/projects/*/.wf-active → pathlib.Path.glob)
  - 작은따옴표 spec 매칭 (type: 'auto_register' 패턴)
  - seen_offsets 영속화 (~/.claude/.ruler/state/event-cache/offsets.json)
  - registry.has_cwd() 래퍼 (.session-registry.txt 파싱)

목적: patrol.md 3분 루프 첫 단계가 본 스크립트를 호출해 event-rules.yaml 의
활성 이벤트를 iterate 하고, trigger.type 별로 cheap 한 pre-scan 을 돌려
"발화 후보" 를 stdout JSON 라인으로 출력한다. 실제 판정/통보는 하지 않는다.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.stderr.write("ERROR: pyyaml missing — pip install pyyaml\n")
    sys.exit(1)


# ─────────────────────────────────────────────────────────────
# 경로 헬퍼
# ─────────────────────────────────────────────────────────────

def expand(p: str) -> Path:
    if not p:
        return Path("")
    return Path(os.path.expanduser(p))


def log(event_id: str, msg: str) -> None:
    ts = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    sys.stderr.write(f"[{ts}] [{event_id}] {msg}\n")


def emit(result: dict) -> None:
    sys.stdout.write(json.dumps(result, ensure_ascii=False) + "\n")


# ─────────────────────────────────────────────────────────────
# seen_offsets 영속화 (v0.2)
# ─────────────────────────────────────────────────────────────

OFFSET_CACHE_DIR = expand("~/.claude/.ruler/state/event-cache")
OFFSET_CACHE_FILE = OFFSET_CACHE_DIR / "offsets.json"


def load_offsets() -> dict:
    try:
        with OFFSET_CACHE_FILE.open("r", encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_offsets(offsets: dict) -> None:
    OFFSET_CACHE_DIR.mkdir(parents=True, exist_ok=True)
    with OFFSET_CACHE_FILE.open("w", encoding="utf-8") as f:
        json.dump(offsets, f, indent=2)


# ─────────────────────────────────────────────────────────────
# registry 래퍼 (v0.2)
# ─────────────────────────────────────────────────────────────

REGISTRY_PATH = expand("D:/projects/button/agent/.secretary/.session-registry.txt")


def registry_entries() -> list[dict]:
    """Parse .session-registry.txt → list of {name, model, cwd, ...}"""
    entries = []
    try:
        with REGISTRY_PATH.open("r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split("|")
                if len(parts) >= 3:
                    entries.append({
                        "name": parts[0].strip(),
                        "model": parts[1].strip() if len(parts) > 1 else "",
                        "cwd": parts[2].strip() if len(parts) > 2 else "",
                    })
    except FileNotFoundError:
        pass
    return entries


def registry_has_cwd(cwd: str) -> bool:
    """Check if any session in registry has the given CWD."""
    cwd_norm = cwd.replace("\\", "/").rstrip("/").lower()
    for entry in registry_entries():
        entry_cwd = entry["cwd"].replace("\\", "/").rstrip("/").lower()
        if entry_cwd == cwd_norm:
            return True
    return False


def session_alive(name: str) -> bool:
    """Check if a session exists in registry."""
    return any(e["name"] == name for e in registry_entries())


# ─────────────────────────────────────────────────────────────
# log_event pre-scan (v0.2: 증분 offset + 작은따옴표)
# ─────────────────────────────────────────────────────────────

def extract_needle_type(spec_str: str) -> str | None:
    """
    spec 문자열에서 이벤트 타입 리터럴 추출.
    v0.1: "type":"xxx" 큰따옴표만
    v0.2: "type":"xxx" | 'type':'xxx' | type: 'xxx' | type: "xxx" 모두 지원
    """
    # 1) "type":"xxx" or "type": "xxx"
    m = re.search(r'"type"\s*:\s*"([a-zA-Z_]\w*)"', spec_str)
    if m:
        return m.group(1)
    # 2) 'type':'xxx' or 'type': 'xxx'
    m = re.search(r"'type'\s*:\s*'([a-zA-Z_]\w*)'", spec_str)
    if m:
        return m.group(1)
    # 3) type: 'xxx' or type: "xxx" (YAML-style, unquoted key)
    m = re.search(r'\btype\s*:\s*[\'"]([a-zA-Z_]\w*)[\'"]', spec_str)
    if m:
        return m.group(1)
    return None


def prescan_log_event(event_id: str, spec: dict, audit_log: Path,
                      window_sec: int, offsets: dict) -> dict:
    """
    v0.2: 증분 offset 으로 audit-log 읽기. 이전 위치부터만 스캔.
    """
    if not audit_log.exists():
        return {"event": event_id, "trigger_type": "log_event", "status": "no_audit_log",
                "detail": str(audit_log)}

    spec_str = spec.get("spec", "")
    needle_type = extract_needle_type(spec_str)
    if not needle_type:
        return {"event": event_id, "trigger_type": "log_event", "status": "spec_unparseable",
                "detail": "no type literal in spec"}

    log_key = str(audit_log)
    file_size = audit_log.stat().st_size
    last_offset = offsets.get(log_key, 0)

    # 파일이 줄었으면 (rotation/truncate) 처음부터
    if last_offset > file_size:
        last_offset = 0

    now = time.time()
    cutoff = now - window_sec
    hit_count = 0
    last_ts = None

    try:
        with audit_log.open("r", encoding="utf-8", errors="replace") as f:
            f.seek(last_offset)
            new_lines = f.readlines()
            new_offset = f.tell()

        for ln in new_lines:
            ln = ln.strip()
            if not ln:
                continue
            try:
                ev = json.loads(ln)
            except json.JSONDecodeError:
                continue
            if ev.get("type") != needle_type:
                continue
            ts = ev.get("ts") or ev.get("timestamp")
            ev_epoch = _parse_ts(ts)
            if ev_epoch is not None and ev_epoch < cutoff:
                continue  # window 밖
            hit_count += 1
            if last_ts is None:
                last_ts = ts

        # offset 갱신
        offsets[log_key] = new_offset

    except OSError as e:
        return {"event": event_id, "trigger_type": "log_event", "status": "io_error",
                "detail": str(e)}

    status = "candidate" if hit_count > 0 else "clean"
    return {
        "event": event_id,
        "trigger_type": "log_event",
        "status": status,
        "needle_type": needle_type,
        "window_sec": window_sec,
        "hit_count": hit_count,
        "last_ts": last_ts,
        "offset": {"prev": last_offset, "new": offsets.get(log_key, 0)},
    }


def _parse_ts(ts) -> float | None:
    if isinstance(ts, (int, float)):
        return float(ts)
    if isinstance(ts, str):
        try:
            import datetime as dt
            return dt.datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
        except Exception:
            return None
    return None


# ─────────────────────────────────────────────────────────────
# mtime_poll pre-scan (v0.2: glob + TTL)
# ─────────────────────────────────────────────────────────────

def prescan_mtime_poll(event_id: str, spec: dict) -> dict:
    """
    v0.2: glob 지원 + scope:session 시 registry 확인.
    """
    spec_str = spec.get("spec", "")

    # path 리터럴 추출 (큰따옴표 + 작은따옴표 모두)
    path_literals = re.findall(r'["\']([A-Za-z]:[/\\][^"\']+|~/[^"\']+)["\']', spec_str)
    if not path_literals:
        return {"event": event_id, "trigger_type": "mtime_poll", "status": "spec_unparseable",
                "detail": "no path literals in spec"}

    now = time.time()
    extant = []

    for p in path_literals:
        pp = expand(p)

        if "*" in p:
            # v0.2: glob 지원
            # 경로를 glob 패턴으로 분리 (부모 디렉토리 + 패턴)
            try:
                # "D:/projects/*/.wf-active" → parent="D:/projects", pattern="*/.wf-active"
                p_str = str(pp).replace("\\", "/")
                # glob 앵커: * 이전까지가 base
                parts = p_str.split("*", 1)
                base = Path(parts[0].rstrip("/"))
                pattern = "*" + parts[1] if len(parts) > 1 else "*"

                if base.exists():
                    matches = list(base.glob(pattern))
                    for match in matches:
                        try:
                            st = match.stat()
                            extant.append({
                                "path": str(match),
                                "status": "exists",
                                "size": st.st_size,
                                "mtime": st.st_mtime,
                                "age_sec": now - st.st_mtime,
                                "glob_source": p,
                            })
                        except OSError:
                            pass
                else:
                    extant.append({"path": p, "status": "glob_base_missing"})
            except Exception as e:
                extant.append({"path": p, "status": "glob_error", "detail": str(e)})
            continue

        try:
            st = pp.stat()
            entry = {
                "path": str(pp),
                "status": "exists",
                "size": st.st_size,
                "mtime": st.st_mtime,
                "age_sec": now - st.st_mtime,
            }

            # scope:session 감지 — 해당 디렉토리에 활성 세션이 있는지
            if "scope" in spec_str and "session" in spec_str:
                parent_dir = str(pp.parent).replace("\\", "/")
                entry["session_alive"] = registry_has_cwd(parent_dir)

            extant.append(entry)
        except FileNotFoundError:
            pass
        except OSError as e:
            extant.append({"path": str(pp), "status": "stat_error", "detail": str(e)})

    # prescan_max_age_sec: 이벤트 spec 에 설정된 경우 파일 나이 상한 적용
    # (예: memory_ckpt_format_error 는 MEMORY.md mtime < 30분인 경우만 candidate)
    max_age = spec.get("prescan_max_age_sec")
    if max_age is not None:
        status = "candidate" if any(
            e.get("status") == "exists" and e.get("age_sec", float("inf")) < max_age
            for e in extant
        ) else "clean"
    else:
        status = "candidate" if any(e.get("status") == "exists" for e in extant) else "clean"
    return {
        "event": event_id,
        "trigger_type": "mtime_poll",
        "status": status,
        "paths_checked": len(path_literals),
        "existing": extant,
    }


# ─────────────────────────────────────────────────────────────
# 메인 루프
# ─────────────────────────────────────────────────────────────

def run(rules_path: Path, audit_log: Path, window_sec: int) -> int:
    if not rules_path.exists():
        sys.stderr.write(f"ERROR: rules file missing: {rules_path}\n")
        return 1

    try:
        with rules_path.open("r", encoding="utf-8") as f:
            doc = yaml.safe_load(f)
    except yaml.YAMLError as e:
        sys.stderr.write(f"ERROR: YAML parse failed: {e}\n")
        return 1

    events = (doc or {}).get("events", {}) or {}
    if not events:
        sys.stderr.write("WARN: events section empty\n")
        return 0

    offsets = load_offsets()
    total = active = skipped = candidates = 0

    for event_id, ev in events.items():
        total += 1
        if not isinstance(ev, dict):
            log(event_id, "WARN: event body not dict — skip")
            skipped += 1
            continue

        if ev.get("enabled") is False or ev.get("pending_source_revive"):
            reason = (ev.get("pending_source_revive", {}).get("reason")
                      if ev.get("pending_source_revive") else "enabled:false")
            emit({"event": event_id, "status": "skipped", "reason": reason})
            log(event_id, f"SKIP: {reason}")
            skipped += 1
            continue

        trig = ev.get("trigger") or {}
        ttype = trig.get("type")

        if ttype == "log_event":
            result = prescan_log_event(event_id, trig, audit_log, window_sec, offsets)
        elif ttype == "mtime_poll":
            result = prescan_mtime_poll(event_id, trig)
        elif ttype == "heavy_scan":
            result = {"event": event_id, "trigger_type": "heavy_scan", "status": "deferred",
                      "detail": "heavy_scan is separate tier"}
            log(event_id, "DEFER: heavy_scan")
        else:
            result = {"event": event_id, "trigger_type": ttype or "unknown", "status": "skipped",
                      "reason": "unknown_trigger_type"}
            log(event_id, f"WARN: unknown trigger type: {ttype}")
            skipped += 1
            emit(result)
            continue

        if ev.get("supersedes_patrol"):
            result["supersedes_patrol"] = ev["supersedes_patrol"]
        result["severity"] = ev.get("severity")
        result["urgent"] = bool(ev.get("urgent", False))

        emit(result)
        active += 1
        if result.get("status") == "candidate":
            candidates += 1

    # offset 영속화
    save_offsets(offsets)

    log("summary", f"total={total} active={active} skipped={skipped} candidates={candidates}")
    return 0


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description="event-rules.yaml loader (v0.2)")
    p.add_argument("--rules", default="~/.claude/.ruler/event-rules.yaml")
    p.add_argument("--audit-log", default="~/.claude/audit-log/" + time.strftime("%Y-%m-%d") + ".jsonl")
    p.add_argument("--window-sec", type=int, default=60)
    args = p.parse_args(argv)

    return run(expand(args.rules), expand(args.audit_log), args.window_sec)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
