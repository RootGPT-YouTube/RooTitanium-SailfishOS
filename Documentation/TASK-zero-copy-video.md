# Zero-copy per il video decodificato in hardware

**Indagine del 19/09/2026.** Segue `TASK-decodifica-video.md`.

## 🔴 ESITO DEL CANCELLO Z0 (19/09, pomeriggio): NON PROCEDERE
Misurato il tetto: un lettore **già zero-copy** (gst-droid) consuma **più**
di RooTitanium con la copia, in tutte e tre le coppie. Lo zero-copy su questo
telefono **non porta batteria**: le fasi Z1-Z3 qui sotto restano solo come
riferimento, se un giorno servisse per altre ragioni (per esempio il 4K).
Dati in fondo, sezione «Z0: la misura».

## Il problema, in una riga
Il chip decodifica il frame in un buffer grafico (gralloc) del vendor. Da lì a
schermo oggi facciamo **più copie in CPU** di un frame da 3,1 MB, 30 volte al
secondo:

1. droidmedia con `NO_MEDIA_BUFFER`: MediaCodec in modalità ByteBuffer consegna
   il frame in memoria normale. È probabile una copia dentro il processo del
   vendor, **da verificare**;
2. `libyuv::I420Copy` nel renderer, verso la `VideoFrame` (codice nostro);
3. il compositor copia la `VideoFrame` software verso il processo GPU
   (`VideoResourceUpdater`);
4. `glTexSubImage2D` dei tre piani: il driver Mali copia di nuovo e riordina in
   tile.

Con lo zero-copy le quattro copie spariscono: la GPU **campiona direttamente il
buffer del decoder** e converte da YUV a RGB mentre disegna.

## ⚠️ Il tetto del guadagno (leggere prima di tutto)
Misura del 19/09: il video in hardware costa **+0,29 W** sopra l'app ferma
(2,80 → 3,09 W). Lo zero-copy può togliere **una parte** di quei 0,29 W, non di
più. La composizione GPU, l'audio, il demuxer e lo schermo restano. Stima
realistica: da −0,1 a −0,2 W, cioè il **3-6% del totale**. Non cambia la
batteria in modo radicale: è il pezzo che resta sul lato browser.

La voce più grossa misurata il 19/09 **non è nel browser**. Con l'app ferma un
core grande resta a 2 GHz (`mtkScnHanler`/`mtkpower`) e il telefono a riposo
con lo schermo acceso consuma 2,80 W. È un problema del porting.

## Verificato il 19/09 (non ripetere)

### Chromium in QtWebEngine usa EGL nativo, senza ANGLE
Nel log dell'app: `Chromium GL Backend: egl`, `ANGLE Backend: disabled`,
`use-gl egl`. Il thread GPU di Chromium parla direttamente con l'EGL di
libhybris, quindi può creare EGLImage dai buffer Android.

### Il processo GPU è un thread del processo browser
(`--in-process-gpu`, messo sempre da QtWebEngine, vedi nota
`rootitanium-accelerazione-hardware`). **Conseguenza chiave**: un decoder che
gira «nel processo GPU» vive nello stesso processo dell'EGL, e il buffer del
vendor non deve mai attraversare un processo.

### Come fa zero-copy il resto di SailfishOS: gst-droid
In `gst-libs/gst/droid/gstdroidmediabuffer.c` l'EGLImage si crea passando il
`DroidMediaBuffer` stesso:
```c
eglCreateImageKHR(dpy, ctx, EGL_NATIVE_BUFFER_ANDROID,
                  (EGLClientBuffer) droid_media_buffer, attrs);
```
`_DroidMediaBuffer` deriva da `android_native_base_t` e il suo `handle` è il
gralloc del `GraphicBuffer` (sorgente upstream `droidmediabuffer.cpp`). Il
buffer torna al decoder con `droid_media_buffer_release(buffer, display,
fence)`, dove la fence EGL dice quando la GPU ha finito di leggerlo.

⭐ **È la strada portabile**: il driver conosce i propri formati (i tile
MediaTek, l'UBWC Qualcomm, i formati privati) e li campiona con
`GL_TEXTURE_EXTERNAL_OES`. Nessun formato viene interpretato da noi. È lo
stesso meccanismo che usano la fotocamera e il lettore video di Jolla su ogni
porting, quindi rispetta il vincolo «tutti i device SFOS».

### Estensioni presenti (lette dai binari del target fleur, POCO spento)
- blob Mali (`/var/lib/gpu-a11/lib64/egl/libGLES_mali.so`):
  `EGL_ANDROID_image_native_buffer`, `EGL_KHR_image_base`,
  `EGL_KHR_fence_sync`, `EGL_ANDROID_native_fence_sync`,
  `GL_OES_EGL_image_external(_essl3)`, e anche `EGL_EXT_image_dma_buf_import`;
- libhybris (`libhybris-eglplatformcommon.so`): `EGL_HYBRIS_native_buffer2`,
  con `eglHybrisSerializeNativeBuffer`/`eglHybrisCreateRemoteBuffer` per passare
  un buffer gralloc **tra processi** (fd + int dell'handle).
⚠️ Sono stringhe nei binari, non l'elenco esposto a runtime. Va confermato sul
device, con la sonda Z1.

### La strada dmabuf standard di Chromium Linux è chiusa da Qt
Su Linux Chromium fa lo zero-copy (VAAPI/V4L2) con `NativePixmap` dmabuf →
`OzoneImageBacking` → import `EGL_LINUX_DMA_BUF_EXT`. QtWebEngine però lo spegne:
`EGLHelper` (`core/ozone/gl_context_qt.cpp:302-317`) lo abilita solo con **GBM**
più `EGL_EXT_image_dma_buf_import(_modifiers)` più
`EGL_MESA_image_dma_buf_export`, e poi `gl_surface_egl_qt.cpp:57-63` azzera le
estensioni dmabuf nel display di Chromium. Su hybris non c'è GBM e non c'è
MESA. Anche forzandolo, con dmabuf i formati del vendor (tile MTK, UBWC) vanno
descritti con fourcc e modifier DRM, cioè interpretati da noi: **non è
portabile**. Scartata.

### Dove si aggancia in Chromium 122
- **Lato renderer** oggi manca il decoder «mojo»: su Linux, senza VAAPI e V4L2,
  `media/media_options.gni:305` lascia `mojo_media_services = []`. Serve
  `mojo_media_services = ["video_decoder"]` e `mojo_media_host = "gpu"` negli
  args GN. `DefaultDecoderFactory` mette allora `MojoVideoDecoder` in testa alla
  lista (è il ramo `external_decoder_factory_`, oggi vuoto).
- **Lato GPU** l'aggancio esiste già ed è vuoto:
  `media/mojo/services/gpu_mojo_media_client_stubs.cc`, con
  `CreatePlatformVideoDecoder()` e `GetPlatformSupportedVideoDecoderConfigs()`.
  Al loro posto va un `gpu_mojo_media_client_sfos.cc` nostro. La catena
  `MediaGpuChannelManager` nel processo GPU è codice generico di content e si
  compila comunque (`content/gpu/gpu_child_thread.cc`).
- **Campionatore esterno**: Chromium 122 sa già disegnare un frame YUV come
  **una sola** texture `GL_TEXTURE_EXTERNAL_OES`
  (`SharedImageFormat::PrefersExternalSampler()`, usato da
  `ozone_image_gl_textures_holder.cc:250` e da `skia_gl_image_representation.cc`).
  viz e Skia sanno campionarla: non è da inventare.

## Due architetture, una scelta

| | **A — decoder nel processo GPU** (consigliata) | B — decoder nel renderer, buffer passato al GPU |
|---|---|---|
| Dove gira droidmedia | thread GPU del processo browser | renderer, come oggi |
| Passaggio del buffer | nessuno, stesso processo | handle gralloc (fd + int) via mojo, poi `eglHybrisCreateRemoteBuffer` |
| Restituzione del buffer al decoder | `droid_media_buffer_release` con fence EGL locale | la fence deve attraversare i processi: difficile |
| Aggancio Chromium | quello previsto (MojoVideoDecoder + client GPU) | canale mojo nostro, fuori dagli schemi |
| Ripiego software | gratis, come oggi | gratis |

**A** è il modo in cui Chromium integra ogni decoder hardware (Android, Windows,
Mac, ChromeOS) e l'unico con cui la fence resta locale. **B** esiste solo
perché libhybris sa serializzare un buffer, ma il ciclo di vita diventerebbe
distribuito su due processi.

### Cosa contiene A
1. **args GN**: `mojo_media_services=["video_decoder"]`, `mojo_media_host="gpu"`.
2. **`gpu_mojo_media_client_sfos.cc`** al posto dello stub: crea il nostro
   decoder e riporta le configurazioni supportate interrogando
   `droid_media_codec_is_supported()`. Nessun codec è cablato da noi.
3. **Il decoder** (si riusa gran parte di `droid_video_decoder.cc`: sonda,
   ciclo di vita, le sette correzioni del 18/09), ma **senza**
   `NO_MEDIA_BUFFER`: l'output passa per la `DroidMediaBufferQueue`
   (`frame_available`), non per la callback dati.
4. **Un `SharedImageBacking` nostro** («DroidMediaImageBacking»): EGLImage
   `EGL_NATIVE_BUFFER_ANDROID` dal `DroidMediaBuffer`, legata a una texture
   `GL_TEXTURE_EXTERNAL_OES`, con formato a campionatore esterno e le
   rappresentazioni GL e SkiaGL. Il modello da cui copiare è
   `ozone_image_backing` più `gl_ozone_image_representation`, con l'import
   dmabuf sostituito dall'import del buffer nativo.
5. **Il ritorno del buffer**: quando viz rilascia il frame (sync token), si crea
   una fence EGL e si chiama `droid_media_buffer_release`.
6. **Il decoder attuale resta** come secondo in lista: se il ramo zero-copy
   rifiuta su un device, si scende alla copia con libyuv e poi al software.

### Rischi noti
- **Pochi buffer nella coda del vendor** (tipicamente 4-8): se Chromium tiene i
  frame troppo a lungo il decoder resta senza buffer e si blocca. Android ha la
  stessa trappola e la risolve con un pool: va previsto dall'inizio.
- **`use_virtualized_gl_contexts`** è attivo sui Mali (entry 213 della
  `gpu_driver_bug_list`): le texture esterne con i contesti virtualizzati vanno
  verificate sul device.
- Il **processo GPU con decoder dentro** porta i crash del vendor nel processo
  browser: un SIGSEGV di droidmedia chiuderebbe l'app, non solo la scheda. La
  sonda in 4 passi e la regola «mai chiamare alla cieca» diventano ancora più
  importanti.
- **Sul POCO c'è una sola istanza** del decoder VP9 hardware: il ramo zero-copy
  e il ramo con copia non devono contenderselo.

## Piano, con cancelli

### Z0 — il cancello: vale la pena? (mezza giornata, niente build)
a) **Dove vanno oggi gli 87% di core** in modalità hardware: CPU per thread
   (`/proc/<pid>/task/*/stat`) di browser e renderer durante il video.
   Compositor, `VizCompositorThread`, `CrGpuMain` e il thread di droidmedia
   dicono quanto pesano davvero le copie.
b) **Il tetto reale**: stesso video, stessa luminosità, stesso `orchestra.sh`,
   ma riprodotto da un lettore **già zero-copy**: gst-droid, cioè il lettore di
   sistema o una QML minima con `MediaPlayer` + `VideoOutput`. Se consuma quanto
   RooTitanium in hardware, lo zero-copy non vale la pena. ⚠️ Prima verificare
   che gst-droid sul POCO accetti VP9 in WebM; altrimenti usare la stessa clip
   in H.264 per **entrambi**.
Se il tetto misurato è sotto ~0,1 W, **ci si ferma qui**.

### Z1 — sonda in C (1-2 giorni, sul modello di `scratch/sonde/`)
droidmedia **senza** `NO_MEDIA_BUFFER` → `frame_available` →
`eglCreateImageKHR(EGL_NATIVE_BUFFER_ANDROID)` → quad con
`samplerExternalOES` in una finestra Wayland → `droid_media_buffer_release`
con fence. Risponde a: la coda di buffer funziona su questo porting? quali
`hal_format` escono? l'EGL a runtime espone le estensioni? Da provare su POCO
**e** X10 III (Mali e Adreno), con l'app chiusa.

### Z2 — Chromium (2-4 settimane, 2-3 build complete da ~5 h)
Punti 1-6 di «Cosa contiene A». Come per il decoder: i sorgenti in
`packaging/qt6-qtwebengine-sfos/`, innestati da uno script idempotente dopo
ogni rigenerazione del build tree.

### Z3 — misura
Stessa serie a coppie del 19/09 (`scratch/misura-consumi-0919/`), con tre
configurazioni: software, hardware con copia, hardware zero-copy.

## Z0: la misura (19/09, 14:33-15:06)

POCO a batteria (54% → 48%), CPU sbloccate (boot_freq -1), luminosità 60, lo
stesso `vp9.webm` 1080p30 muto in loop, allineato in alto e a tutta larghezza
in entrambi i lettori. Giri da 180 s in ordine a specchio. Dati e script in
`scratch/misura-zerocopy-0919/` (in `scartati-1/` c'è un primo tentativo senza
tunnel DevTools, in cui RooTitanium non aveva caricato il video).

Il lettore zero-copy è una QML minima (`rtzc.qml`, `MediaPlayer` +
`VideoOutput`, lanciata con `sailfish-qml rtzc`). Verificato che è davvero
zero-copy: `droidvdec` crea il codec VP9 hardware e il vendor emette il
formato opaco `0x7f000789` («unrecognized» per gst-droid), che non si può
mappare in CPU e va per forza alla GPU come buffer nativo. Screenshot a ogni
giro: video visibile.

| coppia adiacente | RooTitanium hw (con copia) | gst-droid zero-copy | differenza |
|---|---|---|---|
| giri 2-3 | 2,62 W | 2,74 W | **+0,12 W** |
| giri 4-5 | 2,62 W | 2,70 W | **+0,08 W** |
| giri 7-8 | 2,81 W | 2,85 W | **+0,04 W** |
| media | 2,68 W | 2,76 W | **+0,08 W** |

| media | app ferma | RooTitanium hw | zero-copy |
|---|---|---|---|
| consumo | 2,52 W | 2,68 W | 2,76 W |
| CPU dell'app (% di un core) | 0 | 99-108 | 40-43 |
| GPU | 0% | 42% | 18% |
| frequenza del cluster grande | 1986 MHz | ~1530 MHz | ~1760 MHz |
| frame persi (RooTitanium) | — | 0 su ~6800 | non misurato |

Lo zero-copy fa quello che promette: **meno della metà della CPU e meno della
metà della GPU**. Però il telefono **non consuma di meno**. Un'ipotesi,
**non dimostrata**: col carico basso il cluster grande resta a frequenza più
alta (1760 contro 1530 MHz), per colpa della voce qui sotto.

### ⭐ La voce che conta davvero: mtkpower
In **tutti** gli 8 giri, compresi quelli con l'app ferma,
`vendor.mediatek.hardware.mtkpower@1.0-service` consuma **106-110% di un core**,
fisso. È più di tutto RooTitanium in riproduzione. È un problema del porting
(segnalato all'agente del porting il 19/09 alle 15:10), non del browser, ed è
il candidato più probabile per il consumo alto a riposo. Il porting lo conosce
dal 01/08: il thread `mtkScnHanler` gira a vuoto e vale ~310 mA da sveglio. Non
si può spegnere, perché la HAL Codec2 fa un `getService` bloccante su `IMtkPerf`
e senza il power HAL nessun video parte. La loro strada è capire con strace su
cosa cicla.

### Dove va oggi la CPU di RooTitanium in hardware (thread, % di un core)
`Chrome_InProcGpuThread` 14, `ThreadPoolForeground` 13 (qui c'è la copia
libyuv), `QSGRenderThread` 10, `VizCompositorThread` 10, driver Mali 7,
`Chrome_ChildIOThread` 7, `VideoFrameCompositor` 6, `Media` 4. Fuori dall'app,
uguali nei due lettori: lipstick 37%, decoder Codec2 MediaTek 23-25%,
composer 11%, vpud 4%.
