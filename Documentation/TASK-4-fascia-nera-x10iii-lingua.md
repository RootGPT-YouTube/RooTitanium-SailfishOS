# TASK 4 — Fascia nera X10 III: l'indizio del cambio lingua (26 lug 2026)

Stato: **aperta**, ma con il primo indizio riproducibile dall'utente.
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
