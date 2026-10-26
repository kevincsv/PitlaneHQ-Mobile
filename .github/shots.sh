#!/usr/bin/env bash
# One picture per screen of the Android app in each language, with the demo data (see ShotMode.kt).
set -e
mkdir -p shots
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell settings put system screen_off_timeout 600000
# no "isn't responding" windows of the emulator's own apps over the pictures
adb shell settings put global hide_error_dialogs 1 || true
sleep 45
adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null 2>&1 || true
for lang in es en; do
  for s in home live analysis:0 analysis:1 analysis:2 analysis:3 race community; do
    adb shell am force-stop com.pitlanehq.android
    adb shell am start -W -n com.pitlanehq.android/.MainActivity --es shot "$s" --es lang "$lang" >/dev/null
    sleep 10
    adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null 2>&1 || true
    sleep 2
    adb exec-out screencap -p > "shots/$lang-${s/:/-}.png"
  done
done
ls -la shots
