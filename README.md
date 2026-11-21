<div><img src="ThinkpadAssistant/Assets.xcassets/AppIcon.appiconset/appIcon-64-min.png" width="48" height="48" align="left"/><h1>Thinkpad Assistant</h1></div>

Aplikasi pendamping untuk laptop ThinkPad seri T yang dijalankan sebagai macOS (Hackintosh). Aplikasi ini mengembalikan fungsi tombol keyboard, mengatur batas pengisian baterai lewat YogaSMC, dan memeriksa rilis terbaru langsung dari GitHub.

> Versi ini ditujukan untuk **macOS Ventura 13 ke atas**. Binary hasil build bersifat **universal** (x86_64 + arm64) dan ditandatangani secara ad-hoc.

---

## Fitur

### Tombol fungsi

| Tombol | Fungsi |
|---|---|
| **F4** | Bisu / aktifkan mikrofon (dengan indikator LED status) |
| **F7** | Cerminkan / perpanjang layar |
| **F8** | Aktifkan / nonaktifkan Wi-Fi |
| **Shift + F8** | Aktifkan / nonaktifkan Bluetooth |
| **F9** | Buka Pengaturan Sistem |
| **F12** | Buka Launchpad |
| **Fn + Spasi** | Aktifkan / nonaktifkan lampu keyboard |

### Pengatur batas pengisian baterai (Battery Threshold)

Fitur ini memakai jalur yang benar-benar ada di **YogaSMC 1.5.3** (kext lokal di folder `Refrensi-YogaSMC/Kexts/`), bukan SMC key yang sering disebut di internet.

Hasil audit terhadap binary referensi:

- `B0St`, `B0Sp`, `B0En`, `B1St`, `B1Sp`, `B1En` **tidak ada** di YogaSMC.
- `B0St` yang beredar berasal dari **SMCBatteryManager 1.3.8** dan artinya **status baterai**, bukan batas pengisian.
- Batas pengisian ditulis lewat properti `ThinkVPC`:
  - `setCMstart` → method ACPI `BCCS` → EC
  - `setCMstop` → method ACPI `BCSS` → EC
  - `setCMInhibitCharge` → `BICS`
  - `setCMForceDischarge` → `BDSS`
  - `setCMPeakShiftState` → `PSSS`

Aplikasi hanya menulis properti tersebut. Logika `setCMstart`/`setCMstop` → `BCCS`/`BCSS` tidak diubah.

### Pemeriksa pembaruan

Menu **Check for Updates...** menanyakan rilis terbaru dari:

```
https://api.github.com/repos/Syuhadak27/ThinkpadAssistent/releases/latest
```

Saat aplikasi dibuka, pengecekan dilakukan diam-diam. Bila ada tag rilis baru, judul menu berubah menjadi `Update Available (vN)` dan muncul pilihan **Download**, **Skip This Version**, atau **Later**.

---

## Tampilan menu

Menu utama di menu bar:

```
About Thinkpad Assistant
Monitor Capslock ✓
Launch on Login ✓
Battery Threshold >
Check for Updates...
Quit
```

Submenu **Battery Threshold**:

```
BAT0 - 64% - Charging ⚡
Threshold: Start 75% → Stop 85%

Set Start Charge At  >
Set Stop Charge At   >

[✓] Enable Threshold
Refresh Threshold
```

Keterangan:

- Baris pertama diambil dari `AppleSmartBattery` di IORegistry (persentase nyata, status `Charging ⚡` / `Not Charging 🔌` / `Discharging 🔋`).
- Nama baterai dideteksi otomatis (`BAT0` atau `BAT1`); hanya satu baterai yang ditampilkan.
- Pilihan Start/Stop tersedia dari 0% sampai 100% dengan kelipatan 5%.
- **Enable Threshold** dinonaktifkan → mengirim `setCMstart=0`, `setCMstop=100`, `setCMInhibitCharge=0`.
- **Enable Threshold** diaktifkan → mengirim nilai Start/Stop yang dipilih.
- Kode internal YogaSMC (`BCTG`, `BCSG`) tidak pernah ditampilkan di antarmuka; hanya masuk log debug untuk keperluan audit.

---

## Instalasi

### Persyaratan

1. macOS **Ventura 13 atau lebih baru**.
2. **YogaSMC 1.5.3** terpasang dan aktif di EFI (kext `YogaSMC-VENTURA.kext` untuk Ventura, `YogaSMC-SEQUOIA.kext` untuk Sequoia).
3. SSDT pendukung sudah ada di `EFI/OC/ACPI` (misalnya `SSDT-THINK.aml`, `SSDT-BATX.aml`).
4. Aplikasi **tidak disandbox** karena harus menulis properti ke IOService milik kext.

### Langkah

1. Unduh `ThinkpadAssistant-macOS.zip` dari halaman [Rilis GitHub](https://github.com/Syuhadak27/ThinkpadAssistent/releases).
2. Ekstrak, lalu pindahkan `ThinkpadAssistant.app` ke folder **Aplikasi**.
3. Karena aplikasi ditandatangani secara ad-hoc, jalankan dulu di Terminal bila macOS menolak:

   ```bash
   xattr -cr /Applications/ThinkpadAssistant.app
   ```

4. Jalankan aplikasi, lalu centang **Launch on Login** di menu bar agar otomatis berjalan saat masuk.
5. Buka **Battery Threshold** dan atur nilai Start/Stop sesuai keinginan.

### SSDT tombol keyboard

Folder `Samples/` berisi pasangan patch dan SSDT untuk beberapa model (T440p, T460, T480, X1C6). Cara umumnya:

```bash
iasl -vo SSDT-T460-KBRD.dsl
```

Lalu salin file `.aml` hasil kompilasi ke `EFI/OC/ACPI` dan terapkan patch yang sesuai ke `config.plist`.

---

## Build otomatis (GitHub Actions)

Dua workflow tersedia di `.github/workflows/`:

| File | Fungsi |
|---|---|
| `build.yml` | Build Release untuk branch selain `master` dan pull request |
| `release.yml` | Build Release untuk `master` / tag `v*`, lalu membuat atau memperbarui GitHub Release |

Keduanya memakai runner **macos-15-intel** dan argumen:

```
MACOSX_DEPLOYMENT_TARGET=13.0
ARCHS='x86_64 arm64'
CODE_SIGN_IDENTITY=-
```

Hasil build dikemas sebagai `ThinkpadAssistant-macOS.zip` dan diunggah ke rilis GitHub.

Folder `Refrensi-YogaSMC/` hanya dipakai sebagai **referensi audit** dan tidak pernah dimasukkan ke target build Xcode.

---

## Catatan penting

- Batas pengisian sangat bergantung pada method ACPI `BCCS`/`BCSS` di firmware ThinkPad. Kalau method tidak ada, penulisan threshold akan gagal dan aplikasi menampilkan pesan kesalahan.
- Ikon **petir ⚡** berarti baterai benar-benar sedang diisi. Ikon **colokan 🔌** berarti AC terpasang tetapi pengisian berhenti (misalnya karena batas Stop sudah tercapai).
- Start threshold adalah batas saat pengisian **dimulai kembali** setelah berhenti; Stop threshold adalah batas saat pengisian **dihentikan**. mengubah Start saja tidak selalu menghentikan pengisian yang sedang berjalan.
- Detail lengkap audit SMC key, offset binary, dan alur panggilan ada di [`SUMMARY.md`](SUMMARY.md).

---

## Repository

https://github.com/Syuhadak27/ThinkpadAssistent
