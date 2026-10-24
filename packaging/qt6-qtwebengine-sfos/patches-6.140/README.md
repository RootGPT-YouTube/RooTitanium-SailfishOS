# Patch RooTitanium per QtWebEngine 6.140 (Chromium 140)

Serie riportata dalla 6.8.4 (`../patches/`) il 10 ott 2026, verificata con
`patch -p1 --dry-run` dalla radice di qtwebengine 6.140.0 (ramo di rilascio
`6.140.0`, Chromium 140.0.7339.264).

| Patch | Stato su 6.140 |
|---|---|
| 0300 v4l2-oprgb-shim | applica invariata |
| 0301 sockaddr-include-order | applica invariata |
| 0302 browser-interface-binders-O1 | applica invariata |
| 0303 terser-in-process | **tolta**: `rollup-plugin-terser.js` non esiste più; se il fork di node sotto qemu dà ancora problemi, va riscritta sul nuovo punto |
| 0304 compress-files-sequential | **ribasata**: metà accolta a monte (ricomprimere se manca l'output), resta la compressione sequenziale |
| 0305 zlib-crc32-gcc-arm32 | **tolta**: corretta a monte (`-march=armv8-a+crc` per arm a 32 bit) |
| 0306 arm32-gcc-no-tree-vectorize | applica invariata (da ricontrollare al collaudo: il SIGBUS si vede solo su pagine con CSS vero) |
| 0307 sfos-eglimage-texture | NUOVA (11 ott): consegna frame senza dma_buf (MakeCurrent+glFinish; ID nudo con 0308, ripiego EGLImage, sonde RT_GLPROBE) |
| 0308 sfos-qt-share-group | NUOVA (11 ott, idea Fable): ✅ COLLAUDATA sul POCO, GPU funzionante (home, Wikipedia, YouTube, WebGL); attiva di default, RT_NOSHAREGROUP=1 per spegnerla |
| 0309 unifiedpush-web-push | NUOVA (18 ott, task 2.8 #0): Web Push via UnifiedPush/Foghorn al posto dei server Google (driver GCM nostro, sottoscrizioni persistenti, `clients.openWindow`). L'app la trova con dlsym (`rtpush_*`); senza la patch il Web Push resta spento |
| 0310 notification-click-after-restart | NUOVA (20 ott, dopo la 0309): il tocco su una notifica di un service worker arriva al sito anche ad app riavviata dal tocco. Niente sincronizzazione del database delle notifiche all'avvio (un processo nuovo non ha notifiche in memoria e Chromium le cancellava), `rtpush_notification_current_id` (id persistente durante `presentNotification`) e `rtpush_notification_click` (click accodato finché il profilo non è su disco; se non consegnabile apre l'origine). Si applica DOPO la 0309 |
| 0311 push-aesgcm-headers-and-registration | NUOVA (24 ott, dopo la 0310): `rtpush_message_ex` porta al driver le intestazioni di cifratura del vecchio formato aesgcm (Firebase verso endpoint non Google, es. avito.ru) quando il distributore le inoltra; con le intestazioni la decifra Chromium, senza resta aes128gcm come prima. Registrazione più robusta: attesa dell'endpoint 30 → 120 s (l'app riprova la Register se Foghorn è scollegato), richieste ripetute per lo stesso app_id unite invece di creare un secondo token, callback in sospeso eseguite in DeleteToken, endpoint arrivato per un token già scartato tolto dal distributore. Si applica DOPO la 0310 |

Patch SFOS di Rinigus (chum `qt6-lts-6.11.1`) sullo stesso albero: tutte
applicano (hwcap2-bti con offset di 3 righe, dalla cartella `chromium/`),
tranne `fix-build-on-SFOS-Comment-out-GL-includes`, che **non serve più**:
`qt_overrides.cc` in 140 non include più gli header GL.

Innesto droidmedia (`../scripts/apply-droidmedia.sh`): tutte le ancore
esistono in 140. Il sorgente del decoder va adattato a mano:
`DecoderBuffer::data_size()` → `size()`, `VideoFrame::kYPlane/kUPlane/kVPlane`
→ `kY/kU/kV`, `VideoFrame::stride()` ora restituisce `size_t`.
`VideoDecoder` (interfaccia) è identica a 122.
