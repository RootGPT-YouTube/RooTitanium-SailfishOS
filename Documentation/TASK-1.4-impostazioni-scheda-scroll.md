# TASK 1.4 — Impostazioni: scheda dedicata + niente scroll-to-top al toggle

Stato: **PIANO** (da eseguire). Richiesta utente del 22 lug 2026.

## Il problema (due sintomi, una stessa causa architetturale)

Oggi la pagina Impostazioni **non** è una pagina Silica: è una pagina HTML interna
(`settingsHtml()`) renderizzata *dentro il WebView della scheda in cui ti trovi*.
Stesso pattern di Cronologia / Segnalibri / Download.

Punti nel codice (`smoke-test/test.qml`):
- Voce di menu → `doAction("settings")` → `openSettings(currentView)` — righe 633, 649, 1175.
- `openSettings(view)` fa `loadInternal(view, "settings", settingsHtml(), "https://settings.local/")` — riga 1175-1178.
- I toggle sono link `https://settings.local/set?k=...&v=...`, intercettati in
  `onNavigationRequested` — riga 2174 e seguenti. Ogni `set` termina con
  `win.loadInternal(this, "settings", win.settingsHtml(), "https://settings.local/")` — riga 2191.

Conseguenze:
1. **Sovrascrive la scheda corrente.** Apri Impostazioni e perdi la pagina su cui eri:
   l'HTML delle impostazioni prende il posto del contenuto nella `currentView`.
2. **Ogni toggle riporta in cima.** Il `set` rigenera *tutto* l'HTML e fa un reload
   completo → lo scroll si azzera. Se cambi un'impostazione in fondo alla lista,
   la pagina salta all'inizio.

## Cosa vogliamo

1. Le Impostazioni si aprono in una **nuova scheda** (come una new-tab), senza
   distruggere la pagina di partenza.
2. Applicare una modifica (toggle on/off, radio tema, ecc.) **non** deve far
   tornare la pagina in cima: resta sull'impostazione appena toccata.

## Approccio proposto

### 1. Nuova scheda per le Impostazioni
`newTab(priv)` (riga 153) e `newTabUrl` (riga 689) appendono a `tabsModel`; la view
viene poi creata in modo asincrono dal ListView/Repeater sul modello. Quindi
`openSettings` va riscritto così:
- crea una nuova scheda non-incognito e la rende attiva (come fa `newTab(false)`);
- con `Qt.callLater` (la view non esiste ancora nello stesso frame) chiama
  `loadInternal(nuovaView, "settings", settingsHtml(), "https://settings.local/")`.

Serve un modo pulito per ottenere la view appena creata: o un helper
`openInternalInNewTab(kind, html, base)` che incapsula append + attivazione +
callLater, riusabile anche per Cronologia/Segnalibri/Download se in futuro vorremo
lo stesso comportamento. **Per ora limitare il cambiamento alle Impostazioni**, come
chiesto, ma scrivere l'helper in modo generico.

Nota UX: la nuova scheda avrà `mtitle` = "Impostazioni"/"Settings" (non "Home").

### 2. Niente scroll-to-top al toggle
La causa è il reload completo alla riga 2191. Due strade:

- **(a) Minima** — preservare/ripristinare la posizione: prima del reload leggere
  `window.scrollY` via `runJavaScript`, e dopo il reload ripristinarla. Semplice ma
  resta un reload (piccolo flicker) e c'è un round-trip asincrono.

- **(b) Pulita (consigliata)** — niente reload: alla ricezione del `set`, aggiornare
  solo lo stato QML/SQLite (già fatto da `applySetting`) e riflettere il cambiamento
  nel DOM con un `runJavaScript` mirato che commuta la classe `on`/`off` della sola
  riga toccata (i toggle sono `<a class="srow">` con il pallino/segno di stato).
  Nessun reload → nessun salto, nessun flicker. Richiede che `settingsHtml()` dia agli
  elementi un `id` stabile per riga così da poterli agire da JS.

Raccomandazione: (b). Se troppo invasiva per alcune righe particolari (es. "Pulisci
dati" con conferma inline `settingsClearArm`, o il cambio tema che ricolora tutta la
pagina), quelle possono continuare a fare reload — lì il salto in cima è accettabile
perché la pagina cambia comunque aspetto.

## Verifica sul device
- Apri una pagina qualsiasi, poi Menu › Impostazioni → deve comparire una **nuova
  scheda**; tornando indietro la pagina di prima è ancora lì.
- Scrolla in fondo alle impostazioni, tocca un toggle → lo stato cambia e la vista
  **resta ferma** sull'impostazione toccata.
- Regressione tema: cambiare Scuro/Chiaro continua a funzionare.

## File toccati
- `smoke-test/test.qml` — `openSettings`, eventuale nuovo helper new-tab-interno,
  `settingsHtml()` (id per riga), interceptor `set` alla riga ~2182-2191.
