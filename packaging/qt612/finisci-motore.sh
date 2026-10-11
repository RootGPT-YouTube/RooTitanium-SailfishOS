#!/bin/bash
# Dopo la build del motore 6.140: installa nel target …-qt612, compila
# webengine-smoke contro 6.12 e monta il bundle (assembla-bundle-qt612.py).
# Dalla workstation:  ARCH=aarch64|armv7hl packaging/qt612/finisci-motore.sh
# Installa per cartella (core, process, webenginequick): QtPdf non si compila
# (il bundle non lo usa) e un "cmake --install" di tutto l'albero lo cercherebbe.
set -euo pipefail
R=$(cd "$(dirname "$0")/../.." && pwd)
ARCH=${ARCH:-aarch64}
T=SailfishOS-5.1.0.11-$ARCH-qt612
B=$R/scratch/qt612/build-$ARCH/qtwebengine
E="docker exec -u mersdk sailfish-sdk-build-engine_RootGPT"
for d in core process webenginequick; do
  echo "== install src/$d"
  $E bash -c "cd $B && sb2 -t $T -m sdk-install -R cmake --install $B/src/$d" | grep -v WARNING | tail -2
done
echo "== webengine-smoke"
$E bash -c "ARCH=$ARCH bash $R/packaging/qt612/build-smoke-qt612.sh" 2>&1 | grep -v WARNING | tail -2
echo "== bundle"
$E python3 $R/packaging/qt612/assembla-bundle-qt612.py --arch $ARCH \
  --smoke $R/scratch/qt612/build-$ARCH/smoke/webengine-smoke \
  --position $R/packaging/rt-position-plugin/build-$ARCH-qt612/libqtposition_rtgeoclue1.so \
  --maliit $R/scratch/qt612/build-$ARCH/maliit/libmaliitplatforminputcontextplugin.so
