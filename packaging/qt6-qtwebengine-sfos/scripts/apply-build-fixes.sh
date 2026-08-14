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

REPO=/home/RootGPT/Developing/SailfishOS/RooTitanium
VER=${VER:-6.8.4}
BT=$REPO/packaging/qt6-qtwebengine-sfos/build/BUILD/qt6-qtwebengine-$VER/upstream
GNDIR=$BT/src/core/RelWithDebInfo/aarch64
ENGINE=sailfish-sdk-build-engine_RootGPT
TARGET=SailfishOS-5.1.0.11-aarch64.default
QEMU10=/home/RootGPT/qemu-aarch64-10       # qemu-aarch64-static 10.x dell'HOST

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
  touch -d '2026-07-06 12:00' "$BT/CMakeLists.txt"
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
  local mangled="home_RootGPT_Developing_SailfishOS_RooTitanium_packaging_qt6-qtwebengine-sfos_build_BUILD_qt6-qtwebengine-${VER}_upstream_src_core_"
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
  [ -x "$QEMU10" ] || die "manca $QEMU10 (copia /usr/bin/qemu-aarch64-static dell'host; NB: /tmp non e' condiviso col container, /home si')"
  local gen=$GNDIR/v8_context_snapshot_generator
  [ -f "$gen" ] || die "generatore non trovato: $gen"
  if [ -f "$gen.real" ]; then
    echo "  = wrapper gia' installato"
  else
    mv "$gen" "$gen.real"
    cat > "$gen" <<EOF
#!/bin/sh
# Wrapper RooTitanium: esegue il generatore aarch64 col qemu 10 dell'host,
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
  snapshot) echo "== v8_context_snapshot"; fix_snapshot ;;
  qmlcache) echo "== permessi qmlcachegen"; fix_qmlcache ;;
  all)      echo "== args.gn (V8)";        fix_gn
            echo "== toolchain.ninja";     fix_rsp
            echo "== build.ninja (link)";  fix_link
            echo "== permessi qmlcachegen"; fix_qmlcache ;;
  *) die "uso: $0 {gn|ninja|snapshot|qmlcache|all}" ;;
esac
echo "fatto."
