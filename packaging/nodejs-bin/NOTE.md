# nodejs-bin — note di packaging

Ricerca svolta il 5 luglio 2026 (agente cloud). Decisione: **opzione B — repack
dei binari prebuilt ufficiali** invece del build da sorgente.

## Perché il repack (opzione B)

- QtWebEngine 6.8.3 richiede solo **Node.js ≥ 14** come *tool host* a build-time
  (configure check in `configure.cmake` / `cmake/FindNodejs.cmake` di qtwebengine):
  esegue script di code-gen stile Chromium, non compila/embedda V8.
- Il build da sorgente (opzione A) è bloccato dal problema **mksnapshot/Torque**:
  i tool di V8 devono girare nativi x86_64 sull'host durante il build di Node,
  servirebbe una doppia toolchain host+target non supportata da sb2 — nessun
  precedente di successo trovato (cfr. nodejs/node#42544).
- Compatibilità ABI verificata: i prebuilt `linux-arm64` richiedono **glibc ≥ 2.28**
  e libstdc++ con `GLIBCXX_3.4.25` (nodejs/node#42659); SailfishOS 5.1 ha
  **glibc 2.41+git** (github.com/sailfishos/glibc).
- Nessun pacchetto nodejs maturo esiste per Sailfish (solo tentativi abbandonati
  su OpenRepos e un progetto OBS "experiments"); il gecko di Jolla non usa Node.
- Node NON è un runtime di sistema qui: niente npm/corepack/header/doc nel
  pacchetto, solo `/usr/bin/node`.

## Versione scelta

Node **22.23.1** (LTS 22.x più recente al 5 lug 2026; la bozza originale citava
22.17.0, aggiornata per i fix di sicurezza). SHA256 pinnato nello spec e
verificato contro `SHASUMS256.txt` ufficiale.

## Rischi aperti da verificare in locale

1. **Overhead qemu-user**: `node` viene invocato ripetutamente dagli script di
   code-gen di Chromium/gn sotto emulazione — misurare l'impatto sui tempi.
2. **Simbolo libstdc++**: confermare `GLIBCXX_3.4.25` nel sysroot target 5.1:
   `strings libstdc++.so.6 | grep GLIBCXX`.
3. **Kernel host per qemu-user**: il requisito "kernel ≥ 4.18" dei prebuilt
   riguarda l'host x86_64 del Platform SDK (ok: Fedora recente); verificare che
   qemu-user gestisca tutte le syscall del binario.
4. **npm/npx richiesti?**: verificare nei log di configure/build di qtwebengine
   6.8.3 se servono `npm`/`npx` oltre a `node` puro — in tal caso estendere il
   repack.
5. ~~Checksum/provenienza~~ ✅ hash SHA256 pinnato nello spec (5 lug 2026).
6. **Policy chum/OBS**: per pubblicazione su chum (non solo build locale),
   verificare se un repack binario è accettabile per i maintainer.
7. **Fallback opzione A**: se mai servisse il source build — Node 18/20 LTS max
   (Node 22+ richiede gcc ≥ 12.2/C++20, nodejs/build#3806), dipendenze bundled
   (openssl/icu/zlib/libuv/c-ares), gcc di SFOS 5.1 da confermare.
8. **Issue upstream con Node 22+**: verificare eventuali problemi noti
   Qt/Chromium con Node molto recente prima del primo build reale.
