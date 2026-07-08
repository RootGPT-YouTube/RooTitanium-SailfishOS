# RooTitanium — smoke test WebEngine

Mini app (PoC) usata per verificare che **qt6-qtwebengine 6.8.3** (build nativa
sb2) renderizzi su SailfishOS 5.1 aarch64. Esito 8 lug 2026: **funziona con
accelerazione hardware** (Adreno 619, OpenGL ES 3.2 via hybris), navigazione web
reale, multiprocesso.

## File
- `main.cpp` — launcher C++: `QtWebEngineQuick::initialize()` + `QQmlApplicationEngine`
  che carica `test.qml`. Compilato nativo via sb2 (`sb2 -t <target> g++ ... -lQt6WebEngineQuick -lQt6WebEngineCore`).
- `test.qml` — `WebEngineView` con barra di pulsanti (niente tastiera: manca il
  plugin Qt6↔Maliit nel target); parte su `chrome://gpu`.
- `run.sh` — script di lancio con env: `QT_QPA_PLATFORM=wayland`,
  `WAYLAND_DISPLAY=../../display/wayland-0`, `XDG_RUNTIME_DIR=/run/user/100000`,
  path Qt/WebEngine del bundle, flag Chromium (`--no-sandbox --use-gl=egl`).

## Come gira (bundle self-contained in /home, niente install di sistema)
Il bundle completo (Qt6 runtime + WebEngine + risorse, ~376 MB, assemblato dal
sysroot) sta in `scratch/webengine-bundle/` (non tracciato, riproducibile) e va
copiato in `/home/defaultuser/webengine-smoke/` sul device, poi `./run.sh`.
Reversibile: `rm -rf` della cartella, `/` mai toccato.

Roadmap per farne un browser vero: memoria `rootitanium-browser-backlog`.
