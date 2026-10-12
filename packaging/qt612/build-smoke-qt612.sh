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
# Link visitati (blocco RT_VISITED_LINKS in main.cpp): header privati del
# profilo QML (installati) + header interni del core, che cmake --install non
# copia: si prendono dai sorgenti da cui e' compilato QUESTO motore.
WV=6.140.0
INC="$INC -I$I/QtWebEngineCore/$WV -I$I/QtWebEngineCore/$WV/QtWebEngineCore -I$I/QtWebEngineCore/$WV/QtWebEngineCore/private -I$I/QtWebEngineQuick/$WV -I$I/QtWebEngineQuick/$WV/QtWebEngineQuick -I$R/scratch/qtwebengine-6.140/src/core"
sb2 -t $T /usr/$L/qt6/libexec/moc $INC main.cpp -o main.moc
sb2 -t $T c++ -std=c++17 -fPIC -O2 $INC main.cpp -o webengine-smoke \
  -L/usr/$L -lQt6WebEngineQuick -lQt6WebEngineCore -lQt6Qml -lQt6DBus -lQt6Gui -lQt6Core -lwayland-client
sb2 -t $T strip webengine-smoke
file webengine-smoke
# __has_include fallisce in silenzio: se mancano gli header il blocco non entra
# e l'app perde la funzione senza errori. Meglio fermarsi qui.
sb2 -t $T nm -D webengine-smoke | grep -q deleteVisitedLinkDataForUrls \
  || { echo "ERRORE: blocco RT_VISITED_LINKS non compilato (header mancanti?)"; exit 1; }
echo "ok: link visitati compilati"
