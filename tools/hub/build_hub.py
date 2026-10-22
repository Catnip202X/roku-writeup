#!/usr/bin/env python3
"""
hub/build_hub.py — merge several Roku channels into ONE dev package with a menu.

Roku allows a single sideloaded channel (id "dev"), so this is how you get more
than one app on the TV: namespace every app's components, keep one entry point,
and put a menu in front.

    python3 build_hub.py            build into ../build/hub-app
    python3 build_hub.py --check    build then static-verify only

Namespacing rules (Roku component names are package-global, hence the prefix):
    <component name="MainScene"        -> <component name="yt_MainScene"
    pkg:/components/MainScene.brs      -> pkg:/components/yt_MainScene.brs
    CreateObject("roSGNode", "ApiTask")-> CreateObject("roSGNode", "yt_ApiTask")
    CreateScene("MainScene")           -> CreateScene("yt_MainScene")
    pkg:/fonts/...  pkg:/images/...    -> pkg:/fonts/<ns>/...  pkg:/images/<ns>/...
    sub Main                           -> sub <ns>_Main
"""
import argparse
import re
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
OUT = ROOT / "build" / "hub-app"
TEMPLATE = HERE / "template"


def read_conf():
    apps = []
    for line in (HERE / "apps.conf").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|")
        if len(parts) < 3:
            sys.exit(f"bad apps.conf line: {line}")
        ns, path, label = parts[0].strip(), parts[1].strip(), parts[2].strip()
        src = (HERE / path).resolve()
        if not (src / "manifest").is_file():
            sys.exit(f"no manifest for {label}: {src}")
        apps.append((ns, src, label))
    return apps


def component_names(app_dir):
    """Names that must be namespaced.

    Includes script-only files (Qr.brs has no Qr.xml) — they are referenced by
    <script uri="pkg:/components/Qr.brs"> and renamed like components, so they
    have to be in this set too or the uri rewrite misses them.
    """
    names = set()
    cdir = app_dir / "components"
    if not cdir.is_dir():
        return names
    for f in cdir.iterdir():
        if f.suffix == ".xml":
            m = re.search(r'<component\s+name\s*=\s*"([A-Za-z0-9_]+)"', f.read_text(encoding="utf-8"))
            if m:
                names.add(m.group(1))
    xml_stems = {(f.name[:-4]) for f in cdir.iterdir() if f.suffix == ".xml"}
    for f in cdir.iterdir():
        if f.suffix == ".brs" and f.name[:-4] not in xml_stems:
            names.add(f.name[:-4])
    return names


def rewrite(text, ns, names):
    for n in sorted(names, key=len, reverse=True):
        e = re.escape(n)
        text = re.sub(rf'(<component\s+name\s*=\s*)"{e}"', rf'\1"{ns}_{n}"', text)
        text = re.sub(rf'(pkg:/components/){e}(\.)', rf'\1{ns}_{n}\2', text)
        text = re.sub(rf'("roSGNode"\s*,\s*)"{e}"', rf'\1"{ns}_{n}"', text, flags=re.IGNORECASE)
        text = re.sub(rf'(CreateScene\()"{e}"(\))', rf'\1"{ns}_{n}"\2', text, flags=re.IGNORECASE)
    # asset directories become per-app so identical filenames cannot collide
    text = text.replace("pkg:/fonts/", f"pkg:/fonts/{ns}/")
    text = text.replace("pkg:/images/", f"pkg:/images/{ns}/")
    return text


def copy_assets(app_dir, ns):
    for kind in ("fonts", "images"):
        src = app_dir / kind
        if not src.is_dir():
            continue
        dst = OUT / kind / ns
        dst.mkdir(parents=True, exist_ok=True)
        for f in src.iterdir():
            if f.is_file() and f.name != ".DS_Store":
                shutil.copy2(f, dst / f.name)


def emit(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    apps = read_conf()
    if not apps:
        sys.exit("apps.conf has no entries")

    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)

    # hub shell
    shutil.copy2(TEMPLATE / "manifest", OUT / "manifest")
    for f in (TEMPLATE / "source").iterdir():
        emit(OUT / "source" / f.name, f.read_text(encoding="utf-8"))
    for f in (TEMPLATE / "components").iterdir():
        emit(OUT / "components" / f.name, f.read_text(encoding="utf-8"))

    keys, labels, dispatch = [], [], []
    for ns, app_dir, label in apps:
        names = component_names(app_dir)
        keys.append(ns)
        labels.append(label)
        dispatch.append(
            f'    if key = "{ns}" then\n        {ns}_Main(args)\n        return true\n    end if'
        )

        for f in sorted((app_dir / "components").iterdir()) if (app_dir / "components").is_dir() else []:
            if f.suffix not in (".brs", ".xml"):
                continue
            text = rewrite(f.read_text(encoding="utf-8"), ns, names)
            emit(OUT / "components" / f"{ns}_{f.name}", text)

        entry = app_dir / "source" / "main.brs"
        if entry.is_file():
            text = entry.read_text(encoding="utf-8")
            text = re.sub(r'\bsub\s+Main\b', f'sub {ns}_Main', text, count=1, flags=re.IGNORECASE)
            text = rewrite(text, ns, names)
            emit(OUT / "source" / f"{ns}_main.brs", text)
        else:
            print(f"WARN {label} has no source/main.brs", file=sys.stderr)

        copy_assets(app_dir, ns)
        print(f"  bundled {label:22} ns={ns:8} components={len(names)}")

    key_lines = "\n".join(f'    keys.Push("{k}")' for k in keys)
    label_lines = "\n".join(f'    labels.Push("{l}")' for l in labels)
    emit(OUT / "source" / "entries_generated.brs",
         "' GENERATED by build_hub.py from apps.conf — do not edit.\n\n"
         "function HubKeys() as object\n    keys = []\n" + key_lines + "\n    return keys\nend function\n\n"
         "function HubLabels() as object\n    labels = []\n" + label_lines + "\n    return labels\nend function\n\n"
         "function HubLaunch(key as string, args as dynamic) as boolean\n"
         + "\n".join(dispatch) + "\n    return false\nend function\n")

    print(f"\nbuilt {OUT}")
    return verify() if args.check else 0


def verify():
    """Static checks that catch the mistakes I would otherwise only find on-device."""
    problems = []
    warnings = []

    defined = set()
    for f in (OUT / "components").glob("*.xml"):
        m = re.search(r'<component\s+name\s*=\s*"([A-Za-z0-9_]+)"', f.read_text(encoding="utf-8"))
        if m:
            if m.group(1) in defined:
                problems.append(f"duplicate component name: {m.group(1)}")
            defined.add(m.group(1))

    refs = set()
    for f in list((OUT / "components").glob("*")) + list((OUT / "source").glob("*.brs")):
        text = f.read_text(encoding="utf-8")
        refs.update(re.findall(r'"roSGNode"\s*,\s*"([A-Za-z0-9_]+)"', text, flags=re.IGNORECASE))
        refs.update(re.findall(r'CreateScene\("([A-Za-z0-9_]+)"\)', text, flags=re.IGNORECASE))
        for uri in re.findall(r'pkg:/components/([A-Za-z0-9_]+\.(?:brs|xml))', text):
            if not (OUT / "components" / uri).is_file():
                problems.append(f"missing script {uri} referenced by {f.name}")
        for asset in re.findall(r'pkg:/((?:fonts|images)/[A-Za-z0-9_./-]+)', text):
            if not (OUT / asset).is_file():
                # apps legitimately probe font fallbacks (cjk.ttf next to cjk.otf)
                warnings.append(f"asset not shipped: pkg:/{asset} (referenced by {f.name})")

    builtin = {"ContentNode", "Label", "LabelList", "Scene", "Group", "RowList",
               "MarkupGrid", "Font", "Poster", "Rectangle", "Timer"}
    for r in sorted(refs - defined - builtin):
        problems.append(f"roSGNode ref with no component: {r}")

    print(f"verify: {len(defined)} components defined, {len(refs)} refs checked")
    for w in warnings:
        print(f"  warn: {w}")
    if problems:
        print("\nPROBLEMS:")
        for p in problems:
            print("  -", p)
        return 1
    print("verify: clean — no duplicate names, no dangling refs, no missing scripts")
    return 0


if __name__ == "__main__":
    sys.exit(main())
