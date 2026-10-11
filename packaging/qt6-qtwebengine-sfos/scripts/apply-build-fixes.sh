#!/bin/bash
# RooTitanium — fix del build tree qt6-qtwebengine che NON sono esprimibili come
# patch sui sorgenti (toccano file GENERATI da cmake/gn/ninja, o sono passi da
# eseguire con un tool esterno). Le patch sui sorgenti stanno in ../patches/ e le
# applica lo spec.
#
# Tutti i passi sono IDEMPOTENTI: rilanciare lo script non fa danni.
#
# Uso, dalla workstation (fuori dal container):
#   ./apply-build-fixes.sh gn        # DOPO il configure, PRIMA della build
#   ./apply-build-fixes.sh ninja     # DOPO ogni gn-regen (rsp + link flags)
#   ./apply-build-fixes.sh snapshot  # SOLO se fallisce v8_context_snapshot_generator
#   ./apply-build-fixes.sh qmlcache  # SOLO se cc1plus dice "Permission denied" su .rcc/qmlcache
#   ./apply-build-fixes.sh all       # gn + ninja
#
# Perche' non stanno nello spec: args.gn/toolchain.ninja/build.ninja sono
# rigenerati dal configure, quindi una patch non li puo' raggiungere.
set -euo pipefail

# Root del repo derivata dalla posizione dello script (scripts/ e' 3 livelli sotto),
# come negli altri script: niente path assoluti cablati.
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
VER=${VER:-6.8.4}
# ARCH=armv7hl per il motore a 32 bit (albero e target separati, vedi
# RUNBOOK-armv7hl.md); senza, tutto come prima (aarch64).
ARCH=${ARCH:-aarch64}
case "$ARCH" in
  aarch64) TOPDIR=build;         GNSUB=RelWithDebInfo/aarch64
           TARGET=SailfishOS-5.1.0.11-aarch64.default; QEMUBIN=qemu-aarch64-10 ;;
  armv7hl) TOPDIR=build-armv7hl; GNSUB=Release/armv7l
           TARGET=SailfishOS-5.1.0.11-armv7hl;         QEMUBIN=qemu-arm-10 ;;
  *) echo "ERRORE: ARCH sconosciuta: $ARCH" >&2; exit 1 ;;
esac
# Chromium 140 (task 2.5 #6): target sb2 clonati con Qt 6.12 e build Release
# per entrambe le arch → GNSUB_OVR=Release/aarch64 TARGET_OVR=...-qt612
GNSUB=${GNSUB_OVR:-$GNSUB}; TARGET=${TARGET_OVR:-$TARGET}
# BT = cartella di BUILD; SRCT = sorgenti (per la 6.8.x coincidono: build
# in-place). Per Chromium 140 (task 2.5 #6) la build e' fuori dai sorgenti, una
# cartella per arch: BT=.../build-aarch64/qtwebengine SRCT=.../qtwebengine-6.140
BT=${BT:-$REPO/packaging/qt6-qtwebengine-sfos/$TOPDIR/BUILD/qt6-qtwebengine-$VER/upstream}
SRCT=${SRCT:-$BT}
GNDIR=$BT/src/core/$GNSUB
ENGINE=sailfish-sdk-build-engine_RootGPT
# qemu-<arch>-static 10.x dell'HOST, copiato nella home (dev'essere sotto /home:
# /tmp NON e' condiviso col container). Si sposta con QEMU10=...
QEMU10=${QEMU10:-$HOME/$QEMUBIN}

die() { echo "ERRORE: $*" >&2; exit 1; }
[ -d "$BT" ] || die "build tree non trovato: $BT (VER=$VER giusto?)"

# ── 1) args.gn: V8 senza sandbox ne' pointer compression ─────────────────────
# mksnapshot e gli altri tool V8 girano sotto qemu-user, che concede ~4 GB di
# spazio di indirizzamento: il sandbox V8 ne vuole riservare ~1 TB e la pointer
# compression ~4 GB, quindi entrambi vanno spenti o i tool muoiono (signal 5).
# Servono TUTTI E TRE i flag: il solo sandbox non basta.
# TRAPPOLA: args.gn e' generato. Se cmake fa un reconfigure lo riscrive e i
# flag spariscono → per questo, dopo l'edit, si retrodata CMakeLists.txt cosi'
# cmake non si riattiva (--regenerate-during-build ricalcolerebbe anche le
# feature Qt, con rebuild di massa).
fix_gn() {
  local f=$GNDIR/args.gn
  [ -f "$f" ] || die "args.gn non trovato: $f — hai gia' fatto il configure?"
  # TRAPPOLA (scoperta sulla 6.8.4, 14 ago 2026): args.gn puo' NON finire con
  # newline. Senza questa guardia il primo flag si incolla all'ultima riga
  # ("build_webnn_with_xnnpack=falsev8_enable_sandbox=false") e gn muore con
  # "ERROR at build arg file ...: Operator ..." → "-- GN FAILED".
  if [ -s "$f" ] && [ -n "$(tail -c 1 "$f")" ]; then
    echo >> "$f"
    echo "  + newline finale mancante in args.gn (aggiunta)"
  fi
  local added=0
  for flag in v8_enable_sandbox=false \
              v8_enable_pointer_compression=false \
              v8_enable_pointer_compression_shared_cage=false; do
    if grep -qF "$flag" "$f"; then
      echo "  = $flag (gia' presente)"
    else
      echo "$flag" >> "$f"; echo "  + $flag"; added=1
    fi
  done
  # CMakeLists piu' vecchio della cache = niente rigenerazione
  touch -d '2026-07-06 12:00' "$SRCT/CMakeLists.txt"
  echo "  = CMakeLists.txt retrodatato (blocca il reconfigure)"
  [ $added -eq 1 ] && echo "  ! verifica: ninja build.ninja && grep sandbox $GNDIR/gen/v8/v8_features.json"
  return 0
}

# ── 2) toolchain.ninja: accorcia i nomi dei file .rsp ────────────────────────
# Il path di lavoro e' lungo (scelta dell'utente: la cartella resta
# $REPO). Ninja lo mangla dentro i nomi dei .rsp e per i target
# mojom __jumbo_merge si superano i 255 char di NAME_MAX → "File name too long".
# I nomi .rsp sono temporanei interni a ninja (il comando usa ${rspfile}), quindi
# accorciarli e' sicuro; si tocca SOLO la riga "  rspfile = ".
fix_rsp() {
  local f=$GNDIR/toolchain.ninja
  [ -f "$f" ] || die "toolchain.ninja non trovato: $f"
  # = path di $BT/src/core/ senza la / iniziale e con gli slash in underscore
  local mangled
  mangled=$(echo "${BT#/}/src/core/" | tr / _)
  if grep -q "$mangled" "$f"; then
    cp -n "$f" "$f.bak-rsplen"
    sed -i "/^  rspfile = /s#${mangled}##g" "$f"
    echo "  + nomi rsp accorciati (backup: $(basename "$f").bak-rsplen)"
  else
    echo "  = nomi rsp gia' corti"
  fi
  local max
  max=$(grep '^  rspfile = ' "$f" | sed 's#.*/##' | awk '{print length}' | sort -n | tail -1)
  echo "  = nome rsp piu' lungo: ${max:-0} char (limite 255)"
  [ "${max:-0}" -gt 255 ] && die "ci sono ancora nomi rsp oltre NAME_MAX"
  return 0
}

# ── 3) build.ninja (cmake esterno): link di libQt6WebEngineCore ──────────────
# La .so finale sta sopra 1,3 GB e il linker, pur nativo, e' a 32 bit: senza
# questi flag esaurisce i ~4 GB con "final link failed: memory exhausted".
fix_link() {
  local f=$BT/build.ninja
  [ -f "$f" ] || die "build.ninja non trovato: $f"
  if grep -q -- "--no-keep-memory" "$f"; then
    echo "  = flag di link gia' presenti"
  else
    cp -n "$f" "$f.bak-linkflags"
    # unico edge che linka WebEngineCore (anchor: la sua version script)
    sed -i '/WebEngineCore\.version/s#LINK_FLAGS = #LINK_FLAGS = -Wl,--no-keep-memory -Wl,--reduce-memory-overheads #' "$f"
    grep -q -- "--no-keep-memory" "$f" || die "anchor WebEngineCore.version non trovato: controlla a mano"
    echo "  + -Wl,--no-keep-memory -Wl,--reduce-memory-overheads (backup: build.ninja.bak-linkflags)"
  fi
}

# ── 4b) gn con il qemu dell'host (Chromium 140, 10 ott 2026) ─────────────────
# Il gn di QtWebEngine 6.140 e' un binario per il target e sotto il qemu 5.1 di
# sb2 abortisce ("terminate called recursively", signal 6) appena fa
# "gn gen": stessa famiglia del guasto dello snapshot V8, stesso rimedio.
# Se gn viene rilinkato sovrascrive il wrapper: si guarda cosa c'e' adesso.
fix_gnqemu() {
  [ -x "$QEMU10" ] || die "manca $QEMU10"
  local g=$BT/install/bin/gn
  [ -f "$g" ] || die "gn non trovato: $g"
  # Ponte per gli script Python di gn: lanciato direttamente da gn sotto il
  # qemu dell'host, /usr/bin/python3 parte senza libreria standard
  # ("init_fs_encoding"). Uno script NATIVO fuori dal sysroot rientra invece
  # nella mappatura di sb2 (LD_PRELOAD sopravvive al passaggio) e trova il
  # python giusto e i pkg-config del target (verificato: Qt6Core 6.12.0).
  # generate_bindings.py va col python NATIVO del tooling: sotto quello emulato
  # il suo pool multiprocessing si blocca senza errori (vedi fix_pynativo).
  cat > "$BT/install/bin/py-sb2.sh" <<'PYSB2'
#!/bin/sh
case "$1" in
  */generate_bindings.py) exec /srv/mer/toolings/SailfishOS-5.1.0.11/usr/bin/python3 "$@" ;;
esac
exec /usr/bin/python3 "$@"
PYSB2
  chmod +x "$BT/install/bin/py-sb2.sh"
  # il wrapper si (ri)scrive se manca o e' di una versione senza ponte
  if head -c2 "$g" 2>/dev/null | grep -q '#!' && grep -q py-sb2 "$g"; then
    echo "  = wrapper gn gia' installato"
    return 0
  fi
  head -c2 "$g" 2>/dev/null | grep -q '#!' || mv -f "$g" "$g.real"
  cat > "$g" <<WRAP
#!/bin/sh
# Wrapper RooTitanium: gn ($ARCH) col qemu 10 dell host (quello del target
# abortisce) e con il ponte py-sb2.sh come interprete degli script.
B="\$(dirname "\$0")/py-sb2.sh"
for a; do shift; case "\$a" in
  --script-executable=*) set -- "\$@" "--script-executable=\$B" ;;
  *) set -- "\$@" "\$a" ;;
esac; done
exec $QEMU10 -L /srv/mer/targets/$TARGET "\$(dirname "\$0")/gn.real" "\$@"
WRAP
  chmod +x "$g"
  echo "  + wrapper qemu-10 per gn installato (con ponte python)"
}

# ── 4c) node con il qemu dell'host (Chromium 140, 10 ott 2026) ───────────────
# Il frontend DevTools di 140 usa rollup in WebAssembly. Il node del target gira
# sotto il qemu di sb2, che e' un eseguibile a 32 bit (~4 GB di indirizzi): V8
# non riesce a riservare le regioni di guardia del wasm ("Cannot allocate Wasm
# memory"), e --disable-wasm-trap-handler li' fa morire node col signal 5.
# Sotto il qemu 10 a 64 bit dell'host funziona (verificato). Si punta
# NODEJS_EXECUTABLE (build.ninja + cache) a un wrapper accanto a gn.
fix_nodeqemu() {
  [ -x "$QEMU10" ] || die "manca $QEMU10"
  local w=$BT/install/bin/node-qemu10.sh
  printf '#!/bin/sh\n# node (%s) col qemu 10 dell host: wasm di rollup sotto il qemu a 32 bit di sb2 va in OOM\nexec %s -L /srv/mer/targets/%s /srv/mer/targets/%s/usr/bin/node "$@"\n' \
    "$ARCH" "$QEMU10" "$TARGET" "$TARGET" > "$w"
  chmod +x "$w"
  sed -i "s#NODEJS_EXECUTABLE=/usr/bin/node#NODEJS_EXECUTABLE=$w#g" "$BT/build.ninja"
  sed -i "s#^Nodejs_EXECUTABLE:FILEPATH=.*#Nodejs_EXECUTABLE:FILEPATH=$w#" "$BT/CMakeCache.txt"
  echo "  + node via qemu-10: $(grep -c "NODEJS_EXECUTABLE=$w" "$BT/build.ninja") punti in build.ninja"
}

# ── 4d) mksnapshot col qemu dell'host (Chromium 140, 11 ott 2026) ─────────────
# Con args.gn senza i flag V8 (vedi fix_gn: il regen di gn puo' averli tolti)
# mksnapshot vuole riservare lo spazio del sandbox V8 e sotto il qemu a 32 bit
# di sb2 muore: "Failed to reserve the virtual address space for the V8
# sandbox" + signal 5. Sotto il qemu 10 a 64 bit dell'host funziona. Stesso
# schema dello snapshot: wrapper al posto del binario, il .real accanto.
fix_mksnapshot() {
  [ -x "$QEMU10" ] || die "manca $QEMU10"
  local m=$GNDIR/mksnapshot
  [ -f "$m" ] || die "mksnapshot non trovato: $m"
  if head -c2 "$m" 2>/dev/null | grep -q '#!'; then
    echo "  = wrapper mksnapshot gia' installato"
  else
    mv -f "$m" "$m.real"
    printf '#!/bin/sh\n# Wrapper RooTitanium: mksnapshot (%s) col qemu 10 dell host (sandbox V8 > 4 GB di indirizzi)\nexec %s -L /srv/mer/targets/%s "$(dirname "$0")/mksnapshot.real" "$@"\n' \
      "$ARCH" "$QEMU10" "$TARGET" > "$m"
    chmod +x "$m"
    echo "  + wrapper qemu-10 per mksnapshot (originale: mksnapshot.real)"
  fi
}

# ── 4e) generatore dei binding di Blink col python NATIVO (11 ott 2026) ──────
# generate_bindings.py lancia un pool multiprocessing (~32 processi): sotto il
# python aarch64 emulato da sb2 il pool si BLOCCA (processi vivi a 0% CPU,
# nessun file scritto, per ore: e' cio' che ha portato all'OOM del 10 ott).
# Lo script e' puro Python e l'output non dipende dall'arch: si usa il python
# x86 del tooling SDK (3.11 come quello del target), che sotto sb2 gira nativo.
fix_pynativo() {
  local w=$BT/install/bin/py-nativo.sh f=$GNDIR/toolchain.ninja
  printf '#!/bin/sh\n# python x86 del tooling SDK (nativo, niente qemu) per generate_bindings.py\nexec /srv/mer/toolings/SailfishOS-5.1.0.11/usr/bin/python3 "$@"\n' > "$w"
  chmod +x "$w"
  sed -i '/generate_bindings\.py/s#install/bin/py-sb2\.sh #install/bin/py-nativo.sh #' "$f"
  echo "  + generate_bindings col python nativo: $(grep -c py-nativo.sh "$f") regole"
}

# ── 4) v8_context_snapshot_generator con il qemu dell'host ───────────────────
# Il qemu 5.1 del target lo fa trappare (signal 5); il qemu 10.x dell'host lo
# esegue senza problemi.
#
# 🔴 CORREZIONE 14 ago 2026: generare il .bin a mano NON basta, e il runbook che
# diceva "una volta prodotto il .bin ninja salta lo step" era sbagliato. Ninja
# rifa' comunque il target — il .bin era piu' recente del generatore e veniva
# ricostruito lo stesso — e la build entrava in loop: rimedio applicato, build
# ripartita, stesso fallimento, a ogni giro.
# Rimedio vero: mettere al posto del generatore un WRAPPER che lo esegue col
# qemu dell'host. Cosi' e' ninja stesso a produrre il .bin e a registrarne il
# successo, e il passo non si ripresenta piu'. Idempotente.
fix_snapshot() {
  [ -x "$QEMU10" ] || die "manca $QEMU10 (copia /usr/bin/qemu-<arch>-static dell'host; NB: /tmp non e' condiviso col container, /home si')"
  local gen=$GNDIR/v8_context_snapshot_generator
  [ -f "$gen" ] || die "generatore non trovato: $gen"
  # ⚠️ Il test NON puo' essere "esiste $gen.real" (com'era fino al 18/09): ogni
  # build che rilinka il generatore SOVRASCRIVE il wrapper col binario ELF e
  # lascia al suo posto il .real vecchio. Lo script diceva "gia' installato" e
  # la build ricadeva nel signal 5. Si guarda quindi COSA e' il file adesso, e
  # il .real si aggiorna con -f: il binario appena linkato e' quello buono.
  if head -c2 "$gen" 2>/dev/null | grep -q '#!'; then
    echo "  = wrapper gia' installato"
  else
    mv -f "$gen" "$gen.real"
    cat > "$gen" <<EOF
#!/bin/sh
# Wrapper RooTitanium: esegue il generatore ($ARCH) col qemu 10 dell'host,
# perche' quello del target (5.1) trappa con signal 5.
exec $QEMU10 -L /srv/mer/targets/$TARGET "\$(dirname "\$0")/v8_context_snapshot_generator.real" "\$@"
EOF
    chmod +x "$gen"
    echo "  + wrapper qemu-10 installato (originale: $(basename "$gen").real)"
  fi
  # il .bin lo rifara' ninja passando dal wrapper: qui si toglie solo quello
  # eventualmente prodotto a mano, che ninja non considera valido
  rm -f "$GNDIR/v8_context_snapshot.bin"
  return 0
}

# ── 5) qmlcachegen: i .cpp generati nascono con permessi 000 ────────────────
# Riprodotto sulla 6.8.4 il 14 ago 2026 (era l'incognita senza descrizione del
# riepilogo 7-8 lug, vedi ../patches/README.md §C): qmlcachegen scrive i suoi
# .cpp sotto .rcc/qmlcache/ con modo 000, e subito dopo cc1plus non riesce ad
# aprirli ("fatal error: ...: Permission denied"). Gli altri file dello stesso
# passo (.aotstats) nascono regolari, quindi non e' l'umask: e' come il tool
# crea QUEL file sotto sb2/qemu.
# Rimedio: rendere leggibile tutto cio' che e' a 000 nel build tree. Non tocca
# nient'altro. Si rilancia ogni volta che la build si ferma con quell'errore
# (i file rigenerati ripresentano il problema).
fix_qmlcache() {
  local n
  n=$(find "$BT" -type f -perm 000 | wc -l)
  if [ "$n" -eq 0 ]; then
    echo "  = nessun file a permessi 000"
  else
    find "$BT" -type f -perm 000 -exec chmod 644 {} +
    echo "  + $n file riportati a 644 (qmlcachegen)"
  fi
}

case "${1:-all}" in
  gn)       echo "== args.gn (V8)";        fix_gn ;;
  ninja)    echo "== toolchain.ninja";     fix_rsp; echo "== build.ninja (link)"; fix_link ;;
  # ⚠️ 11 ott: su una build GIA' avviata usare SOLO "link". fix_rsp cambia la
  # riga di comando delle azioni con rspfile → ninja le rifa' e a cascata
  # ricompila ~11.000 passi (successo sul motore aarch64 6.140).
  link)     echo "== build.ninja (link)";  fix_link ;;
  snapshot) echo "== v8_context_snapshot"; fix_snapshot ;;
  gnqemu)   echo "== gn col qemu dell host"; fix_gnqemu ;;
  nodeqemu) echo "== node col qemu dell host"; fix_nodeqemu ;;
  mksnapshot) echo "== mksnapshot col qemu dell host"; fix_mksnapshot ;;
  pynativo) echo "== binding Blink col python nativo"; fix_pynativo ;;
  qmlcache) echo "== permessi qmlcachegen"; fix_qmlcache ;;
  all)      echo "== args.gn (V8)";        fix_gn
            echo "== toolchain.ninja";     fix_rsp
            echo "== build.ninja (link)";  fix_link
            echo "== permessi qmlcachegen"; fix_qmlcache ;;
  *) die "uso: $0 {gn|ninja|snapshot|qmlcache|all}" ;;
esac
echo "fatto."
