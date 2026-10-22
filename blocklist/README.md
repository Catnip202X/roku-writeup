# Blocklist

Two lists, one purpose: stop the TV talking to the monetisation stack, without
breaking the channels the owner actually uses.

| File | Lines | What it is |
|---|---|---|
| [`roku-blocklist.txt`](roku-blocklist.txt) | 52 | Roku ad / telemetry / analytics domains, **each entry citing the plugin observed on this TV that talks to it** |
| [`bilibili-allowlist.txt`](bilibili-allowlist.txt) | 38 | the streaming client's own domains — the allowlist half of a default-deny posture |

Format: one domain per line, `#` starts a comment, wildcards as `*.example.com`. Feed
it to Pi-hole, AdGuard Home, dnsmasq or Unbound as a custom list.

## Why each line cites a plugin

A blocklist copied from the internet is a guess about someone else's TV. Every entry
here was matched to a plugin in *this* device's own `plugins` inventory, so the
provenance is checkable:

```
# Evidence: "Roku Ads Library, 3.29.30" (58484), "Grand Central, 26.42.12" (155883)
ads.roku.com
advertising.roku.com
ads.ravm.tv
display.ravm.tv
```

That convention is the most useful thing in this directory. It means you can re-derive
the whole list for your own device instead of trusting mine — inventory your plugins,
then look at what they call.

## Why `cloudservices.roku.com` is commented out

It serves channel **install and update manifests** as well as ads. Enabling it blocks
new installs. It is commented out, with the reason next to it, because a blocklist
that quietly breaks the device is a blocklist that gets abandoned — and an unexplained
outage is worse than a documented gap.

## The implementation detail that decides success

**The sinkhole must answer `0.0.0.0`, not blackhole.**

This TV resolves via `GATEWAY_IP` with `8.8.8.8` and `8.8.4.4` in its fallback chain
(read out of `roDeviceInfo.GetConnectionInfo()`). A blackholed query makes the TV fall
through to Google — and the ads come back. Answering `0.0.0.0` gives an immediate,
authoritative-looking negative with nothing behind it to fall through to.

That is the difference between this working and this being a placebo. The mechanism,
the verified responses and the DHCP steps are in
[`../docs/06-ad-suppression.md`](../docs/06-ad-suppression.md).

## What is in the list

| Tier | Domains | Serving plugin |
|---|---|---|
| Roku ad SDK | `ads.roku.com`, `advertising.roku.com`, `ads.ravm.tv`, `display.ravm.tv` | Roku Ads Library `58484`, Grand Central `155883` |
| Home-screen tile art | `images.sr.roku.com` | console `r2d2_bitmaps` — the image-resizing service behind sponsored tiles |
| Google DFP | `googleads.g.doubleclick.net`, `securepubads.g.doubleclick.net`, `pubads.g.doubleclick.net` | DFP Ad Service `54383` |
| Interactive ads | `innovid.com`, `*.innovid.com`, `brightline.tv`, `*.brightline.tv`, `interactive.ads.roku.com` | Innovid `794761`, BrightLine `751600`, Interactive Ads `260537` / `820229` |
| Ad measurement | `*.moatads.com` and friends | ad-verification vendors Roku traffic is routed to |
| Telemetry | `cooper.logs.roku.com`, `tracker.sr.roku.com` | Roku Analytics Library `109022` |
| ACR | entries tied to `98832` / `686402` | ACR Lib Channel, AcrAddon |

The ACR rows matter most. Those two plugins cannot be removed
([`../docs/03-findings.md`](../docs/03-findings.md)) and cannot be reached from a
channel ([`../docs/04-brightscript-sandbox.md`](../docs/04-brightscript-sandbox.md)),
so the network edge plus the owner-facing toggle in
[`../docs/06-ad-suppression.md`](../docs/06-ad-suppression.md) §6b are the only two
levers that exist.

## What it does not fix

- **In-channel ads.** YouTube and friends serve from their own CDNs. Blocking the
  channel's own domains breaks the channel. Different client, not a network block.
- **Home-screen banner tiles, until the DNS change lands.** The plugins that serve
  them (`Roku Ads Library`, `Grand Central`) are flag-locked, so the network is the
  only interception point.
- **Anything, on a TV that keeps resolving through the ISP.** Verify with the sinkhole
  log: you want to see `BLOCK` lines sourced from `TARGET_IP`.

## Re-deriving it for your own device

```bash
printf 'plugins\n' | nc YOUR_ROKU_IP 8080          # inventory: ids, names, versions
python3 ../tools/collector.py --port 8899          # watch what the TV asks for
sudo ../tools/sinkhole.py --port 53 --upstream 1.1.1.1   # add what you see, cite the plugin
```

Then reconcile: every blocked domain should name a plugin you can see in your own
inventory. If it does not, you are pasting someone else's list.
