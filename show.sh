#!/usr/bin/env bash
# Munculkan kembali pet yang sedang disembunyikan.
# Kalau pet belum jalan, sekalian dinyalakan.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

if pgrep -f "Pet.app/Contents/MacOS/pet" >/dev/null; then
  mkdir -p "$HOME/.pet"
  touch "$HOME/.pet/show.request"
  sleep 1
  echo "Pet dimunculkan kembali."
else
  echo "Pet belum jalan, menyalakan..."
  "$ROOT/run.sh"
fi
