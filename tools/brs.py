#!/usr/bin/env python3
"""
roku-debloat/brs.py — BrightScript debugger driver for tcp/8085.

A crashing sideloaded channel drops into "BrightScript Micro Debugger", which
evaluates arbitrary BrightScript statements. The session is per-crash and
transient: if the only connection closes, the app resumes and exits with
EXIT_BRIGHTSCRIPT_CRASH, so everything must be driven in ONE live session.

    ./brs.py --launch < statements.txt     # relaunch app, then drive it
    ./brs.py < statements.txt              # attach to an already-paused app
"""
import argparse
import os
import socket
import sys
import time
import urllib.request

IP = os.environ.get("ROKU_IP", "TARGET_IP")
PORT = int(os.environ.get("ROKU_BRS_PORT", "8085"))
PROMPT = "Brightscript Debugger>"


def launch():
    req = urllib.request.Request(f"http://{IP}:8060/launch/dev", method="POST")
    try:
        urllib.request.urlopen(req, timeout=5)
        print("[launched RSPROBE]", file=sys.stderr)
    except Exception as exc:  # noqa: BLE001
        print(f"[launch failed: {exc}]", file=sys.stderr)


def connect(wait_for_prompt=15.0):
    """Connect and block until the debugger banner+p Prompt shows up."""
    s = socket.create_connection((IP, PORT), timeout=10)
    s.settimeout(2.0)
    buf = ""
    deadline = time.time() + wait_for_prompt
    while time.time() < deadline:
        try:
            chunk = s.recv(4096)
        except socket.timeout:
            continue
        if not chunk:
            break
        buf += chunk.decode("latin-1")
        if PROMPT in buf:
            return s, buf
    s.close()
    return None, buf


def read_to_prompt(sock, deadline_s=8.0):
    buf = ""
    deadline = time.time() + deadline_s
    while time.time() < deadline:
        try:
            chunk = sock.recv(4096)
        except socket.timeout:
            continue
        if not chunk:
            break
        buf += chunk.decode("latin-1")
        if PROMPT in buf:
            return buf
    return buf


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--launch", action="store_true")
    ap.add_argument("--delay", type=float, default=2.5,
                    help="seconds between launch and attach")
    args = ap.parse_args()

    cmds = [ln.rstrip("\n") for ln in sys.stdin
            if ln.strip() and not ln.lstrip().startswith("#")]
    if not cmds:
        print("no statements on stdin", file=sys.stderr)
        return 1

    if args.launch:
        launch()
        time.sleep(args.delay)

    sock, banner = connect()
    if sock is None:
        print(f"[no debugger prompt. banner tail:]\n{banner[-500:]}", file=sys.stderr)
        return 2

    # The console replays buffered output from earlier sessions, so responses
    # arrive shifted. Fire N numbered sentinels and consume everything up to the
    # LAST one; after that the stream is aligned with our commands.
    N = 8
    for i in range(1, N + 1):
        sock.sendall(f'? "#SYNC{i}"\n'.encode())
        time.sleep(0.05)
    tail = ""
    deadline = time.time() + 20
    while f"#SYNC{N}" not in tail and time.time() < deadline:
        try:
            chunk = sock.recv(4096)
        except socket.timeout:
            continue
        if not chunk:
            break
        tail += chunk.decode("latin-1")
    tail = read_to_prompt(sock).replace("\r", "")
    if f"#SYNC{N}" not in tail:
        print(f"[sync unreliable, last bytes: {tail[-200:]!r}]", file=sys.stderr)

    for cmd in cmds:
        sock.sendall(cmd.encode() + b"\n")
        raw = read_to_prompt(sock).replace("\r", "")
        resp = raw.rsplit(PROMPT, 1)[0].strip("\n").strip()
        print(f"### {cmd}")
        print(resp if resp else "<no output>")
        print()
        if "EXIT_BRIGHTSCRIPT_CRASH" in raw or not raw:
            print("[session appears dead — stopping]", file=sys.stderr)
            break
    sock.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
