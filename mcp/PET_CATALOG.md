# Katalog karakter dan pose pet

Katalog aset terpasang. Gunakan `list_characters` untuk daftar terbaru setelah aset berubah. Total saat ini 117 pose asli di 6 karakter: 99 pose dari empat paket lama, 6 pose Friday, dan 12 pose Iron Man.

Nama pose di bawah adalah nama animasi asli; alias tidak menambah jumlah pose.

## Nori (`nori`) — 21 pose

| Nama pose | Frame |
|---|---|
| `failed` | 6 |
| `hand-on-knee` | 6 |
| `hug` | 6 |
| `idle` | 6 |
| `interaksi_bawah_1` | 6 |
| `interaksi_bawah_2` | 6 |
| `jumping` | 6 |
| `kiss` | 6 |
| `laughing` | 6 |
| `mood_intense` | 6 |
| `okay-smile` | 6 |
| `review` | 6 |
| `running` | 6 |
| `running-left` | 6 |
| `running-right` | 6 |
| `seated-split` | 6 |
| `sitting` | 6 |
| `skin_base` | 6 |
| `talking` | 6 |
| `waiting` | 6 |
| `waving` | 6 |

Mode standby:
```json
[]
```

Alias pemanggilan:
```json
{
  "hand_on_knee": "hand-on-knee",
  "okay_smile": "okay-smile",
  "running_left": "running-left",
  "running_right": "running-right",
  "seated_split": "seated-split",
  "duduk": "sitting",
  "ketawa": "laughing",
  "peluk": "hug",
  "lompat": "jumping",
  "lambai": "waving",
  "cium": "kiss",
  "senyum": "okay-smile",
  "sedih": "failed",
  "menunggu": "waiting",
  "bicara": "talking",
  "telutut": "hand-on-knee",
  "regang": "seated-split",
  "hide_clothes": "skin_base",
  "horny": "mood_intense",
  "orgasme": "mood_intense",
  "pegang_memek": "interaksi_bawah_1",
  "mainkan_anal": "interaksi_bawah_2"
}
```

## Friday (`friday`) — 5 pose

| Nama pose | Frame |
|---|---:|
| `home_waking_up` | 60 |
| `home_cooking_stir` | 60 |
| `home_sweeping` | 60 |
| `home_watering_plants` | 60 |
| `home_hanging_laundry` | 60 |

Kelima kegiatan memakai animasi loop 5 detik. Mode menunggu dan status lain memakai `home_waking_up`. `home_bathing` tidak dipakai.

Mode standby hanya satu, `rumah` berlabel **Di rumah**: `home_waking_up`, `home_cooking_stir`, `home_sweeping`, `home_watering_plants`, `home_hanging_laundry`. Mode mandi santai tidak dipakai.

Gunakan `play_pose` dengan `character: "friday"` agar nama pose yang sama pada paket lain tidak ambigu. Alias MCP untuk kegiatan Friday:

| Permintaan | Alias pose |
|---|---|
| bangun tidur | `bangun_tidur` |
| masak | `masak` |
| nyapu | `nyapu` |
| nyiram tanaman | `nyiram_tanaman` |
| jemur pakaian | `jemur_pakaian` |
| jemur | `jemur` |

## Iron Man (`iron-man`) — 12 pose percobaan, perlu perbaikan visual

Paket berisi 12 animasi rig bitmap 2D dari gambar Iron Man yang disetujui sebagai sumber armor konsisten. Tiap animasi memiliki 60 frame PNG RGBA unik, 960×1040 pada 30 fps (loop 2 detik), total 720 frame. Build dan ketersediaan MCP telah diverifikasi. Pengguna menolak kualitas visual rig ini karena gerak tidak natural dan proporsi berubah; aset tetap disimpan sebagai percobaan dan menunggu pembuatan ulang.

| Nama pose | Frame |
|---|---:|
| `action_ready` | 60 |
| `action_repulsor_shoot` | 60 |
| `action_jump` | 60 |
| `action_flight` | 60 |
| `action_landing` | 60 |
| `action_running` | 60 |
| `action_dash` | 60 |
| `action_punch` | 60 |
| `action_block` | 60 |
| `action_chest_blast` | 60 |
| `action_scan` | 60 |
| `action_energy_charge` | 60 |

Mode standby (satu mode `action`, label `Standby Action`):
```json
[
  {
    "id": "action",
    "label": "Standby Action",
    "clips": [
      "action_ready",
      "action_repulsor_shoot",
      "action_jump",
      "action_flight",
      "action_landing",
      "action_running",
      "action_dash",
      "action_punch",
      "action_block",
      "action_chest_blast",
      "action_scan",
      "action_energy_charge"
    ]
  }
]
```

Semua 12 klip tersedia melalui MCP. Gunakan `list_characters` dan `list_poses` untuk melihat status terbaru.

## Nori rumah (`nori-rumah`) — 24 pose

| Nama pose | Frame |
|---|---|
| `home_drinking_tea` | 6 |
| `home_eating` | 6 |
| `home_reading_book` | 6 |
| `home_sleeping` | 6 |
| `home_waking_up` | 6 |
| `idle` | 6 |
| `pesona` | 6 |
| `pesona_breathing_v2` | 6 |
| `pesona_check_watch` | 6 |
| `pesona_clapping_v2` | 6 |
| `pesona_hair` | 6 |
| `pesona_hair_v2` | 6 |
| `pesona_hand_heart` | 6 |
| `pesona_knee` | 6 |
| `pesona_knee_v2` | 6 |
| `pesona_listening_v2` | 6 |
| `pesona_nod` | 6 |
| `pesona_rest` | 6 |
| `pesona_rest_v2` | 6 |
| `pesona_shrug` | 6 |
| `pesona_thinking_v2` | 6 |
| `pesona_typing_v2` | 6 |
| `pesona_v2` | 6 |
| `pesona_wave` | 6 |

Mode standby:
```json
[
  {
    "id": "santai",
    "label": "Santai di rumah",
    "clips": [
      "home_drinking_tea",
      "home_reading_book",
      "home_eating"
    ]
  },
  {
    "id": "pagi",
    "label": "Bangun pagi",
    "clips": [
      "home_waking_up",
      "home_drinking_tea"
    ]
  },
  {
    "id": "tidur",
    "label": "Tidur",
    "clips": [
      "home_sleeping"
    ]
  },
  {
    "id": "pesona",
    "label": "Pesona",
    "clips": [
      "pesona",
      "pesona_rest",
      "pesona_hair",
      "pesona_knee"
    ]
  },
  {
    "id": "pesona_v2",
    "label": "Pesona v2",
    "clips": [
      "pesona_v2",
      "pesona_rest_v2",
      "pesona_hair_v2",
      "pesona_knee_v2",
      "pesona_listening_v2",
      "pesona_thinking_v2",
      "pesona_typing_v2",
      "pesona_breathing_v2",
      "pesona_clapping_v2",
      "pesona_wave",
      "pesona_nod",
      "pesona_shrug",
      "pesona_check_watch",
      "pesona_hand_heart"
    ]
  }
]
```

Alias pemanggilan:
```json
{
  "hug": "idle",
  "okay_smile": "idle",
  "laughing": "idle",
  "skin_base": "idle",
  "mood_intense": "idle",
  "ketawa": "idle",
  "peluk": "idle",
  "senyum": "idle",
  "hide_clothes": "idle",
  "horny": "idle",
  "orgasme": "idle"
}
```

## Nori terang (`nori-terang`) — 27 pose

| Nama pose | Frame |
|---|---|
| `failed` | 8 |
| `gym_barbell_squat` | 6 |
| `gym_biceps_curl` | 6 |
| `gym_lat_pulldown` | 6 |
| `gym_leg_press` | 6 |
| `gym_seated_row` | 6 |
| `gym_shoulder_press` | 6 |
| `gym_stationary_cycle` | 6 |
| `gym_treadmill_walk` | 6 |
| `home_cooking_stir` | 6 |
| `home_folding_laundry` | 6 |
| `home_sweeping` | 6 |
| `home_washing_dishes` | 6 |
| `home_washing_hair` | 6 |
| `home_wiping_counter` | 6 |
| `idle` | 6 |
| `jumping` | 5 |
| `review` | 6 |
| `running` | 6 |
| `running-left` | 8 |
| `running-right` | 8 |
| `seated-double-leg-raise` | 8 |
| `seated-straddle-leg-raise` | 5 |
| `standby-fitness` | 6 |
| `standby-stretch` | 7 |
| `waiting` | 6 |
| `waving` | 4 |

Mode standby:
```json
[
  {
    "id": "fitness",
    "label": "Fitness",
    "clips": [
      "standby-fitness",
      "standby-stretch",
      "seated-double-leg-raise",
      "seated-straddle-leg-raise"
    ]
  },
  {
    "id": "gym",
    "label": "Gym",
    "clips": [
      "gym_barbell_squat",
      "gym_leg_press",
      "gym_biceps_curl",
      "gym_shoulder_press",
      "gym_lat_pulldown",
      "gym_seated_row",
      "gym_treadmill_walk",
      "gym_stationary_cycle"
    ]
  },
  {
    "id": "rumah",
    "label": "Di rumah",
    "clips": [
      "home_sweeping",
      "home_cooking_stir",
      "home_washing_dishes",
      "home_wiping_counter",
      "home_folding_laundry",
      "home_washing_hair"
    ]
  }
]
```

Alias pemanggilan:
```json
{
  "running_left": "running-left",
  "running_right": "running-right",
  "seated_double_leg_raise": "seated-double-leg-raise",
  "seated_straddle_leg_raise": "seated-straddle-leg-raise",
  "standby_fitness": "standby-fitness",
  "standby_stretch": "standby-stretch",
  "talking": "waiting",
  "kiss": "waving",
  "hug": "idle",
  "okay_smile": "idle",
  "laughing": "idle",
  "sitting": "seated-double-leg-raise",
  "seated_split": "standby-stretch",
  "hand_on_knee": "standby-stretch",
  "skin_base": "idle",
  "interaksi_bawah_1": "seated-double-leg-raise",
  "interaksi_bawah_2": "seated-straddle-leg-raise",
  "mood_intense": "idle",
  "duduk": "seated-double-leg-raise",
  "ketawa": "idle",
  "peluk": "idle",
  "lompat": "jumping",
  "lambai": "waving",
  "cium": "waving",
  "senyum": "idle",
  "sedih": "failed",
  "menunggu": "waiting",
  "bicara": "waiting",
  "telutut": "standby-stretch",
  "regang": "standby-stretch",
  "hide_clothes": "idle",
  "horny": "idle",
  "orgasme": "idle",
  "pegang_memek": "seated-double-leg-raise",
  "mainkan_anal": "seated-straddle-leg-raise"
}
```

## Put (`put`) — 27 pose

| Nama pose | Frame |
|---|---|
| `failed` | 8 |
| `gym_barbell_squat` | 6 |
| `gym_biceps_curl` | 6 |
| `gym_lat_pulldown` | 6 |
| `gym_leg_press` | 6 |
| `gym_seated_row` | 6 |
| `gym_shoulder_press` | 6 |
| `gym_stationary_cycle` | 6 |
| `gym_treadmill_walk` | 6 |
| `home_cooking_stir` | 6 |
| `home_folding_laundry` | 6 |
| `home_sweeping` | 6 |
| `home_washing_dishes` | 6 |
| `home_washing_hair` | 6 |
| `home_wiping_counter` | 6 |
| `idle` | 6 |
| `jumping` | 5 |
| `review` | 6 |
| `running` | 6 |
| `running-left` | 8 |
| `running-right` | 8 |
| `seated-double-leg-raise` | 8 |
| `seated-straddle-leg-raise` | 5 |
| `standby-fitness` | 6 |
| `standby-stretch` | 7 |
| `waiting` | 6 |
| `waving` | 4 |

Mode standby:
```json
[
  {
    "id": "fitness",
    "label": "Fitness",
    "clips": [
      "standby-fitness",
      "standby-stretch",
      "seated-double-leg-raise",
      "seated-straddle-leg-raise"
    ]
  },
  {
    "id": "gym",
    "label": "Gym",
    "clips": [
      "gym_barbell_squat",
      "gym_leg_press",
      "gym_biceps_curl",
      "gym_shoulder_press",
      "gym_lat_pulldown",
      "gym_seated_row",
      "gym_treadmill_walk",
      "gym_stationary_cycle"
    ]
  },
  {
    "id": "rumah",
    "label": "Di rumah",
    "clips": [
      "home_sweeping",
      "home_cooking_stir",
      "home_washing_dishes",
      "home_wiping_counter",
      "home_folding_laundry",
      "home_washing_hair"
    ]
  }
]
```

Alias pemanggilan:
```json
{
  "running_left": "running-left",
  "running_right": "running-right",
  "seated_double_leg_raise": "seated-double-leg-raise",
  "seated_straddle_leg_raise": "seated-straddle-leg-raise",
  "standby_fitness": "standby-fitness",
  "standby_stretch": "standby-stretch",
  "talking": "waiting",
  "kiss": "waving",
  "hug": "idle",
  "okay_smile": "idle",
  "laughing": "idle",
  "sitting": "seated-double-leg-raise",
  "seated_split": "standby-stretch",
  "hand_on_knee": "standby-stretch",
  "skin_base": "idle",
  "interaksi_bawah_1": "seated-double-leg-raise",
  "interaksi_bawah_2": "seated-straddle-leg-raise",
  "mood_intense": "idle",
  "duduk": "seated-double-leg-raise",
  "ketawa": "idle",
  "peluk": "idle",
  "lompat": "jumping",
  "lambai": "waving",
  "cium": "waving",
  "senyum": "idle",
  "sedih": "failed",
  "menunggu": "waiting",
  "bicara": "waiting",
  "telutut": "standby-stretch",
  "regang": "standby-stretch",
  "hide_clothes": "idle",
  "horny": "idle",
  "orgasme": "idle",
  "pegang_memek": "seated-double-leg-raise",
  "mainkan_anal": "seated-straddle-leg-raise"
}
```

## Pemanggilan MCP

Jika aplikasi belum berjalan, panggil `start_pet` dahulu. Karakter dapat diganti tanpa restart. Beberapa pose diputar berurutan.

```text
list_characters {}
list_poses {"character":"friday"}
play_pose {"character":"friday","pose":"home_waking_up"}
set_pet_character {"character":"nori-rumah"}
play_pose {"character":"nori","poses":["lambai","lompat"]}
```

Gunakan parameter character untuk nama pose yang sama. get_pet_status menunjukkan pose aktif dan antrean.
