#!/bin/bash
# Configure di QtWebEngine 6.140 (Chromium 140) sopra Qt 6.12 — task 2.5 #6.
# Dalla workstation:  ARCH=aarch64|armv7hl ./configure-6.140.sh
# Sorgenti: scratch/qtwebengine-6.140 (ramo 6.140.0, gia' patchato: patch SFOS
# di Rinigus + patches-6.140/ + innesto droidmedia). Build fuori dai sorgenti,
# una cartella per arch, nel target sb2 clonato con Qt 6.12 (…-qt612).
# NINJAFLAGS (default -j10) finisce in build.ninja e limita il ninja INTERNO di
# Chromium: senza, usa nproc dell host +2 (=34) e satura i 31 GB (OOM 10 ott).
# QtPdf spento di default (QTPDF=ON per riaccenderlo): il bundle non lo usa e
# il suo albero Chromium separato sono ~45.000 oggetti in piu (11 ott).
# Stesse feature della 6.8.4 (configure-only.sh); Rust spento esplicitamente.
# Dopo il configure: BT=<build> SRCT=<sorgenti> GNSUB_OVR=Release/<cpu>
#   TARGET_OVR=<target> ./apply-build-fixes.sh gn
set -euo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
ARCH=${ARCH:-aarch64}
case $ARCH in
  aarch64) T=SailfishOS-5.1.0.11-aarch64-qt612; L=lib64; MARCH=-march=armv8-a ;;
  armv7hl) T=SailfishOS-5.1.0.11-armv7hl-qt612; L=lib;   MARCH="-march=armv7-a -mfloat-abi=hard -mfpu=neon -mthumb" ;;
  *) echo "ARCH sconosciuta: $ARCH" >&2; exit 1 ;;
esac
SRC=$REPO/scratch/qtwebengine-6.140
BLD=$REPO/scratch/qt612/build-$ARCH/qtwebengine
mkdir -p "$BLD"
FL="-O2 -pipe -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector --param=ssp-buffer-size=4 $MARCH"
docker exec -u mersdk sailfish-sdk-build-engine_RootGPT bash -c "cd $BLD && NINJAFLAGS='${NINJAFLAGS:--j10}' CFLAGS='$FL' CXXFLAGS='$FL' \
 sb2 -t $T cmake --fresh -S $SRC -B $BLD -GNinja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_SHARED_LIBS=ON \
  -DCMAKE_TOOLCHAIN_FILE=/usr/$L/cmake/Qt6/qt.toolchain.cmake \
  -DINSTALL_ARCHDATADIR=/usr/$L/qt6 -DINSTALL_BINDIR=/usr/$L/qt6/bin -DINSTALL_LIBDIR=/usr/$L \
  -DINSTALL_LIBEXECDIR=/usr/$L/qt6/libexec -DINSTALL_DATADIR=/usr/share/qt6 \
  -DINSTALL_INCLUDEDIR=/usr/include/qt6 -DINSTALL_MKSPECSDIR=/usr/$L/qt6/mkspecs \
  -DINSTALL_PLUGINSDIR=/usr/$L/qt6/plugins -DINSTALL_QMLDIR=/usr/$L/qt6/qml \
  -DINSTALL_SYSCONFDIR=/etc/xdg -DINSTALL_TRANSLATIONSDIR=/usr/share/qt6/translations \
  -DQT_GENERATE_SBOM=OFF -DQT_DISABLE_RPATH=TRUE \
  -DFEATURE_qtpdf_build=${QTPDF:-OFF} -DFEATURE_webengine_developer_build=OFF \
  -DFEATURE_webengine_embedded_build=OFF -DFEATURE_webengine_extensions=ON \
  -DFEATURE_webengine_kerberos=OFF -DFEATURE_webengine_native_spellchecker=OFF \
  -DFEATURE_webengine_printing_and_pdf=ON -DFEATURE_webengine_proprietary_codecs=ON \
  -DFEATURE_webengine_system_icu=OFF -DFEATURE_webengine_system_libevent=ON \
  -DFEATURE_webengine_system_ffmpeg=OFF -DFEATURE_webengine_webrtc=ON \
  -DFEATURE_webengine_ozone_x11=OFF -DFEATURE_qtwebengine_widgets_build=OFF \
  -DFEATURE_qtpdf_widgets_build=OFF -DFEATURE_webengine_rust_build=OFF \
  -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF -DQT_INSTALL_EXAMPLES_SOURCES=OFF"
