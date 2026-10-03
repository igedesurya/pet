# Generator gambar lokal

ComfyUI v0.38.0 tersedia di `/Users/surya/.local/share/comfyui`.
Runtime Python terpisah: `/Users/surya/.local/share/comfy-runtime`.
Model awal: DreamShaper 8, checkpoint SD 1.5 (~2.1 GB), dengan checksum SHA-256 yang sudah diverifikasi dari metadata sumber Lykon/DreamShaper.

## Menjalankan

```bash
cd /Users/surya/.local/share/comfyui
/Users/surya/.local/share/comfy-runtime/bin/python main.py --listen 127.0.0.1 --port 8188 --disable-api-nodes --disable-all-custom-nodes
```

Buka `http://127.0.0.1:8188`. Server hanya menerima koneksi lokal; workflow draft menggunakan model lokal. Ctrl+C di terminal server untuk menghentikannya.

## MCP Codex

Server `comfy-local` terdaftar secara global, command:
`/Users/surya/.local/share/comfy-runtime/bin/comfy-mcp`.
Environment `COMFY_BIN` menunjuk executable `comfy` di runtime yang sama. Pengaturan default comfy-cli menunjuk workspace ComfyUI di atas.

Cek dengan `codex mcp get comfy-local`. Jika daftar tool chat yang sudah terbuka belum memuat server baru, muat ulang sesi/klien. Tool koneksi sudah diuji melalui MCP SDK (39 tool ditemukan).

Alur agent: `server_info` → `run_workflow` dengan workflow API → pantau job → `fetch_outputs`. Jangan memakai template default dengan checkpoint yang tidak terpasang. Model yang sudah tersedia bernama `DreamShaper_8_pruned.safetensors`.

## Draft Iron Man

Workflow yang dijalankan: `/Users/surya/pet/artwork/iron-man-draft/workflow-api.json`.
Prompt, negative prompt, seed, dan pengaturan sampler tersimpan di workflow tersebut.
Model DreamShaper 8, resolusi 512×768, 24 langkah, Euler, CFG 7, seed 3072026.

Script uji:

```bash
python3 /Users/surya/pet/tools/generate_local_draft.py
```

Script membuat satu job dan menyimpan gambar ke `/Users/surya/pet/artwork/iron-man-draft/iron-man-draft-v1.png`. Script uji ini menggunakan nama keluaran tetap; salin draft lama terlebih dahulu jika ingin menyimpan versi sebelum menjalankan ulang. Jika timeout, baca job.json dan periksa history job sebelum mengirim ulang.

Hasil awal adalah konsep dengan latar putih, belum sprite transparan dan belum paket animasi. Persetujuan desain mendahului produksi frame. Daftar lama berisi 99 entri pose lintas empat karakter, dengan beberapa nama gerakan sama; pemetaan gerakan karakter baru perlu dibahas setelah konsep disetujui.

Sumber:
- https://github.com/Comfy-Org/ComfyUI
- https://github.com/Comfy-Org/comfy-mcp
- https://huggingface.co/Lykon/DreamShaper
