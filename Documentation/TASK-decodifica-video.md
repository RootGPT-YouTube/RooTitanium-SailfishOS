# Decodifica video hardware via droidmedia

**Aperta il 17/09/2026.** Decisione dell'utente: strada **droidmedia**, non V4L2.

## Perché questa task esiste (e perché NON esiste quella sulla GPU)

La richiesta di partenza era «far funzionare RooTitanium a livello hardware».
Misurando si è visto che **il browser è già in accelerazione hardware**: GPU al 30%
di media con picchi al 90%, frequenza che sale da 300 a 950 MHz, 5609 import di
texture zero-copy in una sessione di 4 minuti. Dettagli e trappole in
`Documentation/` e nella nota di memoria `rootitanium-accelerazione-hardware`.

L'unica cosa che oggi gira davvero in software è la **decodifica video**, e non
per una scelta a runtime: in `media/gpu/args.gni` di Chromium 122

```
use_v4l2_codec = is_chromeos_lacros && (arm || arm64)
use_vaapi      = ... && (x86 || x64)
```

Per Linux/aarch64 non-Lacros valgono **entrambi false per costruzione**, e
`media/gpu/BUILD.gn:195` include i sorgenti V4L2 solo `if (use_v4l2_codec)`. Quel
codice non entra proprio nel binario.

## Perché droidmedia e non V4L2

| | Portabilità |
|---|---|
| **droidmedia** | **Tutti i device SailfishOS.** È un pacchetto di sistema presente su ogni porting; ci gira sopra sailfish-browser/Gecko via `gmp-droid`. Astrae il codec del vendor dietro un'unica API C. |
| **V4L2** | **Solo il POCO.** Legata a `mtk-vcodec` + daemon vendor `vpud` di MediaTek. Sull'X10 III (Qualcomm) non funzionerebbe. |

Una sola implementazione, tutti i device: è il motivo della scelta.

## Verificato il 17/09 (non ripetere)

- Sul POCO: `/dev/video0` = `mtk-vcodec-dec`, `/dev/video1` = enc, daemon `vpud`
  in esecuzione, `droidmedia-0.20260522` e `gstreamer1.0-droid` installati.
- Codec Android del device (`media_codecs_mediatek_video.xml`):
  `OMX.MTK.VIDEO.DECODER.{AVC,HEVC,VP9,VPX,MPEG2,MPEG4,VC1}` e `c2.mtk.*`.
  ⚠️ **AV1 in hardware NON c'è** — e YouTube lo serve volentieri.
- `droidmedia-devel-0.20260522.0-1.12.1.jolla.aarch64` è **disponibile** nel repo
  `adaptation-common` (stessa versione della lib installata): gli header si
  possono installare nel target sb2.
- `libdroidmedia.so` sta in `/usr/libexec/droid-hybris/system/lib64/` ed esporta
  **18 simboli C** (`droid_media_codec_create_decoder`, `_drain`, `_flush`,
  `_get_buffer_queue`, …), interfaccia C non manglata.
- Precedente da cui copiare: `github.com/sailfishos/gmp-droid`. Usa
  `droid_media_codec_*` con `DROID_MEDIA_CODEC_HW_ONLY|NO_MEDIA_BUFFER`, codec
  H264/VP8/VP9. ⚠️ **Nemmeno gmp-droid è zero-copy**: riporta i frame in I420 in
  RAM con la CPU (`droid_media_convert_to_i420`). Il guadagno è reale ma non è
  magia: si toglie la decodifica dalla CPU, non la copia.

## Piano

### Fase 0 — il cancello: ✅ SUPERATO il 17/09
Misurato sul POCO, trailer 1080p reale (1920x1080), 30 s di campionamento su
TUTTI i processi dell'app:

```
browser     26%
renderer    93%   ← di cui ~63% in 4 thread ThreadPoolForeg
            ----
TOTALE     120%   (100% = un core; il device ne ha 8)
```

I quattro `ThreadPoolForeg` sono `OffloadingVpxVideoDecoder`: **è la decodifica
VP9 in software**, ed è la metà abbondante del costo totale dell'app.

Codec verificato agganciando `MediaSource.prototype.addSourceBuffer` via CDP:
`video/webm; codecs="vp09.00.51.08.01.01.01.01.00"` = **VP9 profilo 0, 8 bit**
(audio Opus). ⭐ VP9 **è** nella lista hardware del POCO
(`OMX.MTK.VIDEO.DECODER.VP9`): il caso reale è coperto, non è AV1.

Riproduzione già fluida (4 frame persi su 3120, 0,13%), quindi il guadagno atteso
non è fluidità ma **batteria e calore** — che è il fastidio reale riferito
dall'utente, ed è la ragione per cui la task è stata approvata.

⚠️ `ged_kpi` su questo device dà solo zeri: niente split per-frame.
⚠️ **CLK_TCK = 100**: la percentuale CPU da `/proc/.../stat` è `tick / secondi`.
La prima versione del campionatore moltiplicava per 10 e gonfiava tutto di dieci
volte. Numeri assurdi (>800% su 8 core) = quasi certamente questo errore.

### Fase 1 — dove si aggancia: ✅ TROVATO il 17/09
`media/renderers/default_decoder_factory.cc`, funzione
`DefaultDecoderFactory::CreateVideoDecoders()`: costruisce la **lista ordinata**
che `DecoderSelector` prova in sequenza.

```cpp
if (external_decoder_factory_ && gpu_factories && ...)      // hw, oggi vuoto
#if BUILDFLAG(ENABLE_LIBVPX)         OffloadingVpxVideoDecoder      // VP9
#if BUILDFLAG(ENABLE_DAV1D_DECODER)  OffloadingDav1dVideoDecoder    // AV1
#if BUILDFLAG(ENABLE_FFMPEG_VIDEO_DECODERS) FFmpegVideoDecoder      // H.264
```

Il nostro decoder va inserito **prima** di questi tre. Due proprietà che
regaliamo gratis così:
- **ripiego automatico**: se `Initialize()` fallisce (droidmedia assente, codec
  non supportato dal device, errore del vendor) `DecoderSelector` passa al
  successivo da solo — nessuna logica di fallback da scrivere;
- **un RPM solo per tutti i device**, coerente con la scelta droidmedia.

⚠️ La decodifica sta nel processo **renderer**, non nel browser: chi misura deve
campionare tutti i processi dell'app, altrimenti non vede niente (errore fatto e
corretto il 17/09).

### Fase 1-bis — ambiente di build: ✅ PRONTO, non c'era niente da aggiungere (17/09)
`adaptation-common` **era già configurato** nel target
`SailfishOS-5.1.0.11-aarch64.default` (come `plugin:ssu?repo=adaptation-common`) e
**`droidmedia-devel-0.20260522.0-1.12.1.jolla` era già installato**, stessa
versione della libreria sul POCO. Contenuto:

```
/usr/include/droidmedia/{droidmedia,droidmediacodec,droidmediaconvert,...}.h
/usr/lib64/libdroidmedia.a
/usr/lib64/pkgconfig/droidmedia.pc   → -I/usr/include/droidmedia -ldroidmedia -ldl
/usr/share/droidmedia/hybris.c
```

⭐ **`hybris.c` decide la questione «link diretto o dlopen»**, e la risposta è:
nessuna delle due come le immaginavamo. `libdroidmedia.so` è una libreria
**Android** e non si può caricare col loader glibc; il modo ufficiale è il shim
`hybris.c` di Jolla, che fa `dlopen("libhybris-common.so.1")`, ne prende
`android_dlopen`/`android_dlsym` e risolve i simboli droidmedia in puntatori a
funzione. `libdroidmedia.a` è quel shim già compilato.

Conseguenze, tutte a nostro favore:
- si linka **statico** (`.a`): nessuna dipendenza `.so` nell'RPM, il bundle resta
  self-contained e **un RPM solo per tutti i device**, come voluto;
- il caricamento è comunque a runtime, quindi dove droidmedia manca si degrada;
- ⚠️ non serve inventarsi un `dlopen` a mano: usare il shim upstream.

### ⚠️ VINCOLO DI PORTABILITÀ (requisito esplicito dell'utente, 17/09)

«L'importante è che funzioni sugli hardware che supportano SFOS, non solo sul
mio.» Non è un desiderata: è il criterio con cui questa task va progettata e
collaudata.

Cosa ce la dà, già oggi:
- **droidmedia è parte dell'adattamento hardware** di ogni porting hybris: non è
  roba del POCO, c'è ovunque ci sia un droid-hal;
- **`droid_media_codec_is_supported()` interroga il device a runtime**: nessun
  codec cablato da noi. Ogni telefono ottiene quello che il suo hardware sa fare
  (H.264 praticamente ovunque, VP9/HEVC dove c'è), e per il resto va in software;
- **link statico del shim** (`libdroidmedia.a`): nessuna dipendenza `.so`
  nell'RPM → un pacchetto solo, installabile su tutti;
- **ripiego gratis**: se `Initialize()` rifiuta, `DecoderSelector` passa al
  decoder software successivo.

🔴 **Il pericolo, verificato leggendo `hybris.c`**: il shim **non degrada, fa
`abort()`**. `__resolve_sym` fa `assert(ptr != NULL)` e poi `abort()`, e
`__load_library` aborta se manca libhybris o se `libdroidmedia.so` non si carica.
Su un porting **nativo** (senza HAL Android) o con un droidmedia più vecchio che
non ha un simbolo che usiamo, la prima chiamata **ammazzerebbe il browser**
invece di ripiegare.

**Requisito di progetto che ne discende**: mai chiamare una funzione droidmedia
alla cieca. Prima una **sonda nostra**, fatta con `dlopen` normale:
1. `dlopen("libhybris-common.so.1")` e presenza di `android_dlopen`/`android_dlsym`;
2. `android_dlopen("libdroidmedia.so")` riuscito;
3. solo allora la prima chiamata vera.
Se uno dei tre passi fallisce, `Initialize()` ritorna errore e non si tocca più
droidmedia per il resto della sessione. Esiste anche `__try_resolve_sym`, che
ritorna NULL invece di abortire: da preferire ovunque possibile.

**Collaudo minimo prima di dire che è fatta**: POCO M4 Pro (Mali/MediaTek) **e**
Xperia 10 III (Adreno/Qualcomm), più una verifica che su un device senza
droidmedia l'app parta e riproduca in software.

### Fase 2 — il decoder (settimane)

**Mappatura sul contratto `media::VideoDecoder`** (API verificata in
`droidmediacodec.h` del target):

| Chromium | droidmedia |
|---|---|
| `Initialize()` | `droid_media_codec_is_supported(meta, false)` → `droid_media_codec_create_decoder` → `set_data_callbacks` → `start`. ⭐ `is_supported` dà il rifiuto pulito che fa scattare il ripiego software di `DecoderSelector`. |
| `Decode()` | `droid_media_codec_queue` |
| `Reset()` | `droid_media_codec_flush` |
| fine flusso | `droid_media_codec_drain` |
| output | callback dati → `VideoFrame`; conversione in `droidmediaconvert.h` |
| `Destroy` | `droid_media_codec_stop` + `droid_media_codec_destroy` |

Resta da progettare: pompa di `droid_media_codec_loop` su quale thread, gestione
del cambio risoluzione (`droid_media_codec_get_output_info` + `DroidMediaRect`
di crop), e il ciclo di vita dei buffer.

### Fase 2 (dettaglio originale)
`media::VideoDecoder` che parla droidmedia, sul modello gmp-droid: Initialize/
Decode/Reset/flush, gestione EOS e cambio risoluzione, mapping dei formati,
consegna di `VideoFrame` I420.

### Fase 3 — impacchettamento
⚠️ `droidmedia` è di sistema e **device-specific: non va bundlato**. Valutare
`dlopen` + lookup dei simboli a runtime invece del link diretto: niente dipendenza
a build-time, l'RPM resta uno solo per tutti i device, e dove droidmedia manca si
degrada da soli alla decodifica software invece di non partire.

## Rischi
- Nessun progetto SailfishOS/Halium risulta aver già integrato un decoder hardware
  in un Chromium desktop-style: siamo i primi, quindi stime larghe.
- Il guadagno non tocca AV1 sul POCO (non c'è in hardware).
- La copia I420 resta a carico della CPU.
