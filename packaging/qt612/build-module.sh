#!/bin/bash
# Compila un modulo Qt 6.12.0 nel target sb2 clonato e lo installa in /usr del target.
#   build-module.sh MODULO [argomenti cmake extra]      (ARCH=aarch64|armv7hl)
# Percorsi e opzioni = quelli di %cmake_qt6 (qt6-rpm-macros) dei pacchetti piggz/chum,
# ma Release senza -g (si strippa comunque nel bundle).
set -euo pipefail
R=$(cd "$(dirname "$0")/../.." && pwd)
M=$1; shift
ARCH=${ARCH:-aarch64}
case $ARCH in
  aarch64) T=SailfishOS-5.1.0.11-aarch64-qt612; L=lib64; MARCH=-march=armv8-a ;;
  armv7hl) T=SailfishOS-5.1.0.11-armv7hl-qt612; L=lib;   MARCH="-march=armv7-a -mfloat-abi=hard -mfpu=neon -mthumb" ;;
esac
SRC=$R/scratch/qt612-src/$M-everywhere-src-6.12.0
BLD=$R/scratch/qt612/build-$ARCH/$M
LOG=$R/scratch/qt612/log-$ARCH-$M.log
mkdir -p $BLD
FL="-O2 -pipe -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector --param=ssp-buffer-size=4 $MARCH"
E="docker exec -u mersdk sailfish-sdk-build-engine_RootGPT"
{
echo "=== $(date '+%F %T') configure $M ($ARCH)"
$E bash -c "cd $BLD && CFLAGS='$FL' CXXFLAGS='$FL' sb2 -t $T cmake --fresh -S $SRC -B $BLD -GNinja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_SHARED_LIBS=ON \
  -DINSTALL_ARCHDATADIR=/usr/$L/qt6 -DINSTALL_BINDIR=/usr/$L/qt6/bin -DINSTALL_LIBDIR=/usr/$L \
  -DINSTALL_LIBEXECDIR=/usr/$L/qt6/libexec -DINSTALL_DATADIR=/usr/share/qt6 \
  -DINSTALL_INCLUDEDIR=/usr/include/qt6 -DINSTALL_EXAMPLESDIR=/usr/$L/qt6/examples \
  -DINSTALL_MKSPECSDIR=/usr/$L/qt6/mkspecs -DINSTALL_PLUGINSDIR=/usr/$L/qt6/plugins \
  -DINSTALL_QMLDIR=/usr/$L/qt6/qml -DINSTALL_SYSCONFDIR=/etc/xdg \
  -DINSTALL_TRANSLATIONSDIR=/usr/share/qt6/translations -DINSTALL_DOCDIR=/usr/share/doc/qt6 \
  -DQT_GENERATE_SBOM=OFF -DQT_DISABLE_RPATH=TRUE -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF \
  -DQT_INSTALL_EXAMPLES_SOURCES=OFF $*"
echo "=== $(date '+%F %T') build $M"
# Sotto sb2 alcuni strumenti Qt (qmltyperegistrar, rcc...) lasciano file con
# permessi 000 (bug gia' visto sulla 6.8.4): se la build fallisce e ce ne sono,
# si sistemano e si riprende, fino a 30 volte.
# sorvegliante: corregge i 000 mentre la build gira (riduce i giri di ripresa)
( while sleep 3; do find $BLD -type f -perm 000 -exec chmod 644 {} + 2>/dev/null; done ) &
SORV=$!; trap 'kill $SORV 2>/dev/null' EXIT
for tentativo in $(seq 1 30); do
  inizio=$(wc -l < $LOG)
  if $E bash -c "cd $BLD && sb2 -t $T cmake --build $BLD -j12 -- -k 0"; then break; fi
  n=$(find $BLD -type f -perm 000 | wc -l)
  # errori di questo giro che NON sono di permesso = errore vero → stop
  veri=$(tail -n +$((inizio+1)) $LOG | grep -E "error:|Error copying|Unable to open" | grep -vcE "Permission denied|Error copying|Unable to open" || true)
  if [ "$veri" -gt 0 ]; then echo "build fallita: $veri errori non di permesso"; exit 1; fi
  echo "=== $(date '+%F %T') $n file con permessi 000: chmod 644 e riprendo (tentativo $tentativo)"
  find $BLD -type f -perm 000 -exec chmod 644 {} +
  [ $tentativo -lt 30 ] || { echo "troppi tentativi"; exit 1; }
done
echo "=== $(date '+%F %T') install $M"
$E bash -c "cd $BLD && sb2 -t $T -m sdk-install -R cmake --install $BLD"
echo "=== $(date '+%F %T') FATTO $M"
} > $LOG 2>&1
