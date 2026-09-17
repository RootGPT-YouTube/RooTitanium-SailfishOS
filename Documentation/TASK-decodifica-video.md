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

### Fase 0 — il cancello: quanto costa davvero un 1080p (ore)
Prima di spendere settimane, misurare con `rt-gpu-sampler.sh` + `top -H` la CPU
su un 1080p VP9 e su un H.264. Se il consumo non giustifica il lavoro, la task si
chiude qui. ⚠️ `ged_kpi` su questo device dà solo zeri: niente split per-frame.

### Fase 1 — dove si aggancia in Chromium 122 (giorni, INDAGINE APERTA)
Punto meno chiaro e primo vero rischio tecnico: individuare il punto di
registrazione di un `media::VideoDecoder` custom nella pipeline di QtWebEngine
(media gira in-process, quindi la via `GpuMojoMediaClient` potrebbe non essere
quella giusta). Da leggere nel nostro tree prima di scrivere una riga.

### Fase 2 — il decoder (settimane)
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
