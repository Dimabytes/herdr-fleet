#!/usr/bin/env python3
# usage: [R=<run dir>] session.py        prints `export HERDR_*=...` for the orchestrator's own herdr pane
# Inherited HERDR_* can point to another herdr session (several sessions open; a background job started from another pane).
# The orchestrator pane is the agent pane whose cwd is $PWD or its nearest parent. The inherited pane wins if it matches;
# otherwise every running session is searched. No match or a tie: exit 1 with the candidates.
# With R set, the result is pinned in $R/herdr.env and every fleet script loads it, so the whole run stays in one session.
# To pick a pane by hand, write that file yourself (same export line).
import json, os, subprocess, sys

R = os.environ.get("R")
pin = R and os.path.join(R, "herdr.env")
if pin and os.path.exists(pin):
    print(open(pin).read().strip()); sys.exit()
pwd, home = os.environ.get("PWD") or os.getcwd(), os.path.expanduser("~")

def depth(p):  # length of the pane cwd if it is $PWD or a parent of it, else None
    c = (p.get("foreground_cwd") or p.get("cwd") or "").rstrip("/")
    return len(c) if p.get("agent") and c not in ("", home) and (pwd == c or pwd.startswith(c + "/")) else None

def panes(sock):
    out = subprocess.check_output(["herdr", "pane", "list"], env=dict(os.environ, HERDR_SOCKET_PATH=sock))
    return json.loads(out)["result"]["panes"]

def emit(sock, p):
    line = (f"export HERDR_SOCKET_PATH={sock} HERDR_WORKSPACE_ID={p['workspace_id']} "
            f"HERDR_TAB_ID={p['tab_id']} HERDR_PANE_ID={p['pane_id']}")
    if pin:
        os.makedirs(R, exist_ok=True)
        open(pin, "w").write(line + "\n")
    print(line); sys.exit()

sessions = {s["socket_path"]: s["name"] for s in json.loads(subprocess.check_output(["herdr", "session", "list", "--json"]))["sessions"] if s["running"]}
sock, pid = os.environ.get("HERDR_SOCKET_PATH"), os.environ.get("HERDR_PANE_ID")
if sock in sessions:
    me = next((p for p in panes(sock) if p["pane_id"] == pid), None)
    if me and depth(me) is not None: emit(sock, me)
    print(f"inherited HERDR_PANE_ID={pid} (session {sessions[sock]}) is not this agent: its cwd is {me and me.get('cwd')}, PWD is {pwd}", file=sys.stderr)
found = [(depth(p), s, p) for s in sessions for p in panes(s) if depth(p) is not None]
best = [f for f in found if f[0] == max(f[0] for f in found)] if found else []
if len(best) == 1: emit(*best[0][1:])
for _, s, p in found: print(f"  candidate: session {sessions[s]} pane {p['pane_id']} {p['agent']} {p.get('cwd')}", file=sys.stderr)
sys.exit(f"no single herdr pane for this agent ({'tie' if best else 'none'}); write {pin or '$R/herdr.env'} by hand")
