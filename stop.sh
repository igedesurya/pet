#!/usr/bin/env bash
# Hentikan Pet Asisten.
set -euo pipefail

if pkill -f "Pet.app/Contents/MacOS/pet"; then
  echo "Pet Asisten dihentikan."
else
  echo "Pet Asisten sedang tidak berjalan."
fi
