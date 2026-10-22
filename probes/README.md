# Probes

Seven BrightScript channels, each built to answer exactly one question. They were
installed one at a time into the TV's single developer slot via
[`../tools/sideload-probe.sh`](../tools/sideload-probe.sh), run, and driven through
the Micro Debugger on `tcp/8085` with
[`../tools/brs.py`](../tools/brs.py).

Nothing here is an exploit. Every probe is an ordinary channel that asks the runtime
for something and records the refusal — which is the whole methodology: the sandbox
is documented by what it says no to.

| Probe | Question | Result |
|---|---|---|
| `probe/` | what does the sandbox allow, and does crashing buy a REPL? | crashes on purpose at a known line → Micro Debugger on `tcp/8085`; six-axis sandbox matrix |
| `probe-sg/` | are the same classes reachable from inside a SceneGraph render context? | most are not — the **render thread is crippled**; needed a MAIN-thread retest |
| `probe-ca/` | can a channel read or install a CA bundle? | `common:/certs/ca-bundle.crt` readable; write denied |
| `probe-enc/` | what does the filesystem say to a write outside `tmp:`? | `false` for `common:/`, `Missing or invalid PHY` for absolute paths |
| `probe-enc2/` | same question, second encoding of the path | same refusals — the check is on the path, not the string |
| `probe-fileread/` | what is actually readable on the system volume? | `common:/LibCore/v30` → `bslCore.brs`, `bslDefender.brs` |
| `probe-nvram/` | is there a fifth volume or an alias into `/nvram/`? | no — `GetVolumeList()` returns exactly four |

Findings and the full matrix: [`../docs/04-brightscript-sandbox.md`](../docs/04-brightscript-sandbox.md).

---

## Anatomy of a probe

Every one is the same three files:

```
probe/
├── manifest              title, id, version, splash — the channel's identity
└── source/
    └── main.brs          the whole probe
```

`main.brs` does two things: calls the API under test, and writes the answer
somewhere it can be read back. Two readback paths were used:

1. **`print` to the debug console** — visible on `tcp/8080` and in the app's debug
   output on `tcp/8085`.
2. **A report POSTed to a local collector** —
   [`../tools/collector.py`](../tools/collector.py) listens on the LAN and writes each
   report to disk, which survives the crash.

The second path is why `probe/` is built to throw: a probe that reports and then exits
cleanly would never produce a REPL, and the REPL is what makes iteration cheap. Crash
on purpose, at a line you chose, in developer mode only.

## Running one

```bash
# 1. put the probe in the TV's single dev slot
./tools/sideload-probe.sh probes/probe

# 2. start the collector if the probe reports over HTTP
python3 tools/collector.py --listen 0.0.0.0 --port 8899

# 3. launch it, let it crash, then drive the REPL
python3 tools/brs.py TARGET_IP --eval 'GetVolumeList()'
```

## The one caveat that cost a full sweep

`probe-sg/` runs its checks from a SceneGraph component's `init()`, which executes on
the **RENDER thread** — a deliberately crippled context. On that thread
`roDeviceInfo.GetVersion()` returns the dummy `999.99E99999A`, `GetModel()` returns
`L000X`, and `roUrlTransfer` fails with `creating MAIN|TASK-only component failed on
RENDER thread`.

A class that is thread-restricted and a class that is genuinely absent both surface
as `unknown classname` in that context. So `probe-sg/`'s results are **inconclusive
on their own**, and the sweep had to be redone from `source/main.brs`. That is why
`probe/` and `probe-sg/` both exist: one is the cautionary tale, the other is the
retest.

See [`../docs/04-brightscript-sandbox.md`](../docs/04-brightscript-sandbox.md) for
the matrix and the thread trap in full.

## Safety

Every probe is read-only or writes to `tmp:` / `cachefs:` only. The one class of
check deliberately excluded is anything that would need the secret-screen menu,
because that menu contains **factory reset** — that one was walked by hand, key by
key, with the owner watching, and then abandoned
([`../docs/07-negative-results.md`](../docs/07-negative-results.md) §8).
