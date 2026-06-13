# RooTmium

Browser **Chromium per SailfishOS** (runtime target: SailfishOS 5.1.0.11), basato su
**Qt6 QtWebEngine**. UI scritta da zero in QML/Silica — non è un fork di browser esistenti.

## Stato: studio di fattibilità (pre-sviluppo)

Aggiornato al 13 giugno 2026.

### Decisioni
- **Niente fork**: UI propria (QML/Silica) attorno a `WebEngineView`.
- **Solo aarch64**: Qt6 QtWebEngine non supporta più il 32-bit (no armv7hl/i486).
  Confermato da `%qt6_qtwebengine_arches x86_64 aarch64` e da `ExclusiveArch` dello spec.
- **Dipendenza Qt6 sperimentale**: su SailfishOS Qt6 non è ufficiale; si usa lo stack
  della community (OBS `home:/piggz:/qt6sb2`, target `sailfish_51_aarch64`).

### Il motore
`qt6-qtwebengine` (v6.8.3) **non è precompilato da nessuna parte** (né Chum né piggz):
va buildato da `github.com/sailfishos-chum/qt6-qtwebengine` sopra lo stack Qt6 di piggz.
È un build Chromium completo (decine di GB, ore). Lo spec abilita `proprietary_codecs`
(H.264/AAC) → da valutare per le licenze. Produce anche `qt6-qtpdf`.

### Prossimi passi
1. Riparare il clone del submodule Chromium (`upstream/src/3rdparty`).
2. Verificare che `qt6sb2` copra tutti i `BuildRequires` di qtwebengine.
3. Scegliere la strategia di build: OBS (linkando qt6sb2) vs target sb2 locale.

> La cartella `qt6-qtwebengine/` (clone upstream, ~3.6 GB) è esclusa da git: riproducibile
> con `git clone --recursive https://github.com/sailfishos-chum/qt6-qtwebengine`.
