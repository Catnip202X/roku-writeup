# Sanitisation policy

This repository is derived from a working directory that contained a real device's
identifiers. Everything published here has been rewritten to placeholders. This
file records what that means, so nobody has to guess.

## The rule

**No value that identifies a specific device, network, or person is published.**
Where a value matters to the argument, it is replaced by a *stable, semantic*
placeholder rather than deleted, so the technical content survives.

| Class | Placeholder |
|---|---|
| Roku serial number | `ROKU_SERIAL` |
| Roku ECP device id | `ROKU_DEVICE_ID` |
| Roku UDN | `ROKU_UDN` |
| Advertising id | `ADVERTISING_ID` |
| Per-device channel client id | `CLIENT_ID` |
| AirPlay serial / device id | `AIRPLAY_SERIAL`, `AIRPLAY_DEVICE_ID` |
| Display UUID | `DISPLAY_UUID` |
| Device MAC addresses | `ETHERNET_MAC`, `WIFI_MAC`, `BLUETOOTH_MAC` |
| MAC OUI prefix | `MAC_OUI` |
| Any MAC not enumerated above | `MAC_ADDR` |
| TV's LAN address | `TARGET_IP` |
| Gateway's LAN address | `GATEWAY_IP` |
| Host machine LAN addresses | `HOST_IP_EN0`, `HOST_IP_EN1` |
| Any other RFC1918 address | `LAN_IP` |
| Public egress address | `PUBLIC_IP` |
| Device display name | `ROKU_TV` |
| Device location string | `ROOM` |
| ISP DHCP domain suffix | `ISP_DOMAIN` |
| Local account / home path | `USER`, `USER_MACHINE` |
| Workspace directory name | `WORKSPACE` |
| Streaming-service device fingerprints | `BUVID`, `BILIBILI_UID` |

## How it is enforced

`scripts/sanitize.py` runs the mapping, then **re-runs the scan on its own output**
and exits non-zero if anything is still replaceable. The check is a pre-push gate,
not a convention:

```bash
python3 scripts/sanitize.py --scan || { echo "dirty, refusing to push"; exit 1; }
```

Two layers:

1. **Literal table** — `redactions.local.txt`, git-ignored. Longest-first so a
   full MAC is caught before the bare OUI, a full UUID before its prefix.
2. **Structural patterns** — applied always, regardless of the table: any RFC1918
   address, any MAC in either case, any `/Users/USER` path, and the fingerprint
   query parameters that appear in captured streaming URLs (`buvid=`, `mid=`,
   `upsig=`, `trid=`, `hmac=`, `oi=`, `deadline=`).

The table is deliberately outside the repo. If it were committed, the repository
would contain exactly the strings it exists to hide, and a `git log` would keep
them there forever.

## What was not published at all

Not scrubbed — excluded, because scrubbing them would leave nothing useful:

| Excluded | Why |
|---|---|
| App source (`biliku` / 云听小电视) | Its own repository, its own licence, its own release process. A writeup does not need to ship 4 MB of app code to make its point, and a mirrored copy rots. Linked from [`apps/`](apps/). |
| `cast-log.txt` | Signed Bilibili CDN URLs. Each embeds a `buvid` device fingerprint plus per-session `upsig` / `hmac` signatures. Time-limited, but they are live credentials for the length of their window. |
| `loot/` beacon captures | Operator-side loopback test traffic; no analytical value, non-zero fingerprint value. |
| Compiled `.zip` channel packages | Reproducible from `probes/` and `tools/`; binaries would just be unreviewable blobs. |
| Keychain material | The sideload tool's stored developer password never had a plaintext form in the workspace. `tools/sideload-probe.sh` shows the Keychain calls; the item itself stays on the machine. |
| Registry secret values | `roRegistrySection("auth")` returned key names `("buvid","cookie")` and the values were deliberately never read. Recorded as existence only. |

## One deliberate exception

The **local** account name is scrubbed to `USER`, and every absolute home path is
rewritten so the account segment becomes `USER` — that is a home-directory leak.

The **GitHub handle** is not scrubbed. It is public the moment the repository is: it is
in the clone URL, in the commit metadata, and in the one outbound link this directory
exists to make ([`apps/`](apps/) → the app lives in its own repo). Scrubbing it out of
the prose while `github.com/<handle>/roku-writeup` sits in the remote would be theatre,
and would break the useful link to buy nothing.

The distinction is worth keeping sharp: this repo's claim is that no **device or
network identifier** is published. It is not a claim that the author is anonymous —
which a public git repository cannot offer anyway.

## A leak class this repo caught in practice

The streaming client's helper scripts — `install.sh`, `send-to-tv.sh`, the cast bridge
— each defaulted to the TV's LAN address, so the same device fingerprint appeared in
four files and in a README. That is the ordinary shape of this leak: not one secret in
one place, but an operational convenience repeated wherever it saved typing.

The four scripts now read `ROKU_IP` with `TARGET_IP` as the documented placeholder.
Anything you publish about your own hardware will have the same pattern — check the
defaults, not just the documents.

## What the placeholder scheme gives up

- **Cross-referenceable OUI.** Replacing `MAC_OUI` with `MAC_OUI` hides the
  vendor (Roku's own OUI). That is intentional: publishing "the TV has a Roku OUI"
  adds nothing to the argument and narrows the device fingerprint.
- **LAN topology.** `TARGET_IP` → `TARGET_IP` and `GATEWAY_IP` →
  `GATEWAY_IP` keeps the *relationship* (same /24, gateway is `.254`) while
  removing the addresses. The relationship is the technical content.
- **Absolute dates of capture** are kept. They are needed to reason about firmware
  recency (OS 15.3.4, built 2026-09-07) and reveal nothing about a person.
