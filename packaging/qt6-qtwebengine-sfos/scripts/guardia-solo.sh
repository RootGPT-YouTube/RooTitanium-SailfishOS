#!/bin/bash
# Guardia termica VRM SOLO (senza lanciare build) da attaccare a una build
# qt6-qtwebengine gia' in corso dentro l'engine docker.
#
# Nata il 7 lug 2026 18:4x: la guardia originale e' stata terminata per il bug
# del restore (--cpus 0 non sblocca), ma la build dentro l'engine e' rimasta
# viva orfana (sfdk lascia il ninja remoto in esecuzione). Questo watcher
# ripristina la protezione termica SENZA toccare la build: monitora VRM e
# throttla/ripristina l'engine con il restore CORRETTO (--cpus 16, non 0).
# Termina da solo quando il processo sfdk della build sparisce.

set -u
# Root del repo, derivata dalla posizione dello script (scripts/ è 3 livelli sotto)
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
ENGINE=sailfish-sdk-build-engine_RootGPT
CHIP=it8689-isa-0a40
SOGLIA_STOP=85
SOGLIA_RIPRESA=60
INTERVALLO=20
CORE_RIDOTTI=2
CORE_PIENI=12          # regime stazionario (VRM ~73-74°C); mai --cpus 0 (bug)
GUARDLOG=$REPO/packaging/qt6-qtwebengine-sfos/build/guardia-vrm.log
BUILDLOG=$REPO/packaging/qt6-qtwebengine-sfos/build/build-j16.log

leggi_vrm() { sensors "$CHIP" 2>/dev/null | awk -F'[+.]' '/^VRM:/ {print $2}'; }
nota() { echo "$(date '+%F %T')  $*" | tee -a "$GUARDLOG"; }

nota "=== [guardia-solo] attaccata a build in corso. restore=${CORE_PIENI} core. ==="
ridotto=0
ultimo_report=0
# considera "pieno" gia' impostato (l'ho messo a 16 a mano prima di partire)
while pgrep -f 'cmake --build . -j16 --verbose' >/dev/null; do
    t=$(leggi_vrm)
    if [ -n "$t" ]; then
        if [ "$ridotto" -eq 0 ] && [ "$t" -ge "$SOGLIA_STOP" ]; then
            docker update --cpus "$CORE_RIDOTTI" "$ENGINE" >/dev/null
            ridotto=1
            nota "VRM ${t}°C >= ${SOGLIA_STOP}°C: engine ridotto a ${CORE_RIDOTTI} core"
        elif [ "$ridotto" -eq 1 ] && [ "$t" -le "$SOGLIA_RIPRESA" ]; then
            docker update --cpus "$CORE_PIENI" "$ENGINE" >/dev/null
            ridotto=0
            nota "VRM ${t}°C <= ${SOGLIA_RIPRESA}°C: ripristinati ${CORE_PIENI} core (restore corretto)"
        fi
        adesso=$(date +%s)
        if [ $((adesso - ultimo_report)) -ge 300 ]; then
            stato=$([ "$ridotto" -eq 1 ] && echo "RIDOTTO" || echo "pieno-${CORE_PIENI}")
            av=$(grep -oE '\[[0-9]+/[0-9]+\]' "$BUILDLOG" | tail -1)
            nota "VRM ${t}°C, regime ${stato}, avanzamento ${av:-n/d}"
            ultimo_report=$adesso
        fi
    fi
    sleep "$INTERVALLO"
done
nota "=== [guardia-solo] build terminata (processo sfdk sparito). Watcher chiuso. ==="
