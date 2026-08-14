# Runbook — aggiornamento qt6-qtwebengine 6.8.3 → 6.8.4

Prova generale dell'aggiornamento del motore. **Chromium resta 122**: cambia solo
il livello di backport CVE (6.8.4 è la release di luglio 2025, pubblicata in LGPL
solo a luglio 2026, dopo i 12 mesi di embargo LTS). Il salto vero — Chromium 134
con 6.8.8 — sarà possibile quando Qt ne pubblicherà il tag LGPL, atteso nel 2027:
lo scopo di questo giro è **arrivarci con la procedura già rodata**.

## Stato: esecuzione avviata il 14 ago 2026 (richiesta dell'utente)

Il guadagno è più grande di quanto questo runbook prevedeva. `CHROMIUM_VERSION`
del tag `v6.8.4-lts-lgpl` dice:

| | Chromium base | patch di sicurezza fino a |
|---|---|---|
| 6.8.3 (in uso) | 122.0.6261.171 | **134.0.6998.89** |
| 6.8.4 (questo giro) | 122.0.6261.171 | **138.0.7204.96** |

Quindi non è solo una prova di procedura: sono **quattro major di backport CVE**
in più, a Chromium invariato e rischio quasi nullo. `v6.8.4-lts-lgpl` è anche
l'**ultimo** tag LGPL pubblicato del ramo (nessun 6.8.5+ su code.qt.io alla data),
cioè il massimo livello di sicurezza raggiungibile senza cambiare Chromium.

Passi già eseguiti — vedi gli script in `scratch/` e i rispettivi `.log`:

1. **Clone** `qtwebengine-6.8.4/` — fatto **shallow** (`--depth 1` sul tag e sui
   submodule): servono i file per il tarball, non la history. 4,8 GB e pochi
   minuti invece di ore. `node_modules` di devtools-frontend: **presente**.
2. **Tarball** `SOURCES/qt6-qtwebengine-6.8.4.tar` (3,77 GB, 267.870 file sotto
   `chromium/`), struttura `qt6-qtwebengine-6.8.4/upstream/…` come attesa.
3. **Spec** portato a `Version: 6.8.4` / `%global qt_version 6.8.4`.
4. **`%prep`: PASSATO (exit 0).** Le 5 patch RooTitanium `0300`-`0304` applicano
   **pulite, zero fuzz** — nessun file toccato da upstream, nemmeno quello che il
   runbook si aspettava cambiato (0301). Le patch chum applicano con offset e
   fuzz fino a 2, assorbito dal `--fuzz=2` che rpmbuild usa di default: il "gate
   senza fuzz" **non** è rispettato dalle patch chum, ma non blocca. Se un domani
   si volesse fuzz 0, va rigenerata soprattutto `1001` (fuzz 2 su
   `qt_overrides.cc`).
5. **Configure** in corso.

Due correzioni agli script, entrambe necessarie per non ripetere lavoro a mano:

- `scripts/build-con-guardia.sh` (ex `build-j16-…`, rinominato: girava a -j12 da luglio) aveva la dir di build **cablata su 6.8.3**;
  ora la versione si legge dallo spec (`VER=` per forzarla).
- `scripts/configure-only.sh` non passava a `cmake` **alcun path sorgente**: così
  com'era non poteva partire. Il configure è **in-place** (come il tree 6.8.3:
  `CMAKE_HOME_DIRECTORY` = la dir stessa), quindi ora finisce con `"${SRCDIR:-.}"`
  e si lancia da `BUILD/qt6-qtwebengine-<ver>/upstream`.

Path di lavoro: `<repo>/` (scelta
dell'utente, non si accorcia).

## 0. Prerequisiti

- Engine docker `sailfish-sdk-build-engine_RootGPT` Up, target `SailfishOS-5.1.0.11-aarch64`.
- `$HOME/qemu-aarch64-10` presente (qemu-aarch64-static ≥10 dell'host).
- Guardia VRM: build a **12 core**, di giorno, presidiata ([[vrm-thermal-build-limit]]).
- Spazio: il build tree 6.8.3 occupa decine di GB. Decidere se **tenerlo** (utile
  come riferimento e per `build-launcher.sh`, che ci prende gli header di
  QtWebEngine) o rimuoverlo prima di partire.

## 1. Sorgente 6.8.4

Lo spec parte da un tarball `qt6-qtwebengine-<ver>.tar` in `build/SOURCES/`
(3,6 GB per la 6.8.3). Per la 6.8.4 non esiste ancora un tarball chum: va
prodotto dal tag LGPL.

```bash
git clone https://code.qt.io/qt/qtwebengine.git qtwebengine-6.8.4
cd qtwebengine-6.8.4 && git checkout v6.8.4-lts-lgpl
git submodule update --init --recursive          # src/3rdparty = qtwebengine-chromium, ore di download
```

Poi impacchettare con la **stessa struttura** che lo spec si aspetta
(`qt6-qtwebengine-6.8.4/upstream/...`, vedi `%setup -n %{name}-%{version}/upstream`).

⚠️ Verificare che nel tarball finisca anche
`third_party/devtools-frontend/src/node_modules/` (la patch 0303 tocca un file lì
dentro; nella 6.8.3 c'era).

## 2. Spec

In `rpm/qt6-qtwebengine.spec`: `Version: 6.8.4` e `%global qt_version 6.8.4`.
Le patch RooTitanium (`Patch300`-`Patch304`) sono già cablate — vedi
`patches/README.md`.

Copiare le patch dove rpmbuild le cerca:

```bash
cp packaging/qt6-qtwebengine-sfos/patches/0*.patch packaging/qt6-qtwebengine-sfos/build/SOURCES/
```

**Gate: `%prep` deve passare senza fuzz.** Se una patch fallisce, è un segnale
utile — significa che upstream ha toccato quel file (atteso per 0301: quel file
ha ricevuto un backport di sicurezza nell'agosto 2025). Riapplicare a mano,
rigenerare la patch, aggiornare la tabella nel README.

## 3. Configure

`scripts/configure-only.sh` (esistente). Al termine deve esistere
`upstream/src/core/RelWithDebInfo/aarch64/args.gn`.

```bash
VER=6.8.4 packaging/qt6-qtwebengine-sfos/scripts/apply-build-fixes.sh gn
```

Verifica che i flag siano passati davvero:

```bash
# dentro l'engine, in .../aarch64
ninja build.ninja && grep -E 'sandbox|pointer_compression' gen/v8/v8_features.json   # tutti false
```

## 4. Build

**Un comando solo**, che porta con sé guardia termica e ripresa dai blocchi noti:

```bash
packaging/qt6-qtwebengine-sfos/scripts/build-con-ripresa.sh
```

Riconosce il sintomo nel log, applica il rimedio da `apply-build-fixes.sh` e
riprende (la build è incrementale). Si ferma e chiama una persona **solo** su un
errore non riconosciuto. Sotto resta il modo manuale, se serve pilotare a mano:

```bash
VER=6.8.4 packaging/qt6-qtwebengine-sfos/scripts/apply-build-fixes.sh ninja
packaging/qt6-qtwebengine-sfos/scripts/build-con-guardia.sh    # 12 core + guardia VRM
```

⚠️ `toolchain.ninja` **non esiste finché la build non ha fatto il `gn gen`**: il
passo `ninja` fallisce se lanciato subito dopo il configure. Il primo giro di
build lo genera; da lì in poi il passo va rilanciato dopo **ogni** gn-regen — è
proprio quello che fa il ciclo di ripresa.

Punti in cui la build si può fermare, in ordine storico di comparsa:

| Sintomo | Rimedio | automatico |
|---|---|---|
| `cc1plus: fatal error: …/.rcc/qmlcache/…cpp: Permission denied` | `apply-build-fixes.sh qmlcache` (i .cpp di qmlcachegen nascono a 000, vedi `patches/README.md` §C) | ✔ |
| `v8_context_snapshot_generator`, qemu signal 5 (~92%) | `apply-build-fixes.sh snapshot`, poi riprendi | ✔ |
| `ninja: error: WriteFile(...): File name too long` | è tornato un gn-regen: rilancia `apply-build-fixes.sh ninja` | ✔ |
| `final link failed: memory exhausted` | idem: il flag di link si perde se cmake rigenera `build.ninja` | ✔ |
| crash node sotto qemu in fasi devtools | dovrebbe essere coperto da 0303/0304; se è un file nuovo, stesso schema (in-process / sequenziale) | ✗ |

## 5. Verifica e pacchetto

1. `upstream/lib64/`: `libQt6WebEngineCore.so` ~1,3 GB, aarch64 valido (`file`).
2. `cmake --install` in un DESTDIR di staging (via sb2), poi repack RPM come per
   la 6.8.3 (`scratch/rt-repack.spec`).
3. Rigenerare il bundle dell'app: sostituire le lib in `scratch/webengine-bundle/`
   e in `scratch/pkg-staging/bundle/`, poi **ricompilare `webengine-smoke`**
   (`scratch/build-launcher.sh`) contro i nuovi header.
4. Test sul device prima di rilasciare: avvio, render accelerato
   (`chrome://gpu`), video, tastiera, file picker, link da altra app.

## 6. Criterio di riuscita

L'obiettivo non è la 6.8.4 in sé: è che al prossimo giro (6.8.8, Chromium 134)
il percorso sia **`%prep` pulito → tre invocazioni dello script → build**. Ogni
fix che qui si scopre ancora "a mano" va convertita in patch o in un passo dello
script prima di chiudere il lavoro.
