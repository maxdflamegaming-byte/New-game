#!/bin/sh
# Builds the game's Android library (Reminders.aar) that the export plugin in addons/reminders
# adds to the app: scheduled reminders, the screen's refresh rate, and rewarded ads. Compiles
# the Java classes against Android's android.jar (and, for the ads, against the Google Mobile
# Ads library, fetched by fetch_ads.py) and packs them with the manifest.
# Usage: build_aar.sh ANDROID_SDK_ROOT [API]
# ADMOB_APP_ID (environment) = the game's AdMob app id; without it, Google's test app id, which
# only ever shows test ads. If the ads library can't be fetched, the library is built without ads.
set -e
here="$(cd "$(dirname "$0")" && pwd)"
sdk="$1"
api="${2:-36}"
addon="$here/../../addons/reminders"
out="$addon/Reminders.aar"
app_id="${ADMOB_APP_ID:-ca-app-pub-3940256099942544~3347511713}"
tmp="$(mktemp -d)"
mkdir -p "$tmp/classes" "$tmp/aar" "$tmp/ads"
rm -f "$addon/ads_version.txt"
sources="$here/src/com/towersiege/reminders/*.java"
cp_extra=""
if python3 "$here/fetch_ads.py" "$tmp/ads"; then
  sources="$sources $here/src/com/towersiege/ads/*.java"
  cp_extra=$(ls "$tmp"/ads/*.jar | tr '\n' ':')
  cp "$tmp/ads/version.txt" "$addon/ads_version.txt"
else
  echo "warning: the Google Mobile Ads library couldn't be fetched; building without ads"
fi
javac --release 17 -cp "$cp_extra$sdk/platforms/android-$api/android.jar" -d "$tmp/classes" $sources
(cd "$tmp/classes" && jar cf "$tmp/aar/classes.jar" .)
sed "s/ADMOB_APP_ID/$app_id/" "$here/AndroidManifest.xml" > "$tmp/aar/AndroidManifest.xml"
: > "$tmp/aar/R.txt"
rm -f "$out"
(cd "$tmp/aar" && jar cfM "$out" AndroidManifest.xml classes.jar R.txt)
rm -rf "$tmp"
echo "built $out (AdMob app id $app_id)"
