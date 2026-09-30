#!/bin/sh
# Cuts a Mac app release. This is what `make release VERSION=1.1` runs.
#
# It stamps the version into mac/Info.plist, republishes the site (a new page is
# only signed if index.html changed), commits that, and makes the annotated tag v1.1. Pushing the tag is left to you, and is what
# actually builds and publishes the download — see .github/workflows/release.yml.
#
# The tag has to point at a commit that already carries the new version, or the
# build would put the old number in the app, so the working tree must be clean
# before we start and the version bump is committed before the tag is made.

set -e

VERSION="$1"

if [ -z "$VERSION" ]; then
  echo 'usage: make release VERSION=1.1' >&2
  exit 1
fi

case "$VERSION" in
  v*)
    echo "release: give the version without the v: make release VERSION=${VERSION#v}" >&2
    exit 1
    ;;
esac

if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+(\.[0-9]+)*$'; then
  echo "release: '$VERSION' does not look like a version number (1.1, 1.2.3)." >&2
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo 'release: the working tree has uncommitted changes.' >&2
  echo '         A release tag has to point at a finished commit, so commit or' >&2
  echo '         discard these first, then run this again:' >&2
  echo '' >&2
  git status --short >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  echo "release: the tag v$VERSION already exists. Pick another version." >&2
  exit 1
fi

# An installed copy only mentions a release newer than itself, so an older or equal
# number would ship an app nobody is ever told about.
# "Newer" is decided the way publish.py and the app decide it (1.2 and 1.2.0 are the
# same version), so a release this accepts is always one the app will announce.
CURRENT=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' mac/Info.plist)
if ! python3 -c 'import sys; sys.path.insert(0, "tools"); import publish; sys.exit(0 if publish.newer(sys.argv[1], sys.argv[2]) else 1)' "$VERSION" "$CURRENT"; then
  echo "release: $VERSION is not newer than the current $CURRENT." >&2
  exit 1
fi

# Fails loudly here, if the page needs signing and the key is missing, rather than
# after the plist has been rewritten.
python3 tools/publish.py --check >/dev/null

BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' mac/Info.plist)
BUILD=$((BUILD + 1))

# From here the tree is being changed. If anything stops before the commit, the files
# go back as they were, so a failed run never leaves a half-bumped plist behind.
COMMITTED=
trap 'if [ -z "$COMMITTED" ]; then
  # from HEAD, not the index: a failed commit leaves the bump already staged
  git checkout -q HEAD -- mac/Info.plist index.html docs/editor.html docs/update.json
  echo "release: stopped before committing; mac/Info.plist and the site are as they were." >&2
fi' EXIT

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" mac/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" mac/Info.plist

python3 tools/publish.py

git add -A
git commit -q -m "Myrling $VERSION"
COMMITTED=1
git tag -a "v$VERSION" -m "Myrling $VERSION"

echo ''
echo "Myrling $VERSION (build $BUILD) is committed and tagged v$VERSION."
echo 'Nothing is published yet. Pushing the tag is what builds the download:'
echo ''
echo "    git push && git push origin v$VERSION"
echo ''
echo 'That runs .github/workflows/release.yml, which builds Myrling.app on a Mac'
echo 'runner, attaches the zip to a GitHub Release for the tag, and only then'
echo 'tells installed copies about it by updating docs/update.json on main.'
