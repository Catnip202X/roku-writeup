# 04 — The BrightScript sandbox, probed on six axes

The question: **can a sideloaded channel, which is ordinary code running on the TV,
reach anything it should not?**

A channel is the only code an owner can get onto a Roku without Roku's involvement.
If the sandbox leaks, the owner gains a privilege the developer model does not
intend. So the sandbox is the thing worth attacking, and it was attacked with a
purpose-built probe channel driven through the Micro Debugger on `tcp/8085`.

Method: [`probes/probe/`](../probes/probe/) crashes on purpose at a known line,
[`tools/brs.py`](../tools/brs.py) drives the resulting REPL, and every probe below is
a real evaluation on OS 15.3.4.2402 — not a documentation claim.

---

## Results

| Probe | Result | Boundary |
|---|---|---|
| `GetVolumeList()` | `cachefs:`, `common:`, `pkg:`, `tmp:` | — |
| `ListDir("common:/")` | `LibCore`, `certs` | **readable** |
| `common:/certs/ca-bundle.crt` | present | **readable** |
| `common:/LibCore/v30` | `bslCore.brs`, `bslDefender.brs` | **readable** |
| `WriteAsciiFile("common:/x.txt")` | `false` | **denied** |
| `WriteAsciiFile("/var/…")`, `/etc`, `/` | `Missing or invalid PHY` | **denied** |
| `WriteAsciiFile("tmp:/…")`, `cachefs:/…` | `true` | allowed (by design) |
| `roRegistry.GetSectionList()` | `auth, danmaku, prefs, wbi` only | **system sections hidden** |
| `roNetworkConfiguration` | `unknown classname` | **unavailable** |
| `roHtmlWidget` | `unknown classname` (non-SceneGraph) | SceneGraph only |

### Verdict: **no escape.**

Roku's sandbox held on every axis that matters. You get read-only sight of the
shared system volume — including its own `bslCore.brs` and `bslDefender.brs` — plus
writable `tmp:` and `cachefs:`, and nothing else.

Two consequences are load-bearing for the rest of this writeup:

1. **You cannot touch system registry sections**, so the ad/ACR flags are out of
   reach from a channel. There is no `ads` section to flip.
2. **You cannot construct `roNetworkConfiguration`**, so the TV's DNS cannot be
   changed from a channel either. The router remains the only DNS control point.

Which is why [`06-ad-suppression.md`](06-ad-suppression.md) is about a sinkhole and
four toggles rather than about a patch.

---

## What the probe did uncover

### The DNS configuration, read through a legitimately exposed API

`roDeviceInfo.GetConnectionInfo()` returns the interface, the TV's address, and the
resolver chain:

```
eth0  ·  ip TARGET_IP  ·  gateway GATEWAY_IP
dns.0 GATEWAY_IP  ·  dns.1 8.8.8.8  ·  dns.2 8.8.4.4
```

Nothing illegitimate — `GetConnectionInfo()` is a normal channel API. But it
answers the question the sinkhole depends on: the router is confirmed as the DNS
source, **and there are public fallbacks.**

That second half changes the design. A sinkhole that blackholes gets bypassed,
because the TV falls through to `8.8.8.8` and the ads come back. The sinkhole must
**answer `0.0.0.0`** so the resolver returns a cached-looking authoritative negative
rather than timing out. One implementation detail, extracted from a probe rather
than a guess.

### A persistent device identifier handed to every channel

`GetChannelClientId()` → `CLIENT_ID`, a stable per-device value available to any
channel with no permission gate. Not a sandbox break; worth recording, because it
means channel authors get a durable device identifier for free.

### Registry remanence

`roRegistry.GetSectionList()` returned `auth`, `danmaku`, `prefs`, `wbi` — the
previous app's sections, readable by an unrelated probe. `auth` held key names
`buvid` and `cookie`. **The values were deliberately not read.** See
[`03-findings.md`](03-findings.md) §4 for why this is a design property rather than a
vulnerability, and [`08-engagement-record.md`](08-engagement-record.md) for the rule
that produced "did not read it".

---

## The thread trap — the mistake worth documenting

The first sweep was wrong, and the way it was wrong is a general lesson.

A SceneGraph component's `init()` runs on the **RENDER thread**, and that thread is
deliberately crippled:

| On the render thread | Result |
|---|---|
| `roUrlTransfer` | `creating MAIN\|TASK-only component failed on RENDER thread` |
| `roDeviceInfo.GetVersion()` | `999.99E99999A` (dummy) |
| `roDeviceInfo.GetModel()` | `L000X` (dummy) |
| `roHtmlWidget` | `unknown classname` |

So **"unknown classname" on the render thread proves nothing.** It is a
thread-restriction error wearing a missing-class error's clothes. The honest
conclusion from sweep v1 was "inconclusive", not "absent" — and the difference
mattered, because the whole `roHtmlWidget` → Chromium 104 escape path
([`05-escape-avenues.md`](05-escape-avenues.md) Path 1) hinged on it.

Sweep v3 moved the probing into `source/main.brs`, i.e. the **MAIN thread**, after a
live Scene existed — and got the same verdict:

```
unknown classname "roHtmlWidget"        ← main thread
unknown classname "roHtmlWidgetVideo"
unknown classname "roNetworkConfiguration"
```

The runtime *does* distinguish the two failure modes: `roUrlTransfer` returned
`creating MAIN|TASK-only component failed on RENDER thread`, a completely different
message from `unknown classname`. So `unknown classname` on both threads means the
class genuinely is not registered for channels. `Roku Browser 104.11.33` is internal
to system UI (microsites, legal agreements) and is **not exposed to sideloaded
channels**.

**Generalisable lesson:** a negative result from code running on the wrong thread is
not a negative result. Before concluding a class is absent, prove the probe can see
a class that *is* present, from the same thread, in the same context. This sweep
learned that the hard way and the writeup keeps the scar.

### Side finding

Inside a channel, `roDeviceInfo.GetModel()` returns the masked value `L000X` (real
model is `50R4CX` / `L816X`), and `GetOSVersion()` does not exist. Roku deliberately
masks model identity from channel code — the same information AirPlay's `/info`
hands out for free to an unauthenticated LAN peer. Worth noting as an inconsistency
in the platform's own disclosure posture.

---

## Why this matters beyond this TV

The sandbox result is the reason the ad stack cannot be removed locally:

```
channel code  ──denied──▶  common:/          (read-only)
              ──denied──▶  system registry   (sections hidden)
              ──absent──▶  roNetworkConfiguration
              ──absent──▶  roHtmlWidget → Chromium 104
```

Four doors, three locks and one missing door. There is no fifth door in
BrightScript. So the remaining work is either a SceneGraph-only surface or native
code reached over the network — which is exactly the ranking in
[`05-escape-avenues.md`](05-escape-avenues.md).
