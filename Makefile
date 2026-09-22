# Builds the Mac app around index.html. Needs only the Xcode command line tools:
#   xcode-select --install
# Then:
#   make app                builds dist/Myrling.app
#   make run                builds and opens it
#   make site               publishes the editor page to docs/ (run before committing)
#   make release VERSION=…  stamps a version, tags it, ready to push
#   make clean              removes dist
#
# The app is built for this machine's architecture and macOS version. There is no
# Apple Developer account involved: the app is ad-hoc signed, which runs fine on the
# machine that built it. index.html itself needs no build at all; open it in a browser.
#
# The download other people get is built the same way, by .github/workflows/release.yml
# on a Mac runner, when a tag is pushed. That is the only place an Apple Developer ID
# comes into it, and only if the certificate secrets are set; see the workflow.

APP := dist/Myrling.app

app:
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	swiftc -O -o "$(APP)/Contents/MacOS/Myrling" mac/main.swift
	cp mac/Info.plist "$(APP)/Contents/Info.plist"
	cp index.html mac/bridge.js mac/AppIcon.icns "$(APP)/Contents/Resources/"
	codesign --force --sign - "$(APP)"
	@echo 'Built $(APP)'

run: app
	open "$(APP)"

# redraws mac/AppIcon.icns, docs/logo.png and docs/favicon.png from mac/make-icon.py
icon:
	python3 mac/make-icon.py

# docs/ is the GitHub Pages site: the landing page, the editor itself as
# editor.html, and update.json — the manifest the Mac app reads to find out a
# newer editor page exists. Run this after editing index.html so the hosted copy
# keeps up: it gives the page today's version number, copies it across, and
# writes update.json with the page's sha256 and an Ed25519 signature over both.
#
# Signing needs the private key at ~/.myrling/update-key.b64. It lives outside
# the repository and is never committed or copied into CI. Without it this fails
# and writes nothing at all: the app refuses an update whose signature does not
# check out, so an unsigned or stale manifest would quietly stop everybody's
# updates. Losing the key means no one can be updated again — keep a backup.
site:
	python3 tools/publish.py

# Cuts a release of the Mac app: stamps the version into mac/Info.plist,
# republishes the site, commits that and tags it. Pushing the tag is what
# actually builds the download, and is left to you.
release:
	@tools/release.sh "$(VERSION)"

clean:
	rm -rf dist

.PHONY: app run icon site release clean
