# Builds the Mac app around index.html. Needs only the Xcode command line tools:
#   xcode-select --install
# Then:
#   make app     builds dist/Myrling.app
#   make run     builds and opens it
#   make clean   removes dist
#
# The app is built for this machine's architecture and macOS version. There is no
# Apple Developer account involved: the app is ad-hoc signed, which runs fine on the
# machine that built it. index.html itself needs no build at all; open it in a browser.

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

clean:
	rm -rf dist

.PHONY: app run icon clean
