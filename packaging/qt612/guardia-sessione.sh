#!/bin/bash
# Guardia VRM per una sessione di build Qt 6.12 (tante build in fila).
# Engine a 12 core; VRM >= 85 -> 2 core; <= 60 -> 12 core. Mai --cpus 0 (bug).
# Si ferma quando esiste il file STOP qui accanto (e rimette 12 core).
D=$(cd "$(dirname "$0")" && pwd); ENGINE=sailfish-sdk-build-engine_RootGPT; CHIP=it8689-isa-0a40
LOG=$D/guardia-vrm.log; rm -f $D/STOP
leggi() { sensors $CHIP 2>/dev/null | awk -F'[+.]' '/^VRM:/ {print $2}'; }
nota() { echo "$(date '+%F %T')  $*" >> $LOG; }
docker update --cpus 12 $ENGINE >/dev/null; rid=0; ult=0
nota "=== guardia avviata, VRM $(leggi)°C, engine 12 core ==="
while [ ! -f $D/STOP ]; do
  t=$(leggi)
  if [ -n "$t" ]; then
    if [ $rid -eq 0 ] && [ "$t" -ge 85 ]; then docker update --cpus 2 $ENGINE >/dev/null; rid=1; nota "VRM ${t}°C >= 85: engine a 2 core"
    elif [ $rid -eq 1 ] && [ "$t" -le 60 ]; then docker update --cpus 12 $ENGINE >/dev/null; rid=0; nota "VRM ${t}°C <= 60: engine a 12 core"; fi
    now=$(date +%s); [ $((now-ult)) -ge 600 ] && { nota "VRM ${t}°C regime $([ $rid -eq 1 ] && echo 2 || echo 12) core"; ult=$now; }
  else nota "lettura VRM fallita"; fi
  sleep 20
done
docker update --cpus 12 $ENGINE >/dev/null; nota "=== guardia fermata (STOP), engine 12 core ==="
