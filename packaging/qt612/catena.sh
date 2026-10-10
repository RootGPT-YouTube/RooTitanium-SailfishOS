#!/bin/bash
# Compila in fila i moduli passati; si ferma al primo che fallisce. ARCH dall'ambiente.
D=$(cd "$(dirname "$0")" && pwd)
for m in "$@"; do
  echo "$(date '+%T') INIZIO $m"
  if ! $D/build-module.sh $m; then echo "$(date '+%T') FALLITO $m"; exit 1; fi
  echo "$(date '+%T') OK $m"
done
echo "$(date '+%T') CATENA COMPLETATA"
