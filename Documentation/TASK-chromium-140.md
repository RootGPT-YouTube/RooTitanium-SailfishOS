# TASK Chromium 140 — aggiornare il motore a QtWebEngine 6.11.1

Stato: **INVESTIGAZIONE FATTA — da decidere se procedere** (13 ago 2026).
Nessun codice scritto, nessuna build lanciata.
Analisi rivista e confermata da un secondo revisore (Fable) prima della
registrazione; le due correzioni che ha portato sono già incorporate qui sotto.

## L'obiettivo

Passare da **QtWebEngine 6.8.3 = Chromium 122.0.6261.171** (patch di sicurezza
fino a 134.0.6998.89) a **QtWebEngine 6.11.1 = Chromium 140.0.7339.264** (patch
fino a 148.0.7778.96), riusando le patch SFOS già esistenti.
Numeri letti da `upstream/CHROMIUM_VERSION` nel clone e dal tag `v6.11.1`.

## Il vincolo che credevamo bloccante non esiste

La memoria di progetto diceva «vincolo = Qt base 6.8 LTS di piggz» e «embargo
LGPL 12 mesi». Vanno corrette entrambe:

- **L'embargo riguarda solo i rami LTS.** Qt 6.11 non è LTS (dal 6.8 l'LTS è ogni
  quarta minor: la prossima sarà 6.12), quindi i sorgenti sono pubblici da
  subito — il tag `v6.11.1` è scaricabile da GitHub senza credenziali.
  ⚠️ Il branch chum si chiama `qt6-lts-6.11.1`: è una convenzione di nome di
  Rinigus, **non** significa che 6.11 sia LTS. Non farsi confondere.
- **RooTitanium bundle-a il proprio Qt.** Sul device c'è
  `/home/rootitanium/lib/libQt6Core.so.6.8.3`, e SailfishOS 5.1.0.11 di sistema
  ha solo Qt 5.6. Non siamo legati a quello che chum spedisce.

**Il vincolo reale è un altro:** qtwebengine si compila contro qtbase della
*stessa minor*. Il `CMakeLists.txt` di v6.11.1 fa
`find_package(Qt6 ${PROJECT_VERSION} REQUIRED Core)` → pretende qtbase ≥ 6.11.1,
e nessuna patch chum rilassa il controllo. Serve quindi un **intero stack Qt
6.11.1 per SFOS, che oggi non esiste**: `sailfishos-chum/qt6-qtbase` è fermo a
6.8.4 e non ha alcun branch 6.11 (idem qtdeclarative e qtwebchannel); anche
`rinigus/tbuilder-qt6`, lo stack di build reale, pinna qtbase 6.8.3.

## Le patch: esistono, ma sono di Rinigus e non sono mai state buildate

Il branch `qt6-lts-6.11.1` di `sailfishos-chum/qt6-qtwebengine` (ultimo commit
7 giu 2026) porta le patch SFOS già adattate a 6.11.1:

- `qtwebengine-sfos-egl-validating-command-decoder.patch` — forza EGL e il
  validating GL decoder su Sailfish;
- `qtwebengine-sfos-shared-gl-texture-compositor.patch` — **ripristina il
  compositor a texture condivise di 6.8**: segnale netto che 6.11 di suo non
  rende correttamente su hybris;
- `qtwebengine-aarch64-hwcap2-bti.patch`;
- più le già note (SIOCGSTAMP, aarch64-new-stat, openh264 di sistema, pipewire,
  GL includes). Sparisce `qtwebengine-fix-arm-build.patch`.

🔴 **Quel branch non risulta mai compilato da nessuno**: `tbuilder-qt6` continua a
pinnare qtwebengine su `main` (6.8.3) e non esiste uno stack Qt 6.11 contro cui
costruirlo. È materiale preparatorio, non un risultato collaudato. Non ci sono
browser SFOS con Chromium 140 in circolazione.

**Su piggz:** non risultano suoi repo qtwebengine pubblici. Sul packaging
qtwebengine di chum c'è un solo suo commit; le patch SFOS-specifiche sono di
Rinigus. Il contributo di piggz è lo stack `home:piggz:qt6 / qt6sb2 / qt6apps`
su OBS, cioè il target contro cui compiliamo. Se emergessero patch sue non
intercettate, vanno aggiunte qui.

## Requisiti di build: verificati, siamo a posto

| | serve (Qt 6.11) | abbiamo |
|---|---|---|
| GCC | ≥ 10, C++20 | **13.4.0** nel target SailfishOS-5.1.0.11-aarch64 ✔ |
| Node.js | ≥ 20 | **22.23.1** (`nodejs-bin`) ✔ |
| CMake / Ninja / Python | 3.19 / 1.8 / 3.8 | già collaudati sulla 6.8.3 ✔ |

## Il costo

`guardia-vrm.log` copre ~21,5 ore di wall-clock (7 lug 17:46 → 8 lug 15:07), ma
**non è la misura pulita di una singola build**: dentro ci sono run fallite e
riprese incrementali, quasi tutte a `-j16`, con il passaggio a sb2 nativo `-j12`
solo alle 12:52 dell'8 luglio. Una build pulita in sb2 nativo sarebbe
verosimilmente più corta; di conseguenza **non abbiamo una stima solida** per
Chromium 140 — solo la certezza che si parla di molte ore.

A quello vanno sommati: costruzione dell'intero stack Qt 6.11.1, rebase delle 7
patch qtbase di chum da 6.8 a 6.11, ricompilazione dell'app e del bundle,
collaudo. Ordine di grandezza **una settimana**, di cui gran parte macchina — e
potrebbe essere ottimista, visto che nessuno ha mai compilato quel branch.

## Cosa NON si guadagna

Il salto **non risolve** le due segnalazioni note:
- il popup dei `<select>` HTML non selezionabile: in v6.11.1
  `render_widget_host_view_qt_delegate_quickwindow.cpp` ha la **stessa
  architettura** (QQuickWindow separata), quindi il difetto resta;
- i captcha che non si vedono: causa nostra, il toggle `noreferrer` in
  `smoke-test/main.cpp:41,75`.

Il guadagno reale è: compatibilità web (18 major di Chromium) e sicurezza
(134 → 148 di patch level).

## Piano a fasi

**Fase 0 — sonda a costo minimo (mezza giornata).** Configure-probe del branch
`qt6-lts-6.11.1`: anche solo un `cmake configure`, per far emergere subito gli
FTBFS di Chromium 140 con GCC oltre le fix già presenti. Nessuno l'ha mai
compilato: è qui che si scopre se la strada è percorribile.

**Fase 1 — inventario e qtbase.** Inventario dei moduli Qt effettivamente nel
bundle: non basta qtbase, servono anche **qtdeclarative, qtwebchannel, qtsvg,
qtquickcontrols2, qttools-static, qtsensors, qtlocation, qtpositioning**
(⚠️ Positioning e folderlistmodel non vanno MAI rimossi). Poi rebase delle 7
patch qtbase su 6.11.1 e build del solo qtbase come seconda sonda.

**Fase 2 — stack + motore.** Resto dei moduli Qt 6.11.1, poi qtwebengine 6.11.1
con le patch del branch chum.

**Fase 3 — bundle e collaudo.** L'app e l'intero bundle vanno **ricompilati**
contro 6.11 (tag ABI privato `Qt_6.11_PRIVATE_API`): non si può mischiare nulla
col bundle 6.8.3. Collaudo del nostro codice (interceptor, farbling, setter di
`QQuickWebEngineProfile`) contro tre minor di deprecazioni.

### Presidi obbligatori

- **Smoke test GL sul device subito dopo la prima build riuscita**, prima di ogni
  altro collaudo: le due patch grafiche (egl-validating, shared-gl-texture) sono
  il punto fragile dell'intera operazione.
- **Rollback pronto:** conservare l'RPM 1.4.7-1 e il bundle 6.8.3 funzionanti.
- **Riportare i fix di riproducibilità** del ramo locale qtwebengine-6.8.4
  (15b277c).
- **Monitorare Rinigus:** se integra 6.11 in `tbuilder-qt6`, gran parte del
  lavoro sullo stack lo fa lui e a noi resta solo il nostro pezzo.

## Alternativa intermedia

chum `main` è passato a **6.8.4** il 19 lug 2026 (noi siamo a 6.8.3): stesso
Chromium 122, patch di sicurezza più recenti, rischio quasi nullo. Costa comunque
un ciclo di build completo.

Cfr. [[rootitanium-chromium-update]], [[rootitanium-packaging-plan]],
[[vrm-thermal-build-limit]], [[cross-nativo-vs-emulato]].
