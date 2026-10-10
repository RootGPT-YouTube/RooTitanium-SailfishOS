# Stack Qt 6.12 per Chromium 140 (task 2.5 #6)

QtWebEngine 6.140 (Chromium 140) richiede Qt 6.12. Su SailfishOS 5.1 il
target di piggz ha Qt 6.8.3, quindi lo stack si compila qui.

## Come è fatto
- Target sb2 **clonati** (`sdk-manage target clone`):
  `SailfishOS-5.1.0.11-aarch64-qt612` e `SailfishOS-5.1.0.11-armv7hl-qt612`.
  Nei cloni i pacchetti `qt6-*` 6.8.3 sono rimossi (`rpm -e --nodeps`) e i
  moduli 6.12 si installano con `cmake --install` in `/usr`. I target
  originali restano intatti per la 2.x.
- Pacchetti aggiunti ai cloni: BuildRequires di qtbase (dallo spec chum),
  `wayland-egl-devel` (in 6.12 il client Wayland è dentro qtbase),
  `wayland-protocols-devel`.
- Sorgenti: tarball ufficiali 6.12.0 (SHA256 verificati) in
  `scratch/qt612-src/`. Patch qtbase: le 6 dello spec chum `qt6-qtbase`
  (6.8.4) + `0001-workaround-sb2-filecopy-bug` (non citata nello spec ma
  necessaria in sb2); tutte applicano su 6.12.0 senza ritocchi.

## Script
- `build-module.sh MODULO [cmake...]` (ARCH=aarch64|armv7hl): configure
  (`--fresh`), build `-j12 -k 0`, install. Percorsi di `%cmake_qt6`.
  ⚠️ Sotto sb2 `qmlcachegen`/`rcc`/copie `.qmltypes` creano file con
  permessi **000**: lo script tiene un sorvegliante che li corregge ogni 3 s e
  riprende la build (fino a 30 giri) se gli errori sono solo di permesso.
- `catena.sh MOD...`: moduli in fila, si ferma al primo che fallisce.
- `guardia-sessione.sh`: guardia VRM persistente (12 core, ≥85 °C → 2,
  ≤60 °C → 12); si ferma col file `STOP`. Non usarla insieme a
  `build-con-guardia.sh`, che ha la sua.
- `flags-qtbase.txt`: feature di qtbase (quelle dello spec chum,
  **libproxy spenta**: la libproxy di SFOS è troppo vecchia per 6.12).

Ordine (aarch64, 10 ott 2026, ~45 min in tutto): qtbase, qtshadertools,
qtsvg, qtdeclarative, qtwebsockets, qtwebchannel, qtpositioning,
qtvirtualkeyboard. qtwayland **non serve più** (il client è in qtbase).

Nota per il launcher: in 6.12 il plugin di piattaforma è `wayland` (EGL come
integrazione interna), non più `wayland-egl`.
