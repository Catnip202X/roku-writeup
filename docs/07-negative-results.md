# 07 — Negative results

Nine things that did not work. This is the majority of the work and it is the part
that makes the rest trustworthy: a writeup with no negative results is a writeup
that stopped when the author got bored.

Each entry records what was tried, what came back, and what it rules out.

---

## 1. `remove_plugin` as a debloat primitive

**Tried.** Uninstalling all 16 ad/telemetry plugins via the `:8080` console.

**Result.** 13 refused (`is not removable`). 3 reported success — Innovid Ad
Renderer, Roku Interactive Ads Library, BrightLineLibrary — then reappeared in
`plugins`, with ref counts climbing `0 → 1`, surviving a standby → power-on cycle.
Re-issuing the command reports "Removed" again, indefinitely.

**Refuted by measurement.** Flash `193.8 → 193.7 MB`; RAM `415612 → 398104 KB`.
Both cache noise.

**What it rules out.** Any local debloat path. The authority that restores those
plugins is account-tied and server-side; no on-device command reaches it.

---

## 2. BrightScript filesystem write outside `tmp:` / `cachefs:`

**Tried.** `WriteAsciiFile` against `common:/x.txt`, `/var/…`, `/etc`, `/`.

**Result.** `common:/` returns `false`. Absolute paths return
`Missing or invalid PHY`.

**What it rules out.** Writing the ad/ACR flags into a config file, planting a
startup script, or replacing any component of the launcher. `GetVolumeList()`
returns exactly four volumes — `cachefs:`, `common:`, `pkg:`, `tmp:` — so there is
no fifth mount to escalate through.

---

## 3. System registry sections

**Tried.** `roRegistry.GetSectionList()` from a sideloaded channel.

**Result.** `auth`, `danmaku`, `prefs`, `wbi` — only the channel-scoped sections
belonging to previously installed apps. No `ads`, no `settings`, no `device`.

**What it rules out.** Flipping the platform's ad/ACR/telemetry flags from code. The
settings exist; the channel sandbox does not expose the sections that hold them. This
is the single most load-bearing negative result in the whole assessment.

---

## 4. `roHtmlWidget` → bundled Chromium 104

**Tried.** Constructing `roHtmlWidget` from a plain channel (render thread) and again
from `source/main.brs` (MAIN thread, after a live Scene existed).

**Result.** `unknown classname "roHtmlWidget"` on both threads. `roHtmlWidgetVideo`
likewise.

**Why the first attempt was inconclusive rather than negative.** The render thread is
deliberately crippled and returns `unknown classname` for thread-restricted classes
too. The control that makes v3 trustworthy: `roUrlTransfer` fails with a *different*
message (`creating MAIN|TASK-only component failed on RENDER thread`), proving the
runtime distinguishes the two cases. A bare `unknown classname` on both threads means
genuinely absent.

**What it rules out.** The Chromium-104 escape path
([`05-escape-avenues.md`](05-escape-avenues.md) Path 1) from a sideloaded channel.
`Roku Browser 104.11.33` is internal to system UI only.

---

## 5. `roNetworkConfiguration`

**Tried.** Constructing the class to change the TV's DNS from inside the channel.

**Result.** `unknown classname`, both threads.

**What it rules out.** Fixing the ad problem from the TV side. Combined with §3, this
is why the working solution in [`06-ad-suppression.md`](06-ad-suppression.md) lives on
the router.

---

## 6. Console `target` selection as a privilege boundary

**Tried.** Re-pointing the `:8080` console at other plugins with `target [n]`.

**Result.** Selection works — the console switches context and reports the new
target — but grants no additional privilege. The per-channel ACL is independent of
which target the console is looking at.

**What it rules out.** Using the debug console as a pivot into system components. It
is a *view* selector, not an authority switch.

**Restored afterwards.** `target` was returned to `[0] main`, as recorded in
[`08-engagement-record.md`](08-engagement-record.md) §3.

---

## 7. ECP launch of internal system channels

**Tried.** `/launch/<id>` against system channel ids, including the Settings app.

**Result.** `503 Service Unavailable` or a connection reset. `/launch/-1` → `404`.

**What it rules out.** Driving Settings — and therefore the privacy toggles —
programmatically. The four toggles in
[`06-ad-suppression.md`](06-ad-suppression.md) §6b are on the remote because there is
no other path.

---

## 8. Secret screen / commercial mode

**Tried.** Three known key sequences, over two different injection paths (ECP
`keypress` and the console's `press`), with the owner watching.

**Result.** Absent. No hidden menu appeared.

**Approach note.** The secret screen contains **factory reset**, so it was never
navigated blind or automated — keys were injected one at a time with the owner
present, per the rules of engagement in
[`09-engagement-template.md`](09-engagement-template.md) §3. A destructive menu is
not a thing you fuzz.

---

## 9. Volume alias into `/nvram/`

**Tried.** Looking for a mount or alias that reaches the non-volatile plugin store.

**Result.** `GetVolumeList()` returns four volumes. There is no fifth.

**What it rules out.** Persisting a modified plugin through a filesystem route. The
`/nvram/plugins/` path is not reachable from a channel at all.

---

## What the nine add up to

| Category | Verdict |
|---|---|
| Remove the ad stack locally | **no** — server-side re-provisioning |
| Persist a modification locally | **no** — no writable system volume |
| Reach system settings from a channel | **no** — sections hidden |
| Reach native code from a channel | **no** — classes absent |
| Reach Settings over ECP | **no** — 503 / reset |
| Reach the OS at all from BrightScript | **no** — sandbox held on six axes |

And the boundary that remains reachable is **native and network-facing** — AirPlay on
`:7000`, DRM/Cobalt through crafted media — neither of which is a BrightScript
problem, and neither of which was pursued past mapping
([`05-escape-avenues.md`](05-escape-avenues.md)).

## Why recording these is the job

Six findings is a short list. Nine negative results with reproductions is what
turns a list of findings into a **boundary map**: it tells the next person which
door not to open, and it tells the owner why the answer to "can I debloat my TV" is
"not from the TV" rather than "nobody has tried hard enough".

A negative result without a reproduction is a rumour. A negative result *with* one —
and with the control that proves the probe was looking in the right place (§4) — is
evidence.
