# harbour-rootitanium — pacchetto RPM self-contained per SailfishOS

Impacchetta il bundle Qt6 WebEngine (già compilato, vedi `smoke-test/` e la
build di `qt6-qtwebengine-sfos/`) in un RPM installabile via Storeman/pkcon.

## Layout del pacchetto
- **`/home/rootitanium/`** — il bundle self-contained (~329 MB dopo il trim: libs
  Qt6+WebEngine strippate, qml, resources, locales EN+IT, `webengine-smoke`,
  `run.sh`). Va su `/home` perché il rootfs SFOS è troppo pieno per ~330 MB.
- **`/usr/bin/harbour-rootitanium`** — launcher ELF (`rootitanium-launch.c`).
  sailjail rifiuta gli script come Exec e pretende il binario in `/usr/bin`; il
  launcher imposta l'ambiente del bundle ed esegue `/home/rootitanium/webengine-smoke`.
- **`/usr/share/applications/harbour-rootitanium.desktop`** — con sezione
  `[X-Sailjail] Sandboxing=Disabled`: l'app gira FUORI dal sandbox firejail
  (le servono `/home/rootitanium`, le lib hybris di sistema e Chromium `--no-sandbox`).
- **`/usr/share/icons/hicolor/{86,108,128,172}/apps/harbour-rootitanium.png`**.

## Perché queste scelte (SFOS sailjail)
Lipstick lancia le app via `invoker --type=<T> -- sailjail -p <profile> -- <bin>`.
sailjail: (1) accetta solo ELF, (2) solo da `/usr/bin`, (3) sandboxa sempre in
firejail (che nasconderebbe `/home/rootitanium`). Con `Sandboxing=Disabled`
lipstick salta sailjail e lancia `invoker --type=generic -- /usr/bin/harbour-rootitanium`.

## Build
Serve il SailfishOS SDK (build engine + target aarch64) e uno *staging* con:
```
<staging>/bundle/                     il bundle trimmato (payload)
<staging>/rootitanium-launch          launcher compilato (vedi sotto)
<staging>/harbour-rootitanium.desktop
<staging>/icons/{86,108,128,172}.png
<staging>/harbour-rootitanium.spec
```
Compilazione del launcher (dentro il build engine, target aarch64):
```
sb2 -t <target-aarch64> gcc -O2 -o rootitanium-launch rootitanium-launch.c
```
Build dell'RPM (repack, nessuna compilazione del bundle):
```
sb2 -t <target-aarch64> rpmbuild -bb harbour-rootitanium.spec \
    --define "_topdir <staging>/rpmbuild" --define "stagingdir <staging>"
```
Risultato: `harbour-rootitanium-1.0-1.aarch64.rpm` (~100 MB, < 300 MB Storeman).

## Trim del bundle (per stare sotto i 300 MB Storeman)
Dal bundle completo (~383 MB) si rimuovono, in modo sicuro:
- `locales/` Chromium tranne `en-US.pak` e `it.pak` (~ -33 MB);
- `resources/qtwebengine_devtools_resources.pak` (~ -4 MB, solo DevTools remoti);
- le librerie Qt6 **non raggiunte** dalla closure `DT_NEEDED` (Designer,
  WaylandCompositor client, Pdf, Location, PrintSupport, QmlCompiler, Sensors,
  ecc. — vedi `closure.py` nello staging);
- file di sviluppo (`main.cpp`, `run-log.sh`, `*.bak`).
Metodo obbligato: trim nello staging, poi **testare che l'app renderizzi** (es.
via CDP) prima di impacchettare.

## Rilascio
`run.sh` nel payload ha logging verboso e remote-debugging SPENTI (build di
rilascio); si riattivano da env per diagnosi. I dati utente (cronologia,
segnalibri, cookie) vivono in `~/.rootitanium` e `~/.local/share/run.sh` — NON
nel pacchetto.
