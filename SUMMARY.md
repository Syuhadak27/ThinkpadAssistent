# SUMMARY — Audit SMC Key dari Referensi Lokal YogaSMC

**Tanggal audit:** 21 November 2026
**Referensi yang dibaca:** `Refrensi-YogaSMC/` (nama folder aslinya; bukan `refrensi/`)
**Target:** project `ThinkpadAssistant`

---

## 1. Apa isi folder referensi (penting dibaca dulu)

Folder referensi **bukan source code**. Isinya kext hasil build. Struktur saat ini (folder sudah berisi salinan lengkap `Kexts/` dari EFI):

```
Refrensi-YogaSMC/
└── Kexts/                         <-- 37 kext EFI (Lilu, VirtualSMC, SMCBatteryManager, ...)
    ├── YogaSMC-VENTURA.kext/
    │   └── Contents/
    │       ├── Info.plist
    │       ├── _CodeSignature/CodeResources
    │       └── MacOS/YogaSMC      <-- Mach-O 64-bit x86_64 kext, 344.352 byte
    └── YogaSMC-SEQUOIA.kext/
        └── Contents/
            ├── Info.plist
            ├── _CodeSignature/CodeResources
            └── MacOS/YogaSMC      <-- Mach-O 64-bit x86_64 kext, 344.352 byte
```

Semua path ke binary di dokumen ini mengikuti struktur `Refrensi-YogaSMC/Kexts/...`.

Tidak ada satu pun file `.cpp`, `.hpp`, `.c`, `.h`, atau `.dsl` di dalamnya.

Data identitas kext (dari `Contents/Info.plist`):

| Item | Nilai |
|---|---|
| CFBundleIdentifier | `org.zhen.YogaSMC` |
| CFBundleShortVersionString | `1.5.3` |
| BuildMachineOSBuild | `20G817` |
| DTXcode / SDK | `13C100` / `macosx12.1` |

**Kedua binary byte-per-byte identik** (bukan cuma mirip):

```
md5 4649f6d4e5655a5308c2aba7c1a71110  YogaSMC-VENTURA.kext/Contents/MacOS/YogaSMC
md5 4649f6d4e5655a5308c2aba7c1a71110  YogaSMC-SEQUOIA.kext/Contents/MacOS/YogaSMC
```

Artinya: folder VENTURA dan SEQUOIA isinya kext yang sama persis. Semua offset di bawah berlaku untuk **kedua** file.

---

## 2. Soal "nomor baris"

Karena referensi tidak punya source code, **nomor baris tidak ada**. Sebagai gantinya saya pakai lokasi yang bisa diverifikasi ulang:

- **Offset byte** di dalam file `Contents/MacOS/YogaSMC` (hex). Alamat di `__TEXT` = offset file (segment `__TEXT` fileoff = 0).
- **Alamat disassembly** (hex) untuk lokasi instruksi yang mendaftarkan key.
- Untuk string: offset dari `strings -t x`.

Cara reproduksi ada di bagian 7.

---

## 3. Daftar SMC Key yang BENAR-BENAR terdaftar di YogaSMC lokal

SMC key didaftarkan lewat `VirtualSMCAPI::addKey(...)`. Di binary ini ada 4 fungsi `addVSMCKey()`:

- `YogaSMC::addVSMCKey()` (base, tabel temperatur)
- `ThinkSMC::addVSMCKey()` (jalur ThinkPad — ThinkVPC)
- `IdeaSMC::addVSMCKey()`
- `DYSMC::addVSMCKey()`

### 3.1 `ThinkSMC::addVSMCKey()` — jalur ThinkPad (ThinkVPC)

Fungsi: `ThinkSMC::addVSMCKey()` @ disasm `0x000D83A`

| SMC Key | Type | Size | Flags | Alamat disasm (movl key) | Offset byte immediate |
|---|---|---|---|---|---|
| `BDVT` | `flag` | 1 | `0xC0` | `0x000D8D3` | `0x000D8D4` |
| `CH0B` | `hex_` | 1 | `0xC0` | `0x000D953` | `0x000D954` |
| `FNum` | `ui8 ` | 1 | `0x88` | `0x000D994` | `0x000D995` |
| `F0Ac` | `fpe2` | 2 | `0x80` | `0x000DA32` | `0x000DA33` |
| `F1Ac` | `fpe2` | 2 | `0x80` | `0x000DADA` | `0x000DADB` |

### 3.2 `IdeaSMC::addVSMCKey()`

Fungsi: `IdeaSMC::addVSMCKey()` @ disasm `0x0008346`

| SMC Key | Type | Size | Flags | Alamat disasm | Offset byte immediate |
|---|---|---|---|---|---|
| `BDVT` | `flag` | 1 | `0xC0` | `0x00083DC` | `0x00083DD` |
| `CH0B` | `hex_` | 1 | `0xC0` | `0x0008453` | `0x0008454` |
| `F0Ac` | `fpe2` | 2 | `0x80` | `0x000852F` | `0x0008530` |
| `F1Ac` | `fpe2` | 2 | `0x80` | `0x00085EF` | `0x00085F0` |
| `FNum` | `ui8 ` | 1 | `0x88` | `0x000863A` | `0x000863B` |
| `F0Mx` | `fpe2` | 2 | `0xC0` | `0x000869D` | `0x000869E` |
| `F1Mx` | `fpe2` | 2 | `0xC0` | `0x00086ED` | `0x00086EE` |
| `TPCD` | `sp78` | 2 | `0x80` | `0x00087BA` | `0x00087BB` |
| `TCXC` | `sp78` | 2 | `0x80` | `0x00088A2` | `0x00088A3` |
| `TCGC` | `sp78` | 2 | `0x80` | `0x000898A` | `0x000898B` |

### 3.3 `DYSMC::addVSMCKey()`

Fungsi: `DYSMC::addVSMCKey()` @ disasm `0x000F1BA`

| SMC Key | Type | Size | Flags | Alamat disasm | Offset byte immediate |
|---|---|---|---|---|---|
| `FNum` | `ui8 ` | 1 | `0x88` | `0x000F8B9` | `0x000F8BA` |

### 3.4 `YogaSMC::addVSMCKey()` — key temperatur (tabel statis)

Fungsi: `YogaSMC::addVSMCKey()` @ disasm `0x0015D22`

Tabel `presetTemperatureDeciKelvin` @ file offset `0x00025310` (entry 16 byte, type `sp78`, size 2, flags `0x80`):

| SMC Key | Offset entry |
|---|---|
| `TB0T` | `0x00025310` |
| `TB1T` | `0x00025320` |
| `TB2T` | `0x00025330` |

Tabel `presetTemperature` @ file offset `0x00025340` (entry 16 byte, type `sp78`, size 2, flags `0x80`):

| SMC Key | Offset entry |
|---|---|
| `TCSA` | `0x00025340` |
| `TCXC` | `0x00025350` |
| `TM0P` | `0x00025360` |
| `TM0p` | `0x00025370` |
| `TM1p` | `0x00025380` |
| `TM2p` | `0x00025390` |
| `TM3p` | `0x000253A0` |
| `TPCD` | `0x000253B0` |
| `TW0P` | `0x000253C0` |
| `TaLC` | `0x000253D0` |
| `TaRC` | `0x000253E0` |
| `Th1H` | `0x000253F0` |
| `Th2H` | `0x00025400` |
| `Ts0P` | `0x00025410` |
| `Ts1P` | `0x00025420` |

**Itu saja SMC key yang didaftarkan build YogaSMC 1.5.3 ini.**

Catatan 1: `strings` memang menemukan 125 string 4 karakter (mis. `BCCS`, `BCTG`, `MHKA`, `VPCR`), tapi mayoritas adalah **nama method ACPI / nama property IOUserClient**, bukan SMC key. Buktinya di bagian 4.

Catatan 2: nama-nama di `Info.plist` seperti `TBAT`, `CPEC`, `CTMP`, `MEM1`, `RSEN`, `TMP0`, `ESTA` adalah nama sensor ACPI/EC untuk fitur WMI, **bukan** SMC key. Jangan dicampur.

---

## 4. Battery Threshold — hasil audit

### 4.1 Key yang diminta: TIDAK ADA

Pencarian di **kedua** binary (`grep -a`, case-insensitive, seluruh file):

| Key yang diminta | Status di referensi lokal |
|---|---|
| `B0St` | **TIDAK ADA** |
| `B0Sp` | **TIDAK ADA** |
| `B0En` | **TIDAK ADA** |
| `B1St` | **TIDAK ADA** |
| `B1Sp` | **TIDAK ADA** |
| `B1En` | **TIDAK ADA** |

Pola `B0xx` / `B1xx` apa pun (mis. `B0AC`, `B0FC`, `B0RM`, `B0TE`) juga **tidak ada** di binary ini.

Jadi saya **tidak memakai** key-key tersebut di ThinkpadAssistant. Kalau dipakai, itu berarti mengarang.

Catatan: kalau `B0St`/`B0Sp`/`B0En` memang ada di sistem X260, key itu berasal dari komponen lain (bukan YogaSMC 1.5.3 di folder ini). Komponen tersebut **tidak ada di folder referensi**, jadi tidak bisa saya jadikan acuan. Sesuai aturan, saya tidak menebak.

### 4.1b Bukti tambahan dari EFI lokal: `B0St` ternyata milik SMCBatteryManager

Karena penasaran, saya cek juga kext lain yang benar-benar dipakai X260 ini (folder EFI lokal, **bukan** dari internet):

`/storage/emulated/0/thinkpad-x260-opencore-ventura-sequoia/EFI/OC/Kexts/SMCBatteryManager.kext`

- Versi: `1.3.8`
- Binary: `Contents/MacOS/SMCBatteryManager` (universal; slice x86_64 md5 `b0d7a8ff5d01bee9bf96866f5c7f8ef6`)
- Di sinilah `B0St` berasal.

Key `B0xx` yang dibangun SMCBatteryManager (prefix `B` + index `0..F` + suffix, lihat loop di `SMCBatteryManager::start()`):

| Key | Dibangun di (disasm x86_64) | Arti |
|---|---|---|
| `B0AC` | `0x0059FD` (`orl $0x43410042`) | AC terpasang |
| `B0AV` | `0x005A99` | voltage |
| `B0BI` | `0x005B39` | battery info |
| `B0CT` | `0x005BD9` | cycle count |
| `B0FC` | `0x005C79` | full charge capacity |
| `B0PS` | `0x005D19` | power source |
| `B0RM` | `0x005DA9` | remaining capacity |
| `B0St` | `0x005E49` (`orl $0x74530042`) | **status baterai** (charging/discharging), lihat `B0St::readAccess()` @ `0x003AF0` |
| `B0T1` / `B0TD` / `B0TF` / `B0TL` | — | temperatur |

**Penting:** `B0St` = status baterai (0x4000 charging / 0x4800 charged / dst), **bukan threshold**.
`B0Sp` dan `B0En` **tidak ada**; yang paling mirip namanya adalah `B0PS` (power source) dan `ACEN` (AC enable) — dua-duanya bukan threshold.

Saya juga sudah scan **102 binary kext dari 3 folder EFI lokal** (`thinkpad-x260-opencore-ventura`, `thinkpad-x260-OpenCore`, `thinkpad-x260-opencore-ventura-sequoia`): tidak ada satu pun yang mengandung `B0Sp`, `B0En`, `B1St`, `B1Sp`, atau `B1En`. `B0St` hanya muncul di `SMCBatteryManager`.

Jadi kesimpulannya tetap: **key threshold `B0St/B0Sp/B0En/B1St/B1Sp/B1En` tidak ada di sistem lokal ini.**

### 4.2 Mekanisme Battery Threshold yang benar-benar dipakai YogaSMC

Battery threshold di YogaSMC **bukan lewat SMC key**, tapi lewat **properti IOUserClient** yang diteruskan ke **method ACPI**. Semuanya ada di fungsi `ThinkVPC::setPropertiesGated()` @ disasm `0x000628E`.

#### Set (tulis threshold)

| Property yang dikirim app | Method ACPI yang dieksekusi | Offset string property | Offset string method |
|---|---|---|---|
| `setCMstart` | `BCCS` | `0x0001767C` | `0x00017687` |
| `setCMstop` | `BCSS` | `0x0001768C` | `0x00017696` |
| `setCMInhibitCharge` | `BICS` | `0x0001769B` | `0x000176AE` |
| `setCMForceDischarge` | `BDSS` | `0x000176B3` | `0x000176C7` |
| `setCMPeakShiftState` | `PSSS` | `0x000176CC` | `0x000176E0` |

#### Get (baca threshold)

Dibaca oleh `ThinkVPC::updateBattery()` @ disasm `0x000522C`, hasilnya dipublikasikan sebagai property IORegistry:

- `BAT_ANY` (`0x0001765A`)
- `BAT_PRIMARY` (`0x00017662`)
- `BAT_SECONDARY` (`0x0001766E`)

Isi dictionary-nya memakai key:

| Key di dictionary | Offset string |
|---|---|
| `BCTG` | `0x00017641` |
| `BCSG` | `0x00017646` |
| `BICG` | `0x0001764B` |
| `BDSG` | `0x00017650` |
| `PSSG` | `0x00017655` |

Pemilihan `BAT_ANY` / `BAT_PRIMARY` / `BAT_SECONDARY` berdasarkan property `Battery` (`0x00016FB3`) yang berisi index 0/1/2.

> Catatan kejujuran: binary hanya memberi nama key, bukan label UI. Dari penamaan, `BCSG` paling mungkin "charge start get" dan `BCTG` "charge threshold get (stop)", tetapi **saya tidak menemukan bukti eksplisit** mana yang start dan mana yang stop. Karena itu jangan hard-code label tanpa verifikasi di mesin X260.

### 4.3 Alur tulis threshold ke EC

```
App / IOUserClient
   │  setProperties({ "setCMstart": <nilai> })
   ▼
ThinkVPC::setPropertiesGated()          @ 0x000628E
   │  baca angka dari dict
   ▼
ThinkVPC::setConservation(method, val)  @ 0x0005A24
   │  arg = (batteryIndex << 8) | val     (batteryIndex di [this+0x178])
   ▼
YogaVPC::evaluateIntegerParam()         @ 0x0013CAE
   │  ACPI evaluate method
   ▼
Method ACPI: BCCS / BCSS / BICS / BDSS / PSSS
   │  (method inilah yang menulis ke EC di namespace ACPI)
   ▼
EC (charge start / charge stop / inhibit / discharge / peak shift)
```

Untuk get:

```
ThinkVPC::updateBattery()               @ 0x000522C
   ▼
ThinkVPC::updateConservation(method,dict,update) @ 0x0005970
   ▼
YogaVPC::evaluateIntegerParam()         @ 0x0013CAE
   ▼
Method ACPI: BCTG / BCSG / BICG / BDSG / PSSG
   ▼
setProperty("BAT_PRIMARY", dict)        @ 0x0005331
```

### 4.4 Soal HKEY

`HKEY` **tidak dipakai** untuk battery threshold. Di binary, HKEY hanya untuk hotkey:

- `HKEY Setting` @ `0x0001747A`
- `HKEY Property` @ `0x0001757C`
- Method terkait: `MHKA`, `MHKB`, `MHKC`, `MHKM`, `MHKN`, `MHKP`, `MHKS`, `MHKV`

### 4.5 Jalur EC langsung (RE1B / WE1B)

YogaSMC juga punya jalur baca/tulis EC langsung lewat method ACPI `RE1B` (read EC 1 byte) dan `WE1B` (write EC 1 byte):

- `RE1B` @ `0x00018AFB`
- `WE1B` @ `0x00018B9A`
- `YogaBaseService::method_re1b()` @ `0x000E74A`
- `YogaBaseService::method_we1b()` @ `0x000EA40`
- Contoh pemakaian: `ThinkSMC::updateECVendor()` @ `0x000DB34` (baca EC `0x84`/`0x85`, tulis EC `0x31`)

Tapi **threshold baterai tidak lewat jalur ini** di build ini; threshold lewat method ACPI `BCCS`/`BCSS` di atas.

### 4.6 Satu-satunya SMC key yang menyentuh baterai

`CH0B` (`hex_`, 1 byte, flags `0xC0`) — didaftarkan di `ThinkSMC::addVSMCKey()` @ `0x000D953`.
Key ini **bukan** threshold; di kelas `CH0B` (lihat `CH0B::writeAccess()` @ `0x000AE0E` dan `CH0B::update()` @ `0x000AE16`) nilainya hanya disalin ke buffer, dan `writeAccess()` mengembalikan `false`.

---

## 5. Status ThinkpadAssistant

### 5.1 SMC key yang ada di ThinkpadAssistant

Hasil pencarian di seluruh source (`*.swift`, `*.m`, `*.h`, `*.pbxproj`):

```
grep -rniE 'B0St|B0Sp|B0En|B1St|B1Sp|B1En|SMC|AppleSMC|IOServiceOpen|IOConnect' ThinkpadAssistant/
```

**Tidak ada satu pun SMC key / kode SMC di ThinkpadAssistant.**

Jadi:
- Tidak ada key yang bentrok.
- Tidak ada key yang perlu diganti.
- Tidak ada yang bisa "disamakan" karena memang belum ada implementasi battery threshold.

### 5.2 Folder referensi tidak ikut build

`Refrensi-YogaSMC/` **tidak** terdaftar di `ThinkpadAssistant.xcodeproj/project.pbxproj`:

```
grep -n 'Refrensi\|refrensi' ThinkpadAssistant.xcodeproj/project.pbxproj
# (tidak ada hasil)
```

Folder referensi tetap hanya untuk dibaca dan tidak masuk target build.

### 5.3 Kalau nanti mau implementasi battery threshold

Satu-satunya jalur yang terbukti ada di referensi YogaSMC lokal:

1. Cari IOService dengan `IOClass = ThinkVPC` (lihat `Info.plist` referensi; `IOUserClientClass = YogaSMCUserClient`).
2. Set threshold dengan mengirim dictionary properti:
   - `{"setCMstart": <0-100>}` untuk batas start
   - `{"setCMstop": <0-100>}` untuk batas stop
   - lewat `IORegistryEntrySetCFProperties(service, dict)` atau `IOConnectSetCFProperties(connection, dict)`.
3. Baca status lewat property `BAT_PRIMARY` / `BAT_SECONDARY` / `BAT_ANY` (dictionary berisi `BCTG`, `BCSG`, `BICG`, `BDSG`, `PSSG`).

Catatan penting sebelum coding:
- App ini **sandboxed** (`com.apple.security.app-sandbox = true`). Perlu diuji apakah `setProperties` ke IOService diizinkan dari sandbox; kalau tidak, perlu penyesuaian entitlement.
- Jangan pakai `B0St` (itu status baterai dari SMCBatteryManager, bukan threshold).
- Jangan pakai `B0Sp`/`B0En` (tidak ada di sistem lokal ini).
- Arti `BCSG` vs `BCTG` (mana start, mana stop) belum bisa dipastikan hanya dari binary; perlu verifikasi di mesin X260.

---

## 6. Kesimpulan

1. Referensi lokal = **binary kext YogaSMC 1.5.3**, bukan source code. Tidak ada nomor baris; dipakai offset byte + alamat disassembly.
2. Di referensi YogaSMC: **`B0St`, `B0Sp`, `B0En`, `B1St`, `B1Sp`, `B1En` tidak ada**. Tidak boleh dipakai/dikarang.
3. `B0St` yang asli ada di **SMCBatteryManager 1.3.8** (VirtualSMC plugin di EFI lokal), dan artinya **status baterai**, bukan threshold. `B0Sp`/`B0En` tidak ada di kext mana pun di EFI lokal.
4. Battery threshold YogaSMC memakai:
   - Set: property `setCMstart` → ACPI `BCCS`; `setCMstop` → `BCSS`; `setCMInhibitCharge` → `BICS`; `setCMForceDischarge` → `BDSS`; `setCMPeakShiftState` → `PSSS`.
   - Get: property `BAT_ANY` / `BAT_PRIMARY` / `BAT_SECONDARY` berisi `BCTG`, `BCSG`, `BICG`, `BDSG`, `PSSG`.
   - Tulis ke EC terjadi di dalam method ACPI tersebut; YogaSMC sendiri memanggilnya lewat `evaluateIntegerParam()`.
5. ThinkpadAssistant saat ini **tidak punya SMC key sama sekali**, jadi tidak ada yang perlu diganti.
6. `Refrensi-YogaSMC/` tidak ada di `.xcodeproj`, jadi aman (tidak ikut build).

---

## 7. Cara reproduksi audit

```bash
cd /storage/emulated/0/ThinkpadAssistant/Refrensi-YogaSMC/Kexts

# 1. Pastikan isinya binary, bukan source
find . -type f

# 2. Pastikan dua binary identik
md5sum YogaSMC-*/Contents/MacOS/YogaSMC

# 3. Cari key yang diminta (hasil: kosong)
grep -aoiE 'B[01](ST|SP|EN)' YogaSMC-*/Contents/MacOS/YogaSMC

# 4. Lihat semua string 4 karakter
strings -n 4 YogaSMC-VENTURA.kext/Contents/MacOS/YogaSMC \
  | grep -E '^[A-Za-z0-9]{4}$' | sort -u

# 5. Lihat pendaftaran SMC key ThinkSMC
objdump -d -C YogaSMC-VENTURA.kext/Contents/MacOS/YogaSMC \
  | sed -n '/<ThinkSMC::addVSMCKey/,/retq/p'

# 6. Lihat jalur set threshold
objdump -d -C YogaSMC-VENTURA.kext/Contents/MacOS/YogaSMC \
  | sed -n '/<ThinkVPC::setPropertiesGated/,/retq/p'
```

---

## 8. Lampiran — 125 string 4 karakter (bukan semuanya SMC key)

```
AVSA AVSH AVSI BCCS BCSG BCSS BCTG BDSG BDSS BEEP BICG BICS BTNC BTNE BTNL BTNS
Base Beep Bt6I CKxn CSSI DHKE DHKF DHKN DYTC Desk ECAV ECRG F0Ac F1Ac F2Ac F3Ac
Flat GBID GBMD GCSM GHKL GHSL GMKS GMMS GSBI GSKL GSMS GTMS GUID HALS HAUM HDEM
HDMC HDMM HDSM HEBC HEEC MHAT MHGT MHKA MHKB MHKC MHKM MHKN MHKP MHKS MHKV MLCG
MLCS MMTG MMTS Mute NBAT OKEC PSSG PSSS RCDS RE1B RECB RPWR SALS SAUM SBMC SCSM
SECU SHDA SMKS SSKL SSMS TB0T TB1T TB2T TBFP TCGC TCSA TCXC TG0P TG1P TH0a TH0b
TM0P TM0p TM1p TM2p TM3p TPCD TTRD TW0P TaLC TaRC Tent Th1H Th2H Ts0P Ts1P U518
VGBS VPCR VPCW WCDS WE1B fpe2 guid jlGZ kEG3 sp78 t7E1 type uEL9
```

Dari daftar ini, yang benar-benar SMC key hanyalah yang ada di tabel bagian 3.

---

## 9. Implementasi Battery Threshold di ThinkpadAssistant

Status: **sudah ditambahkan ke kode** (belum bisa di-build/dites di sini karena environment ini Android/Termux, bukan macOS).

### 9.1 File yang diubah

| File | Perubahan |
|---|---|
| `ThinkpadAssistant/AppDelegate.swift` | Seluruh logika threshold ditaruh di sini (baris 76, 79–265). Tidak ada file Swift baru, jadi `project.pbxproj` **tidak perlu diubah**. |
| `ThinkpadAssistant/ThinkpadAssistant.entitlements` | `com.apple.security.app-sandbox` diubah dari `true` menjadi `false` (baris 4–9). IOKit registry write ke service milik kext tidak diizinkan di dalam App Sandbox. |

### 9.2 Isi implementasi (AppDelegate.swift)

| Baris | Fungsi | Keterangan |
|---|---|---|
| 10 | `import IOKit` | akses IOKit registry/user client |
| 25–27 | prop menu | referensi ke menu item status/start/stop |
| 89–107 | `BatteryThresholdError` | pesan error (service tidak ada, write gagal, baca gagal) |
| 109–112 | `BatteryThresholdState` | hasil baca (`BCTG`, `BCSG`) |
| 114–169 | `BatteryThresholdManager` | pencarian `ThinkVPC` via `IOServiceMatching`, set via `IORegistryEntrySetCFProperties`, fallback `IOServiceOpen` + `IOConnectSetCFProperties`, baca via `IORegistryEntryCreateCFProperty("BAT_PRIMARY")` |
| 172–221 | `setupBatteryThresholdMenu()` | membuat submenu **Battery Threshold** di status bar (0–100%, langkah 5) |
| 224–244 | `refreshThresholdMenu()` | menampilkan nilai `BCTG`/`BCSG` dan centang pilihan aktif |
| 247–266 | `setStart` / `setStop` / `applyThreshold` | menulis threshold dan menampilkan alert bila gagal |

Payload yang dikirim (sesuai disassembly YogaSMC, bagian 4.2/4.3):

```swift
["Battery": 1, "setCMstart": 80]   // -> ACPI BCCS
["Battery": 1, "setCMstop":  90]   // -> ACPI BCSS
```

`Battery = 1` = `BAT_PRIMARY` (0 = ANY, 1 = PRIMARY, 2 = SECONDARY).
Tidak ada `B0St`/`B0Sp`/`B0En`/`B1St`/`B1Sp`/`B1En` yang dipakai.

### 9.3 Cara pakai (tampilan menu baru)

Menu utama: **About → Monitor Capslock → Launch on Login → Battery Threshold → Check for Updates... → Quit**.

`Check for Updates...` menanyakan `https://api.github.com/repos/Syuhadak27/ThinkpadAssistent/releases/latest` (silent saat launch, manual saat diklik). Kalau tag release berbeda dengan tag terakhir yang disimpan di `UserDefaults`, menu berubah jadi `Update Available (vN)` dan muncul pilihan **Download / Skip This Version / Later**.

Submenu **Battery Threshold**:

```
BAT0 - 64% - Charging ⚡
Threshold: Start 75% → Stop 85%

Set Start Charge At  >
Set Stop Charge At   >

[✓] Enable Threshold
Refresh Threshold
```

- Baris pertama diambil dari `AppleSmartBattery` di IORegistry (`CurrentCapacity`/`MaxCapacity`, `IsCharging`, `ExternalConnected`), **bukan** dari `BCTG`/`BCSG`.
- Nama baterai dideteksi otomatis (`BAT0` atau `BAT1`); hanya satu yang ditampilkan.
- `Set Start Charge At` / `Set Stop Charge At`: 0–100% kelipatan 5, dengan centang pada nilai aktif.
- `Enable Threshold`: matikan → kirim `setCMstart=0`, `setCMstop=100`, `setCMInhibitCharge=0`. Hidupkan → kirim Start/Stop yang dipilih.
- `BCTG`/`BCSG` **tidak lagi muncul di UI**; hanya dicatat ke debug log (`NSLog`) untuk keperluan audit.

### 9.4 Yang masih perlu diverifikasi di mesin X260

- `ThinkVPC` benar-benar ter-load (`ioreg -lw0 | grep -i ThinkVPC`).
- Method ACPI `BCCS`/`BCSS` benar-benar ada di DSDT X260. Tidak ada SSDT lokal yang mendefinisikannya (semuanya hanya HKEY), jadi ini bergantung pada firmware OEM. Kalau tidak ada, `IORegistryEntrySetCFProperties` akan gagal dan alert akan muncul.
- Pasangan get `BCTG` vs `BCSG`: masih belum dipakai untuk UI. Nilai Start/Stop yang ditampilkan berasal dari pilihan user (UserDefaults), bukan dari pembacaan ACPI. Data mentah `BAT_PRIMARY` hanya masuk debug log.
- Nilai baca dari method ACPI bukan persentase mentah: **byte rendah = persentase (0–100), byte tinggi = flag/status**. Contoh hasil nyata di X260: `863 (0x035F)` → 95%, `768 (0x0300)` → 0%. Informasi ini disimpan sebagai catatan audit, tidak lagi dipakai tampilan.
- App Sandbox sudah dimatikan; apabila distribusi App Store diinginkan, pendekatan ini harus diganti helper privileged (SMJobBless).

### 9.5 Ringkasan status

- ✅ Kode implementasi threshold sudah ada di repo.
- ✅ Referensi lokal tetap tidak masuk target build.
- ⚠️ Belum ada verifikasi runtime karena tidak ada macOS di environment ini.
- ⚠️ Sandbox dimatikan agar akses IOKit tidak diblokir.
