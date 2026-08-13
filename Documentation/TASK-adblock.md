# TASK ad-block — toggle di blocco pubblicità e tracker

Stato: **APERTA — investigazione fatta il 24 lug 2026, esecuzione rimandata**
dall'utente («la faremo un altro giorno»). Estratta a task propria il 13 ago 2026.
Nessun codice scritto.

Obiettivo: un toggle **ad-block** nelle Impostazioni, spento di default come gli
altri toggle che possono rompere i siti.

## Gli agganci esistono già: non reinventarli

1. **Blocco di rete** — `HeaderInterceptor::interceptRequest` in
   `smoke-test/main.cpp:52`: intercetta già ogni richiesta (Sec-CH-UA, Referer,
   DNT). Qt 6.8 espone `info.block(true)` → basta chiamarlo quando l'host della
   richiesta è nella blocklist. È il livello che ferma davvero pubblicità e
   tracker: risparmia banda *e* protegge la privacy.
2. **Filtro cosmetico** — riusare il pattern di `cookieBannerJs` in
   `smoke-test/test.qml` (~537): CSS `display:none` sui contenitori noti +
   `MutationObserver`, per nascondere i riquadri vuoti che restano dopo il blocco
   di rete.
   ⚠️ Lezione dai captcha: quello script gira con `runsOnSubFrames: true` e
   clicca/nasconde per selettori generici. Il filtro cosmetico dell'ad-block va
   scritto **più stretto**, o si finisce a nascondere elementi legittimi.
3. **Toggle** — pattern già rodato (`cfgFarble`, `cfgNoCookieBanner`): aggiungere
   `cfgAdblock` + `sToggle` in `settingsHtml()`, e un flag atomico nella struct
   `PrivacyFlags` di `smoke-test/main.cpp:39` (oggi `dnt`, `noReferrer`,
   `block3pCookies`), propagato con `setPrivacyFlags()` (`main.cpp:238`).
   Nota: quella firma è posizionale a tre bool — aggiungendo il quarto flag vanno
   aggiornati sia la `Q_INVOKABLE` sia la chiamata in `test.qml:385`.

## Le opzioni, con le licenze

L'app è GPLv3 e i crediti si tengono in ordine: la licenza della lista conta.

- **A — blocklist di DOMINI (consigliata per la Fase 1).** Lista di domini
  ad/tracker in un `QSet<QString>`, con walk sui domini padre e lookup O(1)
  nell'interceptor. Lista consigliata: **AdGuard DNS filter (GPLv3)**, licenza
  allineata alla nostra e conversione a lista di domini banale. Alternative:
  Peter Lowe / OISD / StevenBlack (MIT + attribuzione). Pesa 1-3 MB nel bundle,
  funziona offline, si fa in poche ore e non richiede alcun parser ABP.
- **B — EasyList (sintassi ABP) + matcher C++ minimale.** EasyList è GPLv3 +
  CC-BY-SA 3.0 (share-alike e attribuzione). Il matcher è fattibile ma pieno di
  casi limite.
- **C — motore Brave `adblock-rust` (MPL-2.0).** EasyList completo: rete,
  cosmetico ed eccezioni. In cambio introduce toolchain Rust, cross-compilazione
  aarch64 per SFOS e un livello FFI. Pesante: da tenere per una Fase 2.
- ⚠️ **uBlock Origin non è riusabile**: il suo motore è JavaScript da estensione e
  **QtWebEngine non supporta le WebExtensions**. Le sue *liste* sì (famiglia
  EasyList).

## Piano

- **Fase 1** — opzione A: blocklist di domini nell'interceptor + toggle + una
  passata cosmetica leggera. Spento di default (da confermare con l'utente).
- **Fase 2** (opzionale) — `adblock-rust`, se servirà il match per-URL con le
  eccezioni.
- **Crediti** — la lista scelta va aggiunta con la sua licenza sia in `NOTICE.md`
  sia nella sezione Crediti di `aboutHtml()` (`https://about.local/`), dove sono
  già citati Brave e Cromite; in Fase 2 anche Brave `adblock-rust` (MPL-2.0).

Cfr. [[rootitanium-adblock-task]], [[rootitanium-interceptor-farble-cookie]],
[[rootitanium-1-4]] (struttura dei crediti in About).
