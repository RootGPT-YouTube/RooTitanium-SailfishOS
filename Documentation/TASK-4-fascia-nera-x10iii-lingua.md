# TASK 4 — Fascia nera X10 III: l'indizio del cambio lingua (26 lug 2026)

Stato: ✅ **RISOLTA — task archiviata il 14 ago 2026.**
La cura è in `rtGeomCheck` (`showNormal` + geometria da `Screen`, rinegoziata solo
se il compositore sottrae ≥15% dell'altezza), rilasciata nella **1.4.7-1** il 9 ago
2026 e verificata su X10 III e POCO M4 Pro — la verifica sui due device è in fondo
a questo documento. Era l'intestazione a essere rimasta indietro, non il lavoro.
Il documento resta come storia dell'indagine (l'indizio del cambio lingua, la
race con maliit-server, le misure di clamp).
⚠️ Prima di riaprire qualsiasi ipotesi sulla fascia nera: farsi mandare
`/tmp/rootitanium.log`. Cfr. [[rootitanium-fascia-nera-x10iii]].

Stato storico: **aperta**, ma con **ricetta di riproduzione** (agg. 27 lug, vedi in fondo).
Contesto precedente: `showFullScreen()` (1.4) non risolve sul device di Steve ed è
stato rimosso in 1.4.5 perché causava schermo nero su X10 II (Adreno 508).
La 1.4.5 torna al rendering della 1.3 e aggiunge solo la pagina Impostazioni/About:
la fascia nera resta.

## Il dato nuovo (segnalazione di Steve, Xperia 10 III "Loki", SFOS 5.1.0.11)

Sequenza verificata da lui:

1. Impostazioni di sistema → lingua **Italiano** → riavvio (SFOS riavvia sempre
   dopo un cambio lingua) → **RooTitanium va a schermo pieno**.
2. Lingua rimessa a **Inglese** → riavvio → **resta a schermo pieno**.
3. Riavvio successivo **senza toccare la lingua** (inglese → inglese) →
   **torna a usare 2/3 di schermo**.

Quindi non è la lingua in sé (l'inglese funziona, al punto 2) e non è il layout di
tastiera italiano: è **l'atto del cambio lingua** a produrre un boot "buono", uno solo.

## Lettura del fenomeno

Coerente con la diagnosi già consolidata: la fascia = 2520−1660 = 860 px fisici =
328 px logici = altezza esatta della tastiera, cioè la **riserva input-panel
permanente** che lipstick applica alla finestra maximized (vedi log 23 lug).
L'unica variabile che il cambio lingua muove al boot è **maliit-server**: cambiare
lingua invalida/rigenera i layout e la sua configurazione, quindi al primo avvio
successivo maliit parte più tardi o in stato "pulito". Ipotesi di lavoro:

> È una **race di avvio** fra maliit-server e la prima finestra Qt6/xdg-shell.
> Se al momento del `configure` l'input panel risulta già mappato/registrato,
> lipstick riserva l'area per sempre; se maliit non è ancora pronto (boot dopo il
> cambio lingua) la riserva non viene applicata e la finestra prende tutto lo schermo.
> Ai boot successivi la cache dei layout è di nuovo valida → maliit torna veloce →
> riserva.

Ipotesi alternativa da non scartare: non la tempistica ma uno **stato incastrato**
in dconf/cache di maliit che il cambio lingua ripulisce e che si ricostruisce guasto
al boot pulito successivo.

## Cosa chiedere/far fare a Steve (in ordine di costo)

1. Con l'app aperta nello stato ROTTO: `systemctl --user restart maliit-server`
   → già provato il 23 lug, la fascia RESTA. Ripeterlo invece **chiudendo l'app,
   riavviando maliit e poi riaprendo l'app**: se torna a schermo pieno, la race è
   confermata e il workaround è banale.
2. `dconf dump /sailfish/text_input/` e `dconf dump /desktop/lipstick-jolla-home/`
   nei due stati (boot buono dopo cambio lingua / boot rotto) → **diff**.
   È il test che discrimina "race" da "stato incastrato".
3. `/tmp/rootitanium.log` nei due stati: nel boot buono ci aspettiamo
   `configure 1080x2520` fin dal primo, nel rotto il 1660 come sempre.
4. `systemctl --user list-units --all | grep -i maliit` + `journalctl --user -b -u
   maliit-server` nei due boot: confrontare l'istante di avvio rispetto alla sessione.

## Possibili cure lato nostro (nessuna ancora scelta)

- **Ri-negoziare lo stato quando il configure è degradato**: `showNormal()` +
  geometria esplicita da `Screen` (finestra non-maximized: la size la decide il
  client). Da testare per primo, è indipendente da maliit.
- Ritentare il set_fullscreen su un configure a geometria ridotta — ma attenzione:
  ogni cosa che passi per `showFullScreen()` va **ricollaudata su X10 II** prima di
  rilasciare (regressione schermo nero, 1.4).
- Se si confermasse la race: nessuna cura pulita lato app, si documenta il
  workaround (riavviare maliit prima di aprire l'app).

⚠️ Vincolo permanente: qualunque fix qui deve essere neutro sull'X10 II.

---

# Aggiornamento 27 lug 2026 — riproduzione trovata e log A/B analizzati

## La ricetta (Steve, verificata su 10 III, 10 IV e 10 V)

> In una qualsiasi app con la tastiera SFOS, **long-press sulla barra spazio →
> layout Emoji**. Da quel momento RooTitanium parte a 2/3 di schermo. Nessun
> reboot necessario, e vale su **tutti** i device, non solo il 10 III.

Non curano: tornare al layout EN, `systemctl --user restart maliit-server`.
Cura confermata: cambio lingua di sistema + reboot (quello che sembrava "l'atto
del cambio lingua" era in realtà solo il reboot che azzera lo stato in RAM).

Cade quindi l'ipotesi **race di avvio** della sezione precedente: il trigger non
è il boot, è l'uso del layout emoji a sessione avviata.

## Log a confronto (in `scratch/log-steve-27lug/`, fuori da git)

Stesso binario 1.4.5, A = stato buono, B = stato rotto:

- **A**: tutti i `xdg_toplevel.configure` a `QSize(1080, 2520)`.
- **B**: il **secondo** configure (riga 77) è già `QSize(1080, 1660)`, e ci resta
  per tutta la sessione. Arriva **prima del primo frame di WebEngine** e senza che
  nessun campo di testo abbia il focus → non è l'app ad aprire la tastiera.
- In entrambi lo stato è `WindowMaximized`, **mai** `WindowFullScreen` (come già
  noto: lipstick non acka il set_fullscreen da nessuna parte).
- `A-maliit.txt` e `B-maliit.txt` identici: `maliit-server` active/running in
  entrambi → non è maliit acceso/spento.
- `dconf dump /sailfish/text_input/` **non discrimina**: entrambi hanno
  `active_layout='en.qml'`, `previous_layout='emojis.qml'`, `enabled_layouts` con
  `emojis.qml`. Unica differenza: `split_landscape=true` presente solo in A —
  debole, e i due dump potrebbero venire da device diversi.

## Conclusione

Lo stato incastrato **non è su disco** (dconf identico): sta in RAM in
lipstick/maliit, ed è per questo che solo il reboot lo azzera. Dopo il passaggio
al layout emoji, l'area input-panel che maliit comunica a lipstick non torna più
a zero; lipstick la sottrae in permanenza alle finestre `Maximized`. Le app Silica
non ne risentono perché lipstick le tratta come fullscreen: RooTitanium è l'unica
app Qt6/xdg-shell sul device di Steve, quindi l'unica che paga.

## 28 lug — RIPRODOTTO E CURATO SUL DEVICE DI SVILUPPO

Riproduzione **senza toccare il telefono** (X10 III di sviluppo, 5.1.0.11):

```
systemctl --user restart maliit-server     # basta questo!
# poi (ri)lanciare RooTitanium
```

Il trigger vero **non è il layout Emoji**: è maliit-server che **ri-crea la sua
surface** (restart del servizio, oppure cambio di layout come il passaggio a
Emoji). Da quel momento lipstick tiene riservata l'area dell'input panel e la
sottrae a ogni finestra `Maximized` aperta **dopo**, per sempre. Misure sul dev
device: configure `1080x1860` invece di `1080x2520` → fascia nera di 660 px
(su Steve era 860: l'altezza dipende dal panel).

**Cosa NON pulisce**: tornare al layout precedente, riavviare maliit-server.
**Cosa pulisce**: `systemctl --user restart lipstick` (verificato: torna sano
senza reboot) — è il workaround da dare agli utenti — oppure il riavvio del telefono.

### La cura, verificata

In `rtGeomCheck` (`smoke-test/test.qml`), **solo** su configure degradato e
**una sola volta**: `showNormal()` + `width`/`height` espliciti da `Screen`.
Una finestra non-maximized decide da sé la propria size, quindi il clamp di
lipstick non la tocca. Esito misurato sugli screenshot:

| stato | prima | dopo la cura |
|---|---|---|
| rotto (riserva attiva) | 1080x1860, fascia 660 px | **1080x2520, fascia 0** |
| sano (dopo restart lipstick) | 1080x2520 | ramo **non scattato** (0 volte) |

Stabile a 45 s dall'avvio, nessun configure di ritorno, UI corretta. Il ramo che
non scatta su device sano è la garanzia per l'**X10 II**: lì la surface non viene
mai riconfigurata, quindi la regressione dello schermo nero (1.4) non può tornare.
Niente `showFullScreen()`: lipstick non lo acka mai, su nessun device.

### 28 lug sera — il primo tentativo di cura non bastava: due difetti

Dopo il collaudo tattile la fascia era tornata, **e nel log non c'era nessun
warning**: la cura non era proprio scattata. Due cause, entrambe corrette:

1. **I binding `width/height: Screen…` mascheravano il clamp.** Erano stati messi
   il 21 lug come "geometria imposta, non subita": non hanno mai impedito al
   compositor di rimpicciolire la surface. Peggio: quando il primo `configure`
   arriva **già** ridotto (com'è successo lanciando dall'icona: primo configure
   `1080x1860`), il binding riporta `height` a 2520 mentre la surface resta 1860 →
   la Window disegna per 2520, se ne vede 1860, e `onHeightChanged` non scatta mai.
   **Rimossi**: ora la geometria della Window è quella vera del compositor.
2. **Un solo tentativo non basta**: lipstick ri-clampa anche durante l'uso. Nel
   collaudo dell'utente sono arrivati **2 clamp** e sono servite **2
   rinegoziazioni** (tetto attuale: 8).

Con `width !== sw || height >= sh || height < sh/2` si ignora tutto ciò che non è
il clamp vero — in particolare la geometria `500x500` che la Window ha prima di
essere mappata, che senza binding adesso esiste.

✅ **Collaudo tattile superato** (utente, 28 lug sera): tastiera in-app, rotazione,
minimizza/riprendi, link da altra app — nessuna fascia nera, 2 clamp intercettati e
rinegoziati. Commit `eec20c5`.

### Cosa manca prima del rilascio

- ~~collaudo tattile~~ ✅ fatto il 28 lug sera, superato;
- bump versione + RPM (pipeline `/rilascia_rootitanium`) e messaggio a Steve con
  il workaround immediato (`systemctl --user restart lipstick`).

## Prossimo passo (superato dal blocco qui sopra)

Il bug ora è riproducibile **anche sul device di sviluppo**: riattivare
maliit-server, usare una volta il layout Emoji, rilanciare RooTitanium e
verificare il 1660 nel log. Da lì si collaudano in locale le cure, che vanno
comunque rese **reattive** e non incondizionate:

- scatenare la rinegoziazione **solo** da `rtGeomCheck` (`smoke-test/test.qml:27`)
  quando il configure arriva ridotto, **all'avvio e una sola volta**, prima che
  WebEngine abbia creato la sua subsurface;
- primo candidato `showNormal()` + geometria esplicita da `Screen` (finestra non
  maximized: la size la decide il client), che non passa da `showFullScreen()`;
- su device sani il ramo non scatta mai → l'X10 II resta intatto per costruzione.

## 9 ago 2026 — regressione su porting con cutout (POCO M4 Pro 4G) e soglia del 15%

Segnalazione dell'utente su **Xiaomi POCO M4 Pro 4G** (`fleur`), 1.4.6 installata:
fascia nera in alto **e tastiera in-app tagliata in fondo**. Misura sullo
screenshot (1080x2400): 93 px di nero in alto, e in basso manca esattamente
altrettanto — cioè la finestra è alta quanto lo schermo ma **ancorata sotto** la
striscia riservata, quindi sfora oltre il bordo inferiore.

Diagnosi sul device (ssh, `QT_FORCE_STDERR_LOGGING=1`, bundle di sistema intatto:
`test.qml` patchato in `/tmp/rtdiag` + copia di `run.sh` con `HERE` fisso e
`argv[0]` forgiato su `/tmp/rtdiag`, così `main.cpp` carica il QML di prova):

```
[rt] geometria finestra 1080x2274 diversa dallo schermo 1080x2400
[rt] geometria rinegoziata (1) … (8)        ← ping-pong fino al tetto
```

**Il clamp non è la riserva dell'input panel**: sono 126 px, il 5% dell'altezza —
la striscia che il compositor del porting riserva stabilmente (cutout/punch-hole).
La cura dell'X10 III scattava lo stesso, riportava la finestra a 2400 senza
spostarne l'origine (il client xdg-shell non decide la propria posizione) e
lipstick ri-clampava subito: fascia nera **più** contenuto tagliato **più**
ping-pong.

### La correzione

In `rtGeomCheck` si rinegozia solo se il pezzo mancante è grande quanto una
tastiera: **gap ≥ 15% dell'altezza dello schermo**. Sotto soglia si accetta la
geometria del compositor (si perde la striscia, ma il contenuto resta integro) e
si logga una riga sola.

| device | configure | gap | % | rinegozia |
|---|---|---|---|---|
| X10 III, riserva input panel | 1080x1860 su 2520 | 660 px | 26,2% | **sì** |
| POCO M4 Pro, cutout | 1080x2274 su 2400 | 126 px | 5,3% | **no** |

### Verifica sui due device (9 ago 2026)

- **POCO M4 Pro** (`fleur`, 1080x2400): una sola riga
  `[rt] clamp piccolo del compositor: finestra 1080x2274 … (126 px, 5%) —
  accettato`, nessuna rinegoziazione, nessun ping-pong.
- **X10 III** (`xqbt52`, 1080x2520): bug riprodotto con
  `systemctl --user restart maliit-server`, poi rilancio dell'app → clamp
  `1080x1860` intercettato, **1 rinegoziazione**, geometria stabile `1080x2520`
  a ~50 s. Comportamento identico a 1.4.6. Stato di lipstick ripulito dopo il
  test con `systemctl --user restart lipstick`.

La condizione è più stretta, non più larga: i casi in cui la cura non scattava
(X10 II incluso) restano intatti per costruzione.
