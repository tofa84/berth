#!/usr/bin/env python3
"""Generate THIRD_PARTY_LICENSES.txt from the resolved Swift Package dependencies.

berth bundles its SPM dependencies into the shipped binary. Apache-2.0 (§4), MIT
and BSD all require carrying each dependency's license text (and any NOTICE file)
in the distribution. This script aggregates them from the checked-out package
sources into a single file at the repo root.

Run it after changing dependencies (and after at least one build, so SwiftPM has
checked the sources out):

    python3 scripts/generate-third-party-licenses.py [DERIVED_DATA_PATH]

It locates the SwiftPM checkouts in this order:
  1) the path given as the first argument (a -derivedDataPath), or $BERTH_DD
  2) /tmp/berth-dd                         (the isolated path used by this repo)
  3) ~/Library/Developer/Xcode/DerivedData/berth-*  (Xcode's default)
"""
import json, os, re, sys, glob

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOLVED = os.path.join(
    REPO, "berth.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
)
OUT = os.path.join(REPO, "THIRD_PARTY_LICENSES.txt")
PROJECT_URL = "https://github.com/tofa84/berth"


def find_checkouts():
    candidates = []
    if len(sys.argv) > 1:
        candidates.append(os.path.join(sys.argv[1], "SourcePackages/checkouts"))
    if os.environ.get("BERTH_DD"):
        candidates.append(os.path.join(os.environ["BERTH_DD"], "SourcePackages/checkouts"))
    candidates.append("/tmp/berth-dd/SourcePackages/checkouts")
    candidates += sorted(
        glob.glob(
            os.path.expanduser(
                "~/Library/Developer/Xcode/DerivedData/berth-*/SourcePackages/checkouts"
            )
        )
    )
    for c in candidates:
        if os.path.isdir(c) and os.path.isdir(os.path.join(c, "container")):
            return c
    sys.exit(
        "error: could not find SwiftPM checkouts. Build berth once, or pass the\n"
        "       -derivedDataPath as the first argument. Tried:\n  - "
        + "\n  - ".join(candidates)
    )


def dirname_for(location):
    base = location.rstrip("/").split("/")[-1]
    return base[:-4] if base.endswith(".git") else base


def detect_license(text):
    t = text[:4000]
    if "Apache License" in t:
        return "Apache-2.0"
    if "GNU GENERAL PUBLIC LICENSE" in t:
        return "GPL-2.0"
    if re.search(r"\bBSD\b", t):
        return "BSD-3-Clause"
    if "MIT License" in t or "Permission is hereby granted, free of charge" in t:
        return "MIT"
    return "see text below"


LICENSE_RE = re.compile(r"^(LICENSE|COPYING|NOTICE)(\..*)?$", re.IGNORECASE)


def license_files(d):
    if not os.path.isdir(d):
        return []
    files = [f for f in os.listdir(d) if LICENSE_RE.match(f)]

    def prio(f):
        u = f.upper()
        if u.startswith("LICENSE"):
            return (0, f)
        if u.startswith("NOTICE"):
            return (1, f)
        if u.startswith("COPYING"):
            return (2, f)
        return (3, f)

    return sorted(files, key=prio)


def main():
    CO = find_checkouts()
    with open(RESOLVED) as f:
        pins = json.load(f)["pins"]

    records = {}
    for p in pins:
        ver = p.get("state", {}).get("version") or p.get("state", {}).get("revision", "")[:12]
        name = dirname_for(p["location"])
        records[p["identity"]] = {
            "loc": p["location"],
            "ver": ver,
            "dir": os.path.join(CO, name),
            "name": name,
        }

    primary = ["container", "containerization"]
    rest = sorted(
        (i for i in records if i not in primary), key=lambda s: records[s]["name"].lower()
    )
    order = [i for i in primary if i in records] + rest

    SEP, SUB = "=" * 80, "-" * 80
    out, missing = [], []
    out += [
        SEP,
        "THIRD-PARTY SOFTWARE LICENSES",
        "",
        "berth (%s) is licensed under the MIT License (see the LICENSE file)." % PROJECT_URL,
        "",
        "berth bundles the following third-party Swift packages. Each is reproduced",
        "below with its license and, where present, its NOTICE file, as required by",
        "the Apache License 2.0 (Section 4), the MIT License, and the BSD License.",
        "",
        "Generated from Package.resolved by scripts/generate-third-party-licenses.py.",
        "Component count: %d." % len(order),
        SEP,
        "",
    ]

    for ident in order:
        r = records[ident]
        files = license_files(r["dir"])
        combined, file_texts = "", []
        for fn in files:
            try:
                with open(os.path.join(r["dir"], fn), encoding="utf-8", errors="replace") as fh:
                    txt = fh.read()
            except Exception as e:
                txt = "<error reading %s: %s>" % (fn, e)
            file_texts.append((fn, txt))
            combined += "\n" + txt
        lic = detect_license(combined) if combined.strip() else "NOT FOUND"
        if not files:
            missing.append(ident)
        is_zstd = r["name"].lower() == "zstd"
        if is_zstd:
            lic = "BSD-3-Clause (selected by berth) / GPL-2.0 (dual-licensed, not used)"

        out += [SEP, "%s  (version %s)" % (r["name"], r["ver"]), r["loc"], "License: %s" % lic, SEP, ""]
        if is_zstd:
            out += [
                ">> zstd is dual-licensed under BSD-3-Clause OR GPL-2.0. berth uses it",
                ">> under the BSD-3-Clause license. The GPL-2.0 text (COPYING) is included",
                ">> only for completeness and does NOT apply to berth's use.",
                "",
            ]
        if not file_texts:
            out += ["<<< No LICENSE/NOTICE file found. VERIFY MANUALLY: %s >>>" % r["loc"], ""]
        for fn, txt in file_texts:
            out += [SUB, "%s — %s" % (r["name"], fn), SUB, txt.rstrip("\n"), ""]
        out.append("")

    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(out))

    print("Wrote %s (%d components, %.0f KB)" % (OUT, len(order), os.path.getsize(OUT) / 1024.0))
    if missing:
        print("WARNING: no license file found for: %s" % ", ".join(missing))


if __name__ == "__main__":
    main()
