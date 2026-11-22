<div><img src="ThinkpadAssistant/Assets.xcassets/AppIcon.appiconset/appIcon-64-min.png" width="48" height="48" align="left"/><h1>Thinkpad Assistant</h1></div>

Aplikasi menu bar untuk ThinkPad X260 (dan seri T lain) yang dijalankan di macOS / Hackintosh.
Fokus utamanya adalah **Battery Threshold 20–100%** lewat YogaSMC, dikombinasikan dengan
pemulihan tombol fungsi keyboard dan pembaruan otomatis via Sparkle 2.

> **macOS Ventura 13 ke atas • Universal (x86_64 + arm64) • Ad-hoc signed**

---

## Tampilan Menu Bar

Ikon kecil di menu bar (di dekat ikon baterai) adalah status item aplikasi. Klik untuk membuka menu:

```
About Thinkpad Assistant
Monitor Capslock ✓
Launch on Login ✓
Battery Threshold >
Check for Updates...
Automatically Check for Updates ✓
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

---

## Fitur

### Battery Threshold 20–100%

- Mengatur batas **Start** dan **Stop** pengisian (0–100%, langkah 5%) lewat properti
  `ThinkVPC` milik YogaSMC 1.5.3.
- `setCMstart` → ACPI `BCCS`, `setCMstop` → ACPI `BCSS`, `setCMInhibitCharge` → `BICS`.
- Tidak memakai SMC key `B0St`/`B0Sp`/`B0En` yang sering disebut di internet
  (audit detail ada di [`SUMMARY.md`](SUMMARY.md)).
- Saat **Enable Threshold** dimatikan, nilai dikirim `start=0`, `stop=100`,
  `inhibit=0` (pengisian penuh seperti semula).

### Monitor Baterai / Status Sistem

- Baris pertama submenu menampilkan persentase baterai nyata dari `AppleSmartBattery`
  beserta status `Charging ⚡` / `Not Charging 🔌` / `Discharging 🔋`.
- Nama baterai (`BAT0` / `BAT1`) dideteksi otomatis.
- Untuk metrik CPU/RAM, gunakan `Activity Monitor.app`; status item aplikasi ini
  difokuskan pada baterai dan threshold.

### Menu Bar Icon & Tombol Fungsi

Ikon menu bar memakai `menuIcon` (light/dark otomatis). Tombol keyboard yang didukung:

| Tombol | Fungsi |
|---|---|
| **F4** | Bisu / aktifkan mikrofon |
| **F7** | Cerminkan / perpanjang layar |
| **F8** | Wi-Fi on/off |
| **Shift + F8** | Bluetooth on/off |
| **F9** | Pengaturan Sistem |
| **F12** | Launchpad |
| **Fn + Spasi** | Lampu keyboard |

### Update otomatis (Sparkle 2)

- **Check for Updates...** memanggil `SPUStandardUpdaterController.checkForUpdates(nil)`.
- **Automatically Check for Updates** (default ON) mengontrol
  `updater.automaticallyChecksForUpdates`.
- Feed: `https://raw.githubusercontent.com/Syuhadak27/ThinkpadAssistent/main/appcast.xml`
- Cek otomatis tiap 86400 detik (24 jam). Tanpa internet, Sparkle menampilkan
  error dialog standar — aplikasi tidak crash.

---

## Instalasi

1. Unduh zip terbaru dari [GitHub Releases](https://github.com/Syuhadak27/ThinkpadAssistent/releases).
2. Ekstrak dan pindahkan `ThinkpadAssistant.app` ke folder **Applications**.
3. Karena binary ad-hoc signed, jalankan sekali:

   ```bash
   xattr -cr /Applications/ThinkpadAssistant.app
   ```

4. Jalankan aplikasi, centang **Launch on Login** jika ingin otomatis.
5. Buka **Battery Threshold**, pilih Start/Stop, lalu aktifkan **Enable Threshold**.

Persyaratan: YogaSMC 1.5.3 aktif di EFI dan SSDT pendukung terpasang. Aplikasi
tidak disandbox karena harus menulis properti IOKit milik kext.

---

## Cara Update

- Otomatis: Sparkle mengecek tiap 24 jam dan menampilkan dialog saat ada versi baru.
- Manual: klik ikon di menu bar → **Check for Updates...**.
- Matikan/nyalakan otomatis lewat **Automatically Check for Updates** di menu yang sama.

---

## Build dari Source

Butuh **Xcode** (macOS 13+ SDK). Tidak perlu CocoaPods; dependency diambil via
Swift Package Manager (Sparkle 2.10.1).

```bash
git clone https://github.com/Syuhadak27/ThinkpadAssistent.git
cd ThinkpadAssistent
open ThinkpadAssistant.xcodeproj
# Pilih scheme ThinkpadAssistant → Product > Build (⌘B)
```

Atau lewat CLI:

```bash
xcodebuild -project ThinkpadAssistant.xcodeproj \
  -scheme ThinkpadAssistant \
  -configuration Release \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  ARCHS='x86_64 arm64'
```

Hasil: `build/Build/Products/Release/ThinkpadAssistant.app`.

---

## Rilis Versi Baru (ringkasan)

1. Naikkan `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` di Xcode.
2. Jalankan `./build_release.sh` → menghasilkan zip + `edSignature` + `length`.
3. Upload `ThinkpadAssistent-X.X.X.zip` ke GitHub Releases dengan tag `vX.X.X`.
4. Update `appcast.xml` dengan signature, length, dan URL baru.
5. Push `appcast.xml` ke `main`.

Panduan lengkap ada di [`SUMMARY_SPARKLE.md`](SUMMARY_SPARKLE.md).

---

## Lisensi

MIT — lihat [`LICENSE`](LICENSE).

## Repository

https://github.com/Syuhadak27/ThinkpadAssistent
