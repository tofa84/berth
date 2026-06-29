#!/usr/bin/env bash
#
# release.sh — build berth as an ad-hoc-signed .app, pack it into a DMG, and
# (optionally) publish a GitHub release. NO Developer ID / notarization needed.
#
# The app is still ad-hoc signed (mandatory on Apple Silicon); we only skip the
# paid Developer-ID + notarization path. Users get a one-time Gatekeeper prompt
# (System Settings ▸ Privacy & Security ▸ "Open Anyway", or `xattr -dr
# com.apple.quarantine /Applications/berth.app`).
#
# Usage:
#   scripts/release.sh [VERSION] [--publish]
#
#   VERSION    marketing version, e.g. 1.0.0  (default: current MARKETING_VERSION)
#   --publish  create/push tag vVERSION and run `gh release create` with the DMG
#
# Examples:
#   scripts/release.sh                 # build dist/berth-<current>.dmg
#   scripts/release.sh 1.1.0           # build dist/berth-1.1.0.dmg
#   scripts/release.sh 1.1.0 --publish # build + tag + GitHub release
#
set -euo pipefail

# ── locate full Xcode (the active dir is usually Command Line Tools) ──────────
if [[ -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "error: full Xcode not found. Install Xcode 26 or set DEVELOPER_DIR." >&2
  exit 1
fi

# ── paths & config ───────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PROJECT="berth.xcodeproj"
SCHEME="berth"
DD="$(mktemp -d /tmp/berth-dd.XXXX)"           # isolated DerivedData (Xcode may hold the default lock)
DIST="$REPO_ROOT/dist"
PBXPROJ="$PROJECT/project.pbxproj"

# ── version / build number ─────────────────────────────────────────────────-
PUBLISH=0
VERSION=""
for arg in "$@"; do
  case "$arg" in
    --publish) PUBLISH=1 ;;
    -*)        echo "error: unknown flag $arg" >&2; exit 1 ;;
    *)         VERSION="$arg" ;;
  esac
done
if [[ -z "$VERSION" ]]; then
  VERSION="$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed -E 's/.*= *([^;]+);/\1/' | tr -d ' ')"
fi
BUILD="$(git rev-list --count HEAD)"           # monotonic build number from commit count
APP_NAME="berth"
DMG="$DIST/${APP_NAME}-${VERSION}.dmg"

echo "▸ berth $VERSION (build $BUILD)"
echo "▸ DerivedData: $DD"

# ── 1) Release build, ad-hoc signed ('-'), version injected via overrides ─────
echo "▸ Building Release (ad-hoc signed)…"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DD" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  clean build

APP="$DD/Build/Products/Release/${APP_NAME}.app"
[[ -d "$APP" ]] || { echo "error: build product not found at $APP" >&2; exit 1; }
codesign --verify --verbose=1 "$APP"
echo "▸ Built $APP"

# ── 2) Package into a compressed read-only DMG (zero extra dependencies) ──────
echo "▸ Packaging DMG…"
mkdir -p "$DIST"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"      # drag-to-install target
# Carry third-party license texts alongside the app (Apache-2.0 §4 / MIT / BSD).
[[ -f "$REPO_ROOT/THIRD_PARTY_LICENSES.txt" ]] && cp "$REPO_ROOT/THIRD_PARTY_LICENSES.txt" "$STAGE/"
[[ -f "$REPO_ROOT/LICENSE" ]] && cp "$REPO_ROOT/LICENSE" "$STAGE/"

rm -f "$DMG"
hdiutil create \
  -volname "${APP_NAME} ${VERSION}" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO -imagekey zlib-level=9 \
  -ov "$DMG" >/dev/null
rm -rf "$STAGE"
echo "▸ Wrote $DMG"
echo "  $(du -h "$DMG" | cut -f1)  ·  $(shasum -a 256 "$DMG" | cut -d' ' -f1)"

# ── 3) Optional: publish a GitHub release ─────────────────────────────────────
if [[ "$PUBLISH" -eq 1 ]]; then
  TAG="v${VERSION}"
  echo "▸ Publishing GitHub release $TAG…"
  command -v gh >/dev/null || { echo "error: gh CLI not installed (brew install gh; gh auth login)" >&2; exit 1; }
  if ! git rev-parse "$TAG" >/dev/null 2>&1; then
    git tag "$TAG"
    git push origin "$TAG"
  fi
  gh release create "$TAG" "$DMG" \
    --title "berth ${VERSION}" \
    --generate-notes \
    --notes-start-tag "$(git describe --tags --abbrev=0 "${TAG}^" 2>/dev/null || true)" \
    --verify-tag 2>/dev/null \
    || gh release create "$TAG" "$DMG" --title "berth ${VERSION}" --generate-notes
  echo "▸ Done."
else
  cat <<EOF

Next steps to publish on GitHub:
  gh auth login                       # once, if not logged in
  git tag v${VERSION} && git push origin v${VERSION}
  gh release create v${VERSION} "$DMG" --title "berth ${VERSION}" --generate-notes

  …or just re-run:  scripts/release.sh ${VERSION} --publish
EOF
fi

rm -rf "$DD"
