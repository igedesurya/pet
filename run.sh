#!/usr/bin/env bash
# Build kalau perlu, lalu jalankan Pet Asisten.
# Kalau pet sudah jalan tapi sedang disembunyikan, dia akan dimunculkan lagi.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

if [ ! -d "$ROOT/bin/Pet.app" ]; then
  "$ROOT/build.sh"
fi

open "$ROOT/bin/Pet.app"
echo "Pet Asisten dijalankan (kalau sedang disembunyikan, dia dimunculkan)."
