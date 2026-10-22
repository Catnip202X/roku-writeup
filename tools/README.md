# Tools

Everything here is stdlib-only Python or POSIX shell. No `pip install`, no vendored
dependencies, no build step. That is deliberate: these tools ran against a live TV
during an assessment, and a tool that needs a virtualenv is a tool you do not reach
for at the moment you need it.

| Tool | What it does | Touches the TV? |
|---|---|---|
| [`sinkhole.py`](sinkhole.py) | dependency-free DNS sinkhole; blocklist and allowlist modes | no — sits between the TV and the internet |
| [`collector.py`](collector.py) | receives probe reports and browser beacons from the device | receives only |
| [`brs.py`](brs.py) | drives the BrightScript Micro Debugger on `tcp/8085` | read + arbitrary BRS in a crashed channel |
| [`tv.sh`](tv.sh) | plugin inventory, health checks, removal probes | read; optional `remove_plugin` |
| [`apps.sh`](apps.sh) | switch which app occupies the single Roku dev slot | yes — replaces the sideloaded channel |
| [`sideload-probe.sh`](sideload-probe.sh) | package, authenticate and install a channel | yes — installs |
| [`hub/`](hub/) | merges several Roku channels into one sideloadable package with a menu | packages only |

Plus, at the repo root:

| Tool | What it does |
|---|---|
| [`../scripts/sanitize.py`](../scripts/sanitize.py) | identifier rewrite + pre-push leak gate ([`../SANITISATION.md`](../SANITISATION.md)) |

---

## `sinkhole.py`

```bash
sudo ./sinkhole.py --listen 0.0.0.0 --port 53 --upstream 1.1.1.1
sudo ./sinkhole.py --port 53 --upstream 1.1.1.1 | grep --line-buffered TARGET_IP
```

Serves `0.0.0.0` for blocked names and forwards everything else to the upstream.
**Answering rather than blackholing is load-bearing** — the TV has public resolvers
in its fallback chain and would otherwise fall through to Google and serve the ads
anyway. Data comes from [`../blocklist/`](../blocklist/); each entry in
`roku-blocklist.txt` cites the plugin observed talking to it.

Read the file. It is 147 lines and the DNS parsing is the part that matters if you
want to adapt it.

## `brs.py`

The Micro Debugger is a raw socket REPL, so someone has to script it. `brs.py` does
exactly that and supports a batch of expressions from a file:

```bash
python3 brs.py TARGET_IP --eval 'GetVolumeList()'
python3 brs.py TARGET_IP --file probes/questions.txt
```

It is the driver behind every result in
[`../docs/04-brightscript-sandbox.md`](../docs/04-brightscript-sandbox.md).

## `sideload-probe.sh`

Packages a directory into a `.zip`, Digest-authenticates against `tcp/80` as
`rokudev`, and POSTs it to `plugin_install`. It also handles the thing that makes
sideloading tedious: **it asks for the developer password once** and stores it in the
macOS login keychain, so every later install reads it silently.

| | |
|---|---|
| Service | `roku-dev-<TV address>` |
| Account | `rokudev` |
| Written | only after the TV answers with something other than `401`, so a typo is never saved |
| Read | `security find-generic-password -s <service> -a rokudev -w` at the start of each install |

```bash
./sideload-probe.sh --forget                 # delete the stored item
ROKU_NO_KEYCHAIN=1 ./sideload-probe.sh …     # skip the keychain for one run
```

**Scope, honestly:** this is convenience and at-rest encryption, not isolation. Any
process running as the same user can read the item back with
`security find-generic-password`. Proper isolation would mean a dedicated keychain
with an ACL — which reintroduces a per-use approval prompt, the thing this exists to
avoid. The trade is stated here rather than discovered later.

Round-trip was verified with a password containing `/` and `==`, since digest-auth
passwords routinely do; it stored and read back byte-identical.

## `hub/`

**Roku allows exactly one sideloaded channel.** Not one per developer, not one plus
a built-in — one. Replacing it is how you switch apps.

`build_hub.py` is the workaround and the most reusable piece in this repo: it
namespaces several apps' components into one package behind a launcher menu, so you
can have more than one at a time. It rewrites each app's component ids with a prefix,
merges the `manifest`, and generates a menu scene.

```bash
python3 hub/build_hub.py --conf hub/apps.conf --out build/hub.zip
```

The constraint it works around is worth stating plainly, because it is the reason the
tool exists: on 15.x, installing a second app does not add a second app — it removes
the first.

## `tv.sh` and `apps.sh`

Thin wrappers for the two operations that get repeated constantly — inventory the
plugins, and swap which app is in the dev slot. Deliberately small and readable so you
can copy the one curl or `nc` invocation you need instead of reading a framework.

## Why no framework

An assessment tool that abstracts the protocol hides the protocol, and the protocol
*is* the finding here — an unauthenticated command line on `:8080` and an
unauthenticated REPL on `:8085` are interesting precisely because they are that
simple. Every tool in this directory is short enough to audit in one sitting, and
that is a requirement, not a style preference.
