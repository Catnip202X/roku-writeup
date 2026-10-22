# Scope, authorisation, and what this repository is not

## What this is

A security assessment of **one Roku TV, owned by the author, on the author's own home
network**, performed to answer a specific question: *can the owner of a Roku TV
remove the platform's advertising and telemetry?*

The answer is no — not from the device — and the reason is the interesting part. See
[`docs/03-findings.md`](docs/03-findings.md) for the findings and
[`docs/07-negative-results.md`](docs/07-negative-results.md) for the nine things that
did not work.

## What this is not

- **Not a jailbreak.** There is no exploit chain here. The BrightScript sandbox held
  on every axis tested; that is the result, not a step in a longer chain.
- **Not a piracy tool.** The app referenced in [`apps/`](apps/) is a client for a
  service that offers free, ad-supported streaming. It does not circumvent DRM,
  break paywalls, or unlock paid tiers.
- **Not a vulnerability disclosure about Roku you can act on from the internet.**
  Every finding requires either LAN adjacency or developer mode already enabled by
  the owner. None is remotely exploitable.
- **Not advice to change equipment you do not own.** The one finding about third-party
  equipment is a report, made to the vendor, with no configuration changed
  ([`docs/10-third-party-gateway.md`](docs/10-third-party-gateway.md)).

## Authorisation

| Field | Value |
|---|---|
| Operator | Device owner (self) |
| Target | One Roku TV, `TARGET_IP` |
| Basis | Self-owned hardware, personal home network |
| Written authorisation | Not applicable — the owner is the operator |
| Third-party systems | Observed only, never modified, findings routed to the vendor |

The full filled-in record, including the rules that were followed and the two severity
ratings that were revised downward, is
[`docs/08-engagement-record.md`](docs/08-engagement-record.md). The blank template that
produced it is [`docs/09-engagement-template.md`](docs/09-engagement-template.md).

## Rules of engagement applied

- Read-only verification first; state changes only when the owner asks.
- No persistent changes left behind; anything created was logged and reverted.
- Destructive or irreversible actions require explicit per-action approval. The
  secret-screen menu — which contains **factory reset** — was walked one key at a
  time, never fuzzed, never automated.
- **No credential, token or personal data captured.** Where a secret was discovered,
  the record says it exists and not what it is. The engagement record names
  `roRegistrySection("auth")` key names `("buvid","cookie")` and states that the
  values were never read.
- Stop and confirm if a finding implies a wider blast radius than the scope covers.
  Ad blocking was **abandoned** rather than achieved by changing shared DNS
  infrastructure on equipment the operator does not own.

## Not tested

- Denial of service or load testing
- Social engineering
- Data exfiltration beyond the minimum needed to prove a finding
- Physical access — UART, SPI, JTAG, chip-off
- Anything on a network other than the author's own

## Reporting a problem with this repository

If you find something published here that still identifies a device or a person, that
is a sanitisation failure and it should be treated as a bug. Open an issue describing
the class of identifier (not the value), or contact the author privately.

The rewrite is mechanical and re-runnable — [`SANITISATION.md`](SANITISATION.md)
documents the scheme, and [`scripts/sanitize.py`](scripts/sanitize.py) is the gate.

## Licence

MIT — see [`LICENSE`](LICENSE). Use the tools, the blocklist, the probes and the
method. Re-point them at hardware you own.
