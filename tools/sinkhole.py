#!/usr/bin/env python3
"""
roku-debloat/sinkhole.py — dependency-free DNS sinkhole for Roku ad/telemetry suppression.

Two modes:

  blocklist (default)  — deny the named ad/telemetry domains, forward everything else.
                         Easy, but the TV can bypass it via its 8.8.8.8/8.8.4.4
                         fallback resolvers unless you block those at the firewall.

  allowlist            — deny EVERYTHING except the named domains. This is the
                         "only 云听小电视 gets the internet" mode. Much stronger,
                         and the reason to use it: a denied name answers 0.0.0.0
                         so the client fails fast instead of falling through to
                         another resolver.

    sudo ./sinkhole.py --port 53 --mode allowlist --allow blocklist/bilibili-allowlist.txt

Remember to also block the TV's outbound :53/:853 and DoH endpoints at the router,
otherwise it can simply ignore you.
"""
import argparse
import socket
import struct
import sys
import threading
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_BLOCK = HERE / "blocklist" / "roku-blocklist.txt"
DEFAULT_ALLOW = HERE / "blocklist" / "bilibili-allowlist.txt"


def load_list(path):
    names, wildcards = set(), []
    if not Path(path).is_file():
        return names, wildcards
    for raw in Path(path).read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip().lower().rstrip(".")
        if not line:
            continue
        if line.startswith("*."):
            wildcards.append(line[2:])
        else:
            names.add(line)
    return names, wildcards


def matches(qname, names, wildcards):
    if qname in names:
        return True
    return any(qname == w or qname.endswith("." + w) for w in wildcards)


def parse_qname(data):
    pos, labels = 12, []
    while pos < len(data):
        ln = data[pos]
        if ln == 0:
            return ".".join(labels).lower(), pos + 1
        if ln & 0xC0:
            return None, None
        pos += 1
        labels.append(data[pos:pos + ln].decode("latin-1"))
        pos += ln
    return None, None


def build_reply(query, qname_end, qtype, qclass, answers):
    tid = query[:2]
    flags = b"\x81\x80" if answers else b"\x81\x83"
    header = tid + flags + struct.pack("!HHHH", 1, len(answers), 0, 0)
    question = query[12:qname_end + 4]
    body = b""
    for rtype, rdata in answers:
        body += b"\xc0\x0c" + struct.pack("!HHIH", rtype, qclass, 60, len(rdata)) + rdata
    return header + question + body


def handle(sock, data, addr, cfg):
    qname, qname_end = parse_qname(data)
    if not qname:
        return
    qtype, qclass = struct.unpack("!HH", data[qname_end:qname_end + 4])

    if cfg["mode"] == "allowlist":
        deny = not matches(qname, cfg["allow"], cfg["allow_wc"])
        reason = "NOT-ALLOWED"
    else:
        deny = matches(qname, cfg["block"], cfg["block_wc"])
        reason = "BLOCKED"

    if deny:
        answers = []
        if qtype == 1:
            answers = [(1, socket.inet_aton("0.0.0.0"))]
        elif qtype == 28:
            answers = [(28, socket.inet_pton(socket.AF_INET6, "::"))]
        sock.sendto(build_reply(data, qname_end, qtype, qclass, answers), addr)
        print(f"{reason} {qname} type={qtype} from={addr[0]}", flush=True)
        return

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as up:
            up.settimeout(cfg["timeout"])
            up.sendto(data, (cfg["upstream"], 53))
            sock.sendto(up.recvfrom(4096)[0], addr)
    except OSError as exc:
        print(f"upstream fail {qname}: {exc}", file=sys.stderr, flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--listen", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=53)
    ap.add_argument("--upstream", default="1.1.1.1")
    ap.add_argument("--mode", choices=("blocklist", "allowlist"), default="blocklist")
    ap.add_argument("--blocklist", default=str(DEFAULT_BLOCK))
    ap.add_argument("--allow", default=str(DEFAULT_ALLOW))
    ap.add_argument("--timeout", type=float, default=3.0)
    args = ap.parse_args()

    block, block_wc = load_list(args.blocklist)
    allow, allow_wc = load_list(args.allow)

    if args.mode == "allowlist" and not (allow or allow_wc):
        sys.exit(f"allowlist mode needs entries in {args.allow}")

    cfg = {"mode": args.mode, "upstream": args.upstream, "timeout": args.timeout,
           "block": block, "block_wc": block_wc, "allow": allow, "allow_wc": allow_wc}

    if args.mode == "allowlist":
        print(f"mode=allowlist  {len(allow)} names + {len(allow_wc)} wildcards ALLOWED, all else -> 0.0.0.0")
    else:
        print(f"mode=blocklist  {len(block)} names + {len(block_wc)} wildcards BLOCKED")

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind((args.listen, args.port))
        print(f"sinkhole on {args.listen}:{args.port} -> upstream {args.upstream}")
        while True:
            data, addr = sock.recvfrom(4096)
            threading.Thread(target=handle, args=(sock, data, addr, cfg), daemon=True).start()


if __name__ == "__main__":
    main()
