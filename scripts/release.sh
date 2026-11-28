#!/usr/bin/env bash
# Builds, signs, notarizes, and packages a Claude Monitor release into build/release.
# Usage: scripts/release.sh
# Environment: NOTARY_PROFILE (default notary-profile), ALLOW_DIRTY=1 to build a test release from a tree with changes.

set -euo pipefail

cd "$(dirname "$0")/.."

notary_profile="${NOTARY_PROFILE:-notary-profile}"
out="build/release"
app="$out/export/ClaudeMonitor.app"

step() { printf '\n==> %s\n' "$1"; }
fail() { printf 'error: %s\n' "$1" >&2; exit 1; }

# Signature, stapled ticket, and Gatekeeper checks.
verify_app() {
  local assessment
  codesign --verify --deep --strict "$1" || fail "the signature of $1 is not valid."
  xcrun stapler validate -q "$1" || fail "$1 has no valid stapled ticket."
  assessment="$(spctl --assess --type execute --verbose=2 "$1" 2>&1)" || fail "Gatekeeper rejected $1: $assessment"
  grep -q "source=Notarized Developer ID" <<<"$assessment" \
    || fail "the Gatekeeper source of $1 is not Notarized Developer ID: $assessment"
}

changes="$(git status --porcelain)"
if [[ -n "$changes" && "${ALLOW_DIRTY:-0}" != 1 ]]; then
  fail "the working tree has changes. Commit them, or set ALLOW_DIRTY=1 for a test release."
fi
[[ "$(git symbolic-ref --short -q HEAD || true)" == "main" ]] || fail "HEAD is not on the main branch."
commit="$(git rev-parse HEAD)"

version="$(awk -F'"' '/^ *MARKETING_VERSION:/ { print $2; exit }' project.yml)"
[[ -n "$version" ]] || fail "cannot read MARKETING_VERSION from project.yml. Write the value in double quotes."
if git rev-parse -q --verify "refs/tags/v$version" >/dev/null; then
  fail "the tag v$version exists. Set a new MARKETING_VERSION in project.yml."
fi
remote_tag=0
git ls-remote --exit-code --tags origin "refs/tags/v$version" >/dev/null || remote_tag=$?
case "$remote_tag" in
  0) fail "the tag v$version exists on origin. Set a new MARKETING_VERSION in project.yml." ;;
  2) ;;
  *) fail "cannot read the tags of origin." ;;
esac

# Section of this version, up to the next section or the link references.
notes="$(awk -v heading="## [$version]" '
  index($0, heading) == 1 { found = 1; next }
  !found { next }
  /^## \[/ || /^\[[^]]*\]: / { exit }
  /^[[:space:]]*$/ { if (started) blanks++; next }
  { while (blanks > 0) { print ""; blanks-- }; started = 1; print }
' CHANGELOG.md)"
[[ -n "$notes" ]] || fail "CHANGELOG.md has no entries for $version. Add a section '## [$version] - <date>'."

team_id="$(/usr/libexec/PlistBuddy -c 'Print :teamID' scripts/ExportOptions.plist)"
archive="build/archives/ClaudeMonitor-$version.xcarchive"
zip_name="ClaudeMonitor-$version.zip"

rm -rf "$out" "$archive"
mkdir -p "$out" build/archives
printf '%s\n' "$notes" >"$out/release-notes.md"

step "Archive $version from $commit"
xcodebuild -project ClaudeMonitor.xcodeproj -scheme ClaudeMonitor -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$archive" -quiet archive

step "Export with Developer ID"
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath "$out/export" -quiet

built_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
[[ "$built_version" == "$version" ]] \
  || fail "the app has version $built_version, but project.yml has $version. Run xcodegen generate."
echo "Version $version ($build)"

minimum_macos="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist")"
# Homebrew symbols from Library/Homebrew/macos_version.rb.
case "${minimum_macos%%.*}" in
  14) macos_symbol="sonoma" ;;
  15) macos_symbol="sequoia" ;;
  26) macos_symbol="tahoe" ;;
  27) macos_symbol="golden_gate" ;;
  *) fail "no Homebrew symbol for LSMinimumSystemVersion $minimum_macos. Add it to scripts/release.sh." ;;
esac

step "Check the signature"
codesign --verify --deep --strict "$app"
signature="$(codesign --display --verbose=2 "$app" 2>&1)"
grep -q "^Authority=Developer ID Application: .*($team_id)$" <<<"$signature" \
  || fail "the app is not signed with the Developer ID Application certificate of team $team_id."
grep -q "flags=.*runtime" <<<"$signature" || fail "the app does not use the hardened runtime."

step "Notarize"
ditto -c -k --keepParent "$app" "$out/notarize.zip"
# Status read from the output because notarytool can exit nonzero on rejection.
result="$(xcrun notarytool submit "$out/notarize.zip" --keychain-profile "$notary_profile" --wait --output-format json)" || true
status="$(plutil -extract status raw -o - - <<<"$result" 2>/dev/null)" || status=""
submission="$(plutil -extract id raw -o - - <<<"$result" 2>/dev/null)" || submission=""
if [[ "$status" != "Accepted" ]]; then
  if [[ -n "$submission" ]]; then
    xcrun notarytool log "$submission" --keychain-profile "$notary_profile" "$out/notary-log.json" || true
  fi
  fail "notarization status is '${status:-unknown}'. Output: $result"
fi
echo "Submission $submission accepted"
rm "$out/notarize.zip"

step "Staple"
# Retries because the ticket can reach Apple's servers some seconds after acceptance.
for attempt in 1 2 3 4; do
  if xcrun stapler staple "$app"; then
    break
  fi
  [[ "$attempt" -lt 4 ]] || fail "cannot staple the ticket."
  sleep 15
done
verify_app "$app"

step "Package"
# No extended attributes, so that unzip does not add AppleDouble files to the signed bundle.
ditto -c -k --keepParent --norsrc --noextattr --noacl "$app" "$out/$zip_name.tmp"
mkdir "$out/zip-check"
unzip -q "$out/$zip_name.tmp" -d "$out/zip-check"
verify_app "$out/zip-check/ClaudeMonitor.app"
rm -rf "$out/zip-check"
mv "$out/$zip_name.tmp" "$out/$zip_name"
sha256="$(shasum -a 256 "$out/$zip_name" | awk '{ print $1 }')"
sed -e "s/@VERSION@/$version/" -e "s/@SHA256@/$sha256/" -e "s/@MACOS@/$macos_symbol/" \
  scripts/claude-monitor.rb.template >"$out/claude-monitor.rb"

step "Done"
cat <<EOF
Zip:     $out/$zip_name
SHA256:  $sha256
Cask:    $out/claude-monitor.rb
Notes:   $out/release-notes.md
Archive: $archive
Commit:  $commit

Next:
  git push origin main
  git tag v$version $commit
  git push origin v$version
  gh release create v$version $out/$zip_name --repo Eric0625/ClaudeMonitor --title $version --notes-file $out/release-notes.md --verify-tag
  Copy $out/claude-monitor.rb to Casks/claude-monitor.rb in Eric0625/homebrew-tap. Commit and push it.
EOF
if [[ -n "$changes" ]]; then
  printf '\nWARNING: this build has uncommitted changes. Do not publish it.\n' >&2
fi
