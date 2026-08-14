# TASK menù a tendina — il popup dei `<select>` HTML non è selezionabile

Stato: **IMPLEMENTATA il 14 ago 2026 — in attesa di collaudo sul device**
(telefono spento/irraggiungibile al momento della scrittura: `No route to host`).
Soluzione A realizzata in QML puro, nessun rebuild del motore.
Precedenza: **da fare PRIMA della [TASK Chromium 140](TASK-chromium-140.md)**
(richiesta esplicita dell'utente). Consigliata anche prima della
[TASK ad-block](TASK-adblock.md): qui si rompe l'uso normale di molti siti,
là si aggiunge una funzione.

## Il sintomo

Su molti siti (caso di riferimento: **cerchigomme.it**) il menù a tendina si
**apre** al tocco, ma toccando una voce **non succede nulla**: parole
dell'utente, «sembra che il dito attraversi la voce nel menù». Il tocco finisce
alla pagina sotto, non alla lista.

Verificato che cerchigomme.it usa **`<select>` nativi** (20 nella sola home,
classi Bootstrap `form-select`), non menù finti fatti di `<div>`: il difetto è
quello del popup nativo, non un problema di hover/tap su UI custom.
⚠️ Molti di quei `<select>` hanno classe `changer`/`submit`, cioè un handler
sull'evento `change` che filtra a cascata (larghezza → serie → diametro): vedi
sotto, è un vincolo sulla soluzione.

## La causa

Il difetto era **già noto e registrato** come effetto collaterale in
`TASK-chromium-140.md`, ma non aveva una task propria.

QtWebEngine non disegna il popup del `<select>` dentro la scena QML: lo mette in
una **QQuickWindow top-level separata**,
`qt6-qtwebengine/upstream/src/webenginequick/render_widget_host_view_qt_delegate_quickwindow.cpp`,
creata nel costruttore con

```cpp
setFlags(Qt::Tool | Qt::WindowStaysOnTopHint | Qt::FramelessWindowHint
         | Qt::WindowDoesNotAcceptFocus);
```

e mostrata da `InitAsPopup()` con una geometria in coordinate globali.
Su Wayland/lipstick quella surface **viene composta e si vede**, ma non riceve
gli eventi touch: il compositore li consegna alla finestra dell'app sotto. Da qui
l'impressione del dito che attraversa.

🔴 Il salto a Chromium 140 **non risolve**: in `v6.11.1` quel file ha la stessa
architettura (QQuickWindow separata, stessi flag). Registrarlo come task a sé è
quindi corretto e indipendente dall'aggiornamento del motore.

**Non esiste un segnale QML per prendere il controllo del popup.** L'elenco dei
`Q_SIGNALS` di `qquickwebengineview_p.h` (6.8.3) ha `contextMenuRequested`,
`fileDialogRequested`, `colorDialogRequested`, `javaScriptDialogRequested`,
`touchSelectionMenuRequested`… ma **nessun `selectPopupRequested`**: il popup del
`<select>` è interno a Chromium e non passa dall'API pubblica. Questa è la
differenza rispetto al file picker, che abbiamo potuto dirottare con
`onFileDialogRequested` (`smoke-test/test.qml:857`).

## Fase 0 — conferma della diagnosi (mezz'ora, obbligatoria)

Prima di scrivere codice, dimostrare che la surface del popup non riceve il
touch, invece di dedurlo:

1. lanciare l'app da ssh con `WAYLAND_DEBUG=1` (invoker + env di
   `systemctl --user show-environment`, come da prassi) e guardare se sulla
   surface del popup arriva un `wl_touch.down` o se arriva solo alla surface
   principale;
2. controprova a **mouse** (BT o `evdev` sintetico): se col mouse la voce si
   seleziona, il problema è la consegna del *touch*, non l'hit-testing;
3. controprova su una pagina minima locale con un solo `<select>`, per escludere
   sovrapposizioni/`z-index` del sito.

Se il touch arriva ma alle coordinate sbagliate il rimedio è tutt'altro
(geometria in `InitAsPopup`), quindi questo passo decide quale ramo prendere.

## Soluzione A — sostituire il popup con un menù QML nostro (consigliata)

Stessa filosofia del file picker e del quick-menu di selezione: non combattere il
popup di Chromium, **non farlo aprire** e mettere al suo posto UI nostra.

1. **User script** (pattern già rodato: `rtYtTapFix` `test.qml:568`,
   `cookieBannerJs` ~537) che su `pointerdown`/`mousedown` su un `<select>` fa
   `preventDefault()` e serializza `options` (testo, `value`, `selected`,
   `disabled`, gruppi `<optgroup>`, `multiple`, indice corrente) più il
   `getBoundingClientRect()` dell'elemento.
2. **Canale JS → QML.** Oggi non c'è né `WebChannel` né un ponte generico: da
   scegliere in fase di piano fra (a) `WebEngineView.webChannel` con
   `qwebchannel.js` iniettato — la via pulita e bidirezionale, (b) la sentinella
   già collaudata sul lato C++ (richiesta a URL fittizio vista da
   `HeaderInterceptor::interceptRequest`, `smoke-test/main.cpp:52`; ricordare che
   `fetch` verso schema custom è bloccato → si usa `Image`).
   ⚠️ Serve `runsOnSubFrames: true`: i form dentro `<iframe>` sono comuni.
3. **Menù nativo**: riusare `ctxMenu` + `ctxModel` (già usati da
   `showTouchSelection`, `test.qml:819`) — voci alte quanto il resto della UI
   touch, con scroll quando le opzioni sono tante (una tendina di marche auto ne
   ha centinaia) e ricerca/filtro come possibile extra.
4. **Riscrittura del valore**: alla scelta, `runJavaScript` imposta
   `selectedIndex`/`value` e **spara `input` e `change` con `bubbles: true`**.
   Questo punto non è opzionale: su cerchigomme.it i `<select>` con classe
   `changer` filtrano a cascata sull'evento `change` — senza eventi sintetici la
   pagina resterebbe ferma e sembrerebbe di nuovo rotta.
5. **Casi limite** da coprire nel collaudo: `<select multiple>`, `size > 1` (che
   non è un popup e non va toccato), `disabled`, elementi dentro `<label>`,
   select riempiti via JS dopo il load (osservare le mutazioni), e il tasto
   Indietro/tap fuori che deve chiudere senza cambiare valore.

Costo stimato: **1-2 giornate**, nessuna ricompilazione del motore, nessun
rischio di regressione grafica, e resta valido dopo il passaggio a 140.

## Soluzione B — patch al motore (da tenere di riserva)

Togliere `Qt::WindowDoesNotAcceptFocus` / cambiare i flag della popup window, o
in alternativa reparentare il popup dentro la scena QML anziché in una
QQuickWindow separata. Va nella stessa famiglia delle patch SFOS di Rinigus.

Costi e controindicazioni: richiede una **ricompilazione di qtwebengine** (molte
ore, cfr. guardia VRM), va **rifatta a ogni aggiornamento del motore** — quindi
di nuovo alla 6.11.1 — e tocca proprio l'area grafica che le patch
`egl-validating` / `shared-gl-texture` rendono fragile su hybris. Da valutare
solo se la Fase 0 dimostrasse che la via A non basta.

## Com'è stata realizzata (14 ago 2026)

Tutto in `smoke-test/test.qml`, **niente C++, niente rebuild**:

- **`selectMenuJs`** (user script `rtSelectMenu`, DocumentCreation, MainWorld,
  `runsOnSubFrames: true`): intercetta `mousedown` e `click` in **cattura**, fa
  `preventDefault()` — così il popup nativo non si apre proprio — e serializza le
  opzioni. Debounce di 600 ms perché da touch QtWebEngine sintetizza
  mousedown+click e altrimenti il foglio si aprirebbe due volte.
  Lasciati **nativi** i casi che popup non sono: `multiple`, `size > 1`,
  `disabled`.
- **Canale JS → QML: una riga di `console.log('__rtsel:open')`** raccolta da
  `onJavaScriptConsoleMessage`, poi il QML tira i dati con
  `runJavaScript("window.__rtSelData")`. Scelto al posto di `WebChannel`: zero
  dipendenze nuove, zero C++, payload di qualsiasi dimensione (una tendina di
  marche auto ha centinaia di voci, una URL sentinella non basterebbe).
  ⚠️ Verificato sui sorgenti (`qquickwebengineview.cpp:774`): **connettendo quel
  segnale il logging JS di serie si spegne** (`receivers() > 0` → `return`), per
  questo l'handler ristampa warning ed errori, che è esattamente ciò che il
  default faceva (la categoria `js` nasce a `QtWarningMsg`).
- **Iframe**: `runJavaScript` da QML raggiunge **solo il main frame**, quindi nei
  sub-frame il payload sale al top con `postMessage` e il top ricorda
  `event.source` per rispedire giù la scelta.
- **Foglio QML** `selMenu`: sheet dal basso, alto al massimo il 70% dello
  schermo, `ListView` scrollabile che si apre già posizionata sulla voce corrente
  (`positionViewAtIndex(..., ListView.Center)`), spunta sulla voce attiva,
  opzioni disabilitate in grigio e non toccabili, `optgroup` come prefisso della
  riga, tap fuori o Annulla = nessuna modifica.
- **Riscrittura del valore**: `selectedIndex` + `input` e `change` con
  `bubbles: true`.

Collaudo fatto finora, **senza device**: sintassi dello user script (`node
--check`) e due prove su DOM finto — apertura (popup prevenuto, payload con
indice e opzioni disabilitate corretti, `input`+`change` sparati sulla scelta) e
casi limite (una sola apertura per mousedown+click; `multiple`, `size=4`,
`disabled` non intercettati). Bilanciamento del QML verificato.

**Resta da fare sul telefono**: la Fase 0 qui sopra vale ora come verifica del
risultato, non più della causa — aprire cerchigomme.it, controllare che compaia
il foglio nostro e non il popup di Chromium, e che la cascata dei filtri reagisca.

## Fatto quando

Su cerchigomme.it si sceglie stagione, larghezza, serie e diametro con il dito,
la cascata di filtri reagisce a ogni scelta, e la ricerca parte.

Cfr. [[rootitanium-select-popup]], [[rootitanium-chromium-update]],
[[rootitanium-browser-backlog]], [[collaudo-app-device-trappole]].
