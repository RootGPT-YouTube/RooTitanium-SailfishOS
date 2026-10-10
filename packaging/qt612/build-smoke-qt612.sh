#!/bin/bash
# webengine-smoke (main.cpp) contro Qt 6.12 + QtWebEngine 6.140, nel target
# …-qt612 dove il motore e' stato installato (cmake --install). Da eseguire
# DENTRO l'engine come mersdk:  ARCH=aarch64 bash build-smoke-qt612.sh
set -e
R=$(cd "$(dirname "$0")/../.." && pwd)
ARCH=${ARCH:-aarch64}
case $ARCH in
  aarch64) T=SailfishOS-5.1.0.11-aarch64-qt612; L=lib64 ;;
  armv7hl) T=SailfishOS-5.1.0.11-armv7hl-qt612; L=lib ;;
esac
B=$R/scratch/qt612/build-$ARCH/smoke
mkdir -p $B; cp $R/smoke-test/main.cpp $B/; cd $B
V=6.12.0
I=/usr/include/qt6
INC="-I$I -I$I/QtCore -I$I/QtGui -I$I/QtQml -I$I/QtDBus -I$I/QtGui/$V -I$I/QtGui/$V/QtGui -I$I/QtCore/$V -I$I/QtCore/$V/QtCore -I$I/QtWebEngineCore -I$I/QtWebEngineQuick"
sb2 -t $T /usr/$L/qt6/libexec/moc $INC main.cpp -o main.moc
sb2 -t $T c++ -std=c++17 -fPIC -O2 $INC main.cpp -o webengine-smoke \
  -L/usr/$L -lQt6WebEngineQuick -lQt6WebEngineCore -lQt6Qml -lQt6DBus -lQt6Gui -lQt6Core -lwayland-client
sb2 -t $T strip webengine-smoke
file webengine-smoke
