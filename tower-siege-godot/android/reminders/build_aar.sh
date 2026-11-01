#!/bin/sh
# Builds the reminders library (Reminders.aar) that the export plugin in addons/reminders adds
# to the app: compiles the two Java classes against Android's android.jar and packs them with
# the manifest that declares the receiver. Usage: build_aar.sh ANDROID_SDK_ROOT [API]
set -e
here="$(cd "$(dirname "$0")" && pwd)"
sdk="$1"
api="${2:-36}"
out="$here/../../addons/reminders/Reminders.aar"
tmp="$(mktemp -d)"
mkdir -p "$tmp/classes" "$tmp/aar"
javac --release 17 -cp "$sdk/platforms/android-$api/android.jar" -d "$tmp/classes" "$here"/src/com/towersiege/reminders/*.java
(cd "$tmp/classes" && jar cf "$tmp/aar/classes.jar" .)
cp "$here/AndroidManifest.xml" "$tmp/aar/AndroidManifest.xml"
: > "$tmp/aar/R.txt"
rm -f "$out"
(cd "$tmp/aar" && jar cfM "$out" AndroidManifest.xml classes.jar R.txt)
rm -rf "$tmp"
echo "built $out"
