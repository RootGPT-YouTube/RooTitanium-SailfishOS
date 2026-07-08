# RooTitanium

Browser **Chromium per SailfishOS** (runtime target: SailfishOS 5.1.0.11), basato su
**Qt6 QtWebEngine**. UI scritta da zero in QML/Silica — non è un fork di browser esistenti.

## Stato: studio di fattibilità (pre-sviluppo)

Aggiornato al 5 luglio 2026.

### Decisioni
- **Niente fork**: UI propria (QML/Silica) attorno a `WebEngineView`.
- **Solo aarch64**: Qt6 QtWebEngine non supporta più il 32-bit (no armv7hl/i486).
  Confermato da `%qt6_qtwebengine_arches x86_64 aarch64` e da `ExclusiveArch` dello spec.
- **Dipendenza Qt6 sperimentale**: su SailfishOS Qt6 non è ufficiale; si usa lo stack
  della community (OBS `home:/piggz:/qt6sb2`, target `sailfish_51_aarch64`).
- **Build locale via sb2, `-j16`** (vedi "Strategia di build" sotto).

### Il motore
`qt6-qtwebengine` (v6.8.3) **non è precompilato da nessuna parte** (né Chum né piggz):
va buildato da `github.com/sailfishos-chum/qt6-qtwebengine` sopra lo stack Qt6 di piggz.
È un build Chromium completo (decine di GB, ore). Lo spec abilita `proprietary_codecs`
(H.264/AAC) → da valutare per le licenze. Produce anche `qt6-qtpdf`.

### Verifica BuildRequires ↔ qt6sb2 (5 lug 2026) — GATE PASSATO
Confronto tra lo spec e `home:/piggz:/qt6sb2` `sailfish_51_aarch64` (aggiornato
22 giu 2026, Qt **6.8.3** = versione richiesta dallo spec).

**Coperti da qt6sb2**: qt6-qtbase-devel, qt6-qtbase-private-devel,
qt6-qtdeclarative-devel, qt6-qtlocation-devel, qt6-qtsensors-devel, qt6-qtsvg-devel,
qt6-qttools-static, qt6-qtwebchannel-devel, qt6-qtwebsockets-devel, libevent-devel.

**Coperti dai repo core SFOS** (verificati su github.com/sailfishos): nss, ffmpeg,
libvpx, opus, libwebp, poppler (include `poppler-cpp.pc`), gperf, ninja, flex, bison,
libstdc++-static (subpackage di gcc).

**Gap da risolvere**:
| Mancante | Gravità | Soluzione |
|---|---|---|
| `nodejs` | **Alta** (assente da core/chum/qt6sb2; obbligatorio per QtWebEngine 6.8) | da pacchettizzare per SFOS |
| `qt6-srpm-macros` | bassa | pacchettino di macro o inlining nello spec |
| `qt6-qtquickcontrols2-devel` | nulla | in Qt6 è dentro qtdeclarative → rimuovere il BR |
| `python3-html5lib` | bassa | pure-python noarch, pacchettizzazione banale |
| `snappy-devel` | bassa | Chromium bundla snappy: provare a togliere il BR |
| kernel-headers recenti | media | da `nemo:devel:hw:native-common` (build.sailfishos.org) |

### Strategia di build (decisa il 5 lug 2026)
**Build locale via sb2 con `-j16`**, di giorno per monitorare le temperature
(i VRM scaldano sui build lunghi multiprocesso; d'estate serve prudenza).
- `-j16` (soli core fisici del 5950X): riduce potenza sostenuta ed evita
  l'OOM in link (32 GB RAM: `libQt6WebEngineCore` picca a 8-10 GB col linker).
- **PPT già cappato a 65 W** da BIOS per sicurezza VRM: clock all-core ridotti.
- Stima con -j16 + PPT 65 W: **~8-12 ore** (cross-compiler nativo, ma
  GN/python/nodejs sotto qemu; a PPT stock sarebbero ~5-8 h).
- Disco: servono ~60-80 GB di build tree.
- OBS resta il fallback (linkando qt6sb2 + nemo:devel:hw:native-common), ma i worker
  sono lenti (8-15 h) e rischiano i limiti risorse — plausibilmente il motivo per cui
  nessuno ha mai pubblicato qt6-qtwebengine compilato.

### nodejs: risolto con repack (5 lug 2026)
QtWebEngine 6.8 richiede solo **Node ≥ 14 come tool host** a build-time. Il build
da sorgente in sb2 è bloccato dai tool V8 (mksnapshot/Torque devono girare nativi
x86_64); il repack dei prebuilt ufficiali `linux-arm64` invece è pulito: richiedono
glibc ≥ 2.28 e SFOS 5.1 ha glibc 2.41. → **`packaging/nodejs-bin/`**: spec pronto
(Node 22.23.1 LTS, SHA256 pinnato, solo `/usr/bin/node`, niente npm). Dettagli e
rischi aperti in `packaging/nodejs-bin/NOTE.md`.

### Fase 0/1 completate il 5 lug 2026
- **Submodule Chromium**: verificato OK (122.0.6261.171 = QtWebEngine 6.8.3,
  repo completo, fsck pulito) — la riparazione segnata a giugno non serviva più.
- **SDK**: il tooling 5.1 non è ancora pubblicato da Jolla → si builda sul target
  5.0.0.62 **clonato in `RooTitanium-5.1-aarch64`** e aggiornato a 5.1.0.11 via
  `ssu re` + `zypper dup` (il target 5.0 condiviso resta intatto per gli altri
  progetti). Motivo: i pacchetti qt6sb2 richiedono GLIBC_2.34/GLIBCXX_3.4.29+,
  assenti nel 5.0.
- **Pacchetti buildati e testati in sb2** (`packaging/*/build/RPMS/`):
  `nodejs-bin-22.23.1` (node OK sotto qemu), `python3-webencodings-0.5.1`,
  `python3-html5lib-1.1` (import OK nel target).
- **Spec qtwebengine adattato**: overlay in `packaging/qt6-qtwebengine-sfos/`
  (via qt6-srpm-macros e qtquickcontrols2, snappy commentato — dettagli in NOTE).

### Nottata 5→6 lug 2026: target 5.1 — trovato il vero blocco
Cronologia: (a) `sfdk tools clone` è **bacato** coi target che hanno snapshot
(livelock di 5,5 h, bug segnalato dai SOFT ASSERT `targetHasSnapshots`) — ucciso;
(b) scoperto che su releases.sailfishos.org esistono **tooling+target 5.1.0.11
ufficiali** (catalogo sfdk indietro) — tooling installato OK; (c) la creazione del
target fallisce: il cross-gcc del tooling 5.1 **richiede GLIBC_2.38 sull'engine**,
troppo vecchio; (d) il fallback tooling 5.0 è inutilizzabile per Chromium:
**gcc 10.3.1**, serve gcc 12+ (C++20). → **Conclusione: va aggiornato l'SDK**
(engine incluso) prima di poter creare il target 5.1. Da fare col PC presidiato
(tocca anche le pipeline RooTelegram/RooThub).

Preparato intanto: tarball Source0 non compresso
(`packaging/qt6-qtwebengine-sfos/build/SOURCES/qt6-qtwebengine-6.8.3.tar`,
escluso da git) e Source0 adattato nello spec overlay.

### Stato al 6 lug 2026 (~13:20) — CONFIGURE PASSATA ✅
1. ~~Aggiornare il Sailfish SDK~~ **FATTO**: install pulita SDK **3.13.5** da
   installer offline (il silentUpdate 3.12.5→3.13.5 crasha: bad_alloc in
   runUndoOperations). Engine docker glibc **2.41**, tooling 5.1 con
   **gcc 13.4.0**, target `SailfishOS-5.1.0.11-{aarch64,armv7hl,i486}`
   sdk-provided. Vecchio SDK in `~/SailfishOS-3.12.5-bak` (+ immagine docker
   `:RootGPT-3.12.5-bak`). Target 5.0.0.62 ricreati user-defined per le
   pipeline (validati con build RooTelegram 2.8.9 aarch64; aggiunto
   pulseaudio-devel che i target vergini non hanno).
2. ~~Preparazione target 5.1~~ **FATTO**: repo qt6sb2 + nemo-native, nodejs-bin
   installato, python3-webencodings/html5lib **ribuildati per python 3.11**
   (`build51/`), tutti i BuildRequires installati (jsoncpp/re2/zombie-imp non
   servono: dietro flag `use_system_*=0` e `%%if fedora`; gbm →
   `mesa-llvmpipe-libgbm-devel`).
3. ~~Configure qtwebengine~~ **PASSATA**: `%%prep` ok (tar+patch), cmake
   configure ok in 179 s. `config.summary`: QtWebEngineCore **yes**, Quick yes,
   QtPdf yes, proprietary codecs + WebRTC yes, snappy bundled. Fix necessario
   (committato): `CMAKE_TOOLCHAIN_FILE` con path target-side
   `/usr/lib64/...` — il `%%{_libdir}` iniettato da sfdk espande al path host
   della copia sincronizzata, che NON contiene i binari (syncqt mancante).
4. **Fase 2 (PROSSIMA)**: build completa SOLO `-j16` (⚠️ i default del target
   sono `-j32`: sia `%%__ninja_common_opts` sia `%%cmake_build`), di giorno,
   guardia VRM **85°** (throttle automatico, ripresa ≤ **60°**). Script pronto:
   `packaging/qt6-qtwebengine-sfos/build/build-j16-con-guardia.sh` — lancia la
   build (build dir già configurata in `build/BUILD/qt6-qtwebengine-6.8.3/upstream`)
   e a 85° strozza l'engine docker a 2 core con `docker update --cpus` (NON
   SIGSTOP/docker pause: congelerebbero sshd e la sessione sfdk cadrebbe
   uccidendo la build), ripristinando tutti i core a 60°. Anti-stallo: ogni
   15 min verifica che il log cresca e che l'avanzamento `[n/m]` si muova;
   se fermo → allarme nel log + diagnostica (CPU processi engine) +
   notify-send. Non uccide mai la build da solo (un falso positivo, es. link
   finale lungo, costerebbe ore). Log in `build-j16.log` + `guardia-vrm.log`.
   NOTA: `sfdk config --global target=` ora punta a 5.1 (le pipeline lo
   reimpostano da sole a ogni build).
5. **Fase 3**: smoke test `WebEngineView` su device (gate decisivo GPU/hybris).
6. **Fase 4**: UI QML/Silica-like di RooTitanium.

> La cartella `qt6-qtwebengine/` (clone upstream, ~3.6 GB) è esclusa da git: riproducibile
> con `git clone --recursive https://github.com/sailfishos-chum/qt6-qtwebengine`.
