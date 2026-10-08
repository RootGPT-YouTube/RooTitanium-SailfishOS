#!/bin/bash
# Porta nel bundle il plugin input-context di Maliit per Qt6, che ci dà la
# TASTIERA DI SISTEMA di SailfishOS al posto della QtVirtualKeyboard in-app.
#
# PERCHE' scaricarlo invece di tenerlo nel repo: è un binario di terze parti e
# il repo è pubblico. Qui c'è la provenienza verificabile (URL + sha256), non
# una copia opaca. Il pacchetto sta in chum:TESTING, non in Chum stabile: un
# utente qualunque non ce l'ha, quindi non possiamo dichiararlo come dipendenza
# dell'RPM — ce lo portiamo dentro il bundle e lo carichiamo dai nostri path
# (qt.conf resta invariato: i plugin Qt6 di sistema restano fuori).
#
# Licenza LGPLv2: la distribuzione dentro il nostro RPM è consentita; accredito e
# link ai sorgenti in NOTICE.md. Il plugin dipende solo da Qt6 Core/Gui/Quick/DBus
# (tutte nel bundle) e parla con maliit-server via DBus.
#
# Uso: ./fetch-maliit-plugin.sh [dir-bundle]   (default: scratch/webengine-bundle)
set -eu

# ARCH=armv7hl ./fetch-maliit-plugin.sh <bundle> per il pacchetto a 32 bit.
# Lo SHA dell'RPM armv7hl e' quello dei metadati del repo (primary.xml, 8 ott 2026).
ARCH=${ARCH:-aarch64}
PKGVER=1.0.1+qt6.20241010182000.1.g9bb86e6-1.2.1.bso
case "$ARCH" in
  aarch64) SHA_RPM=821c9d25efa018794d9367275cd8aaba64f175443f2d90d4043a00da033083d1
           SHA_SO=609a89dbcd64fb2ef527dcae9ca3adee2d825586131a0917b1d9c880a2624c55
           LIBDIR=lib64 ;;
  armv7hl) SHA_RPM=ba226f098d3d76bccb6d6c2ffbc23a981a6cbb1c2fb91d207c306f723abd916c
           SHA_SO=460b934272d3789f62e9930eb0faae2c6b786cfb87586d02b19286455351f186
           LIBDIR=lib ;;
  *) echo "ARCH sconosciuta: $ARCH"; exit 1 ;;
esac
REPO=https://repo.sailfishos.org/obs/sailfishos:/chum:/testing/5.1_$ARCH/$ARCH
RPM=qt6-sfos-maliit-platforminputcontext-$PKGVER.$ARCH.rpm
SO=usr/$LIBDIR/qt6/plugins/platforminputcontexts/libmaliitplatforminputcontextplugin.so

R=$(cd "$(dirname "$0")/../.." && pwd)
BUNDLE=${1:-$R/scratch/webengine-bundle}
[ -d "$BUNDLE" ] || { echo "bundle inesistente: $BUNDLE"; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
echo "== scarico $RPM"
curl -sfL "$REPO/$RPM" -o "$TMP/$RPM"
echo "$SHA_RPM  $TMP/$RPM" | sha256sum -c - || { echo "CHECKSUM RPM NON CORRISPONDE — non installo"; exit 1; }

( cd "$TMP" && rpm2cpio "$RPM" | cpio -idm --quiet )
echo "$SHA_SO  $TMP/$SO" | sha256sum -c - || { echo "CHECKSUM PLUGIN NON CORRISPONDE — non installo"; exit 1; }

DEST=$BUNDLE/plugins/platforminputcontexts
mkdir -p "$DEST"
cp -f "$TMP/$SO" "$DEST/"
chmod 755 "$DEST/libmaliitplatforminputcontextplugin.so"
echo "== installato in $DEST"
ls -l "$DEST"
