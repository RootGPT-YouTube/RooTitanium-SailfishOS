# RooTitanium

A **Chromium web browser for Sailfish OS 5.1**, built on **Qt 6 QtWebEngine** with
a UI written from scratch in QML — not a fork of an existing browser. Part of the
`RooT*` app family.

Prerequisite: SFOS 5.1.0.11 · **aarch64 only**  
Telegram Group: https://t.me/+E7V-a7x4JbY1Njhk  
RooTitanium is tested on:  
- Sony Xperia 10 III (SFOS 5.1.0.11)  

This application was developed using artificial intelligence technologies, specifically Warp Terminal and Claude Code Opus, but Warp Terminal has been gradually phased out in favor of Claude Code. Therefore, if the use of an application generated via a large-scale language model (LLM) is not comfortable for the user, it is recommended to avoid its installation and use. It is specified that any negative comment regarding this circumstance will not only be ignored but will result in the immediate blocking of the user.
I hereby disclaim any and all responsibility for the application, its functionality, and any consequences arising from its use. By choosing to use this application, the user acknowledges and accepts that they do so entirely at their own risk, and agrees that the developer shall not be held liable for any damages, losses, or adverse effects—whether direct, indirect, incidental, or consequential—resulting from the use or misuse of the application.

Requisiti: SFOS 5.1.0.11 · **solo aarch64**  
Gruppo Telegram: https://t.me/+E7V-a7x4JbY1Njhk  
RooTitanium è testato:  
- Sony Xperia 10 III (SFOS 5.1.0.11)  

Questa applicazione è stata sviluppata utilizzando tecnologie di intelligenza artificiale, in particolare Warp Terminal e Claude Code Opus, ma Warp Terminal è stato abbandonato in favore di Claude Code. Pertanto, se l'uso di un'applicazione generata tramite un modello linguistico su larga scala (LLM) non fosse per l'utente confortevole, si raccomanda di evitarne l'installazione e l'uso. Si specifica che qualsiasi commento negativo riguardante questa circostanza non verrà solo ignorato, ma comporterà il blocco immediato dell'utente.
Con la presente declino ogni responsabilità relativa all’applicazione, al suo funzionamento e a qualsiasi conseguenza derivante dal suo utilizzo. L’utente, scegliendo di utilizzare l’applicazione, riconosce e accetta di farlo a proprio ed esclusivo rischio, e concorda che lo sviluppatore non potrà essere ritenuto responsabile per eventuali danni, perdite o effetti negativi — diretti, indiretti, incidentali o consequenziali — derivanti dall’uso o dall’uso improprio dell’applicazione.

## Browser engine — self-contained bundle

On Sailfish OS, Qt 6 is **not** an official platform component, and
`qt6-qtwebengine` is not precompiled anywhere. RooTitanium therefore ships a
**self-contained bundle**: the whole Qt 6 + QtWebEngine runtime (Chromium 122)
is compiled from source over the community Qt 6 stack and installed under
`/home/rootitanium/`, so the app needs **no system Qt 6** and does not interfere
with the platform.

- **Hardware-accelerated rendering.** QtWebEngine renders through **EGL over
  libhybris** (the device's Android GPU drivers). On the Xperia 10 III (Adreno
  619) hardware acceleration is confirmed via `chrome://gpu`.
- **Runs unsandboxed by design.** Because the bundle lives outside the rootfs and
  needs full access to `/home/rootitanium/`, the hybris system libraries and
  Chromium's own `--no-sandbox` mode, the app declares `Sandboxing=Disabled` in
  its `.desktop`. In-app **App Permissions** (below) are what actually gate what
  sites can use.
- **Custom ELF launcher.** A small launcher in `/usr/bin/harbour-rootitanium`
  sets the bundle environment and execs the browser, forging `argv[0]` so
  Lipstick matches the window to a single app cover.

## Features (1.0)

- **Tabs and private (incognito) tabs**, with a tab switcher and per-mode counts;
  optional "start in private", "close all tabs on exit" or session restore.
- **HOME page** with a **Favorites** grid (your chosen bookmarks) and a
  **History** list, editable in place.
- **Address bar** with search-or-URL entry and selectable search engine
  (DuckDuckGo, Google, Bing, Startpage).
- **Bookmarks** (persistent, SQLite) with a HOME-favorites toggle and reordering,
  and **History** with clear-all.
- **Downloads** with a chosen destination folder (Downloads / Documents /
  Pictures / Videos / Music), live progress, open and cancel.
- **Find in page**, **Share**, **Save page as PDF**, **Desktop/Mobile site**
  toggle, and **landscape rotation** (manual, plus automatic for fullscreen
  video).
- Native-feeling **context menus** (link / image / text), touch-selection menu,
  and custom **JavaScript dialogs** (alert / confirm / prompt) scaled for the
  device.
- **Custom on-screen keyboard** (QtVirtualKeyboard, themed for the browser).
- **Privacy controls**: Do-Not-Track, **anti-fingerprinting** (Brave/Cromite-style
  farbling), automatic **cookie-banner rejection**, a **Client-Hints / user-agent
  interceptor** that presents the browser as Google Chrome for site
  compatibility, session-cookie clearing, JavaScript and popup toggles, forced
  dark mode, and one-tap **clear browsing data**.
- **App Permissions** (master switches for camera, microphone, location,
  notifications and downloads — a gate above the per-site choices) and **Site
  Permissions** (per-site camera / microphone / location / notifications).
- **Background tab lifecycle** (freeze / discard) to keep heavy sites from
  stalling the browser.
- **Bilingual UI (English / Italian)**: Italian on Italian devices, English
  everywhere else — chosen automatically from the system language.

## Roadmap

- Further refinements to permissions, downloads and per-site settings; more UI
  polish.

## Building from source (English)

RooTitanium is built in **two stages**: first the Qt 6 / QtWebEngine **engine**,
then the application **bundle + RPM**. The engine is a full Chromium build (tens
of GB, hours) and its source and build trees are **not** kept in this repository
(see `.gitignore`); the corresponding source is the upstream recipe listed in
[NOTICE.md](NOTICE.md).

**Prerequisites**
- The [Sailfish SDK](https://docs.sailfishos.org/Tools/Sailfish_SDK/) with `sfdk`
  and its build engine, target **SailfishOS-5.1.0.11-aarch64** (aarch64 only —
  Qt 6 QtWebEngine has dropped 32-bit).
- The community **Qt 6 stack** for SFOS 5.1 (OBS `home:/piggz:/qt6sb2`,
  `sailfish_51_aarch64`).

**Steps**

1. **Clone**
   ```sh
   git clone https://github.com/RootGPT-YouTube/RooTitanium-SailfishOS.git
   cd RooTitanium-SailfishOS
   ```
2. **Build the engine** — `qt6-qtwebengine` 6.8.3 from
   [sailfishos-chum/qt6-qtwebengine](https://github.com/sailfishos-chum/qt6-qtwebengine)
   over the piggz Qt 6 stack, cross-compiled natively via `sb2` (see the guarded
   build helper under `packaging/qt6-qtwebengine-sfos/`). This produces the
   QtWebEngine libraries, `QtWebEngineProcess`, resources and locales.
3. **Assemble the bundle** into `/home/rootitanium/` layout (the Qt 6 runtime,
   `webengine-smoke` browser binary, `test.qml`, resources, trimmed locales).
4. **Build the app RPM**:
   ```sh
   sb2 -t SailfishOS-5.1.0.11-aarch64.default rpmbuild -bb \
       packaging/harbour-rootitanium/harbour-rootitanium.spec \
       --define "_topdir $PWD/rpmbuild" --define "stagingdir <staging>"
   # → harbour-rootitanium-1.0-1.aarch64.rpm  (~100 MB)
   ```
5. **Install on the device** (copy the RPM over, then on the phone):
   ```sh
   sudo pkcon install-local --allow-untrusted harbour-rootitanium-1.0-1.aarch64.rpm
   ```

The RPM payload goes to `/home/rootitanium/` (the `/home` partition), while the
`.desktop`, icons and the ELF launcher go to the rootfs under `/usr`. Conventions
shared with the `RooT*` family: package `harbour-rootitanium`, version
single-sourced from the spec.

## Compilare dai sorgenti (Italiano)

RooTitanium si compila in **due fasi**: prima il **motore** Qt 6 / QtWebEngine,
poi il **bundle applicativo + RPM**. Il motore è un build Chromium completo
(decine di GB, ore) e i suoi alberi di sorgente e build **non** sono tenuti in
questo repository (vedi `.gitignore`); la *corresponding source* è la ricetta
upstream indicata in [NOTICE.md](NOTICE.md).

**Prerequisiti**
- Il [Sailfish SDK](https://docs.sailfishos.org/Tools/Sailfish_SDK/) con `sfdk` e
  il suo build engine, target **SailfishOS-5.1.0.11-aarch64** (solo aarch64 — Qt 6
  QtWebEngine ha abbandonato il 32-bit).
- Lo **stack Qt 6** della community per SFOS 5.1 (OBS `home:/piggz:/qt6sb2`,
  `sailfish_51_aarch64`).

**Passi**

1. **Clona**
   ```sh
   git clone https://github.com/RootGPT-YouTube/RooTitanium-SailfishOS.git
   cd RooTitanium-SailfishOS
   ```
2. **Compila il motore** — `qt6-qtwebengine` 6.8.3 da
   [sailfishos-chum/qt6-qtwebengine](https://github.com/sailfishos-chum/qt6-qtwebengine)
   sopra lo stack Qt 6 di piggz, cross-compilato in modo nativo via `sb2` (vedi lo
   script di build con guardia sotto `packaging/qt6-qtwebengine-sfos/`). Produce le
   librerie QtWebEngine, `QtWebEngineProcess`, risorse e locali.
3. **Assembla il bundle** nel layout `/home/rootitanium/` (runtime Qt 6, binario
   del browser `webengine-smoke`, `test.qml`, risorse, locali ridotte).
4. **Compila l'RPM dell'app**:
   ```sh
   sb2 -t SailfishOS-5.1.0.11-aarch64.default rpmbuild -bb \
       packaging/harbour-rootitanium/harbour-rootitanium.spec \
       --define "_topdir $PWD/rpmbuild" --define "stagingdir <staging>"
   # → harbour-rootitanium-1.0-1.aarch64.rpm  (~100 MB)
   ```
5. **Installa sul dispositivo** (copia l'RPM, poi sul telefono):
   ```sh
   sudo pkcon install-local --allow-untrusted harbour-rootitanium-1.0-1.aarch64.rpm
   ```

Il payload dell'RPM va in `/home/rootitanium/` (partizione `/home`), mentre il
`.desktop`, le icone e il launcher ELF vanno nel rootfs sotto `/usr`. Convenzioni
condivise con la famiglia `RooT*`: pacchetto `harbour-rootitanium`, versione
single-source dallo spec.

## Engine, compatibility & trademarks

RooTitanium renders pages with **Qt 6 QtWebEngine** (Chromium 122), bundled as
described above and in [NOTICE.md](NOTICE.md). For site compatibility the browser
presents itself as **Google Chrome** through a Client-Hints / user-agent
interceptor; this is identification only and does not make it a Google product.

*"Chromium" and "Google Chrome" are trademarks of Google LLC, and "Qt" is a
trademark of The Qt Company Ltd. RooTitanium is an independent project, **not
affiliated with, sponsored by or endorsed by** Google LLC or The Qt Company; the
names are used solely for identification.*

## Motore, compatibilità e marchi (Italiano)

RooTitanium mostra le pagine con **Qt 6 QtWebEngine** (Chromium 122), impacchettato
come descritto sopra e in [NOTICE.md](NOTICE.md). Per compatibilità con i siti il
browser si presenta come **Google Chrome** tramite un interceptor di Client-Hints /
user-agent; è solo identificazione e non lo rende un prodotto Google.

*"Chromium" e "Google Chrome" sono marchi di Google LLC, e "Qt" è un marchio di
The Qt Company Ltd. RooTitanium è un progetto indipendente, **non affiliato,
sponsorizzato o approvato** da Google LLC o The Qt Company; i nomi sono usati solo
a scopo identificativo.*

## License

GPL-3.0-or-later © 2026 RootGPT. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md)
for the third-party components (Qt 6 / QtWebEngine, Chromium) bundled in the RPM.
