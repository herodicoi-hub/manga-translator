#!/usr/bin/env bash
# Adds the INTERNET permission to the Android manifest after `flutter create .`
# (release builds cannot reach the Gemini API without it).
set -euo pipefail

MANIFEST="android/app/src/main/AndroidManifest.xml"

if ! grep -q "android.permission.INTERNET" "$MANIFEST"; then
  sed -i 's|<application|<uses-permission android:name="android.permission.INTERNET"/>\n    <application|' "$MANIFEST"
  echo "Added INTERNET permission to $MANIFEST"
else
  echo "INTERNET permission already present"
fi
