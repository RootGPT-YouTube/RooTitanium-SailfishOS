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

REPO=https://repo.sailfishos.org/obs/sailfishos:/chum:/testing/5.1_aarch64/aarch64
RPM=qt6-sfos-maliit-platforminputcontext-1.0.1+qt6.20241010182000.1.g9bb86e6-1.2.1.bso.aarch64.rpm
SHA_RPM=821c9d25efa018794d9367275cd8aaba64f175443f2d90d4043a00da033083d1
SHA_SO=609a89dbcd64fb2ef527dcae9ca3adee2d825586131a0917b1d9c880a2624c55
SO=usr/lib64/qt6/plugins/platforminputcontexts/libmaliitplatforminputcontextplugin.so

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
