# 05 — Escape paths, ranked

The BrightScript sandbox is **closed** ([`04-brightscript-sandbox.md`](04-brightscript-sandbox.md)):
`common:/` is read-only, system registry sections are hidden, and
`roNetworkConfiguration` and `roHtmlWidget` are unavailable outside SceneGraph.

So the remaining work is either a SceneGraph-only surface, or native code reached
over the network. Three candidates, ranked, with the verdict that was actually
reached rather than the one that would make a better story.

Legend: **OPEN** = not yet tested · **TESTING** = probe built · **CLOSED** = ruled out

---

## Path 1 — SceneGraph `roHtmlWidget` → bundled Chromium 104 · **CLOSED**

**Why it looked promising.** `Roku Browser 104.11.33` is installed. Chromium 104 is
from 2022; V8/Blink primitives for that era are public. `roHtmlWidget` returned
`unknown classname` from a plain (non-SceneGraph) channel — but that error is about
the component registry being active only inside a SceneGraph render context, *not*
about the browser being absent. Two very different claims, one identical error
string.

**The thread trap.** A first sweep ran from a SceneGraph component's `init()`, which
executes on the **RENDER thread** — a deliberately crippled context where
`roUrlTransfer` fails with `creating MAIN|TASK-only component failed on RENDER
thread`, `roDeviceInfo.GetVersion()` returns the dummy `999.99E99999A`, and
`GetModel()` returns `L000X`. `roHtmlWidget` also returned `unknown classname`
there, which proves nothing: a thread restriction and a missing class produce the
same message in that context.

**Retested properly.** Sweep v3 moved the probes into `source/main.brs` — the **MAIN
thread**, after a live Scene existed:

```
unknown classname "roHtmlWidget"          ← main thread
unknown classname "roHtmlWidgetVideo"     ← main thread
unknown classname "roNetworkConfiguration"← main thread
```

**Verdict: CLOSED.** The runtime *does* distinguish the two failure modes, which is
the control that makes this result trustworthy: `roUrlTransfer` returned a
completely different error (`creating MAIN|TASK-only component failed on RENDER
thread`) when thread-restricted. So a bare `unknown classname` on **both** threads
means the class is genuinely not registered for channels.

`Roku Browser 104.11.33` is internal to system UI — microsites, legal agreements,
the offer/ad landing pages — and is not exposed to sideloaded channels. The
Chromium-104 vector cannot be reached from a dev app.

**Why this was the best candidate.** Success would have meant JS executing inside
the TV's browser process: code execution in a *native*, non-BrightScript context. A
different privilege domain than the channel sandbox, and the only route in this list
that plausibly reaches the OS rather than the app container.

**Cost of being wrong the first time.** One full sweep, thrown away. The lesson is
in [`04-brightscript-sandbox.md`](04-brightscript-sandbox.md): a negative result
from the wrong thread is not a negative result.

---

## Path 2 — AirPlay receiver on `tcp/7000` · **OPEN**

**Why it is the leading remaining candidate.** `nc TARGET_IP 7000` answers
`HTTP/1.1 403 Forbidden` / `Server: AirTunes/377.40.00`, `supports-airplay: true`,
and both `AirPlay` and `AirPlay Daemon` are version `6.69.540`. This is a large
native C++ stack speaking a binary protocol to any peer that can reach the port. No
BrightScript is involved, so the channel sandbox is simply irrelevant to it.

It is also **not closable from Roku settings** and does not depend on developer mode.
Of everything on this box, it is the exposure that exists whether or not the owner
ever enabled anything.

**Surface mapped, and it is hardened.** Only `GET /info` answers unauthenticated:

| Request | Status |
|---|---|
| `GET /info` | **200** (1825-byte binary plist) |
| `GET /server-info` | 403 |
| `POST /pair-setup` | **400 Bad Request** — alive, rejected the empty body |
| `POST /pair-verify` | 403 |
| `POST /fp-setup` | 403 |
| `POST /play` | 403 |
| `POST /reverse` | 403 |
| `GET /stream.xml` | 403 |
| `OPTIONS *` | 403 |

The stack is current, not legacy:

- `sourceVersion 377.40.00`
- `sdk AirPlay;3.6.0.126`, `protocolVersion 1.1`
- `firmwareRevision 15.34.2402` (built 2026-09-07)
- `fairplay-4.9.21`
- `webEngineName "Apple App Engine"`, `hlsJSVersion 4.0.16`

Feature bitmask `0x038bcf46007f8ad0` decodes to `SupportsAirPlay` (49), Photo (51),
**Mirroring (55)**, screen-rotate (56/57), `VideoHTTPLiveStreams` (4), Audio (6).

**Verdict: OPEN, and deliberately not pursued.** `/pair-setup` answering `400` rather
than `403` is the only unauthenticated *interaction* point — the handler is alive and
parses a body. Attacking a current Apple AirPlay 3.6 pairing handshake is deep
protocol research with a hardened, actively-maintained target. Real work, not a
quick win, and out of proportion to this assessment's objective.

Recorded honestly as: still a real LAN exposure, patched to a current stack,
realistic path is pairing-protocol research.

---

## Path 3 — Native DRM / Cobalt libraries · **OPEN, deprioritised**

**Why.** The box carries `libwidevine 1.0.1287`, `libfairplay 1.0.133`,
`cobaltlib 2.26.14` and `lib-Luna 17.0.28`. Widevine, FairPlay and Cobalt are C++
with long CVE histories, and Cobalt is Chromium-derived — the same class of bug as
Path 1, but reached through playback rather than rendering.

**Next actions, in order.**

1. Identify Cobalt's embedded Chromium version from the Starboard build string.
2. Check which pinned versions of these libraries carry known public issues.
3. Only then decide whether a media-stream-driven trigger is worth building.

**Blocker.** Reaching these requires a channel that feeds crafted media through a
playback component — significantly more setup than Path 1 for the same class of bug,
and Path 1 is now closed. Deprioritised behind Path 2, which needs no dev mode at
all.

---

## What constrains all three

- **BrightScript:** no write to `common:/`, absolute paths rejected with
  `Missing or invalid PHY`. Volume list is exactly four entries.
- **Registry:** only channel-scoped sections; system ad/ACR flags unreachable.
- **`roNetworkConfiguration` unavailable** → DNS cannot be changed from a channel.
- **DNS is `GATEWAY_IP` + `8.8.8.8`/`8.8.4.4` fallbacks** → a sinkhole must
  **answer `0.0.0.0`**, not blackhole, or the TV falls through to Google.
- **`tcp/8085`** gives an unauthenticated BrightScript REPL whenever a dev channel
  crashes. That is the reliable foothold for everything above — and it is a foothold
  *inside* a box that is already closed.

## The shape of the conclusion

```
Sandbox       → closed, on six axes, from both threads
Chromium 104  → present on the box, not exposed to channels
AirPlay 3.6   → native, reachable, current, unauthenticated interface is one endpoint
DRM/Cobalt    → native, reachable only through crafted media, unexplored
```

Nothing here is a jailbreak. What it is: a ranked map of where a real one would have
to come from, produced by closing the door that looks easiest and documenting why
the remaining doors are expensive rather than pretending they are locked.
