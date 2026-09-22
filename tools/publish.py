#!/usr/bin/env python3
"""Publishes the editor page. This is what `make site` runs.

index.html carries its own version in a meta tag. This script gives it today's
date plus a counter, copies the page to docs/editor.html, and writes
docs/update.json: the little manifest the Mac app fetches to find out a newer
editor page exists, carrying the page's sha256 and an Ed25519 signature over
both version and hash.

The signature is over exactly:

    "myrling-page\\n" + version + "\\n" + sha256

signed with the private key at ~/.myrling/update-key.b64 (see tools/sign.swift).
That key is outside the repository on purpose and is never committed or copied
into CI. If it is missing, this script writes nothing at all and says so: an
unsigned or stale-signed manifest is refused by every installed copy of the app,
which would quietly stop updates for everybody.

    python3 tools/publish.py              publish
    python3 tools/publish.py --check-key  just check the key is there
"""

import datetime
import hashlib
import json
import os
import plistlib
import re
import subprocess
import sys

# The public half of the update key, the same one the Mac app checks signatures
# against. Signing with anything else would produce a manifest no installed copy
# would accept, so we compare and refuse rather than publish a dud.
PUBLIC_KEY = "TSNuDQVNl3TLwrxYe4mkB+nThjF9lBbhX32niIRnXgs="

SITE = "https://josiah-turnquist.github.io/myrling-sprite-editor"
RELEASES = "https://github.com/Josiah-Turnquist/myrling-sprite-editor/releases/latest"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INDEX = os.path.join(ROOT, "index.html")
EDITOR = os.path.join(ROOT, "docs", "editor.html")
MANIFEST = os.path.join(ROOT, "docs", "update.json")
PLIST = os.path.join(ROOT, "mac", "Info.plist")
SIGNER = os.path.join(ROOT, "tools", "sign.swift")

META = re.compile(rb'(<meta\s+name="myrling-version"\s+content=")([^"]*)(")')


def die(message):
    sys.stderr.write("publish: " + message + "\n")
    sys.exit(1)


def key_path():
    return os.environ.get("MYRLING_UPDATE_KEY") or os.path.expanduser("~/.myrling/update-key.b64")


def check_key():
    path = key_path()
    if not os.path.isfile(path):
        die(
            "no update signing key at " + path + ".\n"
            "         Every update is signed with it, and the app refuses anything unsigned,\n"
            "         so nothing was written. Restore the key from your backup, or point\n"
            "         MYRLING_UPDATE_KEY at it, and run this again."
        )
    return path


def next_version(current):
    """Today's date, plus a counter so several ships in one day each get a version."""
    today = datetime.date.today().strftime("%Y.%m.%d")
    n = 1
    if current.startswith(today + "."):
        tail = current[len(today) + 1:]
        if tail.isdigit():
            n = int(tail) + 1
    return "%s.%d" % (today, n)


def sign(version, sha):
    message = b"myrling-page\n" + version.encode("utf-8") + b"\n" + sha.encode("utf-8")
    run = subprocess.Popen(
        ["swift", SIGNER],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        cwd=ROOT,
    )
    out, _ = run.communicate(message)
    if run.returncode != 0:
        die("signing failed; nothing was written.")
    lines = out.decode("utf-8").split()
    if len(lines) != 2:
        die("the signer did not return a signature and a public key.")
    signature, public = lines
    if public != PUBLIC_KEY:
        die(
            "that key's public half is " + public + ",\n"
            "         but the app checks updates against " + PUBLIC_KEY + ".\n"
            "         This is the wrong key. Nothing was written."
        )
    return signature


def app_version():
    with open(PLIST, "rb") as f:
        return plistlib.load(f).get("CFBundleShortVersionString", "1.0")


def main():
    if "--check-key" in sys.argv[1:]:
        check_key()
        print("update key found at " + key_path())
        return

    check_key()

    with open(INDEX, "rb") as f:
        page = f.read()

    found = META.search(page)
    if not found:
        die('index.html has no <meta name="myrling-version" content="..."> to bump.')

    version = next_version(found.group(2).decode("utf-8"))
    page = META.sub(lambda m: m.group(1) + version.encode("utf-8") + m.group(3), page, count=1)
    sha = hashlib.sha256(page).hexdigest()

    # Sign before writing anything: if this fails, the tree is left as it was
    # rather than half-published with a stale manifest beside a new page.
    signature = sign(version, sha)

    manifest = {
        "page": {
            "version": version,
            "url": SITE + "/editor.html",
            "sha256": sha,
            "signature": signature,
        },
        "app": {
            "version": app_version(),
            "url": RELEASES,
            "notes": "Myrling %s for macOS, from GitHub Releases." % app_version(),
        },
    }

    with open(INDEX, "wb") as f:
        f.write(page)
    with open(EDITOR, "wb") as f:
        f.write(page)
    with open(MANIFEST, "w") as f:
        f.write(json.dumps(manifest, indent=2) + "\n")

    print("page %s signed, sha256 %s" % (version, sha[:16] + "..."))
    print("docs/editor.html and docs/update.json refreshed. Commit and push to update the site.")


if __name__ == "__main__":
    main()
