#!/bin/bash
# RooTitanium — innesta il decoder video droidmedia nel build tree di Chromium.
#
# Perche' uno script e non una patch: i sorgenti canonici stanno in
# ../droidmedia/ e sono ~500 righe. Tenerli ANCHE dentro una patch scritta a mano
# vorrebbe dire due copie che si disallineano al primo tocco. Qui la copia e' una
# sola, e lo script la porta nel tree insieme al cablaggio.
# Quando il decoder sara' collaudato si potra' congelare tutto in patches/0305.
#
# IDEMPOTENTE: rilanciarlo non fa danni, e va rilanciato dopo ogni rigenerazione
# del build tree (come apply-build-fixes.sh).
#
# Uso, dalla workstation:
#   ./apply-droidmedia.sh          # innesta
#   ./apply-droidmedia.sh --check  # dice solo se e' innestato
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
VER=${VER:-6.8.4}
BT=$REPO/packaging/qt6-qtwebengine-sfos/build/BUILD/qt6-qtwebengine-$VER/upstream
SRC=$REPO/packaging/qt6-qtwebengine-sfos/droidmedia
CR=$BT/src/3rdparty/chromium

die() { echo "ERRORE: $*" >&2; exit 1; }
[ -d "$CR" ] || die "build tree non trovato: $CR (VER=$VER giusto?)"
[ -d "$SRC" ] || die "sorgenti del decoder non trovati: $SRC"

FILTERS_GN=$CR/media/filters/BUILD.gn
FACTORY=$CR/media/renderers/default_decoder_factory.cc

if [ "${1:-}" = "--check" ]; then
    ok=0
    [ -f "$CR/media/filters/droid_video_decoder.cc" ] && echo "✓ sorgenti nel tree" || { echo "✗ sorgenti assenti"; ok=1; }
    grep -q droid_video_decoder "$FILTERS_GN" && echo "✓ GN cablato" || { echo "✗ GN non cablato"; ok=1; }
    grep -q DroidVideoDecoder "$FACTORY" && echo "✓ factory cablata" || { echo "✗ factory non cablata"; ok=1; }
    exit $ok
fi

# ── 1) i sorgenti nel tree ───────────────────────────────────────────────────
cp "$SRC/droid_video_decoder.cc" "$SRC/droid_video_decoder.h" "$CR/media/filters/"
echo "→ sorgenti copiati in media/filters/"

# ── 2) media/filters/BUILD.gn: pkg_config + sorgenti ─────────────────────────
# Il .pc del target da' -I/usr/include/droidmedia -ldroidmedia -ldl. Il
# -ldroidmedia e' il shim STATICO (libdroidmedia.a): non lascia dipendenze .so
# nell'RPM, il caricamento della libreria Android avviene a runtime via hybris.
if ! grep -q droid_video_decoder "$FILTERS_GN"; then
    python3 - "$FILTERS_GN" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()

# il pkg_config va dichiarato prima del target
anchor = 'jumbo_source_set("filters") {'
block = '''# RooTitanium: decodifica video hardware via droidmedia (SailfishOS).
# Il .pc arriva da droidmedia-devel installato nel target sb2.
pkg_config("droidmedia_config") {
  packages = [ "droidmedia" ]
}

'''
assert anchor in s, "target filters non trovato"
s = s.replace(anchor, block + anchor, 1)

# i sorgenti, accanto agli altri decoder condizionali
vpx = '''  if (media_use_libvpx) {
    sources += [
      "vpx_video_decoder.cc",
      "vpx_video_decoder.h",
    ]
    deps += [ "//third_party/libvpx" ]
  }
'''
ours = '''  # RooTitanium: su SailfishOS la decodifica hardware passa da droidmedia.
  # Nessun flag GN nuovo: questo albero si costruisce solo per SFOS.
  if (is_linux) {
    sources += [
      "droid_video_decoder.cc",
      "droid_video_decoder.h",
    ]
    configs += [ ":droidmedia_config" ]
  }

'''
assert vpx in s, "blocco libvpx non trovato"
s = s.replace(vpx, vpx + '\n' + ours, 1)
open(p, 'w', encoding='utf-8').write(s)
PY
    echo "→ media/filters/BUILD.gn cablato"
else
    echo "= media/filters/BUILD.gn gia' cablato"
fi

# ── 3) default_decoder_factory.cc: il nostro PRIMA dei tre software ──────────
if ! grep -q DroidVideoDecoder "$FACTORY"; then
    python3 - "$FACTORY" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()

inc = '#include "media/filters/decrypting_video_decoder.h"'
assert inc in s, "include di riferimento non trovato"
s = s.replace(inc, inc + '\n#include "media/filters/droid_video_decoder.h"', 1)

# Va inserito PRIMA di libvpx/dav1d/ffmpeg: DecoderSelector prova in ordine,
# quindi se il nostro Initialize() rifiuta si ripiega da solo sul software.
vpx = '''#if BUILDFLAG(ENABLE_LIBVPX)
  video_decoders->push_back(std::make_unique<OffloadingVpxVideoDecoder>());
#endif'''
ours = '''  // RooTitanium: decodifica hardware via droidmedia (SailfishOS). Va PRIMA dei
  // tre decoder software perche' DecoderSelector prova la lista in ordine: se
  // Initialize() rifiuta -- device senza droidmedia, codec non supportato dal
  // vendor -- si scende da solo al software, senza logica di fallback nostra.
  if (DroidVideoDecoder::PlatformSupported()) {
    video_decoders->push_back(std::make_unique<DroidVideoDecoder>());
  }

'''
assert vpx in s, "blocco libvpx nella factory non trovato"
s = s.replace(vpx, ours + vpx, 1)
open(p, 'w', encoding='utf-8').write(s)
PY
    echo "→ default_decoder_factory.cc cablata"
else
    echo "= default_decoder_factory.cc gia' cablata"
fi

echo
echo "Innesto completato. Verifica con: $0 --check"
