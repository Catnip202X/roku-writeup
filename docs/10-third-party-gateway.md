# 10 — The ISP gateway: an incidental finding I did not act on

This one did not come from looking for it. It came from needing to understand the
DNS path so the sinkhole would work.

**Finding class:** CWE-306 — Missing Authentication for Critical Function
**Severity:** High, LAN-scoped
**Asset:** ISP-supplied residential gateway, management address `GATEWAY_IP`
**Reporter:** Resident on the network, **not** the equipment owner
**Status:** reported to the ISP's bug bounty program on 2026-10-22, awaiting triage;
CERT/CC coordination request drafted as the fallback

---

## Summary

The gateway serves its complete administrative interface to any client on the local
network without requesting any credential. Configuration pages are fully editable.
The gateway displays a warning that the action is "unprotected / not secure" before
applying changes, but that is a notice about the self-signed certificate and
cleartext HTTP — it performs no authorization check and does not prevent the change.

Because residential gateways are shared infrastructure, this affects every household
member, guest, and any compromised device on the network — none of whom need a
credential to take control of the network's DNS, port forwarding, or Wi-Fi settings.

## Steps to reproduce

1. From a device that has never authenticated to the gateway — a phone, or a private
   browser window — browse to `http://GATEWAY_IP`.
2. The full configuration interface is served. No username or password is requested,
   at any point, including on pages that modify device configuration.
3. Navigate to a settings page. The fields are editable and not greyed out.
4. Attempt a change. The gateway displays a warning that the action is
   "unprotected / not secure" and then proceeds.
5. The same administrative surface is reachable over `https://GATEWAY_IP`
   (HTTP `302` at `/` on both schemes).

**Verification that no session was involved:** reproduced from a second device with
no stored cookies and no prior session.

## Impact

An unauthenticated attacker on the local network can:

- **Set the DNS servers handed to every client**, enabling transparent redirection
  and observation of all devices' name resolution. Clients currently resolve via
  `GATEWAY_IP`.
- Add, modify, or remove port-forwarding rules, exposing internal hosts to the
  internet.
- Change the Wi-Fi network key or security configuration, locking out legitimate
  users.
- Alter other configuration, including firmware update settings.

The administrative interface is also served over plain HTTP, so an administrative
session can additionally be observed by any other host on the same network segment.

## Exposure scope — tested and verified

Internet-facing exposure was explicitly ruled out. From a cellular connection with
Wi-Fi disabled, both `http://<public-ip>` and `https://<public-ip>` hang and time
out, indicating the management interface is filtered at the WAN edge.

The issue is therefore confined to the local network. That does **not** reduce impact
for household members, guests, or anyone who obtains the Wi-Fi key once — the Wi-Fi
password is effectively the only authentication protecting the gateway.

## Reporter status

- The reporter does **not** own this equipment.
- **No configuration change was made.** Settings pages were opened only to establish
  whether the fields were editable.
- No exploitation was attempted, no credential was guessed, and no data was accessed.
- The finding was identified incidentally while assessing a different, self-owned
  device on the same network.

## The consequence for this writeup

This finding is why [`06-ad-suppression.md`](06-ad-suppression.md) documents the DHCP
DNS re-point but does not perform it.

The sinkhole needs the TV to resolve through it, and the only lever that reaches the
TV's DNS is the gateway's DHCP setting. That lever is on equipment I do not own. So
the sinkhole was verified locally, the mechanism was proven, and the shared-
infrastructure step was left as instructions for the owner rather than executed to
make a demo work.

That is the whole point of the exercise: the device was mine and I took it apart; the
gateway was not, so I read it and wrote a report. Passing on a working demo because
the last step crossed an ownership line is the correct trade, and it is worth
recording that it was a trade and not an oversight.

## Requested remediation

1. Require authentication on the administrative interface for **all** LAN clients,
   not only for WAN access.
2. Serve the administrative interface over HTTPS only, with a trusted or
   user-installable certificate.
3. Confirm whether this behaviour is a fleet-wide default rather than specific to
   this unit — if so, it affects every subscriber with this model.

## Disclosure

Coordinated disclosure requested; a 90-day window was proposed. Nothing in the
finding is published here that is not already published by the vendor's own product
documentation, and the management address is a placeholder.

**Triage expectation, recorded honestly:** ISP bug bounty programmes are usually
scoped around the ISP's *services* rather than ISP-supplied CPE, and CWE-306 may not
appear in their weakness scope table. If the report is closed out of scope, the
single useful follow-up is to ask that it be forwarded internally to the product
security team responsible for gateway firmware. A submission date and report ID also
satisfy CERT/CC's "vendor contact status" question, which strengthens a coordination
request.
