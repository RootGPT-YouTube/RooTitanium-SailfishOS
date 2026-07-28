# TASK 4 — Fascia nera X10 III: l'indizio del cambio lingua (26 lug 2026)

Stato: **aperta**, ma con **ricetta di riproduzione** (agg. 27 lug, vedi in fondo).
Contesto precedente: `showFullScreen()` (1.4) non risolve sul device di Steve ed è
stato rimosso in 1.4.5 perché causava schermo nero su X10 II (Adreno 508).
La 1.4.5 torna al rendering della 1.3 e aggiunge solo la pagina Impostazioni/About:
la fascia nera resta.

## Il dato nuovo (segnalazione Steve, Xperia 10 III "Loki", SFOS 5.1.0.11)

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

### Cosa manca prima del rilascio

- collaudo **tattile** sul device con la cura attiva e la riserva presente:
  tastiera in-app, rotazione dal menù ⋮, minimizza/riprendi dalla home,
  apertura di un link da un'altra app (la finestra ora è `Windowed`, non
  `Maximized`: va verificato che lipstick non la disegni diversamente);
- poi bump versione + RPM (pipeline `/rilascia_rootitanium`).

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
