#!/usr/bin/env bash
# Build Pet Asisten menjadi bundle .app di bin/Pet.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/bin/Pet.app"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> compile swift"
swiftc \
  -O \
  -swift-version 5 \
  -framework AppKit \
  -framework AVFoundation \
  -framework Speech \
  "$ROOT/Sources/"*.swift \
  -o "$APP/Contents/MacOS/pet"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# aset karakter (frame animasi hasil ekstraksi sprite sheet)
rm -rf "$APP/Contents/Resources/character" "$APP/Contents/Resources/characters"
cp -R "$ROOT/Resources/character" "$APP/Contents/Resources/character"
if [ -d "$ROOT/Resources/characters" ]; then
  cp -R "$ROOT/Resources/characters" "$APP/Contents/Resources/characters"
fi

# ad-hoc sign supaya macOS bisa mengingat izin mikrofon & speech recognition
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
  echo "   (peringatan: codesign gagal, izin mikrofon mungkin diminta ulang)"

echo "==> selesai: $APP"
