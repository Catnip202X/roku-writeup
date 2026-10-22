# Roku writeup — what "debloating" a Roku TV actually costs you

A self-authorized security assessment of a **Roku TV on Roku OS 15.3.4** (model
`50R4CX` / `L816X`), asking two questions that turned out to be the same question:

1. **Can the owner of a Roku TV remove the platform's advertising and telemetry?**
2. **What does the answer to (1) tell you about the platform's security model?**

Short version: **not from the device, and the reason is instructive.** Roku's
protection is not a clever lock that someone will eventually pick. It is the
*absence of attack surface on the device* combined with *server-side authority over
the client*. That combination is much harder to defeat than a lock, and it is worth
writing down precisely — including every avenue that failed.

This repo is the full record: the findings, the probe channels that produced them,
the tooling, and the nine negative results that make up most of the actual work.

> **Sanitisation.** Every device identifier in this repository — serial numbers,
> MAC addresses, advertising ID, AirPlay serial, LAN layout, machine paths — has
> been replaced with a stable placeholder (`ROKU_SERIAL`, `TARGET_IP`, …). The
> rewrite is mechanical and re-runnable: see [`scripts/sanitize.py`](scripts/sanitize.py)
> and [Sanitisation](#sanitisation) below.

---

## Contents

| Path | What is in it |
|---|---|
| [`docs/01-device.md`](docs/01-device.md) | The device, its firmware, and what it says about itself |
| [`docs/02-attack-surface.md`](docs/02-attack-surface.md) | Four services, three of them unauthenticated |
| [`docs/03-findings.md`](docs/03-findings.md) | The findings table, with reproducible steps |
| [`docs/04-brightscript-sandbox.md`](docs/04-brightscript-sandbox.md) | Six-axis sandbox probe and its verdict |
| [`docs/05-escape-avenues.md`](docs/05-escape-avenues.md) | Three candidate escape paths, ranked, with verdicts |
| [`docs/06-ad-suppression.md`](docs/06-ad-suppression.md) | What actually works, and why the sinkhole must *answer* |
| [`docs/07-negative-results.md`](docs/07-negative-results.md) | The nine things that did not work |
| [`docs/08-engagement-record.md`](docs/08-engagement-record.md) | A filled-in engagement record, including the mistakes |
| [`docs/09-engagement-template.md`](docs/09-engagement-template.md) | The blank template that produced it |
| [`docs/10-third-party-gateway.md`](docs/10-third-party-gateway.md) | An incidental finding on equipment I do not own |
| [`tools/`](tools/) | Sinkhole, debugger driver, sideloader, hub builder |
| [`probes/`](probes/) | Seven BrightScript probe channels |
| [`blocklist/`](blocklist/) | 52-line ad/telemetry blocklist, each entry citing its plugin |
| [`apps/`](apps/) | The sideloaded channel used as a foothold — a pointer to its own repo, not a copy |
| [`evidence/`](evidence/) | Captured device output, scrubbed |

---

## The findings

| # | Finding | Severity | Notes |
|---|---|---|---|
| 1 | Unauthenticated BrightScript debug terminal on `tcp/8080` | high → **low-medium** | Reassessed downward — see below |
| 2 | Unauthenticated ECP keypress injection on `tcp/8060` | medium | Design of the ECP protocol |
| 3 | Unauthenticated BrightScript REPL on `tcp/8085` on channel crash | high (dev-mode gated) | The reliable foothold |
| 4 | Registry remanence across dev-app replacement | medium → **not a boundary violation** | A design property |
| 5 | AirPlay `/info` discloses model, firmware, FairPlay version | low | Only unauthenticated AirPlay endpoint |
| 6 | Third-party ISP gateway: LAN-wide unauthenticated admin (CWE-306) | high, LAN-scoped | Not my equipment; routed to vendor |

Two of those six were rated **downward** after evidence. That is the most
transferable part of this repo. See
[`docs/08-engagement-record.md`](docs/08-engagement-record.md) §4.

### Finding 1, in one paragraph

`tcp/8080` hands a privileged BrightScript console to anyone who connects — no
credential, no session, no origin check:

```console
$ printf 'plugins\n' | nc TARGET_IP 8080
ROKU_SERIAL (ROKU_TV - 15.3.4.2402)
> F-C + S M S6   58484  Roku Ads Library, 3.29.30
  ...
```

It leaks the serial number, exact build, and the complete 54-plugin inventory; it
reports RAM and swap; and it accepts `remove_plugin` (uninstall channels),
`press` / `type` (inject remote-control input — silent full control of the TV) and
`genkey` (mint a fresh developer signing key). Full steps in
[`docs/03-findings.md`](docs/03-findings.md).

It is rated low-medium rather than high because the developer password
independently gates code *installation*. The guaranteed capability from `:8080`
alone is disclosure and input injection, not persistence. The first rating
over-weighted a LAN-local exposure; that correction is the honest version.

---

## The negative result that is the whole point

The obvious debloat move is the console's `remove_plugin`. Sixteen ad/telemetry
candidates were tested on OS 15.3.4:

- **13 refused** with `is not removable`.
- **3 returned `Removed plugin id`** — Innovid Ad Renderer (`794761`), Roku
  Interactive Ads Library (`820229`), BrightLineLibrary (`751600`).

Those three **came back**. They stayed in `plugins`, their ref counts climbed
`0 → 1`, and they survived a standby → power-on cycle. Re-issuing the same
`remove_plugin` reports "Removed" again, forever. Roku re-provisions account-tied
plugins on the next home-screen render.

Measured effect: **zero.** Flash free `193.8 MB → 193.7 MB`; RAM used
`415612 KB → 398104 KB`. Both are cache noise. The home screen never destabilised.

> Roku OS 15.3.4 flag-locks its monetisation stack, and the authority that
> restores it lives on Roku's servers, not on your TV. There is no on-device
> command that deletes the home-screen ad engine.

This is the finding. Not "Roku is unhackable" — but "the property you would have to
break is a server-side provisioning decision, and no local privilege escalation
reaches it." Debloat has to happen at the network edge, and the privacy toggles
happen in Settings.

---

## What actually works

Not a jailbreak, but real, and both are enforced outside the device:

1. **A DNS allowlist sinkhole** — deny everything except the streaming services'
   own domains. [`tools/sinkhole.py`](tools/sinkhole.py), dependency-free,
   [`blocklist/roku-blocklist.txt`](blocklist/roku-blocklist.txt) as the data.
2. **Four settings toggles** — screen saver away from the ad-bearing default, ACR
   off, limit ad tracking on, static theme.

The sinkhole must **answer `0.0.0.0`**, not blackhole. The TV is handed
`GATEWAY_IP` plus public resolvers as fallbacks; a blackhole makes it fall through
to Google and the ads come back. That one detail is the difference between a
working sinkhole and a placebo, and it came out of a probe rather than a doc.

---

## The methodological point

Every "remove ads from your Roku" guide stops at settings toggles. Every "Roku
jailbreak" claim turns out to be about something else — usually sideloading, which
is a supported developer feature, not an exploit.

What this assessment establishes is the shape of the actual boundary:

| Avenue | Result |
|---|---|
| `remove_plugin` on the ad stack | accepts the command, plugin returns — account re-provisioning wins |
| BrightScript fs write to `common:/`, absolute paths | denied (`Missing or invalid PHY`) |
| System registry sections (`ads`, `settings`, `device`) | not visible to a channel |
| `roHtmlWidget` → bundled Chromium 104 | class absent, on **both** threads |
| `roNetworkConfiguration` | class absent |
| Debug console `target` selection | works, grants no privilege — per-channel ACL is independent |
| ECP launch of internal system channels | `503` / connection reset |
| Secret screen / commercial mode | absent after three sequences, two injection paths |
| Volume alias into `/nvram/plugins/` | only four volumes exist |
| **BrightScript sandbox** | **held on every axis tested** |

Read that table as a boundary map, not a failure list. A negative result with a
reproduction is worth more than a rumour, and nine of them say something specific:
the reachable surface is *native and network-facing*, not the channel sandbox.

---

## Tooling

| Path | What it does |
|---|---|
| [`tools/sinkhole.py`](tools/sinkhole.py) | dependency-free DNS sinkhole, blocklist and allowlist modes |
| [`tools/collector.py`](tools/collector.py) | receives probe reports and browser beacons from the device |
| [`tools/brs.py`](tools/brs.py) | drives the BrightScript Micro Debugger on `tcp/8085` |
| [`tools/tv.sh`](tools/tv.sh) | plugin inventory, health checks, removal probes |
| [`tools/apps.sh`](tools/apps.sh) | switch which app occupies the single Roku dev slot |
| [`tools/sideload-probe.sh`](tools/sideload-probe.sh) | package, authenticate and install a channel; stores the developer password in the login keychain so it is typed once |
| [`tools/hub/`](tools/hub/) | merges several Roku channels into one sideloadable package with a menu |
| [`probes/`](probes/) | seven probe channels, each answering one question |

`tools/hub/build_hub.py` is the most reusable piece. Roku allows exactly one
sideloaded channel; namespacing several apps' components into one package behind a
launcher menu is the only way to have more than one.

## The app that was the foothold

The channel installed in the dev slot — the reason developer mode was on, and the
code every probe replaced — is its own project:

> **[github.com/Catnip202X/biliku](https://github.com/Catnip202X/biliku)** —
> Biliku · 云屏 / 云听小电视 · an unofficial Bilibili client for Roku TVs with a
> casting companion. MIT.

It is deliberately **not mirrored here**. A writeup does not need to ship ~4 MB of app
source (mostly a CJK font) to make its point, and two copies of the same code diverge.
[`apps/`](apps/) explains what the app contributed as *evidence* — the TASK/MAIN
thread split that produced the `roHtmlWidget` false negative, the in-channel server
that shows the sandbox's real shape, and the ECP/SSDP companion that is the reason any
of the exposures in [`docs/02-attack-surface.md`](docs/02-attack-surface.md) exist.

The point stands either way: *normal* channel code is what gets sandboxed, so normal
channel code is what you test the sandbox with.

---

## Sanitisation

The rewrite is mechanical, re-runnable, and **fails closed**:

```bash
python3 scripts/sanitize.py --scan    # non-zero exit if any identifier survives
python3 scripts/sanitize.py --apply   # rewrite, then re-scan to prove convergence
```

Two design choices are worth flagging:

- The identifier table is **not in this repo**. It lives in
  `redactions.local.txt`, which is git-ignored, because a public repo must not
  contain the strings it exists to hide. [`redactions.example.txt`](redactions.example.txt)
  shows the format with fake values.
- Placeholders are **stable and semantic** (`ROKU_SERIAL`, `TARGET_IP`,
  `GATEWAY_IP`), not random hashes. The writeup stays readable, and a reader can
  substitute their own device without re-deriving the mapping.

Deliberately **not** published, at any level of scrubbing: the two signed Bilibili
CDN URL captures in the client's debug log (they embed a `buvid` device fingerprint
and per-session `upsig`/`hmac` signatures), and any captured credential value. The
engagement record in [`docs/08-engagement-record.md`](docs/08-engagement-record.md)
records the *existence* of a registry secret and never its value — and says so.

---

## Scope and authorisation

| | |
|---|---|
| Target | One Roku TV, owned by the author, on the author's own home network |
| Basis | Self-owned hardware |
| Written authorisation | Not applicable — owner is the operator |
| Third-party systems | Observed, never modified; finding routed to the vendor and to CERT/CC coordination |
| Not tested | Denial of service, social engineering, data exfiltration, physical/UART/SPI |

See [`SECURITY.md`](SECURITY.md) for the full scope statement and the rules of
engagement this was run under.

Nothing here is a jailbreak, an exploit chain, or a piracy tool. It is a boundary
map, produced by asking the boundary politely and writing down every refusal.

## Licence

MIT — see [`LICENSE`](LICENSE).
