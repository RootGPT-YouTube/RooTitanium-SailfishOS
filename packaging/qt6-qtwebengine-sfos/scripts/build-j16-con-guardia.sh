#!/bin/bash
# Build completa qt6-qtwebengine 6.8.3 (Fase 2) con guardia termica VRM.
#
# Uso: ./build-j16-con-guardia.sh
#
# - Lancia `cmake --build . -j16` nel target 5.1 aarch64 via sfdk (build dir
#   già configurata, vedi configure-only.sh se serve ripartire da zero).
# - Ogni 20 s legge la temperatura VRM (sensors it8689-isa-0a40).
# - >= 85 °C: strozza l'engine docker a 2 core (docker update --cpus 2).
#   NON si usa SIGSTOP/docker pause: congelerebbe anche sshd dell'engine e
#   la sessione sfdk cadrebbe, uccidendo la build. Con 2 core il calore
#   crolla ma la connessione resta viva.
# - <= 60 °C: ripristina tutti i core (docker update --cpus 0 = nessun limite).
# - Anti-stallo: ogni 15 min verifica che il log della build cresca e che
#   l'avanzamento [n/m] si muova; se tutto è fermo logga un ALLARME con
#   diagnostica (CPU processi engine, coda del log) e manda notify-send.
#   NON uccide mai la build da solo: un falso positivo (es. link finale
#   lungo) costerebbe ore. Sta all'utente decidere guardando la diagnostica:
#   processi a CPU alta = probabile lavoro lungo legittimo; tutti ~0% = stallo.
#
# Log: build-j16.log (output build), guardia-vrm.log (eventi termici+stallo).

set -u

REPO=/home/RootGPT/Developing/SailfishOS/RooTitanium
BUILDDIR=$REPO/packaging/qt6-qtwebengine-sfos/build/BUILD/qt6-qtwebengine-6.8.3/upstream
TARGET=SailfishOS-5.1.0.11-aarch64
ENGINE=sailfish-sdk-build-engine_RootGPT
CHIP=it8689-isa-0a40

SOGLIA_STOP=85      # °C: sopra questa, throttle a 2 core
SOGLIA_RIPRESA=60   # °C: sotto questa, ripristino a CORE_PIENI
INTERVALLO=20       # secondi tra le letture
CORE_RIDOTTI=2
CORE_PIENI=12       # regime stazionario (VRM ~73-74°C, sotto 85 senza throttle)
STALL_FINESTRA=900  # secondi (15 min) tra i controlli anti-stallo

LOGDIR=$REPO/packaging/qt6-qtwebengine-sfos/build
BUILDLOG=$LOGDIR/build-j16.log
GUARDLOG=$LOGDIR/guardia-vrm.log

leggi_vrm() { sensors "$CHIP" 2>/dev/null | awk -F'[+.]' '/^VRM:/ {print $2}'; }

nota() { echo "$(date '+%F %T')  $*" | tee -a "$GUARDLOG"; }

ripristina_cpu() { docker update --cpus "$CORE_PIENI" "$ENGINE" >/dev/null 2>&1; }
# NOTA (bug scoperto 7 lug 18:21): "docker update --cpus 0" NON rimuove il
# limite su questo container (resta a NanoCpus del set precedente, es. 2 core,
# nonostante il log dica "ripristinati tutti i core"). Fix: usare un valore
# esplicito. Regime stazionario a 12 core (test 7 lug 19:xx: VRM piatto ~73-74°C
# senza oscillazioni 16<->2; picco piu' basso, mobo meno stressata) — vedi
# richiesta utente. La soglia 85->2 core resta come rete di sicurezza.

# --- controlli preliminari -------------------------------------------------
[ -d "$BUILDDIR" ] || { echo "ERRORE: build dir mancante: $BUILDDIR"; exit 1; }
t=$(leggi_vrm)
[ -n "$t" ] || { echo "ERRORE: lettura VRM fallita (sensors $CHIP)"; exit 1; }
command -v sfdk >/dev/null || PATH=$PATH:$HOME/SailfishOS/bin
command -v sfdk >/dev/null || { echo "ERRORE: sfdk non trovato"; exit 1; }

ripristina_cpu   # imposta subito il regime stazionario (${CORE_PIENI} core)
nota "=== Avvio build -j12 via sb2 (cross-gcc NATIVO) con guardia VRM (regime ${CORE_PIENI} core, throttle >=${SOGLIA_STOP}°C -> ${CORE_RIDOTTI} core, ripresa <=${SOGLIA_RIPRESA}°C). VRM ora: ${t}°C ==="

# --- build in background ---------------------------------------------------
# sb2 mappa /usr/bin/c++ sul cross-compiler host-nativo (opt/cross, gcc 13.4.0):
# niente emulazione qemu -> ~5-10x piu' veloce E niente tetto ~4 GB/processo di
# qemu (i mega-TU tipo browser_interface_binders compilano). cmake/ninja girano
# emulati (leggeri); i compile vanno nativi. Eseguito come utente mersdk (owner
# dei target sb2). -j12 = concorrenza allineata ai 12 core (RAM piu' sicura coi
# compile nativi che possono usare fino a ~4 GB ciascuno).
docker exec -u mersdk "$ENGINE" bash -lc "cd $BUILDDIR && sb2 -t $TARGET cmake --build . -j12 --verbose" \
    >"$BUILDLOG" 2>&1 &
BUILD_PID=$!

trap 'nota "Interruzione richiesta: termino la build."; kill $BUILD_PID 2>/dev/null; ripristina_cpu; exit 130' INT TERM

# --- loop di guardia -------------------------------------------------------
ridotto=0
pause_totali=0
ultimo_report=0
stall_prec_size=-1
stall_prec_marca=""
stall_ultimo_check=$(date +%s)
stall_conta=0
while kill -0 "$BUILD_PID" 2>/dev/null; do
    t=$(leggi_vrm)
    if [ -n "$t" ]; then
        if [ "$ridotto" -eq 0 ] && [ "$t" -ge "$SOGLIA_STOP" ]; then
            docker update --cpus "$CORE_RIDOTTI" "$ENGINE" >/dev/null
            ridotto=1
            pause_totali=$((pause_totali + 1))
            nota "VRM ${t}°C >= ${SOGLIA_STOP}°C: engine ridotto a ${CORE_RIDOTTI} core (pausa n.${pause_totali})"
        elif [ "$ridotto" -eq 1 ] && [ "$t" -le "$SOGLIA_RIPRESA" ]; then
            ripristina_cpu
            ridotto=0
            nota "VRM ${t}°C <= ${SOGLIA_RIPRESA}°C: ripristinati tutti i core"
        fi
        # battito nel log ogni ~5 minuti
        adesso=$(date +%s)
        if [ $((adesso - ultimo_report)) -ge 300 ]; then
            stato=$([ "$ridotto" -eq 1 ] && echo "RIDOTTO" || echo "pieno")
            ultima_riga=$(grep -oE '\[[0-9]+/[0-9]+\]' "$BUILDLOG" | tail -1)
            nota "VRM ${t}°C, regime ${stato}, avanzamento ${ultima_riga:-n/d}"
            ultimo_report=$adesso
        fi
    else
        nota "ATTENZIONE: lettura VRM fallita, riprovo"
    fi

    # controllo anti-stallo ogni STALL_FINESTRA secondi
    adesso=$(date +%s)
    if [ $((adesso - stall_ultimo_check)) -ge "$STALL_FINESTRA" ]; then
        if [ "$ridotto" -eq 1 ]; then
            # a 2 core l'avanzamento lentissimo è normale: salto il controllo
            stall_ultimo_check=$adesso
        else
            size=$(stat -c %s "$BUILDLOG" 2>/dev/null || echo 0)
            marca=$(grep -oE '\[[0-9]+/[0-9]+\]' "$BUILDLOG" | tail -1)
            if [ "$size" -eq "$stall_prec_size" ] && [ "$marca" = "$stall_prec_marca" ]; then
                stall_conta=$((stall_conta + 1))
                nota "⚠️ ALLARME STALLO n.${stall_conta}: nessun output da $((STALL_FINESTRA / 60)) min (log fermo a ${size} byte, ultimo passo ${marca:-n/d})"
                nota "Diagnostica — processi engine per CPU (alta = lavoro lungo legittimo, tutti ~0 = stallo vero):"
                docker top "$ENGINE" -eo pid,pcpu,etime,comm --sort=-pcpu 2>/dev/null | head -8 | tee -a "$GUARDLOG"
                nota "Diagnostica — ultime righe del build log:"
                tail -c 500 "$BUILDLOG" | tail -3 | tee -a "$GUARDLOG"
                command -v notify-send >/dev/null 2>&1 && \
                    notify-send -u critical "RooTitanium build" "Possibile stallo (allarme n.${stall_conta}): nessun avanzamento da $((stall_conta * STALL_FINESTRA / 60)) min"
            else
                [ "$stall_conta" -gt 0 ] && nota "Avanzamento ripreso dopo ${stall_conta} allarmi: rientro allarme stallo"
                stall_conta=0
            fi
            stall_prec_size=$size
            stall_prec_marca=$marca
            stall_ultimo_check=$adesso
        fi
    fi
    sleep "$INTERVALLO"
done

wait "$BUILD_PID"
rc=$?
ripristina_cpu
if [ "$rc" -eq 0 ]; then
    nota "=== BUILD COMPLETATA (exit 0). Pause termiche totali: ${pause_totali} ==="
else
    nota "=== BUILD FALLITA (exit ${rc}). Pause termiche: ${pause_totali}. Vedi ${BUILDLOG} ==="
fi
exit "$rc"
