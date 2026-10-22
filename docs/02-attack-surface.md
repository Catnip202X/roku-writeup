# 02 — Attack surface

Five listening services on the LAN interface. Three of them hand out capability
without a credential.

```
80    developer web server (plugin_install / plugin_package) — Digest auth, realm "rokudev"
8080  BrightScript debug terminal — NO AUTHENTICATION AT ALL
8060  ECP (REST) — no auth: keypress injection, app launch, device-info, app inventory
8085  app debug output / BrightScript Micro Debugger — no auth once a channel crashes
7000  AirPlay / AirTunes — only GET /info answers unauthenticated
```

Developed by walking the port range from a LAN host, then confirming each service by
hand rather than trusting a scanner's banner.

---

## `tcp/8080` — the BrightScript debug terminal

The single most useful service for research, and the one that should worry an owner.
It accepts a text command per connection and answers on the same socket:

```bash
printf 'plugins\n' | nc TARGET_IP 8080
```

```
ROKU_SERIAL (ROKU_TV - 15.3.4.2402)
> F-C + S M S6   58484  Roku Ads Library, 3.29.30
  ...
```

The command set (`help`) includes:

| Command | Capability |
|---|---|
| `plugins` | full plugin inventory, versions, ref counts, flags |
| `free` | RAM / swap totals and usage |
| `remove_plugin <id>` | uninstall a channel — **gated, see below** |
| `press <key>` / `type` | inject remote-control input = silent full control |
| `genkey` | mint a new developer signing key |
| `target [n]` | select which plugin the console is talking to |
| `r2d2_bitmaps` | home-screen telemetry, including tile/image hosts |

No authentication of any kind. No origin check. No rate limit.

**Why it is not rated high.** Installing code still requires the developer
password (Digest auth on `:80`). So `:8080` alone gives disclosure and input
injection — you can drive the TV and read everything it knows, but you cannot
persist a package. The initial high rating over-weighted LAN adjacency; the
correction is in [`08-engagement-record.md`](08-engagement-record.md) §4.

**What `remove_plugin` actually does.** This is the centrepiece negative result,
and it deserves its own section:

```
remove_plugin 794761   Innovid Ad Renderer        -> "Removed plugin id: 794761"
remove_plugin 820229   Roku Interactive Ads Lib   -> "Removed plugin id: 820229"
remove_plugin 751600   BrightLineLibrary          -> "Removed plugin id: 751600"
remove_plugin 54383    DFP Ad Service             -> "not removable"
remove_plugin 58484    Roku Ads Library           -> "not removable"
remove_plugin 155883   Grand Central              -> "not removable"
remove_plugin 98832    ACR Lib Channel            -> "not removable"
remove_plugin 686402   AcrAddon                   -> "not removable"
remove_plugin 109022   Roku Analytics Library     -> "not removable"
remove_plugin 55545    Roku City (ad screensaver) -> "not removable"
remove_plugin 687148   Welcome home to Roku City  -> "not removable"
remove_plugin 260537   Interactive Ads Library    -> "not removable"
remove_plugin 295059   Roku My Offers             -> "not removable"
remove_plugin 611444   Roku Microsite             -> "not removable"
remove_plugin 43508    Roku Content Player        -> "not removable"
remove_plugin 633458   Voice Help                 -> "not removable"
remove_plugin 194485   Roku Survey Channel        -> "not removable"
```

The three that said "Removed" **came back**: `plugins` still listed all three,
`[ref]` climbed `0 → 1`, and they survived standby → power-on. Re-issuing the same
command returns "Removed" again. It never sticks.

Measured effect: **zero.** Flash `193.8 MB → 193.7 MB`; RAM used
`415612 KB → 398104 KB` (cache noise, not debloat). Home screen healthy throughout.

The mechanism is server-side: those three are account-tied and re-provisioned on the
next home-screen render. `remove_plugin` reports what it did locally, not what the
account will permit.

---

## `tcp/8060` — ECP

A REST control protocol with no auth. This is *by design* — it is how the phone app
and every third-party remote work — but the consequence is that any LAN host can do
everything the remote can:

```bash
curl -s http://TARGET_IP:8060/query/device-info      # serial, MACs, advertising-id, firmware
curl -s http://TARGET_IP:8060/query/apps             # installed channel inventory
curl -s -X POST http://TARGET_IP:8060/keypress/Home  # inject any keypress
curl -s -X POST 'http://TARGET_IP:8060/launch/837'   # launch a channel
curl -s -X POST 'http://TARGET_IP:8060/launch/dev?contentId=…&mediaType=movie'  # launch dev channel with args
```

`/launch/dev` with arbitrary arguments is the interesting one: if a dev channel is
installed, an unauthenticated LAN peer can push content onto the screen unprompted.
That is a *feature* the sideloaded channel in [`apps/`](../apps/) depends on — and it is
exactly the kind of feature that becomes an exposure when developer mode stays on
after the project finishes.

Notably, `query/device-info` includes the **advertising-id**: a persistent tracking
identifier handed out in plaintext to anyone who asks.

A note on what ECP will *not* do: launching internal system channels returns `503`
or resets the connection, and the Settings app is not launchable by id (`/launch/-1`
→ `404`). ECP is a control surface, not a privilege boundary to cross.

---

## `tcp/8085` — the BrightScript Micro Debugger

Not listening in the ordinary state. It appears when a sideloaded channel **throws
an unhandled error** in developer mode: the runtime drops the app into an interactive
debugger and serves it on `8085`, unauthenticated, to whoever connects.

That gives a REPL which evaluates arbitrary BrightScript in the crashed channel's
context — `m`, `bt`, `print`, `exit`, and free-form expression evaluation. It is the
reliable foothold for everything in
[`04-brightscript-sandbox.md`](04-brightscript-sandbox.md), and it is why
[`tools/brs.py`](../tools/brs.py) exists: someone has to script a REPL over a raw
socket.

The trigger is cheap: a probe channel that crashes on purpose at a known line.

---

## `tcp/80` — the developer web server

Digest auth, realm `rokudev`, user `rokudev`. Serves the developer UI and the
`plugin_install` / `plugin_package` endpoints. This is the **real** gate on code
installation, and the reason `:8080` is not a persistence primitive.

The password is set interactively on the TV (Home ×3, Up ×2, Right, Left, Right,
Left, Right). [`tools/sideload-probe.sh`](../tools/sideload-probe.sh) stores it in
the macOS login keychain after a successful install so it is typed once — with an
honest note in its header about what that does and does not buy.

---

## `tcp/7000` — AirPlay / AirTunes

`nc TARGET_IP 7000` answers `HTTP/1.1 403 Forbidden` with
`Server: AirTunes/377.40.00`. This is a large native C++ stack, not BrightScript, so
the channel sandbox is irrelevant to it. Which is why it is ranked as an escape path
in [`05-escape-avenues.md`](05-escape-avenues.md) — and why its hardening matters.

Only `GET /info` answers unauthenticated:

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

`/pair-setup` answering `400` rather than `403` is the only crack of light: the
handler is alive and parses a body. Attacking a current Apple AirPlay 3.6 pairing
handshake is deep protocol research, not a quick win — but it is the one
unauthenticated *interaction* point on the box, and it is recorded as such.

---

## The gateway, observed

`GATEWAY_IP` owns DHCP and therefore DNS, and serves an administrative interface.
It is **not the author's equipment**. It was observed because the DNS path had to be
understood to make the sinkhole work, and the observation turned into an incidental
finding — documented in [`10-third-party-gateway.md`](10-third-party-gateway.md),
with no configuration change made and no credential attempted.

That boundary is the point of the exercise: the device was mine and I took it apart;
the gateway was not, so I read it and wrote a report.

---

## Summary

| Port | Service | Auth | Real capability |
|---|---|---|---|
| 80 | dev web server | Digest (`rokudev`) | install a package — the actual gate |
| 8060 | ECP | none | drive the UI, launch channels, read device-info |
| 8080 | debug terminal | none | read everything, inject input, `remove_plugin` (ineffective) |
| 8085 | BRS debugger | none | arbitrary BrightScript in a crashed channel |
| 7000 | AirPlay | per-endpoint | `/info` disclosure; pairing is the only live handler |

Three unauthenticated services is not a vulnerability report on its own — it is the
design of a LAN control protocol and a developer feature. It becomes one when
developer mode is left on after development stops. Which is why the last
recommendation in [`06-ad-suppression.md`](06-ad-suppression.md) is to turn it off.
