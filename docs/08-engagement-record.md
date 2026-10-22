# 08 — Engagement record

**Status:** complete · **Date:** 2026-10-22 · **Operator:** device owner

This is a worked example of the template in
[`09-engagement-template.md`](09-engagement-template.md), filled in *after* the
engagement. It is kept as a reference for what a documented engagement looks like,
including the parts that went wrong and the parts that were deliberately not done.

---

## 1. Authorization basis

| Field | Value |
|---|---|
| Operator | Device owner (self) |
| Target | Roku TV `ROKU_TV`, `TARGET_IP` (50R4CX / L816X, OS 15.3.4.2402, `ROKU_SERIAL`) |
| Owner of the target | The operator |
| Basis | Self-owned hardware, personal home network |
| Written authorization | Not applicable — owner is the operator |
| Adjacent third-party system | Home gateway `GATEWAY_IP` (ISP-supplied, **not owned by the operator**) |

## 2. Scope

**In scope:** the Roku TV only — its network services, its developer interfaces, its
own sandbox and installed components.

**Out of scope and honoured:**

- The ISP gateway was **observed only**. No configuration change was made, no
  credential was attempted, no exploitation was performed. Findings were routed to
  the owner as a written report.
- No denial-of-service testing. No social engineering. No data exfiltration.

## 3. Rules of engagement — what was actually done

| Rule | Applied |
|---|---|
| Read-only first | Yes — every probe before any write attempt |
| No persistent changes | Write probes targeted `tmp:` / `cachefs:` scratch files and a `common:/` path that was denied; console `target` restored to `[0] main` |
| Destructive actions need per-action approval | The secret-screen menu was **never navigated blind** — keys were injected one at a time with the owner watching, because that menu contains factory reset |
| Secrets never recorded | `roRegistrySection("auth").GetKeyList()` returned `("buvid","cookie")`. **Key names recorded, values never read.** |
| Stop if blast radius exceeds scope | Ad blocking was abandoned rather than achieved by changing shared infrastructure |

## 4. Findings summary

| # | Finding | Severity | Asset |
|---|---|---|---|
| 1 | Unauthenticated BrightScript debug terminal `tcp/8080` | high → **revised** low-medium | TV |
| 2 | Unauthenticated ECP keypress injection `tcp/8060` | medium | TV |
| 3 | Unauthenticated BrightScript REPL `tcp/8085` on channel crash | high (dev-mode gated) | TV |
| 4 | Registry remanence across dev-app replacement | medium → **not a boundary violation** | TV |
| 5 | AirPlay `/info` discloses real model, firmware, FairPlay version | low | TV |
| 6 | **ISP gateway: unauthenticated writable admin on LAN (CWE-306)** | high, LAN-scoped | gateway (third party) |

### Severity revisions — both in the operator's favour to record

- Finding 1 was initially rated **high**. Reassessed to **low-medium** after
  establishing that the dev password independently gates code installation, so the
  guaranteed capability is disclosure and input injection, not persistence. The
  original rating over-weighted a LAN-local exposure.
- Finding 4 was initially framed as a credential leak. On review it requires the dev
  password to reach, so the attacker already holds equivalent privilege. Recorded as
  a design property, not a vulnerability.

Recording these corrections is part of the job. An engagement record with no
revisions is usually an engagement record that wasn't reviewed.

## 5. Negative results — the majority of the work

| Avenue | Result |
|---|---|
| Ad-plugin removal via `remove_plugin` | ineffective — re-provisioned by the account |
| BrightScript fs write to `common:/`, absolute paths | denied |
| System registry sections | not visible to a channel |
| `roHtmlWidget` → Chromium 104 | class absent, both threads |
| `roNetworkConfiguration` | class absent |
| Console `target` privilege shift | no effect — independent ACL |
| ECP launch of internal system channels | 503 / connection reset |
| Secret screen / commercial mode | absent after three attempts, two injection paths |
| Volume alias into `/nvram/` | only four volumes exist |

Full detail: [`07-negative-results.md`](07-negative-results.md).

**Conclusion recorded:** the BrightScript attack surface on OS 15.3.4 is closed for a
sideloaded channel. Remaining risk is native and network-reachable (AirPlay, DRM,
Cobalt) or physical (UART/SPI) — neither attempted here.

## 6. Disclosure status

| Finding | Routed to | Status |
|---|---|---|
| Roku TV findings | Roku (if filed) | not yet filed — expected disposition: informative, as all require developer mode plus LAN access |
| Gateway CWE-306 | ISP bug bounty program | **submitted 2026-10-22**, awaiting triage |
| Gateway CWE-306 (fallback) | CERT/CC coordination | coordination request drafted; submission now carries a vendor-contact date and report ID |

## 7. What this record demonstrates

- Scope was declared and the out-of-scope third-party system was **not touched**,
  despite being trivially reachable and trivially modifiable.
- A secret was discovered and deliberately **not read**.
- A destructive menu was approached with the owner watching, key by key, rather than
  by automation.
- Two ratings were **revised downward** on evidence.
- Nine negative results were recorded with the same care as the positives.

That list — not the six findings — is the transferable part.

---

## 8. Note on the redactions in this file

The published version of this record has had every identifier replaced
([`SANITISATION.md`](../SANITISATION.md)). Two things were removed rather than
replaced:

- The bug bounty **report ID** and the vendor contact address, because they are
  live disclosure references.
- The **values** of the `auth` registry keys. They were never read during the
  engagement either — the record of *that restraint* is worth publishing; the
  secret is not.
