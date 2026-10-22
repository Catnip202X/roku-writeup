# 03 — Findings

**Target** Roku TV `ROKU_TV` @ `TARGET_IP` — 50R4CX / L816X, OS **15.3.4.2402**
**Objective** Remove or neutralise the advertising and telemetry stack, keeping the
UI bootable and reversible
**Authorisation** Owner, self-declared, own hardware on own LAN

Every finding below has reproducible steps. Anything without them was recorded as a
fact, not a finding — that distinction is enforced, not stylistic.

---

## 1. `[high]` → `[low-medium]` — Unauthenticated BrightScript debug terminal on `tcp/8080`

Anyone on the LAN gets a privileged console with no credential prompt. It leaks the
serial, exact build and the complete 54-plugin inventory (including every ad/ACR
component), reports RAM/swap, and accepts `remove_plugin` (deletes channels),
`press` / `type` (injects remote-control input = silent full control of the TV) and
`genkey` (mints a new developer signing key).

**Reproduce**

```bash
printf 'plugins\n' | nc TARGET_IP 8080                      # banner + full plugin inventory
printf 'free\n'    | nc TARGET_IP 8080                      # memory totals
printf 'help\n'    | nc TARGET_IP 8080                      # remove_plugin, press, type, genkey
printf 'remove_plugin 693751\n' | nc TARGET_IP 8080          # arbitrary channel removal
```

**Why the rating moved down.** The initial rating of `high` assumed the console
escalates to code execution. It does not: package installation is independently
gated by Digest auth on `tcp/80` with the developer password. The guaranteed
capability is disclosure and input injection, both LAN-local, both requiring
developer mode to already be on. `low-medium` is the honest number.

**Fix.** `Settings → System → Advanced system settings → Control by mobile apps →
Network access → Limited`, and turn developer mode off when you are not actively
developing. That closes `:8080` and `:80`.

---

## 2. `[medium]` — Unauthenticated ECP keypress injection on `tcp/8060`

No auth on ECP. Drive the UI, launch channels with arbitrary arguments, read
`advertising-id` / serial / MACs / firmware, enumerate installed apps — all from any
LAN host. `/launch/dev` lets an attacker push a video onto the screen unprompted.
The `advertising-id` is a persistent tracking identifier handed out in plaintext.

**Reproduce**

```bash
curl -s http://TARGET_IP:8060/query/device-info
curl -s http://TARGET_IP:8060/query/apps
curl -s -X POST http://TARGET_IP:8060/keypress/Home -o /dev/null -w '%{http_code}\n'
curl -s -X POST 'http://TARGET_IP:8060/launch/837'  -o /dev/null -w '%{http_code}\n'
```

**Fix.** Same setting as above — `Control by mobile apps → Network access → Limited`.
There is no way to keep ECP for a third-party remote and close it for everyone else
on the same L2 segment.

---

## 3. `[high]` — Unauthenticated BrightScript REPL on `tcp/8085` once a dev channel crashes

In developer mode, an unhandled error in a sideloaded channel drops the app into the
BrightScript Micro Debugger, served over a raw socket with no authentication. That
REPL evaluates arbitrary BrightScript in the crashed channel's context.

**Reproduce**

1. Install the probe channel that crashes on purpose at a known line
   ([`probes/probe/`](../probes/probe/)):
   ```bash
   ./tools/sideload-probe.sh probes/probe
   ```
2. Launch it; it throws at the marked statement and halts into the debugger.
3. Drive the REPL:
   ```bash
   python3 tools/brs.py TARGET_IP --eval 'GetVolumeList()'
   python3 tools/brs.py TARGET_IP --eval 'ListDir("common:/")'
   ```

**Severity note.** Rated `high` for capability (arbitrary code in a privileged
context), gated by developer mode plus an installed dev channel. It is the reliable
foothold for every probe in
[`04-brightscript-sandbox.md`](04-brightscript-sandbox.md) — and, per that document,
it does not escape the sandbox.

**Fix.** Turn developer mode off. There is no per-port control for `:8085`.

---

## 4. `[medium]` → `[not a boundary violation]` — Registry remanence across dev-app replacement

Registry sections are keyed by channel id and are **not** cleared when the package is
replaced. A probe channel could read `auth` → `("buvid", "cookie")`, the previous
app's login state. Values were deliberately not dumped. Any app you sideload into
that slot inherits them.

**Why the rating moved down.** Reaching this requires an installed dev channel, which
requires the developer password. An attacker who has that already holds equivalent
privilege, so this is not a boundary crossing — it is a documented consequence of
keying registry data by channel id while the dev slot is a single shared slot.
Recorded as a design property, not a vulnerability.

**What it means practically.** If you sideload app A, log into something, then
replace it with app B, app B can read A's stored keys. The correct mental model is
that the dev slot is one identity that keeps its storage across package swaps.

---

## 5. `[low]` — AirPlay `/info` discloses model, firmware and FairPlay version

`GET /info` on `tcp/7000` returns a 1825-byte binary plist with model, hardware
revision, firmware build date, AirPlay SDK, FairPlay CDM and library versions, the
full display capability tree, a display UUID, and an AirPlay serial — unauthenticated.

**Reproduce**

```bash
nc TARGET_IP 7000            # then type:
GET /info HTTP/1.1
Host: TARGET_IP
```

**Why it is only `low`.** It is a documented AirPlay protocol endpoint, reachable
only from the same LAN, and it discloses versions rather than capability. Its value
to an attacker is target selection, not access. Recorded because it is the richest
unauthenticated device description on the box and because it cannot be closed from
Roku settings.

---

## 6. `[high, LAN-scoped]` — Third-party ISP gateway: unauthenticated writable admin interface

Not this device, not this author's equipment. Discovered while mapping the DNS path.
Full write-up and disclosure status in
[`10-third-party-gateway.md`](10-third-party-gateway.md). Summary: `CWE-306`, the
complete administrative interface is served to any LAN client without a credential,
and configuration pages are editable.

Included here so the findings table is complete. It is filed separately because the
handling rules are different — observed, not tested; routed to the owner and the
vendor; nothing changed.

---

## Negative result that matters most

**`remove_plugin` cannot debloat this TV.** 16 ad/telemetry candidates tested:
13 were refused (`is not removable`); 3 returned `Removed plugin id` — Innovid Ad
Renderer (`794761`), Roku Interactive Ads Library (`820229`), BrightLineLibrary
(`751600`) — but all three stayed in `plugins`, their ref counts climbed `0 → 1`,
and they survived a `PowerOff`/`PowerOn` cycle. Re-running the command reports
"Removed" again, forever.

Measured effect: **zero**. Flash free `193.8 → 193.7 MB`, RAM used
`415612 → 398104 KB` (both cache noise). The home screen never destabilised.

Roku OS 15.3.4 flag-locks its monetisation stack. The real ad suppression has to
happen at the DNS edge; see [`06-ad-suppression.md`](06-ad-suppression.md).

---

## Confirmed adware

| Plugin | Id | Role |
|---|---|---|
| Roku Ads Library 3.29.30 | `58484` | ad SDK |
| Grand Central 26.42.12 | `155883` | Roku's ad/identity orchestrator |
| DFP Ad Service 2.2.2 | `54383` | Google DoubleClick |
| Innovid Ad Renderer 1.1.43 | `794761` | video / interactive ads |
| Interactive Ads Library 3.75.2 | `260537` | ad templates |
| Roku Interactive Ads Library 1.1.9 | `820229` | ad templates |
| BrightLineLibrary 3.6.10 | `751600` | interactive TV ads |
| Roku My Offers 8.0.3 | `295059` | offer placements |
| Roku Microsite 1.51.0 | `611444` | ad landing pages |
| Roku Content Player 1.6.10 | `43508` | ad / content playback |
| ACR Lib Channel 8.0.12 | `98832` | **content fingerprinting** |
| AcrAddon 10.3.3 | `686402` | **content fingerprinting** |
| Roku Analytics Library 1.5.1003 | `109022` | telemetry |
| Roku City 7.3.102 | `55545` | ad screensaver |
| Welcome home to Roku City 2.2.0 | `687148` | ad screensaver |

---

## Assets

- `TARGET_IP` — Roku TV; open `tcp/80` (Digest, realm `rokudev`), `7000`, `8060`,
  `8080`, `8085`
- `GATEWAY_IP` — home gateway, `lighttpd/1.4.69`, admin at `/cgi-bin/home.ha`,
  owns DHCP → DNS. Third-party equipment; observed only.
