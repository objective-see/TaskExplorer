#!/bin/bash
#
# release.sh - build, sign, notarize, and staple a TaskExplorer release
# run from the TaskExplorer directory (the one containing TaskExplorer.xcodeproj)
#
# usage: ./release.sh [notarytool keychain profile]   (default: objective-see)
#
# output: Releases/TaskExplorer_<version>.zip (notarized & stapled)
#
# note: the app embeds a system extension (Endpoint Security); both are signed w/ Developer ID via the project's
#       manual-signing profiles ("TaskExplorer App", "TaskExplorer Extension"), and the extension is checked below,
#       as sysextd refuses an extension that isn't correctly signed & notarized ("code signature invalid")
#

set -euo pipefail

# --- config ---------------------------------------------------------------

# Xcode (macOS 26 SDK+; the app targets macOS 14+)
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

SCHEME="TaskExplorer"
CONFIGURATION="Release"
EXTENSION_ID="com.objective-see.taskexplorer.extension"

# Developer ID Application: Objective-See, LLC (VBG97UB4TA)
SIGNING_IDENTITY="7C252D0F28F7D452C3647A78A9781EDD8EDB08E8"
TEAM_ID="VBG97UB4TA"

# notarytool credentials (create once with: xcrun notarytool store-credentials objective-see --apple-id <id> --team-id VBG97UB4TA)
KEYCHAIN_PROFILE="${1:-objective-see}"

# where the final zip lands
OUTPUT_DIR="$PWD/Releases"

# --- setup ----------------------------------------------------------------

log()  { printf '\n[+] %s\n' "$*"; }
fail() { printf '\n[!] %s\n' "$*" >&2; exit 1; }

[[ -d "$DEVELOPER_DIR" ]] || fail "Xcode not found at $DEVELOPER_DIR"
[[ -d "$SCHEME.xcodeproj" ]] || fail "run this from the TaskExplorer directory (no $SCHEME.xcodeproj here)"

# temp build dir, removed on exit (success or failure)
TMP_DIR="$(mktemp -d -t taskexplorer-release)"
trap 'log "cleaning up $TMP_DIR"; rm -rf "$TMP_DIR"' EXIT

ARCHIVE_PATH="$TMP_DIR/$SCHEME.xcarchive"
DERIVED_DATA="$TMP_DIR/DerivedData"
APP_PATH="$ARCHIVE_PATH/Products/Applications/$SCHEME.app"
EXT_PATH="$APP_PATH/Contents/Library/SystemExtensions/$EXTENSION_ID.systemextension"

# --- preflight ------------------------------------------------------------

log "checking signing identity"
IDENTITIES="$(security find-identity -v -p codesigning)"
grep -q "$SIGNING_IDENTITY" <<< "$IDENTITIES" \
    || fail "signing identity $SIGNING_IDENTITY not found in keychain"

log "checking notarytool profile '$KEYCHAIN_PROFILE'"
xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1 \
    || fail "notarytool profile '$KEYCHAIN_PROFILE' not found (run: xcrun notarytool store-credentials $KEYCHAIN_PROFILE --apple-id <id> --team-id $TEAM_ID)"

if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    printf '\n[?] working tree has uncommitted changes:\n'
    git status --short
    read -r -p "    continue anyway? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || fail "aborted"
fi

# --- build ----------------------------------------------------------------

log "archiving $SCHEME ($CONFIGURATION) with $(xcodebuild -version | head -1)"
xcodebuild -scheme "$SCHEME" \
           -configuration "$CONFIGURATION" \
           -derivedDataPath "$DERIVED_DATA" \
           -archivePath "$ARCHIVE_PATH" \
           CODE_SIGN_STYLE=Manual \
           CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
           DEVELOPMENT_TEAM="$TEAM_ID" \
           OTHER_CODE_SIGN_FLAGS="--timestamp" \
           archive | grep -E "error:|warning:|ARCHIVE (SUCCEEDED|FAILED)" || true

[[ -d "$APP_PATH" ]] || fail "archive failed, no app at $APP_PATH"
[[ -d "$EXT_PATH" ]] || fail "archive has no system extension at $EXT_PATH"

VERSION="$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString)"
BUILD="$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleVersion)"
MIN_OS="$(defaults read "$APP_PATH/Contents/Info.plist" LSMinimumSystemVersion)"
EXT_VERSION="$(defaults read "$EXT_PATH/Contents/Info.plist" CFBundleShortVersionString)"
EXT_BUILD="$(defaults read "$EXT_PATH/Contents/Info.plist" CFBundleVersion)"
ZIP_NAME="${SCHEME}_${VERSION}.zip"
SUBMIT_ZIP="$TMP_DIR/$ZIP_NAME"
FINAL_ZIP="$OUTPUT_DIR/$ZIP_NAME"

log "built $SCHEME $VERSION ($BUILD), extension $EXT_VERSION ($EXT_BUILD), min macOS $MIN_OS"
lipo -info "$APP_PATH/Contents/MacOS/$SCHEME"
lipo -info "$EXT_PATH/Contents/MacOS/$EXTENSION_ID"

# the app & extension versions must match (the app checks in with its own extension)
[[ "$VERSION ($BUILD)" == "$EXT_VERSION ($EXT_BUILD)" ]] \
    || fail "app ($VERSION/$BUILD) and extension ($EXT_VERSION/$EXT_BUILD) versions differ"

# fail early, before notarizing, if this version was already packaged
[[ -e "$FINAL_ZIP" ]] && fail "$FINAL_ZIP already exists, move it first"

# --- verify signatures ----------------------------------------------------

log "verifying app signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
# note: capture output first; 'cmd | grep -q' trips pipefail via SIGPIPE
SIG_INFO="$(codesign -dvv "$APP_PATH" 2>&1)"
grep -q "TeamIdentifier=$TEAM_ID" <<< "$SIG_INFO" \
    || fail "app is not signed by team $TEAM_ID"
grep -q "Authority=Developer ID Application" <<< "$SIG_INFO" \
    || fail "app is not signed with a Developer ID certificate"
grep -q "flags=.*runtime" <<< "$SIG_INFO" \
    || fail "hardened runtime not enabled (app)"

log "verifying system extension signature"
codesign --verify --strict --verbose=2 "$EXT_PATH"
EXT_SIG_INFO="$(codesign -dvv "$EXT_PATH" 2>&1)"
grep -q "TeamIdentifier=$TEAM_ID" <<< "$EXT_SIG_INFO" \
    || fail "extension is not signed by team $TEAM_ID"
grep -q "Authority=Developer ID Application" <<< "$EXT_SIG_INFO" \
    || fail "extension is not signed with a Developer ID certificate"
grep -q "flags=.*runtime" <<< "$EXT_SIG_INFO" \
    || fail "hardened runtime not enabled (extension)"
grep -q "Timestamp=" <<< "$EXT_SIG_INFO" \
    || fail "extension signature has no secure timestamp"
[[ -f "$EXT_PATH/Contents/embedded.provisionprofile" ]] \
    || fail "extension has no embedded provisioning profile (needed for the Endpoint Security entitlement)"
EXT_ENTITLEMENTS="$(codesign -d --entitlements - "$EXT_PATH" 2>/dev/null)"
grep -q "com.apple.developer.endpoint-security.client" <<< "$EXT_ENTITLEMENTS" \
    || fail "extension lacks the Endpoint Security entitlement"

# --- notarize -------------------------------------------------------------

log "zipping for submission"
ditto -c -k --keepParent "$APP_PATH" "$SUBMIT_ZIP"

log "submitting to notary service (this can take a few minutes)"
SUBMIT_OUTPUT="$(xcrun notarytool submit "$SUBMIT_ZIP" --keychain-profile "$KEYCHAIN_PROFILE" --wait 2>&1 | tee /dev/stderr)"

SUBMISSION_ID="$(printf '%s' "$SUBMIT_OUTPUT" | awk '/^ *id:/ {print $2; exit}')"
STATUS="$(printf '%s' "$SUBMIT_OUTPUT" | awk '/^ *status:/ {print $2}' | tail -1)"

if [[ "$STATUS" != "Accepted" ]]; then
    log "notarization failed (status: ${STATUS:-unknown}), fetching log"
    [[ -n "$SUBMISSION_ID" ]] && xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$KEYCHAIN_PROFILE"
    fail "notarization was not accepted"
fi

# --- staple & package -----------------------------------------------------

log "stapling ticket"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

log "verifying with Gatekeeper"
SPCTL_INFO="$(spctl -a -vv -t exec "$APP_PATH" 2>&1 || true)"
grep -q "source=Notarized Developer ID" <<< "$SPCTL_INFO" \
    || fail "Gatekeeper does not report app as notarized: $SPCTL_INFO"

log "packaging final zip"
mkdir -p "$OUTPUT_DIR"
ditto -c -k --keepParent "$APP_PATH" "$FINAL_ZIP"

log "done: $FINAL_ZIP"
shasum -a 256 "$FINAL_ZIP"
