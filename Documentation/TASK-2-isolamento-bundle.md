# Task #2 — isolamento del bundle dai path Qt di sistema

Aperta il 21 lug 2026. Affianca la [Task #1 (1.3) — hardening privacy/sicurezza](TASK-1.3-hardening.md):
sono indipendenti e non si contendono niente. La #1 riguarda **cosa il browser
concede alla rete**; la #2 riguarda **cosa il browser si lascia entrare in casa
dal device su cui gira**.

Stato: `qt.conf` e spec 1.2-2 **preparati**, build e collaudo **non ancora fatti**.

> ⚠️ **21 lug, sera — la diagnosi qui sotto è SMENTITA come causa della fascia nera.**
> Sul device di uno dei due segnalanti (che aveva disinstallato Qt Runner)
> `/usr/lib64/qt6/plugins/` **non esiste**, eppure il sintomo c'è. Le dipendenze
> erano quindi state rimosse davvero — contrariamente a quanto assunto sotto — e
> senza quei file il meccanismo descritto non può innescarsi.
>
> Cosa resta valido di questa task: **`qt.conf` come irrobustimento**, non come
> cura. Il difetto strutturale (path di sistema aperti perché `QT_PLUGIN_PATH` è
> additivo e il prefisso compilato è `/usr`) è reale e va chiuso comunque, ma non
> è ciò che produce la fascia nera. La caccia a quella si sposta sul log.
>
> Nota di metodo: la correlazione con Qt Runner è più debole di come è raccontata
> sotto. Ho chiesto **io** di Qt Runner a entrambi, e chi lo installa ha Chum
> abilitato e molto software di comunità: non esiste un gruppo di controllo di
> utenti *senza* Qt Runner di cui si sappia che non hanno il bug.

## Il sintomo che l'ha aperta

Xperia X10 III / SFOS 5.1.0.11, RPM 1.2-1: **circa un terzo inferiore dello
schermo resta nero in permanenza**, e quando si apre la tastiera
QtVirtualKeyboard dell'app è esattamente quella fascia a essere occupata. Cioè
l'area utile della finestra è `schermo − altezza tastiera` **sempre**, non solo a
tastiera aperta. Non riproducibile sul device di sviluppo, stesso modello e
stessa versione di SFOS.

Escluso dagli utenti stessi: OKBoard e homescreen automatico (disabilitarli non
cambia nulla). Coerente — OKBoard è un plugin di `maliit-server` e non tocca il
nostro processo.

## La correlazione

**Due utenti su due che hanno il bug hanno installato Qt Runner** (uno lo ha poi
rimosso, e il sintomo è rimasto). Nessuno senza Qt Runner lo segnala.

La rimozione non assolve: `rpm -e qt-runner` **non rimuove le dipendenze**.
`qt-runner-qt6` richiede `qt6-qtwayland`, `qt6-sfos-maliit-platforminputcontext`
e `kf6-qqc2-breeze-style`, che restano installate in `/usr/lib64/qt6/plugins`.
Non è il programma qt-runner a dare fastidio — quello non gira nemmeno: è **il
Qt6 di sistema che si porta dietro**.

## La causa

```
$ strings scratch/webengine-bundle/lib/libQt6Core.so.6.8.3 | grep qt_prfxpath
qt_prfxpath=/usr
```

Il Qt6 del bundle è compilato con prefisso `/usr`, e **`QT_PLUGIN_PATH` è
additivo, non sostitutivo** (`rootitanium-launch.c:37`, idem in
`smoke-test/run.sh`). Il processo cerca quindi i plugin nel bundle **e anche** in
`/usr/lib64/qt6/plugins`: inesistente su un device pulito, popolato su un device
toccato da Qt Runner.

Dove il bundle ha un plugin omonimo, vince il bundle (il suo path viene prima).
Dove **non** ce l'ha, entra quello di sistema, compilato contro un altro Qt. Il
caso concreto: `plugins/platforminputcontexts/` del bundle contiene solo
`libqtvirtualkeyboardplugin.so`, mentre quei device hanno lì dentro anche
`libmaliitplatforminputcontextplugin.so`. Stesso discorso per eventuali
`wayland-shell-integration` che noi non spediamo — ed è proprio la shell
integration a negoziare la geometria della finestra.

## La cura (preparata)

1. **`smoke-test/qt.conf`**, da tenere accanto all'eseguibile (`/home/rootitanium`
   sul device, `scratch/webengine-bundle/` in sviluppo). I path relativi in
   `qt.conf` sono risolti rispetto alla directory dell'eseguibile e
   **sostituiscono** quelli compilati:

   ```ini
   [Paths]
   Prefix = .
   Plugins = plugins
   Imports = qml
   Qml2Imports = qml
   Libraries = lib
   LibraryExecutables = libexec
   ```

2. **`harbour-rootitanium.spec` → 1.2-2**: il `qt.conf` viene *generato* in
   `%install` invece di essere preso dallo staging, così vale anche per staging
   assemblati prima di questa modifica.

3. **Commit 8c1caf0** (già in repo, mai rilasciato in RPM): la finestra impone la
   propria geometria da `Screen` invece di subirla dal compositor, e `rtGeomCheck()`
   scrive in `/tmp/rootitanium.log` se viene rimpicciolita lo stesso.

I punti 1 e 3 curano **strati diversi** dello stesso sintomo: il 3 impedisce alla
finestra di subire la geometria, l'1 toglie di mezzo la causa che gliela impone.
Il punto 1 è anche l'unica difesa strutturale: domani un altro pacchetto Chum
mette altra roba in `/usr/lib64/qt6` e senza `qt.conf` si ricomincia.

## Verifica — ESEGUITA, esito negativo

```
[defaultuser@Hera ~]$ ls /usr/lib64/qt6/plugins/platforminputcontexts/ \
                         /usr/lib64/qt6/plugins/wayland-shell-integration/
ls: /usr/lib64/qt6/plugins/platforminputcontexts/: No such file or directory
ls: /usr/lib64/qt6/plugins/wayland-shell-integration/: No such file or directory
```

Device di Steve (Qt Runner disinstallato), che **ha il sintomo**. Le directory non
esistono → nessun plugin di sistema può entrare nel nostro processo → la causa è
un'altra. Vedi il riquadro in cima.

Resta da guardare, per la fascia nera (task che ora prosegue altrove):

```
systemctl --user show-environment | grep -i -E 'qt|qml'
rpm -qa | grep -iE 'qt6|maliit|opt-qt5|breeze'
```

più — soprattutto — **`/tmp/rootitanium.log`**, che il `run.sh` scrive sempre e che
con `qt.qpa*=true` contiene già le geometrie reali della finestra anche in 1.2-1.
Era il dato da chiedere per primo.

## Da fare dopo il collaudo

- Verificare che `qt.conf` non tolga nulla che oggi funziona: il bundle è
  self-contained per costruzione, e su device puliti `/usr/lib64/qt6` non esiste,
  quindi la perdita attesa è nulla — ma va visto sul device (lancio da icona, non
  solo da ssh; vedi trappole di collaudo).
- Valutare se il prossimo repack di qtwebengine debba compilare Qt con un
  `-prefix` dedicato invece di `/usr`: risolverebbe alla radice, ma costa una
  ricompilazione completa e `qt.conf` ottiene lo stesso risultato a costo zero.

## Fuori perimetro, ma emerso qui

Il plugin **Maliit input-context per Qt6 esiste** (`qt6-sfos-maliit-platforminputcontext`,
Chum) e parla con `maliit-server` **via DBus**, non via il protocollo Wayland
`text-input`. L'assunzione scritta in `smoke-test/run.sh:34` («Maliit nativo
SCARTATO: lipstick non espone wayland text-input, plugin maliit e' Qt5-only») è
quindi **sbagliata su entrambi i punti**. In prospettiva si potrebbe sostituire
QtVirtualKeyboard con la tastiera SFOS nativa — quindi anche OKBoard. Incognite:
ABI del plugin di sistema contro il Qt del bundle (meglio ricompilarlo: è LGPLv2 e
un solo `.so`) e la rotazione landscape, che noi facciamo ruotando `appRoot` in
QML e che Maliit non vedrebbe. **Non è parte di questa task**: qui l'obiettivo è
il contrario, tenere fuori i plugin di sistema.
