# Panduan MCP Pet untuk Hermes, OpenCode, dan agent lain

Tujuan: menggerakkan pet melalui tool MCP yang benar-benar dieksekusi, lalu melaporkan hasil aplikasi. Menulis contoh pemanggilan dalam jawaban tidak mengirim perintah.

## Alur penggunaan

1. Panggil `get_pet_status` untuk mengetahui apakah pet berjalan dan karakter yang aktif.
2. Jika `running` bernilai false, panggil `start_pet`, lalu periksa status kembali. Proses start belum berarti aplikasi sudah siap menerima pose.
3. Panggil `list_characters` atau `list_poses` untuk melihat nama yang tersedia saat ini. Katalog dibaca dari aset terpasang.
4. Tentukan karakter dan pose sesuai permintaan pengguna. Gunakan `character` secara eksplisit agar nama yang sama tidak tertukar.
5. Eksekusi `play_pose` melalui antarmuka tool agent, lalu baca hasilnya.
6. Nyatakan berhasil hanya jika hasil aplikasi memuat `ok: true`. `current_pose` adalah pose pertama; `accepted_poses` adalah daftar yang diterima; `queued_poses` adalah pose berikutnya yang menunggu.

Animasi diputar sementara, kemudian pet kembali ke standby. Pemeriksaan status setelah animasi selesai dapat menunjukkan pose standby; ini bukan kegagalan pemanggilan. Beberapa pose dikirim dalam satu panggilan `poses`, bukan beberapa panggilan paralel yang dapat saling mengganti animasi aktif.

## Nama karakter dan pose

| Nama tampilan | ID untuk parameter character | Jumlah pose saat panduan dibuat |
|---|---|---:|
| Nori | `nori` | 21 |
| Nori rumah | `nori-rumah` | 24 |
| Nori terang | `nori-terang` | 27 |
| Put | `put` | 27 |
| Friday | `friday` | 5 |
| Iron Man | `iron-man` | 12 |

Katalog lengkap: `PET_CATALOG.md` di direktori yang sama. Utamakan hasil `list_characters` untuk daftar terbaru.

Dropdown aplikasi menggunakan nama unik seperti `Put · gym_barbell_squat`. Untuk MCP, pisahkan menjadi `character: "put"` dan `pose: "gym_barbell_squat"`. Jangan mengirim seluruh judul dropdown sebagai parameter `pose`. Alias adalah nama alternatif atau fallback; alias tidak menambah animasi asli.

Jika pengguna tidak menyebut karakter, pertahankan karakter aktif apabila pose asli tersedia di sana. Jika pose hanya dimiliki satu karakter, gunakan karakter tersebut. Jika beberapa karakter menyediakan pose dan maksud pengguna belum jelas, tanyakan karakter tujuan.

## Tool yang tersedia

| Tool server | Parameter | Fungsi |
|---|---|---|
| `get_pet_status` | `{}` | Status proses, model, karakter, pose aktif, dan antrean |
| `list_characters` | `{}` | Katalog semua karakter, pose, alias, dan mode standby |
| `list_poses` | `{}` atau `{"character":"nori-rumah"}` | Semua pose atau pose satu karakter |
| `play_pose` | `character`, serta `pose` atau `poses` | Ganti karakter bila perlu dan putar animasi |
| `set_pet_character` | `{"character":"put"}` | Ganti karakter tanpa restart |
| `start_pet` | `{}` | Nyalakan aplikasi pet |
| `show_pet` | `{}` | Munculkan pet yang tersembunyi |
| `open_pet_chat` | `{}` | Munculkan pet; klik karakter untuk membuka panel chat |
| `set_pet_size` | `{"scale":1.0}` | Ukuran pet, rentang 0.5–2.0 |

## Hermes

Nama tool model-facing Hermes memakai awalan `mcp__pet__`, misalnya `mcp__pet__play_pose`.

Jika tool tampil langsung dalam daftar tool, panggil langsung dengan argumen JSON. Jika tool ditunda/deferred, muat deskripsinya melalui `tool_describe`, lalu gunakan `tool_call` dengan nama terdaftar yang sama.

Contoh argumen `tool_describe`:

```json
{"names":["mcp__pet__play_pose"]}
```

Contoh argumen `tool_call` setelah tool dimuat:

```json
{"calls":[{"name":"mcp__pet__play_pose","arguments":{"character":"put","pose":"gym_barbell_squat"}}]}
```

Eksekusi sebagai tool nyata. Nama bare `play_pose` dalam `tool_call` tidak sama dengan nama Hermes yang terdaftar. Hasil dapat dibungkus sebagai teks JSON di dalam hasil tool; baca `ok` dari respons aplikasi, bukan hanya status transport.

Server `pet` harus terdaftar dan aktif di `~/.hermes/config.yaml`. Jika daftar tool CLI dibatasi, tambahkan `pet` sambil mempertahankan toolset lainnya:

```yaml
platform_toolsets:
  cli:
    - file
    - skills
    - terminal
    - vision
    - pet
```

Cek koneksi dengan `hermes mcp test pet`. Tes koneksi saja tidak membuktikan tool aktif dalam sesi model. Uji end-to-end harus menghasilkan pemanggilan nyata `mcp__pet__play_pose` dan respons aplikasi `ok: true`. Untuk tes CLI yang hanya memuat MCP pet, gunakan `hermes chat -t pet`; nama filter server adalah `pet`.

## OpenCode dan agent MCP lain

Gunakan nama tool yang benar-benar ditampilkan oleh client. Nama server adalah `pet`, tetapi awalan nama tool dapat berbeda antar-client; jangan mengasumsikan awalan Hermes berlaku di semua client. Argumen `character`, `pose`, dan `poses` tetap sama.

OpenCode sudah menggunakan server lokal. Cek dengan `opencode mcp list`. Jika belum terdaftar, daftarkan dengan:

```bash
opencode mcp add pet --global -- python3 /Users/surya/pet/mcp/pet_mcp.py
```

Untuk client MCP lain, konfigurasi transport stdio:

```json
{"mcpServers":{"pet":{"command":"python3","args":["/Users/surya/pet/mcp/pet_mcp.py"]}}}
```

Sesuaikan struktur konfigurasi dengan client. Client harus berjalan pada Mac yang menjalankan aplikasi pet, atau memiliki eksekusi remote di Mac tersebut: server ini berkomunikasi melalui file lokal `~/.pet`.

## Contoh argumen pemanggilan

Satu pose Nori rumah:

```json
{"character":"nori-rumah","pose":"pesona_wave"}
```

Put melakukan squat:

```json
{"character":"put","pose":"gym_barbell_squat"}
```

### Iron Man

Paket ini adalah percobaan rig 2D yang perlu diperbaiki secara visual. Perintah berikut tetap berfungsi, tetapi gerakan dan proporsi tubuhnya belum diterima pengguna. Karakter aktif dikembalikan ke Friday.

Menembakkan repulsor:

```json
{"character":"iron-man","pose":"action_repulsor_shoot"}
```

Melompat lalu terbang:

```json
{"character":"iron-man","poses":["action_jump","action_flight"]}
```

Nori melambai lalu melompat:

```json
{"character":"nori","poses":["waving","jumping"]}
```

Untuk permintaan percakapan seperti “Nori rumah, coba melambai”, agent mencari pose yang sesuai lalu mengeksekusi contoh pertama. Contoh JSON di panduan ini adalah argumen tool, bukan perintah shell.

## Menghindari kegagalan

- Jika respons berisi `isError` atau `ok: false`, laporkan alasan dan perbaiki sesuai pesan tool; jangan mengklaim pose sudah berubah.
- Jika pose tidak tersedia, baca `list_poses` untuk karakter tujuan. Jangan mengubah aset atau kode aplikasi untuk memperbaiki kesalahan nama.
- Jika karakter ambigu, gunakan ID karakter eksplisit.
- Jika pet berhenti atau belum siap, nyalakan lalu cek status sebelum mencoba kembali.
- Jika request timeout, periksa status terlebih dahulu: perintah mungkin sudah mulai berjalan. Jangan langsung mengulang pose tanpa memeriksa.
- Setelah memanggil pose lewat MCP, jangan menyisipkan tag `[POSE: ...]`, `[MESH: ...]`, atau `[EXPR: ...] dalam balasan yang sama. Parser legacy dapat menimpa animasi yang baru diputar.
- Jangan mengganti MCP dengan tulisan `echo ...` di jawaban atau menulis langsung ke `poses.command`. Jalur lama itu tidak memilih karakter otomatis dan tidak memberi konfirmasi aplikasi.

## Petunjuk singkat untuk system prompt agent

> Untuk mengubah pose pet, gunakan tool MCP server pet secara nyata. Periksa katalog, tentukan character dan pose, lalu panggil play_pose. Untuk beberapa pose gunakan satu daftar poses agar diputar berurutan. Nyatakan berhasil hanya setelah respons aplikasi ok true. Jangan menulis pemanggilan tool sebagai teks pengganti eksekusi dan jangan menambahkan tag pose legacy setelah menggunakan MCP. Baca PET_MCP_GUIDE.md untuk nama tool sesuai client dan PET_CATALOG.md untuk katalog lengkap.

Friday (`friday`) memiliki lima pose terpasang: `home_waking_up`, `home_cooking_stir`, `home_sweeping`, `home_watering_plants`, dan `home_hanging_laundry` (masing-masing 60 frame, loop 5 detik). Status menunggu memakai bangun tidur. `home_bathing` tidak dipakai. Mode standby-nya hanya `rumah` (Di rumah: waking up, cooking, sweeping, watering plants, hanging laundry). Mode mandi tidak dipakai. Periksa `list_characters` untuk detailnya. Gunakan `play_pose` dengan `character: "friday"` untuk menghindari ambiguitas. Alias MCP menerima `bangun_tidur`, `masak`, `nyapu`, `nyiram_tanaman`, `jemur_pakaian`, dan `jemur`.
