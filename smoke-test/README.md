# RooTitanium — smoke test → mini-browser

Mini app (PoC) su **qt6-qtwebengine 6.8.3** (build nativa sb2) che renderizza su
SailfishOS 5.1 aarch64 con **accelerazione hardware** (Adreno 619, OpenGL ES 3.2
via hybris). Da PoC è cresciuta in un mini-browser con UI stile Chrome mobile,
tastiera QtVirtualKeyboard e toggle mobile/desktop.

## File tracciati
- `main.cpp` — launcher C++: `QtWebEngineQuick::initialize()` + `QQmlApplicationEngine`
  che carica `test.qml`. Compilato nativo via sb2.
- `test.qml` — UI del browser:
  - **Toolbar stile Chrome mobile**: home ⌂, pill indirizzo arrotondata (lucchetto/
    incognito + URL colorato con schema verde, placeholder "Cerca o inserisci un
    indirizzo"), contatore schede, menu ⋮.
  - **Sistema a schede (multi-tab)**: `ListModel` `tabsModel` + una `WebEngineView`
    per scheda (solo l'attiva visibile), profili **normale** (persistente) e
    **incognito** (off-the-record, isolato). Contatore schede → **switcher** stile
    Cromite (filtro Schede/Incognito, card con ✕ per chiudere, + per nuova, tap per
    passare). Chiudendo l'ultima scheda si torna alla **HOME**.
  - **Pagina HOME / nuova scheda** (`homeHtml()`): logo, **Preferiti** (tile-link
    predefiniti) + **Cronologia** (placeholder). Scheda anonima → landing
    **"Stai navigando in incognito"** (`incognitoHtml()`).
  - **Menu ⋮ stile Sailfish Browser** (icone Canvas): Nuova scheda, Scheda anonima,
    Cerca nella pagina, Condividi, Salva come PDF, **Versione desktop** (toggle),
    Segnalibri, Cronologia, Download, Impostazioni. Funzionali: *Nuova scheda*,
    *Scheda anonima*, *Versione desktop*, *Salva come PDF*, **Condividi** (copia URL
    negli appunti + toast); le altre sono placeholder.
  - **Toggle mobile/desktop** (backlog #2): `httpUserAgent` bindato a `desktopMode`
    + **`zoomFactor`** che in mobile riduce il viewport CSS a ~412px (SFOS forza
    DPI 96 → devicePixelRatio ≈ 1 → senza zoom i siti responsive scelgono il layout
    desktop). Default = **mobile**.
  - **Tastiera QtVirtualKeyboard in-app** (`InputPanel`).
- `run.sh` — launcher con env: platform wayland-egl, path Qt/WebEngine del bundle,
  flag Chromium, `QT_IM_MODULE=qtvirtualkeyboard`, **`QT_VIRTUALKEYBOARD_STYLE=rt`**,
  **`QT_VIRTUALKEYBOARD_LAYOUT_PATH=$HERE/kbd-layouts`**, `LANG`.
- `rootitanium.desktop` — voce app-grid Lipstick (Exec = run.sh). Va copiata in
  `~/.local/share/applications/` sul device.
- `kbd/Styles/rt/style.qml` — **stile tastiera custom** (copia del builtin *default*
  con glifi armonizzati: lettere centrate `AlignVCenter`, `keyContentMargin` 20,
  `pixelSize` 62 `Font.Light`, `keyboardDesignWidth` **1300** → tastiera più alta e
  glifi più grandi, look Sailfish/ItalianoX). Va installato in
  `<bundle>/qml/QtQuick/VirtualKeyboard/Styles/rt/style.qml` (selezionato da
  `QT_VIRTUALKEYBOARD_STYLE=rt`, nessuna ricompilazione).
- `kbd/layouts/it_IT/main.qml` — **layout custom**: aggiunta la **"/"** nella riga
  bassa (utile per gli URL). Va messo in un albero completo di layout
  (`<bundle>/kbd-layouts/`, copia dell'upstream `src/layouts` + questo main.qml) e
  selezionato da `QT_VIRTUALKEYBOARD_LAYOUT_PATH`.

## Patch runtime sui Components QtVirtualKeyboard (nel bundle, da riapplicare)
File in `<bundle>/qml/QtQuick/VirtualKeyboard/Components/`:
- `EnterKey.qml`, `SpaceKey.qml`, `FillerKey.qml`: `showPreview: false`
  (niente popup di anteprima sui tasti funzione; l'anteprima resta sui tasti-carattere
  via il default di `BaseKey`).

## Come gira (bundle self-contained in /home, niente install di sistema)
Bundle in `scratch/webengine-bundle/` (non tracciato, riproducibile) → copiato in
`/home/defaultuser/webengine-smoke/` sul device, poi `./run.sh` (o dalla griglia app
via `rootitanium.desktop`). Reversibile: `rm -rf` della cartella, `/` mai toccato.

Dipendenza aggiunta (11 lug, cronologia): `plugins/sqldrivers/libqsqlite.so`
(dal target SDK `SailfishOS-5.1.0.11-aarch64.default`, path
`/usr/lib64/qt6/plugins/sqldrivers/`) — serve a `QtQuick.LocalStorage`
(cronologia persistente); senza, `openDatabaseSync` fallisce con
"SQL: Cannot open database". Usa `libsqlite3.so.0` di sistema del device.
Il DB finisce in `~/.local/share/run.sh/QML/OfflineStorage/` (nome app =
argv[0] forgiato; path pulito quando si farà il packaging vero).

Roadmap browser vero: memoria `rootitanium-browser-backlog`.
