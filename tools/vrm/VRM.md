# Karakter VRM 3D

Klik kanan pet atau ikon menu bar → **Impor Karakter 3D (.vrm)…**.
Pilih file VRM 0.x atau VRM 1.0 hasil ekspor VRoid Studio; file `.vroid`
adalah proyek editor dan harus diekspor terlebih dahulu. Model disalin ke
`~/Library/Application Support/PetAsisten/VRM/`, dan pilihan dipulihkan saat
aplikasi dibuka kembali. Impor gagal tidak mengganti karakter yang sedang aktif.

Setelah model dimuat, pilih **Gerakan 3D** pada menu klik kanan atau pilih
**Pose** di jendela chat. Pilihan meliputi sedih, senang, loncat, tertawa,
berpikir, merenung dengan satu lutut terangkat, duduk bersila, bersimpuh,
tepuk tangan, mengangguk, menggeleng, membungkuk, dan meregangkan badan.
Lambai, berjalan, berbicara, dan jalan lalu bicara juga tersedia.

Ketik nama pendek seperti `merenung`, `duduk bersila`, `bersimpuh`, `tepuk tangan`,
`tertawa`, `loncat`, atau `jalan lalu bicara`. Awalan `coba` atau `tolong`
diterima. Perintah ini diputar lokal saat karakter 3D aktif; percakapan lain
tetap dikirim ke asisten. `berdiri` mengembalikan pose santai.
Pose duduk dan merenung berlangsung 15 detik, kemudian kembali ke standby.

Animasi memakai tulang humanoid, IK dua sendi untuk posisi tangan/kaki,
perpaduan quaternion saat berganti pose, kedipan, dan ekspresi wajah.
Ini animasi prosedural, belum motion capture. Kontak tangan dan kaki dapat
bergeser selama transisi atau pada model dengan proporsi berbeda. Animasi
mulut belum mengikuti fonem audio. Berjalan berlangsung di area pet.
Pilih **Kembali ke Karakter PNG** atau pilih paket karakter PNG di chat
untuk kembali ke animasi gambar.

Renderer memakai WebKit, Three.js, dan @pixiv/three-vrm yang dibundel lokal.
Tidak membutuhkan jaringan atau Node.js saat aplikasi dijalankan. Untuk
memperbarui bundle JavaScript setelah mengedit `tools/vrm/viewer.js` atau `tools/vrm/motions.js`:

```bash
cd tools/vrm
npm ci
npm test
npm run build
cd ../..
./build.sh
```

Lisensi dependency tersedia di `Resources/vrm/licenses/`.

## Verifikasi native

`smoke.swift` menguji pemuatan model, lambai, snapshot transparan, dan mouse
passthrough di WKWebView. `integration-smoke.swift` menguji impor tersembunyi
melalui PetView, routing gestur, resize, dan pemulihan PNG. Keduanya adalah
harness terpisah dari aplikasi; kompilasi sebagai `main.swift` dalam bundle
sementara yang berisi salinan `Resources/vrm`. Model pengujian tidak dibundel.
Model contoh pengujian berasal dari pixiv/three-vrm:
https://github.com/pixiv/three-vrm/tree/dev/packages/three-vrm/examples/models

`npm test` memeriksa IK, nilai transform 21 gerakan pada tulang model 3D bawaan,
dan pemulihan tinggi pinggul setelah duduk.
