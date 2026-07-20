# Runbook — aggiornamento qt6-qtwebengine 6.8.3 → 6.8.4

Prova generale dell'aggiornamento del motore. **Chromium resta 122**: cambia solo
il livello di backport CVE (6.8.4 è la release di luglio 2025, pubblicata in LGPL
solo a luglio 2026, dopo i 12 mesi di embargo LTS). Il salto vero — Chromium 134
con 6.8.8 — sarà possibile quando Qt ne pubblicherà il tag LGPL, atteso nel 2027:
lo scopo di questo giro è **arrivarci con la procedura già rodata**.

Path di lavoro: `/home/RootGPT/Developing/SailfishOS/RooTitanium/` (scelta
dell'utente, non si accorcia).

## 0. Prerequisiti

- Engine docker `sailfish-sdk-build-engine_RootGPT` Up, target `SailfishOS-5.1.0.11-aarch64`.
- `/home/RootGPT/qemu-aarch64-10` presente (qemu-aarch64-static ≥10 dell'host).
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

```bash
VER=6.8.4 packaging/qt6-qtwebengine-sfos/scripts/apply-build-fixes.sh ninja
packaging/qt6-qtwebengine-sfos/scripts/build-j16-con-guardia.sh    # 12 core + guardia VRM
```

Punti in cui la build si può fermare, in ordine storico di comparsa:

| Sintomo | Rimedio |
|---|---|
| `v8_context_snapshot_generator`, qemu signal 5 (~92%) | `apply-build-fixes.sh snapshot`, poi riprendi |
| `ninja: error: WriteFile(...): File name too long` | è tornato un gn-regen: rilancia `apply-build-fixes.sh ninja` |
| `final link failed: memory exhausted` | idem: il flag di link si perde se cmake rigenera `build.ninja` |
| crash node sotto qemu in fasi devtools | dovrebbe essere coperto da 0303/0304; se è un file nuovo, stesso schema (in-process / sequenziale) |
| qualcosa su `qmlcachegen` con permessi | incognita nota, vedi `patches/README.md` §C |

Dopo **ogni** `gn gen` o reconfigure: rilanciare il passo `ninja`.

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
