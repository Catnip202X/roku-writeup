# Evidence

Captured output from the device, scrubbed. This is the primary source the writeup
cites, kept so the claims can be checked rather than trusted.

| File | Source | What it establishes |
|---|---|---|
| [`device-info.xml`](device-info.xml) | `GET /query/device-info` on ECP (`tcp/8060`) | model, firmware, plugin-relevant flags, developer mode state — the whole identity surface, unauthenticated |
| [`apps.xml`](apps.xml) | `GET /query/apps` on ECP | installed channel inventory, again unauthenticated |
| [`plugin-inventory.txt`](plugin-inventory.txt) | `plugins` on the debug console (`tcp/8080`) | the 54-plugin list with ids, versions, ref counts and flags — the evidence for every ad/ACR entry in [`../docs/03-findings.md`](../docs/03-findings.md) |
| [`airplay-info.json`](airplay-info.json) | `GET /info` on AirPlay (`tcp:7000`), bplist converted to JSON | the richest unauthenticated device description: AirPlay SDK, FairPlay version, display capability tree, feature bitmask |
| [`airplay-info.plist`](airplay-info.plist) | the same response as a **binary plist**, regenerated from the scrubbed JSON | the wire format, for anyone who wants to diff against their own device |

## How to recapture your own

```bash
curl -s http://TARGET_IP:8060/query/device-info > device-info.xml
curl -s http://TARGET_IP:8060/query/apps        > apps.xml
printf 'plugins\n' | nc TARGET_IP 8080          > plugin-inventory.txt

# AirPlay /info is a binary plist; request it raw, then convert to JSON for reading
printf 'GET /info HTTP/1.1\r\nHost: TARGET_IP\r\n\r\n' | nc TARGET_IP 7000 > airplay-info.raw
plutil -convert xml1 -o - airplay-info.raw        # or: python3 -m plistlib ...
```

Capture these **before** changing anything. On this engagement that baseline is what
made it possible to state "measured effect: zero" for `remove_plugin` instead of
relying on an impression
([`../docs/02-attack-surface.md`](../docs/02-attack-surface.md)).

## Why these are safe to publish

Every one is device metadata, not credential material:

- **Serial numbers, MACs, advertising id, UDNs, UUIDs** → replaced with placeholders
  by [`../scripts/sanitize.py`](../scripts/sanitize.py)
  ([`../SANITISATION.md`](../SANITISATION.md)).
- **Plugin ids and versions** are public Roku package identifiers and are the
  technical content; they stay.
- **No credential, cookie, token or registry value** is in any file here. The one
  registry section that held a login was found by key name only and never read —
  recorded in [`../docs/08-engagement-record.md`](../docs/08-engagement-record.md) §3.

## What was deliberately left out

| Omitted | Why |
|---|---|
| Beacon captures from the local collector | Operator-side loopback test traffic; no analytical value, non-zero fingerprint value |
| The `:8080` `free` output | Memory numbers are quoted inline where they matter; the raw capture adds a timestamp and nothing else |
| Signed streaming-CDN URLs from the client debug log | Live, time-limited signatures plus a device fingerprint — excluded rather than scrubbed |

## A note on the plugin inventory format

Two columns in `plugin-inventory.txt` do most of the work and are worth reading:

- **`[ref N]`** — reference count. This is the number that moved `0 → 1` after
  `remove_plugin`, and then stayed, which is how "the plugin came back" was
  established as fact rather than suspicion.
- **`cmpl` / `*`** — compaction and pinned state. `Roku Ads Library` and
  `Grand Central` both carry `cmpl` and high ref counts, which is consistent with
  being flag-locked into the home-screen render path.

The two trailing lines give **flash space** (`193.8 MB` available) and **allowed
plugin space** (`379.5 MB`) — the pair you compare before and after any removal
attempt. On this TV they did not move, which is the whole negative result in two
numbers.

## Note on the binary plist

The raw `/info` capture contained the device's identifiers as length-prefixed binary
plist strings, so it could not be text-scrubbed — changing a string in a binary plist
invalidates the enclosing offsets. It was therefore **regenerated from the scrubbed
JSON** with `plistlib`, which yields a valid binary plist with the placeholders in
place. Delete it and recapture from your own device if you want the genuine wire
format; the shipped file is for structure, not for byte comparison.
