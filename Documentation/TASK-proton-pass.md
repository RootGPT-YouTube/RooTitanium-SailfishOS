# TASK Proton Pass — compilazione automatica di account e password

Stato: **APERTA — progetto grande per il futuro** (deciso dall'utente il 29 ott 2026).
Solo analisi, nessun codice scritto e nessuna sonda eseguita.

Obiettivo: RooTitanium compila account e password nei moduli di login prendendoli da
**Proton Pass**, senza custodire credenziali proprie (la funzione Password interna è
stata costruita e poi RIMOSSA a luglio: la sicurezza resta al gestore esterno).

## Strade scartate

- **Estensione Proton Pass per Chromium**: QtWebEngine non carica estensioni.
- **App Android via AppSupport**: l'autofill Android non attraversa le app native SFOS.
- **API Proton diretta**: SRP + 2FA + decifratura PGP del vault da rifare noi =
  settimane di lavoro e codice crittografico ad alto rischio. No.

## Strada scelta: `pass-cli` ufficiale

Proton distribuisce `pass-cli` (riga di comando, anche Linux ARM64 secondo Homebrew/nixpkgs).
Comandi utili: `pass-cli item view --vault-name … --item-title … --output json`,
`--field` per un solo campo, URI `pass://SHARE_ID/ITEM_ID`.
⚠️ Dalla 2.1.0 `item view` richiede la variabile `PROTON_PASS_AGENT_REASON`.

### Pezzi da costruire

1. **Rilevamento form di login**: user script (gemello DocumentReady, vedi lezione
   Chromium 140) che segnala `input[type=password]` a QML via `console.log`.
2. **Ponte C++**: `QProcess` → `pass-cli`, filtro delle voci per dominio della pagina,
   risultato in JSON verso QML. Mai le password nei log (`/tmp/rootitanium.log`).
3. **Foglio QML** di scelta account → compilazione con `runJavaScript`
   (setter nativo `HTMLInputElement.prototype.value` + eventi `input`/`change`,
   altrimenti React & co. non vedono i valori).
4. **Regole di sicurezza**: solo frame principale, solo se l'host combacia con l'URL
   della voce (anti-phishing), toggle SPENTO di default, nessuna cache su disco.
5. (fase 2, più delicata) salvataggio di credenziali nuove dentro Proton Pass.

Stima fase 1: 2-4 giorni, **se la sonda passa**.

## Cancello iniziale: sonda sul POCO (~30 min)

In `/home/debugging/AAAA-MM-GG-proton-pass/` (mai nella home):
- il binario ARM64 parte? (glibc di SFOS forse troppo vecchia; armv7hl probabilmente
  non esiste → funzione solo aarch64);
- il login riesce? (lo fa l'UTENTE: le credenziali non le tocchiamo);
- la sessione sopravvive al riavvio? (su Linux usa il Secret Service, che su SFOS
  potrebbe mancare → login a ogni avvio = esperienza da valutare);
- tempi di risposta di `item list`/`item view` sul POCO.

Se un punto fallisce senza rimedio, la task si chiude qui.

## Rischi

- `pass-cli` è giovane e cambia interfaccia: fissare una versione, ricontrollarla a ogni
  aggiornamento.
- Repo PUBBLICO: nessun dato di prova reale nei commit.
