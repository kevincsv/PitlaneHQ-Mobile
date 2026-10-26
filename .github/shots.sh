#!/usr/bin/env bash
# One picture per screen of the Android app, in Spanish, with the demo data (see ShotMode.kt).
set -e
mkdir -p shots
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell settings put system screen_off_timeout 600000
for s in home live analysis:0 analysis:1 analysis:2 analysis:3 race community; do
  adb shell am force-stop com.pitlanehq.android
  adb shell am start -W -n com.pitlanehq.android/.MainActivity --es shot "$s" --es lang es >/dev/null
  sleep 12
  adb exec-out screencap -p > "shots/${s/:/-}.png"
done
ls -la shots
