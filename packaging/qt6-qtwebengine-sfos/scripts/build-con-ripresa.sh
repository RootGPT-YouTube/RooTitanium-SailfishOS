#!/bin/bash
# Build di qt6-qtwebengine con RIPRESA AUTOMATICA sui blocchi noti.
#
# La build si ferma sempre negli stessi punti (vedi RUNBOOK-6.8.4.md §4) e ogni
# volta il rimedio è uno dei passi di apply-build-fixes.sh. Questo script chiude
# il ciclo: lancia build-con-guardia.sh (che porta con sé la guardia termica
# VRM), e se fallisce riconosce il sintomo nel log, applica il rimedio e riprende
# — la build è incrementale, quindi ogni giro riparte da dov'era.
#
# Si ferma e chiama l'utente solo davanti a un errore NON riconosciuto: è lì che
# serve una persona, non sui blocchi che sappiamo già come sbloccare.
#
# Uso:  ./build-con-ripresa.sh            (versione dallo spec)
#       VER=6.8.3 ./build-con-ripresa.sh  (per forzare un altro tree)
#
# Log:  build-ripresa.log (questo script), build.log (build), guardia-vrm.log

set -u
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
SCRIPTS=$REPO/packaging/qt6-qtwebengine-sfos/scripts
# ARCH=armv7hl = motore a 32 bit; passa da sola agli altri due script
ARCH=${ARCH:-aarch64}
export ARCH
case "$ARCH" in
  aarch64) LOGDIR=$REPO/packaging/qt6-qtwebengine-sfos/build ;;
  armv7hl) LOGDIR=$REPO/packaging/qt6-qtwebengine-sfos/build-armv7hl ;;
  *) echo "ERRORE: ARCH sconosciuta: $ARCH"; exit 1 ;;
esac
LOGDIR=${LOGDIR_OVR:-$LOGDIR}
BUILDLOG=$LOGDIR/build.log
LOG=$LOGDIR/build-ripresa.log
MAX_GIRI=${MAX_GIRI:-15}

VER=${VER:-$(sed -n 's/^Version: *//p' "$REPO/packaging/qt6-qtwebengine-sfos/rpm/qt6-qtwebengine.spec" | head -1)}
export VER

nota() { echo "$(date '+%F %T')  $*" | tee -a "$LOG"; }

nota "=== build con ripresa $ARCH, versione $VER, massimo $MAX_GIRI giri ==="

# Rete di sicurezza contro i giri a vuoto: se lo stesso rimedio si ripete senza
# che la build sia avanzata, il rimedio non c'entra col guasto — meglio fermarsi
# e chiamare una persona che consumare tutti i giri (successo il 14 ago 2026).
rimedio_prec=""
avanz_prec=""

for giro in $(seq 1 "$MAX_GIRI"); do
    nota "--- giro $giro: avvio build ---"
    "$SCRIPTS/build-con-guardia.sh" >/dev/null 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then
        nota "=== BUILD COMPLETATA al giro $giro ==="
        exit 0
    fi

    # Si guardano SOLO le righe di errore, non tutto il log: la lista degli
    # argomenti gn contiene stringhe come "use_v8_context_snapshot=true" che
    # facevano scattare il rimedio sbagliato (visto il 14 ago 2026: un
    # "-- GN FAILED" veniva letto come crash dello snapshot V8).
    coda=$(grep -E "^FAILED:|^ninja: |fatal error:|CMake Error|GN FAILED|error:|uncaught target signal|terminate called|init_fs_encoding|Cannot allocate Wasm memory" "$BUILDLOG" 2>/dev/null | tail -30)
    avanz=$(grep -oE '\[[0-9]+/[0-9]+\]' "$BUILDLOG" 2>/dev/null | tail -1)

    case "$coda" in
        # qmlcachegen scrive i .cpp a permessi 000 e cc1plus non li apre
        *"Permission denied"*)
            rimedio=qmlcache ;;
        # gn-regen: i nomi .rsp tornano lunghi oltre NAME_MAX
        *"File name too long"*)
            rimedio=ninja ;;
        # stessa causa: il flag di link si perde se build.ninja viene rigenerato
        *"memory exhausted"*|*"final link failed"*)
            rimedio=ninja ;;
        # lo snapshot V8 trappa sotto il qemu del target. Ninja nomina il TARGET
        # ("FAILED: v8_context_snapshot.bin"), non il binario che l'ha prodotto:
        # cercare "…_generator" non bastava (build ferma per questo il 14 ago).
        # Qui il pattern largo e' sicuro perche' si guardano solo righe di errore.
        # ⚠️ 8 ott 2026 (build armv7hl): NON basta "*v8_context_snapshot*". Il
        # ninja esterno, quando muore QUALSIASI cosa dentro QtWebEngineCore,
        # stampa "FAILED: .../QtWebEngineCore.stamp .../v8_context_snapshot.stamp"
        # e il pattern largo scambiava un errore di compilazione (zlib crc32)
        # per lo snapshot: 5 giri a vuoto. Si guarda il nome del .bin.
        # Chromium 140: gn stesso abortisce sotto il qemu del target. Va PRIMA
        # del caso snapshot, che guarda anche "uncaught target signal".
        *"GN FAILED"*"uncaught target signal"*|*"GN FAILED"*"terminate called"*|*"init_fs_encoding"*)
            rimedio=gnqemu ;;
        # node del target sotto il qemu a 32 bit: il wasm di rollup va in OOM
        *"Cannot allocate Wasm memory"*)
            rimedio=nodeqemu ;;
        # mksnapshot col sandbox V8 sotto il qemu a 32 bit (11 ott): PRIMA del
        # caso snapshot, che altrimenti lo prende per "uncaught target signal"
        *"reserve the virtual address space for the V8 sandbox"*|*"FAILED: gen/v8/embedded.S"*)
            rimedio=mksnapshot ;;
        *"FAILED: v8_context_snapshot.bin"*|*"uncaught target signal"*)
            rimedio=snapshot ;;
        *)
            rimedio="" ;;
    esac

    if [ -z "$rimedio" ]; then
        nota "=== FERMO al giro $giro: errore NON riconosciuto (exit $rc). Serve una persona. ==="
        nota "Ultime righe di errore:"
        echo "$coda" | tail -5 | tee -a "$LOG"
        command -v notify-send >/dev/null 2>&1 && \
            notify-send -u critical "RooTitanium build $VER" "Fermo su errore non riconosciuto (giro $giro)"
        exit "$rc"
    fi

    if [ "$rimedio" = "$rimedio_prec" ] && [ "$avanz" = "$avanz_prec" ]; then
        nota "=== FERMO al giro $giro: rimedio '$rimedio' gia' applicato e build ferma a ${avanz:-n/d}. Non e' questo il guasto. ==="
        echo "$coda" | tail -5 | tee -a "$LOG"
        command -v notify-send >/dev/null 2>&1 && \
            notify-send -u critical "RooTitanium build $VER" "Rimedio '$rimedio' inefficace: build ferma"
        exit "$rc"
    fi

    nota "giro $giro: rimedio '$rimedio' (avanzamento ${avanz:-n/d})"
    # PIPESTATUS: con la sola pipe contava l'exit di tee, e un rimedio fallito
    # ("generatore non trovato") passava per riuscito
    "$SCRIPTS/apply-build-fixes.sh" "$rimedio" 2>&1 | tee -a "$LOG"
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        nota "=== FERMO: il rimedio '$rimedio' e' fallito. ==="
        exit 1
    fi
    rimedio_prec=$rimedio
    avanz_prec=$avanz
done

nota "=== FERMO: esauriti i $MAX_GIRI giri senza completare. ==="
exit 1
