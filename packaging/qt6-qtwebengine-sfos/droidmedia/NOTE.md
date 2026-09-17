# Decoder video droidmedia — stato

`droid_video_decoder.{h,cc}` è la **Fase 2** di
`Documentation/TASK-decodifica-video.md`.

Vivono qui, tracciati in git, e NON nel build tree di Chromium: quel tree si
rigenera e si porterebbe via tutto (è la lezione delle ~10 fix della Fase 2 del
2026, che erano edit volatili nel BUILD e vanno riapplicate a ogni rigenerazione).
Entreranno in `media/filters/` tramite una patch numerata in `../patches/`,
insieme al cablaggio GN e alla riga in `DefaultDecoderFactory`.

## ✅ Stato: COMPILA E SI LINKA (18/09, build di 4h14m, exit 0)

Verificato su `libQt6WebEngineCore.so.6.8.3` (1,34 GB) appena prodotta:
- `media::DroidVideoDecoder::*` presenti (Initialize, OnDataAvailable,
  PlatformSupported, LoopThreadMain, ...);
- `droid_media_codec_create_decoder` / `is_supported` / `queue` sono `T`, cioe'
  **statici dentro la libreria**: il shim `libdroidmedia.a` e' entrato;
- **zero `NEEDED`** contenenti "droid" e **zero simboli droidmedia undefined** →
  il requisito «un RPM solo per tutti i device» regge alla prova dei fatti.

⚠️ Questo dice che il codice compila e si linka, NON che funzioni: nessun
fotogramma e' ancora stato decodificato. I punti deboli qui sotto sono intatti.

### Gli errori veri, e cosa hanno insegnato

1. **`droidmedia-devel` non era nel target dove si compila.** Era installato
   negli snapshot `…-aarch64.default`, mentre `build-con-guardia.sh` usa il
   target **base**: `pkg-config` li' diceva "No package 'droidmedia' found". La
   verifica del 17/09 era stata fatta sullo snapshot sbagliato. Installato nel
   base (`sb2 -t <base> -m sdk-install -R zypper in droidmedia-devel`).
2. **`pkg_config()` non e' una funzione GN nativa**: senza
   `import("//build/config/linux/pkg_config.gni")` il gen muore con "Unknown
   function". Gli altri `BUILD.gn` di `media/` lo importano tutti.
3. **`DroidMediaCodecData` NON e' forward-dichiarabile**: e' una struct
   ANONIMA (`typedef struct { ... } X;`). La forward declaration creava un tipo
   fantasma → "invalid conversion" sul puntatore a funzione + "incomplete type".
   Solo `DroidMediaCodec` e `DroidMediaConvert` hanno un nome
   (`typedef struct _DroidMediaCodec ...`). Cura: il tipo resta confinato nel
   `.cc` e il callback C e' una **lambda senza cattura** dentro `Initialize()`,
   che si converte nella firma esatta e, stando in un metodo membro, puo'
   chiamare lo statico privato. Niente header droidmedia dentro `media/` (in
   jumbo verrebbe fuso con mezzo `media/renderers`), niente cast di puntatori
   a funzione.

### ⚠️ Il gn-regen spazza via le fix persistenti
Toccare `BUILD.gn` fa scattare il `gn gen`, che **riscrive `toolchain.ninja`**:
tornano i nomi `.rsp` oltre NAME_MAX (262 char > 255) e la build muore a meta'
con "File name too long". Rimedio gia' in casa:
`./apply-build-fixes.sh ninja`, ora ricordato anche in coda ad
`apply-droidmedia.sh`.

Stessa famiglia: il link del generatore V8 **sovrascrive il wrapper qemu-10**
col binario ELF. `fix_snapshot` testava `[ -f "$gen.real" ]` — cioe' "esiste il
backup?" invece di "il generatore e' il mio wrapper?" — e rispondeva "gia'
installato" mentre il wrapper non c'era piu', lasciando ricadere la build nel
`signal 5`. Corretto il 18/09: ora guarda se il file inizia per `#!`, e il
`.real` si aggiorna con `mv -f` (il binario appena linkato e' quello buono).

## Come iterare senza rifare 4 ore di build
Per gli errori del solo decoder basta ricompilare il suo oggetto jumbo:
```
sb2 -t SailfishOS-5.1.0.11-aarch64 ninja -j4 obj/media/filters/filters/filters_jumbo_6.o
```
~90 secondi a giro invece di ore. (Il nostro `.cc` finisce in
`gen/media/filters/filters_jumbo_6.cc`; se il numero cambia, cercarlo con
`grep -l droid_video_decoder gen/media/filters/*.cc`.)

## Stato precedente: MAI COMPILATO

Prima bozza. I nomi delle API sono stati verificati **a mano** contro l'albero
6.8.4 — e tre erano sbagliati, poi corretti:
- i piani in 122 sono `VideoFrame::kYPlane/kUPlane/kVPlane`, non `Plane::kY`;
- `DecoderBuffer` espone `data_size()`, non `size()`;
- le costanti droidmedia (`HW_ONLY = 0x2`, `NO_MEDIA_BUFFER = 0x8`, `LOOP_OK`,
  `DroidMediaRect`) sono invece risultate corrette.

Ma la verifica a mano non è un compilatore: aspettarsi altri errori al primo
build vero.

## Cablaggio: ✅ fatto (17/09) — `../scripts/apply-droidmedia.sh`

Idempotente, come `apply-build-fixes.sh`, e **va rilanciato dopo ogni
rigenerazione del build tree**. Fa tre cose: copia i sorgenti in
`media/filters/`, aggiunge a `media/filters/BUILD.gn` un `pkg_config`
(`droidmedia`) e i due file, e inserisce in
`DefaultDecoderFactory::CreateVideoDecoders()` il nostro decoder **prima** dei
tre software. `--check` dice solo se è innestato.

Perché uno script e non `patches/0305`: i sorgenti canonici sono ~500 righe e
tenerli anche dentro una patch scritta a mano vorrebbe dire due copie che si
disallineano al primo tocco. Quando il decoder sarà collaudato si potrà
congelare tutto in una patch vera.

Verificato che il cablaggio regge nel cross-build:
- `sb2 -t <target> pkg-config --cflags --libs droidmedia` →
  `-I/usr/include/droidmedia -ldroidmedia -ldl`;
- `args.gn` ha già `pkg_config="/usr/bin/pkg-config"` e la build gira **dentro**
  sb2, quindi quel pkg-config è quello del target, non dell'host;
- `-ldroidmedia` prende `libdroidmedia.a`, il shim **statico**: nessuna
  dipendenza `.so` nell'RPM.

## Cosa manca
Una **build completa** (~5 h, con guardia VRM, presidiata e di giorno). È il
primo momento in cui un compilatore guarderà questo codice.

## Punti deboli noti, già segnati nel codice
- **una copia di troppo**: `convert_to_i420` scrive un I420 contiguo e noi lo
  ricopiamo nei piani della `VideoFrame`. Nemmeno `gmp-droid` di Gecko è
  zero-copy, quindi partiamo alla pari, ma è il primo posto dove guadagnare.
- **ciclo di vita del buffer in `Decode()`**: ci appoggiamo alla copia di
  MediaCodec con `NO_MEDIA_BUFFER`. Se il collaudo mostrasse corruzione, serve
  `DroidMediaBufferCallbacks` per tenere il ref al `DecoderBuffer`.
- **`OnError` non segnala ancora niente** alla pipeline.
- `fps` nei metadati è messo a 30 fisso: il vendor lo usa solo per dimensionare.

## La parte da non toccare con leggerezza
`PlatformSupported()` è ciò che tiene in piedi il requisito «deve funzionare su
tutti gli hardware SFOS». Il shim `hybris.c` **aborta** invece di degradare, e
quella sonda in quattro passi (solo `dlopen` normale, mai una funzione
droidmedia) è l'unica cosa che impedisce al browser di morire su un porting
nativo o con un droidmedia più vecchio.
