#!/bin/sh
set -e
cd "$(dirname "$0")/.."

VERSION="${1:?usage: Scripts/release.sh <version>}"
REPO="${GITHUB_REPOSITORY:-sam-b-rose/writer-mac}"
OUT=build/release
ZIP="Writer-$VERSION.zip"
TAG="v$VERSION"
BIN=.build/artifacts/sparkle/Sparkle/bin

KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" Resources/Info.plist)
[ -n "$KEY" ] || { echo "Set SUPublicEDKey in Resources/Info.plist (run $BIN/generate_keys)" >&2; exit 1; }

VERSION="$VERSION" ./build.sh

rm -rf "$OUT"
mkdir -p "$OUT"

if [ -n "$DEVELOPER_ID" ]; then
  : "${NOTARY_PROFILE:?set NOTARY_PROFILE to a notarytool keychain profile}"
  ditto -c -k --keepParent build/Writer.app "$OUT/notarize.zip"
  xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple build/Writer.app
  rm "$OUT/notarize.zip"
fi

ditto -c -k --keepParent build/Writer.app "$OUT/$ZIP"

if [ -n "$SPARKLE_PRIVATE_KEY" ]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$BIN/generate_appcast" --ed-key-file - --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" "$OUT"
else
  "$BIN/generate_appcast" --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" "$OUT"
fi

SHA=$(shasum -a 256 "$OUT/$ZIP" | cut -d' ' -f1)
sed -e "s/@VERSION@/$VERSION/g" -e "s/@SHA256@/$SHA/g" -e "s#@REPO@#$REPO#g" Scripts/writer.rb.template > "$OUT/writer.rb"

echo "Release artifacts in $OUT"
echo "  $ZIP  sha256 $SHA"
echo "Publish: gh release create $TAG $OUT/$ZIP $OUT/appcast.xml --repo $REPO --title $TAG --generate-notes"
echo "Cask: copy $OUT/writer.rb to Casks/writer.rb in your homebrew tap"
