#!/usr/bin/env python3
"""Publishes the editor page. This is what `make site` runs.

index.html carries its own version in a meta tag. When the page has changed
since it was last published, this script gives it today's date plus a counter,
copies the page to docs/editor.html, and writes docs/update.json: the little
manifest the Mac app fetches to find out a newer editor page exists, carrying
the page's sha256 and an Ed25519 signature over both version and hash.

When nothing in the page has changed (the version tag aside), the published
page, its version and its signature are left exactly as they are, so no
installed copy is sent an identical editor under a new number. Only the app
half of update.json, which is not signed, is brought up to date.

The signature is over exactly:

    "myrling-page\\n" + version + "\\n" + sha256

signed with the private key at ~/.myrling/update-key.b64 (see tools/sign.swift).
That key is outside the repository on purpose and is never committed or copied
into CI. If a signature is needed and the key is missing, this script writes
nothing at all and says so: an unsigned or stale-signed manifest is refused by
every installed copy of the app, which would quietly stop updates for everybody.

    python3 tools/publish.py              publish, if the page changed
    python3 tools/publish.py --force      publish a new version even if it did not
    python3 tools/publish.py --check      say what publishing would do; fail if it
                                          would need the key and the key is missing
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


def version_key(version):
    """The Mac app's reading of a version: dotted numbers, anything else zero."""
    return [int(p) if p.isdigit() else 0 for p in version.split(".")]


def newer(a, b):
    x, y = version_key(a), version_key(b)
    width = max(len(x), len(y))
    return x + [0] * (width - len(x)) > y + [0] * (width - len(y))


def next_version(current):
    """Today's date, plus a counter so several ships in one day each get a version."""
    today = datetime.date.today().strftime("%Y.%m.%d")
    n = 1
    if current.startswith(today + "."):
        tail = current[len(today) + 1:]
        if tail.isdigit():
            n = int(tail) + 1
    version = "%s.%d" % (today, n)
    # A clock behind the last publish (another machine, another time zone) would
    # give a number the installed copies read as older, and they would ignore the
    # page for good. Count on from the last one instead.
    if not newer(version, current):
        parts = current.split(".")
        if parts[-1].isdigit():
            version = ".".join(parts[:-1] + [str(int(parts[-1]) + 1)])
    return version


def without_version(page):
    """The page with its version tag emptied, to tell a real change from a renumbering."""
    return META.sub(lambda m: m.group(1) + m.group(3), page, count=1)


def published():
    """The page docs/ serves now and its manifest entry, or None when the two do not
    agree with each other, in which case only a fresh publish can put them right."""
    try:
        with open(EDITOR, "rb") as f:
            page = f.read()
        with open(MANIFEST) as f:
            entry = json.load(f).get("page") or {}
    except (OSError, ValueError, AttributeError):
        return None
    found = META.search(page)
    if (not found or not entry.get("signature")
            or entry.get("version") != found.group(2).decode("utf-8")
            or entry.get("sha256") != hashlib.sha256(page).hexdigest()):
        return None
    return page, entry


def write(path, data):
    """Only touch a file whose bytes change, and never leave one half-written."""
    try:
        with open(path, "rb") as f:
            if f.read() == data:
                return False
    except OSError:
        pass
    temp = path + ".publishing"
    with open(temp, "wb") as f:
        f.write(data)
    os.replace(temp, path)
    return True


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
    args = sys.argv[1:]
    if "--check-key" in args:
        check_key()
        print("update key found at " + key_path())
        return

    with open(INDEX, "rb") as f:
        page = f.read()

    found = META.search(page)
    if not found:
        die('index.html has no <meta name="myrling-version" content="..."> to bump.')

    live = published()
    if live and "--force" not in args and without_version(page) == without_version(live[0]):
        # Nothing in the page changed: what is published stays published, number,
        # signature and all, and index.html keeps (or gets back) the live number.
        page, entry = live
        version, sha, signature = entry["version"], entry["sha256"], entry["signature"]
        fresh = False
    else:
        current = found.group(2).decode("utf-8")
        if live and newer(live[1]["version"], current):
            current = live[1]["version"]
        version = next_version(current)
        page = META.sub(lambda m: m.group(1) + version.encode("utf-8") + m.group(3), page, count=1)
        sha = hashlib.sha256(page).hexdigest()
        fresh = True

    if "--check" in args:
        if fresh:
            check_key()
            print("the page changed: publishing would sign it as %s" % version)
        else:
            print("the page is unchanged: publishing would keep %s and sign nothing" % version)
        return

    if fresh:
        # Sign before writing anything: if this fails, the tree is left as it was
        # rather than half-published with a stale manifest beside a new page.
        check_key()
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

    wrote = [name for name, path, data in (
        ("index.html", INDEX, page),
        ("docs/editor.html", EDITOR, page),
        ("docs/update.json", MANIFEST, (json.dumps(manifest, indent=2) + "\n").encode("utf-8")),
    ) if write(path, data)]

    if fresh:
        print("page %s signed, sha256 %s" % (version, sha[:16] + "..."))
    else:
        print("page unchanged since %s; nothing new to sign" % version)
    if wrote:
        print(", ".join(wrote) + " refreshed. Commit and push to update the site.")
    else:
        print("nothing to write: docs/ is already up to date.")


if __name__ == "__main__":
    main()
