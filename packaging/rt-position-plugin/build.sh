#!/bin/bash
# Compila il plugin di posizione (task 2.5 #4) via sb2. Da eseguire DENTRO l'engine:
#   docker exec -u mersdk sailfish-sdk-build-engine_RootGPT bash <repo>/packaging/rt-position-plugin/build.sh
# ARCH=armv7hl per il 32 bit. Output: libqtposition_rtgeoclue1.so qui accanto,
# da installare nel bundle in plugins/position/.
set -e
cd "$(dirname "$0")"
ARCH=${ARCH:-aarch64}
case "$ARCH" in
  aarch64) T=SailfishOS-5.1.0.11-aarch64.default; L=lib64 ;;
  armv7hl) T=SailfishOS-5.1.0.11-armv7hl;         L=lib ;;
esac
INC="-I/usr/include/qt6 -I/usr/include/qt6/QtCore -I/usr/include/qt6/QtDBus -I/usr/include/qt6/QtPositioning"
mkdir -p build-$ARCH
sb2 -t "$T" /usr/$L/qt6/libexec/moc $INC rtgeoclue1.cpp -o build-$ARCH/rtgeoclue1.moc
sb2 -t "$T" c++ -std=c++17 -fPIC -O2 -shared $INC -Ibuild-$ARCH rtgeoclue1.cpp \
  -o build-$ARCH/libqtposition_rtgeoclue1.so -L/usr/$L -lQt6Positioning -lQt6DBus -lQt6Core
sb2 -t "$T" strip build-$ARCH/libqtposition_rtgeoclue1.so
ls -l build-$ARCH/libqtposition_rtgeoclue1.so
