# 09 — Engagement authorization & scope (template)

Copy this file to `engagement/<target>-<yyyy-mm-dd>.md` and fill every field
**before** any probing. If a field cannot be filled, the engagement does not start.

A worked example of the filled-in form is
[`08-engagement-record.md`](08-engagement-record.md).

---

## 1. Authorization basis

| Field | Value |
|---|---|
| Operator (person legally responsible) | |
| Target (host / URL / device / network range) | |
| Owner of the target | |
| Basis of authorization | `I own it` / `written permission ref #` / `CTF, event, rules URL` / `bug bounty program, scope URL` |
| Authorization document / reference | |
| Date authorized | |
| Expiry / review date | |

**Rule:** authorization must come from the party that owns or operates the target,
must cover the specific hosts and techniques used, and must be obtainable on
request. "I'm on the network" is not authorization. "It was reachable" is not
authorization.

## 2. Scope

**In scope**

-

**Explicitly out of scope**

- Denial of service / load testing
- Social engineering of real people
- Any system not listed above
- Physical access beyond what the owner has granted
- Data exfiltration beyond the minimum needed to prove a finding

**Third-party systems encountered during testing**

Systems discovered but not owned by the requester are **observed, not tested**.
Record what was seen, do not attempt to change it, and route findings to the owner.

## 3. Rules of engagement

- [ ] Read-only verification first; state changes only when the owner asks for them
- [ ] Never leave persistent changes; log and revert anything created
- [ ] Destructive or irreversible actions (factory reset, firmware, account changes) require explicit per-action approval
- [ ] No credential, token or personal data is captured in notes; record the *existence* of a secret, never its value
- [ ] Stop and confirm if a finding implies a wider blast radius than the scope covers

## 4. Data handling

| Item | Handling |
|---|---|
| Evidence (screenshots, outputs) | stored locally, not in a shared/public repo |
| Secrets discovered | never recorded; reported as "present" only |
| Personal data | not collected |
| Retention | delete after the disclosure is resolved |

## 5. Findings & disclosure

| # | Title | Severity | Affected asset | Reproducible | Reported to | Status |
|---|---|---|---|---|---|---|
| | | | | | | |

**Negative results are recorded too.** "Tested X, boundary held, evidence Y" is a
finding. It is often the most useful thing in the report.

## 6. Sign-off

| | Name | Date |
|---|---|---|
| Operator | | |
| Target owner (if different) | | |

---

## Why this template exists

The rules above are not ceremony. Each one prevented something specific during the
engagement recorded in [`08-engagement-record.md`](08-engagement-record.md):

| Rule | What it prevented |
|---|---|
| Third-party systems observed, not tested | A reachable, trivially modifiable ISP gateway was left untouched and reported instead |
| Record the existence of a secret, never its value | A registry section containing a live login was found and not read |
| Destructive actions need per-action approval | The secret-screen menu — which contains factory reset — was walked one key at a time, not fuzzed |
| Never leave persistent changes | The console `target` selection was restored; write probes stayed in `tmp:` |
| Stop if blast radius exceeds scope | Ad blocking was **abandoned** rather than achieved by changing shared DNS infrastructure |

Five rules, five concrete outcomes. That is the return on writing them down before
starting rather than after.
