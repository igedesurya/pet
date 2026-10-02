#!/usr/bin/env bash
# Memicu gestur si pet dari terminal.
#
#   ./pose.sh duduk
#   ./pose.sh ketawa peluk        # beberapa sekaligus
#   ./pose.sh list                # lihat semua gestur
#
# Cara ini juga yang bisa dipakai agent (MCP) untuk menggerakkan si pet.
set -euo pipefail

COMMAND_FILE="$HOME/.pet/poses.command"
mkdir -p "$HOME/.pet"

if [ $# -eq 0 ]; then
  echo "pakai: ./pose.sh <gestur> [gestur...]"
  echo "atau:  ./pose.sh list"
  exit 1
fi

if [ "$1" = "list" ]; then
  echo "Gestur yang tersedia:"
  printf '  %s\n' duduk ketawa peluk lompat lambai cium senyum sedih menunggu bicara telutut regang skin_base interaksi_bawah_1 interaksi_bawah_2 mood_intense gym_barbell_squat gym_leg_press gym_biceps_curl gym_shoulder_press gym_lat_pulldown gym_seated_row gym_treadmill_walk gym_stationary_cycle home_sweeping home_cooking_stir home_washing_dishes home_wiping_counter home_folding_laundry home_washing_hair
  exit 0
fi

if ! pgrep -f "Pet.app/Contents/MacOS/pet" >/dev/null; then
  echo "Pet belum jalan. Jalankan ./run.sh dulu."
  exit 1
fi

for pose in "$@"; do
  printf '%s\n' "$pose" >> "$COMMAND_FILE"
done

echo "Dikirim ke pet: $*"
