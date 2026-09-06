# Tastiera di sistema (Maliit) al posto di QtVirtualKeyboard

Aperta e realizzata il **6 set 2026**, su segnalazione di **Cristoffer (Imperador)**,
che ha mostrato la tastiera SFOS dentro RooTitanium con questo solo indizio:
«Tested it without run.sh. So I assume it is probably in one of those variables».

Stato: **implementata**, con un limite noto in orizzontale (sotto).

## La variabile era `QT_IM_MODULE`

La sessione utente di SFOS esporta `QT_IM_MODULE=Maliit`. Sia `smoke-test/run.sh`
sia `rootitanium-launch.c` la sovrascrivevano con `qtvirtualkeyboard` (in C con
`setenv(..., 1)`, quindi anche per i lanci da icona): lanciando l'eseguibile
**senza** wrapper, la variabile sopravviveva e la tastiera di sistema entrava.

## Le tre cose che si credevano vere e non lo erano

1. **«Il plugin Maliit per Qt6 è in Chum.»** No: in Chum stabile per 5.1 non
   esiste **nessun** pacchetto `qt6-*`. `qt6-sfos-maliit-platforminputcontext`
   sta in **`chum:testing`**. Un utente qualunque non ce l'ha → non può essere
   una dipendenza dell'RPM, va imbarcato nel bundle.
2. **«Basta non impostare `QT_IM_MODULE` e Qt usa il text-input di Wayland.»**
   No. Provato sul POCO M4 Pro: senza plugin non compare nessuna tastiera, né con
   `QT_IM_MODULE=Maliit` (Qt cerca un plugin con quel nome, non lo trova e
   ripiega sull'input context `compose`, che non apre tastiere) né con la
   variabile tolta del tutto. Il `libQt6WaylandClient` del bundle *contiene*
   `zwp_text_input_v1/v2/v3`, ma non è quella la strada su SFOS: il canale è
   **D-Bus verso `maliit-server`**, e lo apre il plugin.
3. **«lipstick non ruota le superfici wayland, le app SFOS si ruotano da sole.»**
   (commento storico in `test.qml`) No: non le ruota finché nessuno glielo
   chiede. Dichiarando `contentOrientation` sulla `Window`, lipstick ruota la
   superficie davvero — `xdg_toplevel.configure` passa da `1080x2400` a
   `2274x1080`.

## Come è fatta

- Il plugin (`libmaliitplatforminputcontextplugin.so`, 535 KB, LGPLv2) entra nel
  bundle tramite `packaging/harbour-rootitanium/fetch-maliit-plugin.sh`, che lo
  scarica dal pacchetto pubblicato verificandone lo SHA-256. Nel repo, che è
  pubblico, **non** teniamo il binario: teniamo la provenienza.
  Dipende solo da Qt6 Core/Gui/Quick/DBus, tutte già nel bundle, e carica pulito
  contro il nostro Qt 6.8.3 (nessun rifiuto di versione).
- Launcher (`rootitanium-launch.c`) e `run.sh` scelgono: `QT_IM_MODULE=maliit` se
  il plugin è nel bundle **e** esiste `/usr/bin/maliit-server`, altrimenti
  `qtvirtualkeyboard`. QtVirtualKeyboard, i layout e lo stile `rt` **restano
  imbarcati**: sono il ripiego.
- `main.cpp` espone `rtMaliit` al QML; `test.qml` istanzia l'`InputPanel` di
  QtVirtualKeyboard solo quando `rtMaliit` è falso. Senza questa condizione si
  aprono **due tastiere** insieme (visto sul POCO).

## Il trabocchetto grosso: `rtGeomCheck` contro la tastiera

Con la tastiera di sistema aperta, il compositor **restringe la finestra** per
farle posto: `configure 1080x1421` su schermo 1080x2400. `rtGeomCheck()` — nato
per la fascia nera dell'X10 III — vede un clamp «alto quanto una tastiera»,
crede sia quel difetto e rinegozia con `showNormal()` + geometria da `Screen`.
Il compositor risponde, si rinegozia di nuovo, e in pochi giri arrivano
geometrie assurde (`QSize(194, 1421)`, `QSize(194, 2274)`): **schermo nero**.

Cura: `rtGeomCheck()` esce subito quando `useMaliit` è attivo e l'input method è
visibile. Quel clamp, lì, non è il difetto — è letteralmente una tastiera.

## La rotazione in orizzontale: come si è risolta

Per un giorno intero è sembrata irrisolvibile, e le prime tre diagnosi erano
**tutte sbagliate**. Vale la pena tenerle scritte, perché ognuna sembrava
convincente:

1. *«Manca `contentOrientation`.»* Da solo peggiora: la superficie ruota
   (`configure` 1080x2400 → 2274x1080) ma la tastiera resta dritta e lipstick ci
   riserva l'area di una tastiera verticale — restano `2274x194` px, schermo
   nero. Serve **insieme** alla rotazione della tastiera (sotto), e nel verso
   `InvertedLandscape`: `Landscape` gira dalla parte opposta.
2. *«Serve il protocollo Wayland di Sailfish.»* lipstick espone davvero ancora
   `qt_surface_extension` (verificato con un client `wl_registry` compilato per
   il device: c'è, insieme a `qt_windowmanager`, `qt_touch_extension`,
   `wl_shell`), e con `QT_WAYLAND_SHELL_INTEGRATION=wl-shell` il nostro Qt6 crea
   l'extended surface. Ma non è quella la via: con `xdg-shell` Qt binda
   l'extension e non la usa mai (`WAYLAND_DEBUG=1`: nessun
   `set_content_orientation_mask` sul filo). `qt-shell` non parte proprio.
3. *«maliit-server ignora l'angolo.»* No: l'angolo **non gli arriva mai**.

La causa vera sta nel plugin, e si legge solo nel sorgente della *versione
impacchettata* (`debugsource` del pacchetto, non `master`, dove il codice è
ancora attivo — la differenza ci ha depistati): in `minputcontext.cpp` la
connessione `contentOrientationChanged → updateServerOrientation` è
**commentata** (righe 348 e 354-355), dal commit di Rinigus del 2020 *«follow
Flatpak container window orientation»*. Al suo posto il plugin interroga un
"container" D-Bus, ma **solo** se trova il suo indirizzo in
`FLATPAK_MALIIT_CONTAINER_DBUS` — pensato per le app Flatpak, dove il container
è il compositore annidato. Per un'app normale la variabile è vuota,
`containerOrientation` resta 0 per sempre, e al server non parte nulla.

### La soluzione: facciamo noi da container

`main.cpp` espone al proprio plugin esattamente ciò che il plugin cerca
(`RtMaliitContainer`): server D-Bus **peer-to-peer** su un socket privato in
`XDG_RUNTIME_DIR` (nessun bus di sessione, niente di visibile ad altri
processi), oggetto su `/`, interfaccia `org.container`, proprietà `orientation`
(gradi) e `activeState`, segnali `orientationChanged(int)` e
`activeStateChanged(bool)`. `test.qml` pubblica l'angolo dentro
l'`onOrientChanged` che già esisteva.

Due trappole, entrambe pagate:

- **Il server deve essere in ascolto PRIMA di `QGuiApplication`**: il plugin si
  costruisce lì dentro e legge la variabile d'ambiente una volta sola.
- **E deve vivere in un THREAD suo.** Il plugin, nel costruttore, legge le
  proprietà con una chiamata D-Bus *sincrona*, sul main thread: se a servirla
  fosse lo stesso main thread — fermo ad aspettare quella risposta — l'app si
  pianta prima di mostrare la finestra. Sintomo esatto: il log si ferma su
  `Successfully created platform theme "generic"` e l'app non parte. Con il
  server su `RtMaliitContainerThread` parte e la tastiera ruota.

Se il container non si avvia, l'app parte lo stesso: si perde la rotazione della
tastiera, non l'avvio.

### `activeState`

Il plugin inoltra l'angolo solo se `containerActive && active`
(`updateContainerOrientation`): il nostro `activeState` risponde sempre `true`,
altrimenti l'angolo verrebbe scartato in silenzio.

## L'assetto finale (e i due difetti latenti che ha portato a galla)

Messi insieme i due pezzi — `contentOrientation` (`InvertedLandscape`) **e** il
container che ruota la tastiera — la rotazione la esegue il compositor: la
finestra arriva già orientata, `appRoot` non ruota più nulla e l'area della
tastiera viene sottratta dal lato giusto.

Restava un'alternanza: alla stessa azione, la finestra riceveva a volte 194 px di
altezza (riserva calcolata su tastiera verticale) e a volte 480 (tastiera
ruotata). Causa: il plugin inoltra l'angolo al server **solo con un campo a
fuoco** (`containerActive && active`), quindi la prima notifica arriva insieme
all'apertura della tastiera, quando lipstick può aver già fatto il conto.
Rimedio: `reassertOrientation()` — l'angolo viene ripetuto 250 ms dopo la
comparsa della tastiera, e il calcolo si rifà.

Infine, due difetti che erano **latenti da sempre** e sono emersi solo ora che la
finestra si rimpicciolisce davvero (prima la rotazione era interna e
`rtGeomCheck` respingeva ogni clamp):

- `zoomFactor` della WebEngineView era `min(win.width, win.height) / 412`: con la
  tastiera aperta in orizzontale il lato corto della finestra scende a ~480 e il
  fattore crollava da 2.6 a 1.2 — pagina di colpo minuscola;
- `u`, l'unità di misura di tutta la UI, era `min(width, height) / 540`: stessa
  dinamica, da 2 a 0.9, e toolbar/barra indirizzi si rimpicciolivano.

Entrambi ora si basano sul lato corto dello **schermo**, che non cambia mai.
