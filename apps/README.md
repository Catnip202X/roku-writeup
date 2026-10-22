# Apps — the sideloaded channels, and why they are not mirrored here

The two channels mentioned throughout this writeup are **one project**, and its source
lives in its own repository:

> ### → **[github.com/Catnip202X/biliku](https://github.com/Catnip202X/biliku)**
> Biliku — 云屏 / 云听小电视 · an unofficial Bilibili client for Roku TVs, with a
> companion that installs it and lets the phone app cast to the TV. MIT.

This directory is a pointer, not a copy. Duplicating ~4 MB of app source (mostly a CJK
font) into a writeup repository would mean two diverging copies of the same code, and
the writeup does not need to ship the app to make its point. Follow the link.

---

## Why the app matters to this writeup at all

The probe results in [`../docs/04-brightscript-sandbox.md`](../docs/04-brightscript-sandbox.md)
only mean something in the context of **what a channel is allowed to legitimately
do**. A sandbox test run from a stripped-down harness proves what the harness can
reach; run from a real app with real UI, real network tasks, a local server and a
phone-casting companion, it proves what a *real channel* hits.

Biliku is that real channel. Three specifics from its design show up as evidence:

| In the app | Why it mattered here |
|---|---|
| Network work runs on the **TASK thread** (`ApiTask`), UI state on MAIN | This is the thread distinction that produced the `roHtmlWidget` false negative. Working code that partitions correctly is the reference for what "wrong thread" looks like |
| A **local manifest server** listens on a port inside the channel | The clearest demonstration of the sandbox's actual shape: a channel can bind locally and still cannot write `common:/` |
| The **companion** discovers the TV by SSDP and drives it over ECP | This is why developer mode was on. Every exposure in [`../docs/02-attack-surface.md`](../docs/02-attack-surface.md) exists because an owner wanted to run this app — that is the trade the whole writeup is about |

And the app's name is in the evidence: the plugin inventory lists the dev slot as
`云听小电视, 1.0.1` under the `dev` package id — the earlier name for the same
project, which is why [`../evidence/plugin-inventory.txt`](../evidence/plugin-inventory.txt)
and the app repository use different labels for one thing.

## One consequence worth stating plainly

**Roku allows exactly one sideloaded channel.** Installing a second app does not add a
second app — it removes the first. That constraint is why the app and the probes could
never be installed at the same time, and why every probe run started by replacing the
app in that slot. The workaround for it lives in
[`../tools/hub/`](../tools/hub/) — namespacing several apps' components into one
package behind a launcher menu.

It is also why the sandbox testing happened against this app's own code paths rather
than a purpose-built harness standing next to it: there was no room for both.

## What is not published here, and why

- **No app source.** It is in the repository above, under its own licence and its own
  release process. Mirrored copies rot.
- **No compiled `.zip`.** Reproducible from the source with `scripts/package_roku.py`
  in that repo.
- **No `cast-log.txt`.** It is a debug log of cast sessions, and every line embeds a
  signed CDN URL carrying a `buvid` device fingerprint plus per-session `upsig` /
  `hmac` signatures. Time-limited credentials — excluded rather than scrubbed,
  because scrubbing them leaves nothing.
- **No account credential.** The QR-login flow stores its result on the TV, and the
  engagement record is explicit that the registry section holding it was found and
  **not read** ([`../docs/08-engagement-record.md`](../docs/08-engagement-record.md) §3).

Sanitisation of everything that *is* published is described in
[`../SANITISATION.md`](../SANITISATION.md); two of the tools in that app repository's
`tools/` directory used to hardcode the TV's LAN address as a default, and are cited
there as an example of the class of leak a writeup repo has to catch.
