#!/bin/bash
# Build di qt6-qtwebengine con RIPRESA AUTOMATICA sui blocchi noti.
#
# La build si ferma sempre negli stessi punti (vedi RUNBOOK-6.8.4.md §4) e ogni
# volta il rimedio è uno dei passi di apply-build-fixes.sh. Questo script chiude
# il ciclo: lancia build-j16-con-guardia.sh (che porta con sé la guardia termica
# VRM), e se fallisce riconosce il sintomo nel log, applica il rimedio e riprende
# — la build è incrementale, quindi ogni giro riparte da dov'era.
#
# Si ferma e chiama l'utente solo davanti a un errore NON riconosciuto: è lì che
# serve una persona, non sui blocchi che sappiamo già come sbloccare.
#
# Uso:  ./build-con-ripresa.sh            (versione dallo spec)
#       VER=6.8.3 ./build-con-ripresa.sh  (per forzare un altro tree)
#
# Log:  build-ripresa.log (questo script), build-j16.log (build), guardia-vrm.log

set -u
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
SCRIPTS=$REPO/packaging/qt6-qtwebengine-sfos/scripts
LOGDIR=$REPO/packaging/qt6-qtwebengine-sfos/build
BUILDLOG=$LOGDIR/build-j16.log
LOG=$LOGDIR/build-ripresa.log
MAX_GIRI=${MAX_GIRI:-15}

VER=${VER:-$(sed -n 's/^Version: *//p' "$REPO/packaging/qt6-qtwebengine-sfos/rpm/qt6-qtwebengine.spec" | head -1)}
export VER

nota() { echo "$(date '+%F %T')  $*" | tee -a "$LOG"; }

nota "=== build con ripresa, versione $VER, massimo $MAX_GIRI giri ==="

for giro in $(seq 1 "$MAX_GIRI"); do
    nota "--- giro $giro: avvio build ---"
    "$SCRIPTS/build-j16-con-guardia.sh" >/dev/null 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then
        nota "=== BUILD COMPLETATA al giro $giro ==="
        exit 0
    fi

    coda=$(tail -c 20000 "$BUILDLOG" 2>/dev/null)
    case "$coda" in
        # qmlcachegen scrive i .cpp a permessi 000 e cc1plus non li apre
        *"Permission denied"*)
            nota "giro $giro: permessi 000 (qmlcachegen) → rimedio 'qmlcache'"
            "$SCRIPTS/apply-build-fixes.sh" qmlcache 2>&1 | tee -a "$LOG"
            ;;
        # gn-regen: i nomi .rsp tornano lunghi oltre NAME_MAX
        *"File name too long"*)
            nota "giro $giro: nomi rsp oltre NAME_MAX → rimedio 'ninja'"
            "$SCRIPTS/apply-build-fixes.sh" ninja 2>&1 | tee -a "$LOG"
            ;;
        # stessa causa: il flag di link si perde se build.ninja viene rigenerato
        *"memory exhausted"*|*"final link failed"*)
            nota "giro $giro: link senza --no-keep-memory → rimedio 'ninja'"
            "$SCRIPTS/apply-build-fixes.sh" ninja 2>&1 | tee -a "$LOG"
            ;;
        # il generatore dello snapshot V8 trappa sotto il qemu del target
        *v8_context_snapshot*)
            nota "giro $giro: v8_context_snapshot_generator → rimedio 'snapshot'"
            "$SCRIPTS/apply-build-fixes.sh" snapshot 2>&1 | tee -a "$LOG"
            ;;
        *)
            nota "=== FERMO al giro $giro: errore NON riconosciuto (exit $rc). Serve una persona. ==="
            nota "Ultime righe di $BUILDLOG:"
            grep -iE "FAILED|error:|ninja: " "$BUILDLOG" 2>/dev/null | tail -5 | tee -a "$LOG"
            command -v notify-send >/dev/null 2>&1 && \
                notify-send -u critical "RooTitanium build $VER" "Fermo su errore non riconosciuto (giro $giro)"
            exit "$rc"
            ;;
    esac
done

nota "=== FERMO: esauriti i $MAX_GIRI giri senza completare. ==="
exit 1
