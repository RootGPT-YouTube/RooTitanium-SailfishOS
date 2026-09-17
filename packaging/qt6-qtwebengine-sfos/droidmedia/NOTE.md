# Decoder video droidmedia — stato

`droid_video_decoder.{h,cc}` è la **Fase 2** di
`Documentation/TASK-decodifica-video.md`.

Vivono qui, tracciati in git, e NON nel build tree di Chromium: quel tree si
rigenera e si porterebbe via tutto (è la lezione delle ~10 fix della Fase 2 del
2026, che erano edit volatili nel BUILD e vanno riapplicate a ogni rigenerazione).
Entreranno in `media/filters/` tramite una patch numerata in `../patches/`,
insieme al cablaggio GN e alla riga in `DefaultDecoderFactory`.

## 🔴 Stato: MAI COMPILATO

Prima bozza. I nomi delle API sono stati verificati **a mano** contro l'albero
6.8.4 — e tre erano sbagliati, poi corretti:
- i piani in 122 sono `VideoFrame::kYPlane/kUPlane/kVPlane`, non `Plane::kY`;
- `DecoderBuffer` espone `data_size()`, non `size()`;
- le costanti droidmedia (`HW_ONLY = 0x2`, `NO_MEDIA_BUFFER = 0x8`, `LOOP_OK`,
  `DroidMediaRect`) sono invece risultate corrette.

Ma la verifica a mano non è un compilatore: aspettarsi altri errori al primo
build vero.

## Cosa manca prima di poterlo provare
1. cablaggio GN: compilare il file e aggiungere `pkg-config droidmedia`
   (`-I/usr/include/droidmedia -ldroidmedia -ldl`, link **statico** del shim);
2. la riga in `DefaultDecoderFactory::CreateVideoDecoders()` che lo inserisce
   **prima** dei tre decoder software;
3. una build completa (~5 h, con guardia VRM).

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
