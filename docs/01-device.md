# 01 — The device

A mid-range 50" Roku TV, US region, wired, on a home LAN. Everything in this
section came from the TV itself, over ECP and AirPlay, before any write was
attempted.

## Identity, as reported

| Field | Value |
|---|---|
| Display name | `ROKU_TV` (location `ROOM`) |
| Model | Roku TV **50R4CX** / `L816X`, 50", 1080p panel |
| Region | US (`ATSC` tuner, `US/Eastern`) |
| Roku OS | **15.3.4**, build **2402**, `HXG.34E02402A` |
| Grand Central | 26.42.12 |
| AirPlay | `AirPlay;3.6.0.126`, firmware revision `15.34.2402`, built 2026-09-07 |
| FairPlay | `fairplay-4.9.21` |
| Cobalt | `cobaltlib 2.26.14` |
| Widevine / FairPlay libs | `libwidevine 1.0.1287`, `libfairplay 1.0.133` |
| Bundled browser | `Roku Browser 104.11.33` (Chromium 104) |
| Link | Ethernet, `network-type: ethernet` |
| Developer mode | **already enabled** (`developer-enabled: true`) |
| ECP | `ecp-setting-mode: enabled` |
| Endpoint | `http://TARGET_IP:8060` |

Raw capture: [`evidence/device-info.xml`](../evidence/device-info.xml) (scrubbed).

## Why this device is the interesting one

Two properties make it worth assessing rather than just configuring:

1. **Developer mode is on.** Which means `tcp/8080` and `tcp/80` are listening,
   and the single sideloaded-channel slot is in use. That is the trust decision
   this whole writeup is really about.
2. **The firmware is current.** OS 15.3.4.2402 with an AirPlay subsystem built
   within the month. Any conclusion here is a conclusion about 2026 Roku, not
   about a stale 2022 build someone left in a drawer.

## The plugin inventory — 54 entries

The dev console's `plugins` command returns the full list. What matters is how
much of it is monetisation:

### Ad stack

| Plugin | Id | Role |
|---|---|---|
| Roku Ads Library 3.29.30 | `58484` | ad SDK |
| Grand Central 26.42.12 | `155883` | Roku's ad/identity orchestrator |
| DFP Ad Service 2.2.2 | `54383` | Google DoubleClick for Publishers |
| Innovid Ad Renderer 1.1.43 | `794761` | video / interactive ads |
| Interactive Ads Library 3.75.2 | `260537` | ad templates |
| Roku Interactive Ads Library 1.1.9 | `820229` | ad templates |
| BrightLineLibrary 3.6.10 | `751600` | interactive TV ads |
| Roku My Offers 8.0.3 | `295059` | offer placements |
| Roku Microsite 1.51.0 | `611444` | ad landing pages |
| Roku Content Player 1.6.10 | `43508` | ad / content playback |

### Spyware

| Plugin | Id | Role |
|---|---|---|
| ACR Lib Channel 8.0.12 | `98832` | **content fingerprinting** |
| AcrAddon 10.3.3 | `686402` | **content fingerprinting** |
| Roku Analytics Library 1.5.1003 | `109022` | telemetry |

ACR is Automatic Content Recognition: it fingerprints what is on screen — including
from an HDMI input — and reports it. This is the component worth actually caring
about, and it is not removable.

### Ad-bearing screensavers

| Plugin | Id |
|---|---|
| Roku City ™ 7.3.102 | `55545` |
| Welcome home to Roku City™ 2.2.0 | `687148` |

The neutral replacements are already installed and free to select: `Digital Clock`
(`5533`), `Analog Clock` (`5534`), `4K Screensaver` (`72728`), `Logo Rain`
(`278897`).

### Everything else

Store channels the owner installed (Apple TV, YouTube, Playlet, Spotify Music) and
the single sideloaded developer app. `Roku Dynamic Menu` (`562859`) is the home
screen; it stayed healthy throughout every experiment below.

Full inventory: [`evidence/plugin-inventory.txt`](../evidence/plugin-inventory.txt).

## What the AirPlay `/info` endpoint gives away

`GET /info` on `tcp/7000` is the one unauthenticated AirPlay endpoint and it returns
a 1825-byte binary plist — the single richest unauthenticated description of the
device available:

- exact model (`L816X`), hardware revision (`PVT1`), firmware build date
- AirPlay SDK version and `sourceVersion 377.40.00`
- FairPlay CDM plugin and library versions
- the display tree: max resolution, HDR capability (`HDR10`, `4k60`), refresh rate,
  and a per-display UUID
- AirPlay serial and device id, plus the user-visible device name
- a feature bitmask; `0x038bcf46007f8ad0` decodes to `SupportsAirPlay` (49),
  Photo (51), **Mirroring (55)**, screen-rotate (56/57), `VideoHTTPLiveStreams` (4),
  Audio (6)

That is a fingerprinting surface, and it is rated `low` rather than medium because
it is a documented protocol feature reachable only from the same LAN. Worth
recording anyway — it is the reason the escape-path analysis below treats AirPlay
as a native attack surface rather than a BrightScript one.

Raw capture: [`evidence/airplay-info.json`](../evidence/airplay-info.json) (scrubbed).

## Snapshot discipline

`evidence/` is the pre-change baseline. Before touching anything, capture:

```bash
curl -s http://TARGET_IP:8060/query/device-info > evidence/device-info.xml
curl -s http://TARGET_IP:8060/query/apps        > evidence/apps.xml
printf 'plugins\n' | nc TARGET_IP 8080          > evidence/plugin-inventory.txt
```

Everything in this writeup is reversible — the OS is never modified — but a
baseline is what lets you *prove* that afterwards, and it is what you diff against
when the home screen starts behaving oddly three weeks later.
