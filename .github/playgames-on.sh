#!/usr/bin/env bash
# Adds Google Play Games to the build: switches on the plugin in godot/addons/GodotPlayGameServices,
# puts the Play Games ID in both Android export presets and moves the APK to the Gradle build
# (the plugin's Android library needs it). Used by the build workflows; it only changes the
# CI checkout, never the repository.
#   .github/playgames-on.sh <Play Games ID>
set -euo pipefail
id="$1"
if ! [[ "$id" =~ ^[0-9]+$ ]]; then
  echo "The Play Games ID must be a number (Play Console -> Play Games Services), got: $id" >&2
  exit 1
fi
cd "$(dirname "$0")/../godot"

cat >> project.godot <<'EOF'

[autoload]

GodotPlayGameServices="*res://addons/GodotPlayGameServices/scripts/autoloads/godot_play_game_services.gd"
EOF
# Add the plugin to the enabled list (the AdMob plugin is already on it)
if grep -q '^enabled=PackedStringArray(' project.godot; then
  sed -i 's|^enabled=PackedStringArray(\(.*\))$|enabled=PackedStringArray(\1, "res://addons/GodotPlayGameServices/plugin.cfg")|' project.godot
else
  printf '\n[editor_plugins]\n\nenabled=PackedStringArray("res://addons/GodotPlayGameServices/plugin.cfg")\n' >> project.godot
fi
grep '^enabled=' project.godot

# Both presets: the ID, and the Gradle build
sed -i "s/^gradle_build\/use_gradle_build=.*/gradle_build\/use_gradle_build=true/" export_presets.cfg
sed -i "/^\[preset\.[0-9]*\.options\]$/a godot_play_game_services/game_id=\"$id\"" export_presets.cfg

grep -c "godot_play_game_services/game_id=\"$id\"" export_presets.cfg
grep "use_gradle_build" export_presets.cfg
echo "Google Play Games is on (ID $id)"
