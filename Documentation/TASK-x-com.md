# x.com: caricamento dei post che si ferma

**Aperta il 17/09/2026**, su richiesta dell'utente. Problema vecchio, mai capito.

## Sintomo
Si apre x.com, si scrolla un secondo verso il basso e **smette di caricare i
post**. Non è il login, che dal 14 luglio funziona regolarmente.

## Cosa NON è (verificato oggi)
- **Non è la mancanza di accelerazione hardware**: il browser è già su GPU
  (misure in `TASK-decodifica-video.md` e nella memoria di progetto).
- **Non è solo il nostro farbling.** Il log di sessione mostra che il bundle
  anti-bot di X (`ondemand.castle...js`) martella il canvas per fare
  fingerprinting, e il nostro `rtFarble` intercetta ogni lettura ciclando **su
  ogni pixel** in JavaScript (`test.qml`, `fb(img)`: `for(var i=0;i<d.length;i+=4)`);
  `toDataURL` è peggio ancora. Spegnendo «Disattiva fingerprint» l'utente riferisce
  che X va **«un po' meglio, ma continua ad avere problemi di caricamento»**.
  Quindi è un costo reale ma **non è la causa** del blocco.
- Nel log della sessione del 17 set **non compaiono errori di rete su X**
  (`ERR_` appare 2 volte in tutta la sessione, per un indirizzo irraggiungibile).
  ⚠️ Ma quella sessione era col farbling acceso e non è confermato che l'utente
  avesse scrollato fino a far comparire il blocco: il dato è debole.

## Ipotesi da verificare, in ordine
1. **Richieste dell'infinite scroll che falliscono o non partono.** Da guardare
   dal vivo, non nel log a posteriori.
2. **IntersectionObserver che non scatta**: X carica altri post quando una
   sentinella entra nel viewport. Con `zoomFactor` 2.62 e
   `--force-device-scale-factor=2.6214` la matematica di viewport/visualViewport
   è anomala rispetto a un browser normale — sospetto specifico nostro.
3. Pressione di memoria sul renderer.

## Metodo
Lanciare l'app da `/home/rootitanium/run.sh` (il launcher ELF sovrascrive sempre
i flag, `run.sh` no): così si accende **DevTools sulla porta 9222**, si fa un
tunnel ssh e si guarda la pagina *mentre* si blocca — richieste, observer,
memoria. È lo stesso metodo che ha risolto il login di X a luglio, vedi la nota
di memoria `debug-login-antibot-cdp`.

## Cura possibile per il costo del farbling (indipendente dal blocco)
Farbling solo su tele piccole, o campionamento sparso invece che pixel per pixel:
si toglie il costo senza dover scegliere fra privacy e usabilità.

## ✅ Risolta il 29/09/2026 — era il nostro script «Rifiuta cookie»
Guardando la pagina dal vivo via DevTools (POCO, RPM 2.0-1): `scrollY` sempre 0,
`documentElement.scrollHeight` = 808 (l'altezza dello schermo) e il **body** con
15.939 px di scroll suo. Lo script `cookieBannerJs` iniettava su ogni sito
`html,body{overflow:auto!important}`: con `html` non più `visible`, l'overflow del
body non si propaga alla finestra e il body diventa un contenitore di scroll a sé.
La finestra non scrolla mai, niente evento `scroll` su `window`, e la timeline
virtualizzata di X resta ai primi 4 post mentre il dito scorre nel vuoto.

Prova A/B sulla stessa pagina, 24 swipe per lato:
- con la regola: 4 post, scrollY 0, nessuna richiesta di altri post;
- tolta la regola a caldo: la finestra scrolla e X carica altri post (4→10).

Cura: lo scroll si sblocca **solo** se un banner c'è stato (selettore noto
trovato o bottone «rifiuta» cliccato) e solo sull'elemento che ha davvero
`overflow-y: hidden`, mettendolo a `visible` (che mantiene la propagazione alla
finestra). Dopo la cura, stesso test: 21.000 px scorsi, pagina da 15.600 a 34.200 px.

Riguardava **ogni sito** che carica o anima allo scroll della finestra, col toggle
«Rifiuta cookie» acceso. Il costo del farbling resta un tema a parte (sopra).
