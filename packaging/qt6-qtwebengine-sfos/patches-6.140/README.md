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

Patch SFOS di Rinigus (chum `qt6-lts-6.11.1`) sullo stesso albero: tutte
applicano (hwcap2-bti con offset di 3 righe, dalla cartella `chromium/`),
tranne `fix-build-on-SFOS-Comment-out-GL-includes`, che **non serve più**:
`qt_overrides.cc` in 140 non include più gli header GL.

Innesto droidmedia (`../scripts/apply-droidmedia.sh`): tutte le ancore
esistono in 140. Il sorgente del decoder va adattato a mano:
`DecoderBuffer::data_size()` → `size()`, `VideoFrame::kYPlane/kUPlane/kVPlane`
→ `kY/kU/kV`, `VideoFrame::stride()` ora restituisce `size_t`.
`VideoDecoder` (interfaccia) è identica a 122.
