# Task 1.3 — hardening privacy/sicurezza a costo prestazionale zero

Piano di lavoro, **non ancora implementato** (preparato il 20 lug 2026).

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

🔬 **Incognita da sciogliere per prima** (test da ~10 minuti, prima di scrivere il
resto): `QWebEngineUrlRequestInfo` espone `setHttpHeader()` ma **non** un
`removeHttpHeader()`. Va verificato empiricamente se `setHttpHeader("Referer", "")`
azzera davvero l'header o se Chromium lo reimposta a valle. Verifica: caricare
`httpbin.org/headers` (o un endpoint locale) da un link cross-origin e leggere
cosa è arrivato. Gli switch `--no-referrers` e `--reduced-referrer-granularity`
**non esistono più in 122** (verificato): se il test fallisce, il ripiego è una
`<meta name="referrer" content="no-referrer">` iniettata a DocumentCreation, che
però copre le sottorisorse e non la richiesta di navigazione iniziale.

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
