# Runbook — motore e RPM armv7hl (RooTitanium a 32 bit)

Avviato l'8 ottobre 2026, perché gli utenti continuano a chiedere la versione a
32 bit. Stesso motore della 2.1 aarch64 (QtWebEngine **6.8.4**, Chromium 122,
backport CVE fino a 138), ricompilato per ARMv7 hard-float con NEON.

**Senza** l'innesto droidmedia (decodifica video hardware): sul 32 bit non è
collaudabile e il guadagno misurato su aarch64 era modesto. Decodifica software.

## Albero e target separati

Niente di quello che serve all'aarch64 viene toccato:

| | aarch64 | armv7hl |
|---|---|---|
| topdir rpmbuild | `build/` | `build-armv7hl/` (SOURCES = symlink a `build/SOURCES`) |
| target sb2 | `SailfishOS-5.1.0.11-aarch64` | `SailfishOS-5.1.0.11-armv7hl` |
| dir gn | `src/core/RelWithDebInfo/aarch64` | `src/core/Release/armv7l` |
| qemu host per i tool V8 | `~/qemu-aarch64-10` | `~/qemu-arm-10` (copia di `/usr/bin/qemu-arm-static`) |
| configure | `scripts/configure-only.sh` | `scripts/configure-armv7hl.sh` |

Gli script di build prendono `ARCH` dall'ambiente (default `aarch64`):

```bash
ARCH=armv7hl scripts/build-con-ripresa.sh      # guardia VRM + ripresa
ARCH=armv7hl scripts/apply-build-fixes.sh gn   # ecc.
```

## Preparazione del target armv7hl (fatta l'8 ott, da rifare solo su target nuovo)

1. Repo: `qt6sb2` = `home:piggz:qt6sb2/sailfish_latest_armv7hl`, `nemo-native` =
   `nemo:devel:hw:native-common/sailfish_latest_armv7hl`
   (`sb2 -t <T> -m sdk-install -R ssu ar <alias> <url>`).
2. ⚠️ **Il Qt6 armv7hl di piggz è compilato su SFOS 5.0** (`sailfish_latest` =
   5.0, non esiste un `sailfish_51_armv7hl`) e chiede `libicu*.so.70`, mentre il
   target 5.1 ha ICU 73. Rimedio: `packaging/icu70-compat/` = RPM con le .so.70
   prese dal target 5.0.0.62 armv7hl. **Solo per il target di build**: sul
   telefono le .so.70 viaggiano nel bundle, come il resto di Qt.
3. BuildRequires dello spec (gbm → `mesa-llvmpipe-libgbm-devel`), più
   `kernel-headers qt6-rpm-macros qt6-qtwayland(-devel)` e, per pari con
   l'aarch64, `libxslt openssl python3-devel python3-lxml python3-six
   python3-rpm-macros mesa-dri-drivers`.
4. `nodejs-bin` (spec reso multi-arch: tarball `linux-armv7l`, SHA256
   verificato con `SHASUMS256.txt`) + i due python noarch di `build51/`.
5. ⚠️ **Qt rifiuta Node a 32 bit** (`configure.cmake`: "32bit version of Nodejs is
   not supported", i passi devtools vanno fuori memoria). Nel target armv7hl
   `/usr/bin/node` è quindi un wrapper che esegue il **Node aarch64** del target
   aarch64 col qemu 10 dell'host (`-U LD_PRELOAD` per non far caricare a quel
   loader la libsb2 a 32 bit). L'originale armv7l resta in `/usr/bin/node.armv7l`.

## Prep, configure, build

```bash
# %prep (≈2 min) nel topdir separato
sb2 -t SailfishOS-5.1.0.11-armv7hl rpmbuild -bp --nodeps \
    --define '_topdir <repo>/packaging/qt6-qtwebengine-sfos/build-armv7hl' rpm/qt6-qtwebengine.spec
# configure (≈2 min) in-place
cd build-armv7hl/BUILD/qt6-qtwebengine-6.8.4/upstream
sb2 -t SailfishOS-5.1.0.11-armv7hl bash <repo>/packaging/qt6-qtwebengine-sfos/scripts/configure-armv7hl.sh
ARCH=armv7hl scripts/apply-build-fixes.sh gn
ARCH=armv7hl scripts/build-con-ripresa.sh
```

`CMAKE_BUILD_TYPE=Release` senza `-g`: `symbol_level=0`, la .so finale resta
lontana dai ~4 GB del linker a 32 bit, e nell'RPM finiva comunque strippata.

## Blocchi incontrati (in ordine)

| Sintomo | Causa | Rimedio |
|---|---|---|
| `nothing provides libicuuc.so.70` installando Qt6 | Qt6 piggz armv7hl compilato su 5.0 | `icu70-compat` |
| `32bit version of Nodejs is not supported` | check di Qt | wrapper Node aarch64 |
| `‘armv8-a’ does not support feature ‘aes’` (zlib `crc32_simd.c`) | `-march=armv8-a+aes+crc` va bene solo a gcc aarch64 / clang | **patch 0305** (`+crc` su arm) |
| la ripresa applicava 5 volte il rimedio `snapshot` a vuoto | il pattern `*v8_context_snapshot*` prendeva anche la riga a cascata del ninja esterno; e il fallimento del rimedio era mascherato da `tee` | pattern `FAILED: v8_context_snapshot.bin` + `PIPESTATUS` |
| build OK, ma il **renderer muore** su Wikipedia (`ProcessGone: 3 (135)` = SIGBUS) | vedi sotto | **patch 0306** + ricompilazione completa |

### 🔴 Il SIGBUS del renderer (trovato al collaudo, non dalla build)

La prima build (senza 0306) compila, si linka e apre example.com, ma il renderer
muore con **SIGBUS** su qualsiasi pagina con CSS vero. Preso con gdb (renderer
lanciato con `--renderer-cmd-prefix` = qemu `-g 1234`, gdb dell'SDK
`~/SailfishOS/bin/gdb` dall'host sull'IP del container):

```
=> vld1.64 {d16-d17}, [r1 :64]      r1 = 0x369b84c4   (allineato a 4, non a 8)
#0 std::__introsort_loop<blink::MatchedRule*, ...>
#1 blink::ElementRuleCollector::SortAndTransferMatchedRules
```

Causa: su 32 bit **Oilpan allinea i backing di `HeapVector` a 4 byte**
(`HeapVectorBacking<T>` è una classe vuota, il suo `alignof` non porta quello di
`T`), mentre `MatchedRule` (campi `uint64_t`) ne vuole 8. Il **vettorizzatore
SLP di gcc** copia gli elementi con `vld1.64 … :64`, e un VLD1 con hint di
allineamento fa *sempre* alignment fault sull'hardware, che il kernel non corregge.
Quindi **non è un artefatto di qemu**: su un telefono vero sarebbe crashato tutto.
clang (il compilatore di Chromium) non genera quegli hint.

Verifica a scatola chiusa sul TU vero (`core_hot_jumbo_7`, che è a `-O3`):
hint NEON 31 → **9** con `-fno-tree-vectorize` (o `-fno-tree-slp-vectorize`),
**6 → 0** nella sort di `MatchedRule`. I 9 rimasti sono azzeramenti di oggetti
sullo stack (sempre allineato a 8 per AAPCS), innocui.

Rimedio = **0306**: `-fno-tree-vectorize` per gcc con `current_cpu == "arm"`
(non tocca aarch64). Costo: niente auto-vettorizzazione nel motore a 32 bit; il
codice NEON scritto a mano (Skia, libyuv, zlib, …) resta.

## Collaudo sul PC (qemu)

`scratch/collaudo-qemu-armv7hl.sh` dentro l'engine, sotto `dbus-run-session`
(senza bus di sessione l'app crede di essere una seconda istanza ed esce 0):
qemu-arm 10 con `-L` = target armv7hl, piattaforma `offscreen`, Chromium
`--disable-gpu`, DevTools su 9222; i processi figli passano dal binfmt
qemu-arm dell'host (legge `QEMU_LD_PREFIX`). `scratch/cdp-sonda.py` (solo
stdlib) valuta JS/WebAssembly e salva uno screenshot. ⚠️ Il profilo è cablato in
`/home/defaultuser/.rootitanium`: va creato **sia** nel container **sia** sotto
il target (qemu `-L` reindirizza i path esistenti).
⚠️ `pkill -f qemu-arm` dentro `bash -c '…'` uccide anche la shell stessa (il
pattern è nella sua riga di comando): usare `pgrep -f "[q]emu-arm"`.

## Collaudo senza un telefono a 32 bit

Il kernel del **POCO M4 Pro** (aarch64) esegue codice AArch32 (provato con una
sonda statica senza libc) e l'Android del POCO ha le librerie a 32 bit
(`/system/lib`, `/vendor/lib/egl/libGLES_mali.so`). Strada per il collaudo: un
chroot armv7hl sul POCO.

### Esito sul telefono (8 ott 2026, sera)

App armv7hl avviata **nativamente** nel chroot sul POCO (`sudo chroot …
runuser -u defaultuser`, con `/run/display` e `/run/user/100000` montati dentro e
il `resolv.conf` del telefono copiato). EGL: il chroot ha solo il Mesa del target
SDK, senza driver → il launcher vero abortisce (`getEGLDisplay() failed`), atteso;
sui telefoni a 32 bit veri l'EGL è libhybris. Collaudo quindi in rendering
software (`QT_QPA_PLATFORM=wayland`, `QT_QUICK_BACKEND=software`, `--disable-gpu`):

- Wikipedia: caricata in 2,1 s, testo e font corretti;
- **YouTube**: Big Buck Bunny 360p in tempo reale (30 s di video in 30 s, ~10%
  di fotogrammi scartati, tutto in software);
- con `QT_IM_MODULE=maliit`, come sceglie il launcher, la finestra è a piena
  altezza (`xdg_toplevel.configure 1080x2400`). Con la QtVirtualKeyboard compariva
  invece una zona nera in basso alta quanto una tastiera.

⚠️ **Non smontare il chroot con `umount -R`**: su SFOS i mount sono *shared* e
lo smontaggio dei `--rbind` di `/dev` e `/sys` si propaga ai mount veri del
telefono (dopo quella pulizia sshd rifiutava le connessioni: serve riavviare).
Dopo ogni `--rbind` fare subito `mount --make-rslave`.

### `gn gen` appeso

Due volte su cinque `gn gen` (core e poi QtPdf) è rimasto fermo in stato S per
oltre 15 minuti sotto il qemu 5.1 del target; l'allarme stallo della guardia lo
segnala. Rimedio: uccidere per PID `ninja`/`gn` dentro l'engine e rilanciare
(oppure rifare a mano il `gn gen` della dir interessata con `timeout`). Far
girare `gn` col qemu 10 dell'host fuori da sb2 **non** funziona: i figli
(`pkg-config`) non trovano più i `.pc` del target.
