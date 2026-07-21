# Task 1.3 — hardening privacy/sicurezza a costo prestazionale zero

Piano di lavoro — **ESEGUITO il 21 lug 2026** (commit 6212597, rilasciato in RPM
1.3-1). Esiti e scelte prese in implementazione, rispetto a quanto previsto qui:

| § | Esito |
|---|---|
| A flag | fatto; verificato sul device che le API siano `undefined` |
| B DNT/Sec-GPC | fatto; erano solo JS, ora sono header veri |
| B Referer | fatto; **cross-site deciso sulle ultime due etichette dell'host**, non host-contro-host, altrimenti `www.sito.it` → `cdn.sito.it` perdeva il Referer |
| C cookie 3P | filtro installato, **non verificato end-to-end** (il test via httpbin fallisce per CORS in entrambe le direzioni: non distingue acceso da spento) |
| D override JS | fatto ma **agganciato al toggle farbling**, non sempre attivo come proponeva il piano: l'identità JS è calibrata per il login di X e non va cambiata di default a scatola chiusa |
| E tre toggle | fatti, spenti di default; il terzo passa da `startup-flags.conf` letto da `main.cpp`, non dalla kv SQLite (il nome del file kv è un hash: sproporzionato per un booleano) |

Verifiche eseguite sul device via CDP: cross-site senza `Referer`, same-site col
`Referer` intatto, prova di controllo a toggle spento che lo fa riapparire,
`DNT: 1` + `Sec-GPC: 1` presenti, `Sec-CH-UA` ancora "Google Chrome" (login X non
toccato), e `ThirdPartyStoragePartitioning` sulla cmdline del renderer dopo il
riavvio.

Difetto trovato collaudando: il router di `settings.local` accettava solo chiavi
`[a-z]+`, quindi `cookies3p` e `storage3p` venivano ignorate **in silenzio**.
Corretto in `[a-z0-9]+`.

---

Piano originale (preparato il 20 lug 2026).

Criterio di ammissione scelto dall'utente: si accetta **solo** ciò che non tocca
le prestazioni. Sono già state scartate, per questo motivo, misure pur valide:
`--site-per-process` + StrictOriginIsolation (RAM), partizionamento della cache
per network isolation key (cache hit rate), `--js-flags=--jitless` (CPU),
il farbling di canvas/audio/timing (overhead per chiamata, resta il toggle
esistente `cfgFarble`), e gli hardening di compilazione `-fstack-protector-strong`
/ `-ftrivial-auto-var-init=zero` / `-fwrapv` (1-3% CPU + rebuild).

Ispirazione: l'elenco patch di Cromite. **Nessuna patch di terzi viene applicata**:
tutto è ottenuto con flag Chromium, API Qt pubbliche e codice nostro, quindi non
cambia nulla sul piano delle licenze (restiamo GPL-3.0+ app / LGPLv3 engine).

## A. Flag nel launcher (nessun costo: sono API che non girano)

```
--disable-features=WebBluetooth,WebUSB,WebNFC,IdleDetection,FedCm,WebOTP
--force-webrtc-ip-handling-policy=default_public_interface_only
--enable-features=BlockInsecurePrivateNetworkRequests
```

Tutte verificate presenti in Chromium 122 (`content_features.cc`,
`content_switches.cc`, `blink/common/features.cc`). `DeviceAttributes` e
`DigitalGoods` non esistono ancora in 122: niente da spegnere.

⚠️ **Tre posti da aggiornare**, sempre: `smoke-test/run.sh` (dev), il `run.sh`
release nello staging/device, e `rootitanium-launch.c` **ricompilato** — vedi
[[collaudo-app-device-trappole]] §7. Patchare solo il `.c` senza ricompilare
produce un bug invisibile dai lanci da icona.

## B. Interceptor HTTP (`HeaderInterceptor` in `main.cpp`, già esistente)

| Cosa | Note |
|---|---|
| `DNT: 1` + `Sec-GPC: 1` | **Oggi il toggle "Non tenere traccia" (`cfgDnt`) è solo JS**: imposta `navigator.doNotTrack`/`globalPrivacyControl` ma NON manda alcun header. Qui diventa un segnale vero. Il toggle resta quello, il comportamento migliora. |
| `Referer` azzerato sulle navigazioni cross-origin | Confronto `requestUrl()` con `firstPartyUrl()`; entrambi disponibili nell'API 6.8.3. |
| `Authorization` rimosso sui redirect cross-origin | Stessa logica. |

### Perché il referrer conta (motivazione dell'utente, 20 lug)

Il valore NON è nascondere quale pagina si stava leggendo: quello lo copre già la
policy di default di Chromium 122, `strict-origin-when-cross-origin` (verificato
in `blink/common/loader/referrer_utils.cc`), che cross-origin manda solo l'origine.

Il valore è un altro: **ogni terza parte incorporata in un sito riceve
`Referer: https://quel-sito/`** in ogni richiesta di pixel, font o script. Un
tracker apprende cosi' che l'utente sta su quel sito **anche con i cookie di terze
parti bloccati**. Per chi non vuole far sapere che frequenta determinati siti,
questo e' il canale che conta — non e' una rifinitura.

Conseguenza pratica: il toggle ha senso **in entrambi gli esiti** del test qui
sotto; cambia solo l'implementazione.

### ✅ Incognita SCIOLTA — test eseguito il 20 lug 2026

**Esito: funzionano entrambe le vie. Si adotta l'interceptor.**

Metodo: due origini servite dal device stesso (`http://localhost:8099` = sito A,
`http://127.0.0.1:8100` = terza parte B — host diversi, quindi `Sec-Fetch-Site:
cross-site` confermato nei log). A carica un pixel da B (sottorisorsa) e poi ci
naviga (navigazione). B registra il `Referer` ricevuto. Il browser è stato
pilotato da remoto con `lca-tool --scheme --triggerdefault`, cioè il percorso
link della 1.2 — nessun tap sullo schermo.

| # | Via | Caso | Referer ricevuto | Esito |
|---|---|---|---|---|
| — | *baseline* (binario 1.2-1) | sottorisorsa | `http://localhost:8099/` | riferimento |
| — | *baseline* (binario 1.2-1) | navigazione | `http://localhost:8099/` | riferimento |
| 1 | interceptor | navigazione | *assente* | ✅ |
| 2 | interceptor | sottorisorsa | *assente* | ✅ |
| 3 | meta no-referrer | sottorisorsa | *assente* | ✅ |
| 4 | meta no-referrer | navigazione | *assente* | ✅ |

`setHttpHeader("Referer", QByteArray())` **azzera davvero** l'header: Chromium non
lo reimposta a valle. Prova di controllo eseguita (stesso URL, stesso test, solo
il binario cambia) per escludere che la differenza venisse dal cambio di host.

Conferme secondarie: il baseline manda **solo l'origine**, non l'URL completo →
`strict-origin-when-cross-origin` è davvero il default; le richieste same-host
mantengono il Referer, quindi il criterio non tocca la navigazione interna ai siti.

**Scelta: interceptor** — non tocca il DOM, la pagina non può sovrascriverlo con
una propria policy, e vale anche per le richieste che non nascono dal parsing HTML.
Il meta resta documentato come ripiego, non serve implementarlo.

⚠️ **Da decidere in implementazione:** il test confrontava `firstPartyUrl().host()`
con `requestUrl().host()`. Così `www.sito.it` → `cdn.sito.it` risulta "cross" e
perde il Referer, il che può rompere CDN dello stesso proprietario. Qt non espone
il registrable domain (eTLD+1), quindi o si accetta questo comportamento (più
rigoroso, coerente con l'intento del toggle) o si scrive un confronto approssimato
sul suffisso. Da valutare col toggle acceso su siti reali.

### Nota storica: come si era posto il problema

`QWebEngineUrlRequestInfo` espone `setHttpHeader()` ma **non** un
`removeHttpHeader()`: va verificato empiricamente se `setHttpHeader("Referer", "")`
azzera davvero l'header o se Chromium lo reimposta a valle. Gli switch
`--no-referrers` e `--reduced-referrer-granularity` **non esistono più in 122**
(verificato).

Ripiego: `<meta name="referrer" content="no-referrer">` iniettata a
DocumentCreation. Imposta la policy **del documento**, che governa tutte le
richieste generate da quel documento — quindi in teoria copre sia le sottorisorse
verso terze parti sia le navigazioni in uscita. Da confermare sul campo (una
pagina può dichiarare una propria policy).

Il test deve misurare **quattro** casi, non uno (endpoint tipo `httpbin.org/headers`
o un server locale che rimanda gli header ricevuti):

| # | Via | Caso | Esito atteso |
|---|---|---|---|
| 1 | interceptor | navigazione cross-origin | nessun `Referer` |
| 2 | interceptor | sottorisorsa verso terza parte | nessun `Referer` ← **il caso che conta** |
| 3 | meta no-referrer | sottorisorsa verso terza parte | nessun `Referer` |
| 4 | meta no-referrer | navigazione in uscita | nessun `Referer` |

Se 1-2 passano si usa l'interceptor (piu' pulito, non tocca il DOM); altrimenti si
adotta il ripiego per i casi che 3-4 dimostrano coperti, documentando nella UI del
toggle cosa resta scoperto.

## C. API Qt — blocco cookie di terze parti

`QQuickWebEngineProfile::cookieStore()` è pubblico e `QWebEngineCookieStore::FilterRequest`
espone `thirdParty` (verificato in `src/core/api/qwebenginecookiestore.h`):

```cpp
p->cookieStore()->setCookieFilter([](const QWebEngineCookieStore::FilterRequest &r) {
    return !r.thirdParty;          // solo quando il toggle è acceso
});
```

Aggancio naturale: `NativeHelper::setupProfile()`, che già riceve i due profili
dal QML. Serve un modo per rileggere il filtro quando il toggle cambia (il filtro
è una lambda: catturare un puntatore allo stato, oppure richiamare `setCookieFilter`
al cambio).

## D. Override JS statici (una sola volta per documento, costo trascurabile)

Nello stesso schema di `dntJs`/`farbleJs` in `buildScripts()`:
`navigator.getBattery`, `navigator.connection`, `deviceMemory`,
`hardwareConcurrency`, enumerazione `plugins`, `speechSynthesis.getVoices`.

Da decidere in implementazione: se agganciarli al toggle farbling esistente o
tenerli sempre attivi (sono sostituzioni statiche, non rumore: non hanno il costo
del farbling e non rompono nulla di noto → propendo per sempre attivi).

## E. Toggle in Impostazioni — **tutti e tre spenti di default**

Decisione dell'utente (20 lug): le tre misure che possono rompere siti nascono
**disattivate**. Sono **tre toggle indipendenti**: l'utente accende o spegne
ciascuno per conto suo, in qualsiasi combinazione, e ogni scelta persiste tra le
sessioni (nessun toggle "master", nessuna dipendenza fra i tre).

| Toggle | Chiave kv | Default | Effetto immediato? |
|---|---|---|---|
| Blocca cookie di terze parti | `set_3pcookies` | `0` | ✅ sì (`setCookieFilter` a runtime) |
| Non inviare il referrer ai siti esterni | `set_noreferrer` | `0` | ✅ sì (l'interceptor legge lo stato a ogni richiesta) |
| Isola lo storage di terze parti | `set_3pstorage` | `0` | ❌ **no: richiede riavvio dell'app** |

⚠️ Il terzo è un **flag di Chromium** (`--enable-features=ThirdPartyStoragePartitioning`),
e i flag si leggono solo all'avvio del processo. Il toggle quindi salva la
preferenza e il launcher la applica al lancio successivo: la UI deve dirlo
esplicitamente ("attivo al prossimo avvio"), altrimenti sembra rotto. Implica che
il launcher ELF debba **leggere la kv** (SQLite in `~/.local/share/...`) prima di
comporre `QTWEBENGINE_CHROMIUM_FLAGS` — è la parte di lavoro meno banale di tutta
la 1.3, da valutare: alternativa più semplice è che sia `main.cpp` a comporre i
flag prima di `QtWebEngineQuick::initialize()`.

Persistenza: `loadCfg()`/`kvSet` come tutti gli altri `cfg*` (`set_*`), e la voce
in `sToggle(...)` nella pagina Impostazioni.

## Ordine di lavoro proposto

1. Test dell'incognita Referer (B) — decide se B è fattibile per intero.
2. A: flag nel launcher (i tre posti) + verifica che nulla si rompa.
3. C + toggle cookie 3P.
4. D: override JS statici.
5. E: toggle referrer e storage, con la questione "flag al prossimo avvio".
6. Collaudo sul device su siti reali, **incluso il login X** (era costato fatica:
   interceptor Sec-CH-UA + cooldown, vedi [[rootitanium-interceptor-farble-cookie]])
   e i siti con login federato "accedi con Google/Facebook" per il cookie filter.
7. Rilascio 1.3 con `/rilascia_rootitanium`.
