#!/usr/bin/env python3
# usage: [R=<run dir>] grid.py <tab-label> [--new]
# Re-tiles every pane of tab <tab-label> in $HERDR_WORKSPACE_ID into an even grid: max 3 per row, oldest pane first.
# --new first adds an empty shell pane (creates the tab in $R if it is missing) and prints its id for launch.sh.
# herdr has no re-tile command: panes are parked in a temp tab and moved back. Agents keep running.
import fcntl, json, math, os, subprocess, sys, tempfile

label, new = sys.argv[1], "--new" in sys.argv[2:]
ws, cwd = os.environ["HERDR_WORKSPACE_ID"], os.environ.get("R", os.getcwd())
lock = open(os.path.join(tempfile.gettempdir(), f"herdr-fleet-grid-{ws}-{label}.lock"), "w")
fcntl.flock(lock, fcntl.LOCK_EX)  # several watchers may close panes at once
h = lambda *a: json.loads(subprocess.check_output(["herdr", *a]))["result"]

tab = next((t["tab_id"] for t in h("tab", "list")["tabs"] if t.get("workspace_id") == ws and t.get("label") == label), None)
if tab is None:
    if new:
        print(h("tab", "create", "--workspace", ws, "--label", label, "--cwd", cwd, "--no-focus")["root_pane"]["pane_id"])
    sys.exit()
mine = [p for p in h("pane", "list")["panes"] if p.get("tab_id") == tab]
first = mine[0]["pane_id"]
if new:
    if len(mine) >= 10: sys.exit(f"tab {label} already has 10 panes: use another tab label")
    print(h("pane", "split", first, "--direction", "down", "--cwd", cwd, "--no-focus")["pane"]["pane_id"])
    mine = [p for p in h("pane", "list")["panes"] if p.get("tab_id") == tab]
ids = [p["pane_id"] for p in sorted(mine, key=lambda p: p["terminal_id"])]  # terminal ids grow with creation time
rows = math.ceil(len(ids) / 3)
grid, i = [], 0
for r in range(rows):
    n = len(ids) // rows + (r < len(ids) % rows)
    grid.append(ids[i:i + n]); i += n

if len(ids) > 1:  # ids[0] stays and fills the tab; the rest go back around it
    tmp = h("pane", "move", ids[1], "--new-tab", "--label", "grid-tmp", "--no-focus")["move_result"]["created_tab"]["tab_id"]
    for p in ids[2:]:
        h("pane", "move", p, "--tab", tmp, "--split", "right", "--target-pane", ids[1], "--no-focus")
put = lambda p, t, d, q: h("pane", "move", p, "--tab", tab, "--target-pane", t, "--split", d, "--ratio", str(q), "--no-focus")
for r in range(1, rows):  # --ratio is the share the target keeps: equal heights
    put(grid[r][0], grid[r - 1][0], "down", 1 / (rows - r + 1))
for row in grid:  # then equal widths inside each row
    for c in range(1, len(row)):
        put(row[c], row[c - 1], "right", 1 / (len(row) - c + 1))
