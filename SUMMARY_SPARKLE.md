# Panduan Rilis ThinkpadAssistent dengan Sparkle 2

Dokumen ini menjelaskan alur rilis versi baru. `SUPublicEDKey` sudah terpasang di
`ThinkpadAssistant/Info.plist`; **private key tidak pernah masuk ke git**.

## Prasyarat (sekali saja)

1. Private key ada di luar repo:

   ```bash
   ls -l ~/Documents/ThinkpadAssistent-PrivateKey.txt
   ```

   Jika hilang, **jangan generate key baru** (user yang sudah install akan gagal verifikasi).
   Pulihkan dari backup. Tool-generate oleh Sparkle:

   ```bash
   ./sparkle/bin/generate_keys --account ThinkpadAssistent \
     -x "$HOME/Documents/ThinkpadAssistent-PrivateKey.txt"
   ```

2. Public key yang dipakai build saat ini (boleh dipublikasikan):

   ```
   hF5bifr2o1b6HsuVNlHWb7/vCA3SC5JVR9EbJRh6+0c=
   ```

3. Xcode dengan macOS SDK 13+ terpasang. Tidak perlu CocoaPods — dependencies
   diambil lewat Swift Package Manager (Sparkle 2.10.1).

## Langkah rilis versi baru

1. **Naikkan versi di Xcode.**
   Buka `ThinkpadAssistant.xcodeproj` → target **ThinkpadAssistant** →
   *General → Identity* → `Version` (`MARKETING_VERSION`) dan `Build`
   (`CURRENT_PROJECT_VERSION`). Versi ini yang dibaca oleh `build_release.sh`
   dari `CFBundleShortVersionString`, jangan ditulis manual di script.

2. **Build + tanda tangani:**

   ```bash
   ./build_release.sh
   ```

   Script akan:
   - `xcodebuild -project ThinkpadAssistant.xcodeproj -scheme ThinkpadAssistant -configuration Release`
     (universal `x86_64 arm64`, ad-hoc signed);
   - membungkus `.app` menjadi `ThinkpadAssistent-X.X.X.zip`;
   - menandatangani zip dengan `sign_update` milik Sparkle + private key lokal;
   - mencetak **path zip**, **length**, dan **edSignature** siap tempel.

3. **Upload zip ke GitHub Releases** dengan tag `vX.X.X`
   (contoh: `v1.0.0`, sesuai `MARKETING_VERSION`). Nama aset harus persis
   `ThinkpadAssistent-X.X.X.zip`.

4. **Update `appcast.xml`** di root repo. Ganti/salin block `<item>` dengan
   nilai dari langkah 2:

   ```xml
   <item>
     <title>Version X.X.X</title>
     <pubDate>Sen, 22 Nov 2026 00:00:00 +0700</pubDate>
     <enclosure
       url="https://github.com/Syuhadak27/ThinkpadAssistent/releases/download/vX.X.X/ThinkpadAssistent-X.X.X.zip"
       sparkle:version="NOMOR_BUILD"
       sparkle:shortVersionString="X.X.X"
       sparkle:edSignature="SIGNATURE_DARI_SCRIPT"
       type="application/octet-stream"
       length="UKURAN_DARI_SCRIPT" />
   </item>
   ```

   `sparkle:version` = `CFBundleVersion`, `sparkle:shortVersionString` =
   `CFBundleShortVersionString`.

5. **Push `appcast.xml` ke `main`.** Sparkle membaca feed dari:

   ```
   https://raw.githubusercontent.com/Syuhadak27/ThinkpadAssistent/main/appcast.xml
   ```

6. **Selesai.** User dengan automatic checks mendapat notifikasi dalam
   ≤24 jam (`SUScheduledCheckInterval = 86400`), atau bisa klik
   **Check for Updates...** di menu bar untuk langsung memeriksa.

## Catatan penting

- Jangan mengubah `SUPublicEDKey` selama aplikasi sudah didistribusikan.
- Jangan pernah commit `~/Documents/ThinkpadAssistent-PrivateKey.txt`, file
  `*.p12`, `*.pem`, `*.cer`, atau `*.mobileprovision`.
- Setelah mengubah file apa pun di dalam zip (termasuk appcast), tanda tangan
  berubah — ulangi langkah 2.
- Cek feed dengan:

  ```bash
  curl -fsSL https://raw.githubusercontent.com/Syuhadak27/ThinkpadAssistent/main/appcast.xml | xmllint --noout -
  ```
