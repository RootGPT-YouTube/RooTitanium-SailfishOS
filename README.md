# RooTitanium

A **Chromium web browser for Sailfish OS 5.1**, built on **Qt 6 QtWebEngine** with
a UI written from scratch in QML — not a fork of an existing browser. Part of the
`RooT*` app family.

---

## [ENGLISH]

Prerequisite: SFOS 5.1.0.11 · **aarch64 only**  
Telegram Group: https://t.me/+E7V-a7x4JbY1Njhk  
RooTitanium is tested on:  
- Sony Xperia 10 III (SFOS 5.1.0.11)  

This application was developed using artificial intelligence technologies, specifically Warp Terminal and Claude Code Opus, but Warp Terminal has been gradually phased out in favor of Claude Code. Therefore, if the use of an application generated via a large-scale language model (LLM) is not comfortable for the user, it is recommended to avoid its installation and use. It is specified that any negative comment regarding this circumstance will not only be ignored but will result in the immediate blocking of the user.
I hereby disclaim any and all responsibility for the application, its functionality, and any consequences arising from its use. By choosing to use this application, the user acknowledges and accepts that they do so entirely at their own risk, and agrees that the developer shall not be held liable for any damages, losses, or adverse effects—whether direct, indirect, incidental, or consequential—resulting from the use or misuse of the application.

### Browser engine — self-contained bundle

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

### Features (1.0)

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

### Roadmap

- Further refinements to permissions, downloads and per-site settings; more UI
  polish.

### Building from source

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

### Engine, compatibility & trademarks

RooTitanium renders pages with **Qt 6 QtWebEngine** (Chromium 122), bundled as
described above and in [NOTICE.md](NOTICE.md). For site compatibility the browser
presents itself as **Google Chrome** through a Client-Hints / user-agent
interceptor; this is identification only and does not make it a Google product.

*"Chromium" and "Google Chrome" are trademarks of Google LLC, and "Qt" is a
trademark of The Qt Company Ltd. RooTitanium is an independent project, **not
affiliated with, sponsored by or endorsed by** Google LLC or The Qt Company; the
names are used solely for identification.*

### License

GPL-3.0-or-later © 2026 RootGPT. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md)
for the third-party components (Qt 6 / QtWebEngine, Chromium) bundled in the RPM.

---

## [ITALIANO]

Un **browser web Chromium per Sailfish OS 5.1**, basato su **Qt 6 QtWebEngine**,
con una UI scritta da zero in QML — non un fork di un browser esistente. Parte
della famiglia di app `RooT*`.

Requisiti: SFOS 5.1.0.11 · **solo aarch64**  
Gruppo Telegram: https://t.me/+E7V-a7x4JbY1Njhk  
RooTitanium è testato:  
- Sony Xperia 10 III (SFOS 5.1.0.11)  

Questa applicazione è stata sviluppata utilizzando tecnologie di intelligenza artificiale, in particolare Warp Terminal e Claude Code Opus, ma Warp Terminal è stato abbandonato in favore di Claude Code. Pertanto, se l'uso di un'applicazione generata tramite un modello linguistico su larga scala (LLM) non fosse per l'utente confortevole, si raccomanda di evitarne l'installazione e l'uso. Si specifica che qualsiasi commento negativo riguardante questa circostanza non verrà solo ignorato, ma comporterà il blocco immediato dell'utente.
Con la presente declino ogni responsabilità relativa all’applicazione, al suo funzionamento e a qualsiasi conseguenza derivante dal suo utilizzo. L’utente, scegliendo di utilizzare l’applicazione, riconosce e accetta di farlo a proprio ed esclusivo rischio, e concorda che lo sviluppatore non potrà essere ritenuto responsabile per eventuali danni, perdite o effetti negativi — diretti, indiretti, incidentali o consequenziali — derivanti dall’uso o dall’uso improprio dell’applicazione.

### Motore del browser — bundle self-contained

Su Sailfish OS, Qt 6 **non** è un componente ufficiale della piattaforma, e
`qt6-qtwebengine` non è precompilato da nessuna parte. RooTitanium distribuisce
quindi un **bundle self-contained**: l'intero runtime Qt 6 + QtWebEngine
(Chromium 122) è compilato dai sorgenti sopra lo stack Qt 6 della community e
installato sotto `/home/rootitanium/`, così l'app **non richiede alcun Qt 6 di
sistema** e non interferisce con la piattaforma.

- **Rendering accelerato in hardware.** QtWebEngine renderizza tramite **EGL su
  libhybris** (i driver GPU Android del dispositivo). Sull'Xperia 10 III (Adreno
  619) l'accelerazione hardware è confermata via `chrome://gpu`.
- **Gira senza sandbox, by design.** Poiché il bundle vive fuori dal rootfs e
  richiede accesso pieno a `/home/rootitanium/`, alle librerie di sistema hybris
  e alla modalità `--no-sandbox` di Chromium, l'app dichiara `Sandboxing=Disabled`
  nel suo `.desktop`. Sono i **Permessi App** in-app (sotto) a controllare
  davvero cosa i siti possono usare.
- **Launcher ELF dedicato.** Un piccolo launcher in `/usr/bin/harbour-rootitanium`
  imposta l'ambiente del bundle ed esegue il browser, forgiando `argv[0]` così
  che Lipstick agganci la finestra a un'unica cover dell'app.

### Funzionalità (1.0)

- **Schede e schede private (incognito)**, con selettore schede e conteggi per
  modalità; opzioni "avvia in privata", "chiudi tutte le schede all'uscita" o
  ripristino sessione.
- **Pagina HOME** con una griglia **Preferiti** (i segnalibri che scegli tu) e un
  elenco **Cronologia**, modificabili al volo.
- **Barra degli indirizzi** con inserimento cerca-o-URL e motore di ricerca
  selezionabile (DuckDuckGo, Google, Bing, Startpage).
- **Segnalibri** (persistenti, SQLite) con toggle Preferiti-in-HOME e riordino, e
  **Cronologia** con svuota-tutto.
- **Download** con cartella di destinazione a scelta (Download / Documenti /
  Immagini / Video / Musica), progresso live, apri e annulla.
- **Cerca nella pagina**, **Condividi**, **Salva pagina come PDF**, toggle
  **sito Desktop/Mobile** e **rotazione orizzontale** (manuale, più automatica
  per il video a tutto schermo).
- **Menu contestuali** dall'aspetto nativo (link / immagine / testo), menu di
  selezione touch e **dialoghi JavaScript** personalizzati (alert / confirm /
  prompt) scalati per il dispositivo.
- **Tastiera a schermo personalizzata** (QtVirtualKeyboard, a tema col browser).
- **Controlli privacy**: Do-Not-Track, **anti-fingerprinting** (farbling stile
  Brave/Cromite), **rifiuto automatico dei banner cookie**, un **interceptor
  Client-Hints / user-agent** che presenta il browser come Google Chrome per
  compatibilità coi siti, pulizia dei cookie di sessione, toggle per JavaScript e
  popup, modalità scura forzata e **pulizia dati di navigazione** con un tap.
- **Permessi App** (interruttori master per fotocamera, microfono, posizione,
  notifiche e download — un cancello sopra le scelte per-sito) e **Permessi siti**
  (per singolo sito: fotocamera / microfono / posizione / notifiche).
- **Ciclo di vita delle schede in background** (freeze / discard) per evitare che
  i siti pesanti blocchino il browser.
- **UI bilingue (Inglese / Italiano)**: italiano sui dispositivi italiani,
  inglese altrove — scelta automaticamente dalla lingua di sistema.

### Roadmap

- Ulteriori rifiniture a permessi, download e impostazioni per-sito; più cura
  della UI.

### Compilare dai sorgenti

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

### Motore, compatibilità e marchi

RooTitanium mostra le pagine con **Qt 6 QtWebEngine** (Chromium 122), impacchettato
come descritto sopra e in [NOTICE.md](NOTICE.md). Per compatibilità con i siti il
browser si presenta come **Google Chrome** tramite un interceptor di Client-Hints /
user-agent; è solo identificazione e non lo rende un prodotto Google.

*"Chromium" e "Google Chrome" sono marchi di Google LLC, e "Qt" è un marchio di
The Qt Company Ltd. RooTitanium è un progetto indipendente, **non affiliato,
sponsorizzato o approvato** da Google LLC o The Qt Company; i nomi sono usati solo
a scopo identificativo.*

### Licenza

GPL-3.0-or-later © 2026 RootGPT. Vedi [LICENSE](LICENSE) e [NOTICE.md](NOTICE.md)
per i componenti di terze parti (Qt 6 / QtWebEngine, Chromium) inclusi nell'RPM.
