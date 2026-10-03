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
  printf '  %s\n' duduk ketawa peluk lompat lambai cium senyum sedih menunggu bicara telutut regang skin_base interaksi_bawah_1 interaksi_bawah_2 mood_intense gym_barbell_squat gym_leg_press gym_biceps_curl gym_shoulder_press gym_lat_pulldown gym_seated_row gym_treadmill_walk gym_stationary_cycle home_sweeping home_cooking_stir home_washing_dishes home_wiping_counter home_folding_laundry home_washing_hair home_drinking_tea home_reading_book home_eating home_waking_up home_sleeping pesona pesona_rest pesona_hair pesona_knee pesona_v2 pesona_rest_v2 pesona_hair_v2 pesona_knee_v2 pesona_wave pesona_nod pesona_shrug pesona_check_watch pesona_hand_heart pesona_listening_v2 pesona_thinking_v2 pesona_typing_v2 pesona_breathing_v2 pesona_clapping_v2
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
