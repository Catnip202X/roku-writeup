# 06 — Ad suppression that actually works

`remove_plugin` measured at zero effect ([`02-attack-surface.md`](02-attack-surface.md)).
So the platform's ad engine stays. What you *can* do is stop it from talking to
anything, and turn off the four switches it depends on.

Two mechanisms, both enforced **outside the device**, because nothing inside it is
writable.

---

## 6a. DNS sinkhole — tested, running

[`tools/sinkhole.py`](../tools/sinkhole.py) is a dependency-free DNS server (stdlib
only, no `pip install`) in blocklist or allowlist mode.
[`blocklist/roku-blocklist.txt`](../blocklist/roku-blocklist.txt) is the data: 52
lines, and **every domain cites the plugin observed on this TV that talks to it**.

```bash
cd roku-writeup
sudo ./tools/sinkhole.py --listen 0.0.0.0 --port 53 --upstream 1.1.1.1
```

### The one design decision that makes it work

The sinkhole must **answer `0.0.0.0`**, not blackhole.

`roDeviceInfo.GetConnectionInfo()` on this TV returns
`dns.0 GATEWAY_IP`, `dns.1 8.8.8.8`, `dns.2 8.8.4.4`. With public resolvers in the
fallback chain, a blackholed query makes the TV fall through to Google — and the ads
come back. Answering `0.0.0.0` gives an immediate, authoritative-looking negative,
so there is nothing to fall through to.

That detail was extracted from a probe, not from a guide, and it is the difference
between a sinkhole and a placebo.

### Verified behaviour

```
ads.roku.com                      -> 0.0.0.0
display.ravm.tv                   -> 0.0.0.0
googleads.g.doubleclick.net       -> 0.0.0.0
securepubads.g.doubleclick.net     -> 0.0.0.0
innovid.com                       -> 0.0.0.0
ads.ravm.tv                       -> 0.0.0.0
cooper.logs.roku.com              -> 0.0.0.0
tracker.sr.roku.com               -> 0.0.0.0
ad.moatads.com                    -> 0.0.0.0
roku.com                          -> 162.159.136.11   (forwarded, untouched)
image.roku.com                    -> d1ohvx6nln6ht.cloudfront.net.
www.netflix.com                   -> ftl-www.netflix.com.
```

Note the last three: the sinkhole forwards rather than blocks when a domain is
allowlisted or not listed. That matters — a DNS blocklist that is too aggressive
breaks channel installation.

`cloudservices.roku.com` is deliberately **commented out** in the blocklist: it
serves channel install/update manifests as well as ads. Enabling it blocks new
installs. Left as a documented choice rather than a surprise.

### Making the TV use it

**Roku has no DNS field anywhere in its UI** — not on Ethernet either. So it has to
come from DHCP on the gateway at `GATEWAY_IP`:

1. Log into the gateway as admin.
2. LAN / DHCP settings → **DNS server / Primary DNS** → this machine's LAN address
   (`HOST_IP_EN0` on `en0`, `HOST_IP_EN1` on `en1` — use whichever is on the same
   segment as the TV).
3. Give this machine a DHCP reservation so the address never moves.
4. On the TV: `Settings → System → Power → System restart`, or unplug it.

> That step changes shared infrastructure. On this network the gateway is not the
> author's equipment, so it was **not** changed — see
> [`10-third-party-gateway.md`](10-third-party-gateway.md). The sinkhole is verified
> locally; the DHCP re-point is documented, not performed.

**Proof it is working.** The sinkhole logs a `BLOCK` line per query. Once the TV
picks up the new DNS you see hits sourced from `TARGET_IP`:

```bash
sudo ./tools/sinkhole.py --port 53 --upstream 1.1.1.1 | grep --line-buffered TARGET_IP
```

If nothing from `TARGET_IP` appears within a minute of a reboot, the TV is still on
the old resolver — check the DHCP change and this machine's firewall, in that order.

### For a permanent setup

Do not run this on a laptop. Run **AdGuard Home** or **Pi-hole** with
`roku-blocklist.txt` as a custom list. Same DHCP change, and the laptop is free.
`tools/sinkhole.py` exists to establish the behaviour and to be readable, not to be
production infrastructure.

---

## 6b. The four toggles

The Settings app is not launchable by ECP id (`/launch/-1` → `404`) and its
SceneGraph is not inspectable (`sgnodes` → `Channel access not authorized`). So these
are four paths on the remote, about 60 seconds total:

| Goal | Path | Set to |
|---|---|---|
| Kill ACR / viewing fingerprinting | `Settings → Privacy → Smart TV experience → Use info from TV inputs` | **Off** |
| Kill ad targeting | `Settings → Privacy → Advertising → Limit ad tracking` | **On** |
| Kill Roku City billboard ads | `Settings → System → Screen saver` | **Digital Clock** (or `4K Screensaver`), and raise the wait time |
| Kill seasonal promo takeover | `Settings → Home screen → Theme` | any static theme, not a "featured" one |

The ACR toggle is the one that matters most. `ACR Lib Channel` and `AcrAddon` cannot
be removed and cannot be reached from a channel — but the *feature* they implement
has an owner-facing switch, and that switch is the only control over content
fingerprinting on the box.

---

## 6c. Close the hole when you are done

Two settings, and they undo most of what
[`02-attack-surface.md`](02-attack-surface.md) describes:

- `Settings → System → Advanced system settings → Control by mobile apps → Network
  access` → **Limited**. This is the ECP/kepress exposure.
- **Turn developer mode off** if you no longer need the sideloaded app. That closes
  `:8080`, `:8085` and `:80` — and removes the sideloaded channel, since 15.x allows
  exactly one dev app.

The honest framing: developer mode is a **trust decision**, not a hardening feature.
Leaving it on after the project is the single largest exposure on the box, and it is
the one entirely within the owner's control.

---

## 7. Honest limits

- Home-screen banner and "Sponsored" tiles survive until DNS blocking is in place.
  The plugins that serve them (`Roku Ads Library`, `Grand Central`) are flag-locked
  and cannot be removed.
- In-channel ads (YouTube and friends) come from the channel's own CDN. DNS hurts
  some of them and breaks none of the trusted ones on this box. YouTube ads need a
  different client, not a network block.
- The `:8080` console is the best research foothold here, but it is not a jailbreak.
  It cannot reflash the OS, replace the launcher, or delete a protected plugin.
- Nothing in this document modifies the OS. Rollback for the whole thing is
  `Settings → System → Advanced system settings → Factory reset`, plus restoring the
  `evidence/` baseline if you want the diff.

## 8. Rollback

Nothing in this runbook is destructive. If the TV misbehaves:

```
Settings → System → Advanced system settings → Factory reset
```

That restores every plugin and clears the DHCP/DNS experiment. Keep
[`evidence/`](../evidence/) — the pre-change snapshot — so you can prove what
changed and when.
