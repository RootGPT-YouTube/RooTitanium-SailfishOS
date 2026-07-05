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

### Prossimi passi
1. Riparare il clone del submodule Chromium (`upstream/src/3rdparty`).
2. ~~Verificare che `qt6sb2` copra tutti i `BuildRequires` di qtwebengine.~~ ✅ Fatto
   (vedi sopra): unico ostacolo vero è **nodejs**.
3. ~~Scegliere la strategia di build.~~ ✅ Locale sb2 `-j16` (vedi sopra).
4. ~~Pacchettizzare `nodejs` per SFOS.~~ ✅ Bozza `nodejs-bin` pronta (vedi sopra);
   resta il build/test del pacchetto in sb2.
5. Pacchettizzare `python3-html5lib` + macro `qt6-srpm-macros`; adattare lo spec
   (rimuovere BR qtquickcontrols2, provare senza snappy-devel).
6. Configurare il target sb2 con kernel-headers da `nemo:devel:hw:native-common`.

> La cartella `qt6-qtwebengine/` (clone upstream, ~3.6 GB) è esclusa da git: riproducibile
> con `git clone --recursive https://github.com/sailfishos-chum/qt6-qtwebengine`.
