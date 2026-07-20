# Fix RooTitanium al build di qt6-qtwebengine

Le fix che hanno permesso a qt6-qtwebengine di compilare per SailfishOS 5.1
aarch64 (luglio 2026) nascono come **edit a mano dentro il build tree**: sparivano
a ogni rigenerazione dell'albero e andavano ricostruite a memoria. Qui sono
riproducibili.

Nessuna di queste fix riguarda RooTitanium in sé: sono tutte conseguenze
dell'ambiente di cross-build (kernel-headers vecchi del target, qemu-user a
32 bit di spazio indirizzi, linker a 32 bit, path di lavoro lungo).

## A. Patch sui sorgenti — `patches/`, applicate dallo spec

Numerate `Patch300+` per non collidere con quelle di chum/Fedora. Si applicano
con `-p1` dalla directory `upstream/` (lo spec fa `%setup -n %{name}-%{version}/upstream`).

| Patch | File toccato | Perché |
|---|---|---|
| 0300 | `media/capture/video/linux/v4l2_capture_delegate.cc` | I kernel-headers del target sono anteriori a Linux 4.18: `V4L2_COLORSPACE_OPRGB`/`V4L2_XFER_FUNC_OPRGB` lì si chiamano ancora `..._ADOBERGB` (stessi valori). Shim di compatibilità. |
| 0301 | `sandbox/policy/linux/bpf_network_policy_linux.cc` | `<linux/wireless.h>` veniva incluso prima di `<sys/socket.h>`, con `struct sockaddr` incompleta. Anticipa l'include. |
| 0302 | `content/browser/browser_interface_binders.cc` | TU enorme: a `-O2` cc1plus supera i ~4 GB di spazio indirizzi concessi da qemu-aarch64 5.1. `#pragma GCC optimize("O1")` solo per questo file. |
| 0303 | `third_party/devtools-frontend/.../rollup-plugin-terser.js` | `jest-worker` forka un processo node e il fork/IPC di node è rotto sotto qemu-user. Terser eseguito in-process. |
| 0304 | `third_party/devtools-frontend/src/scripts/build/compress_files.js` | `Promise.all` lanciava centinaia di brotli concorrenti → node segfaulta sotto qemu. Compressione sequenziale + ricompressione se manca il `.compressed` (l'hash da solo non basta: un run crashato lascia l'hash senza il file). |

## B. Fix non patchabili — `scripts/apply-build-fixes.sh`

Toccano file **generati** (`args.gn`, `toolchain.ninja`, `build.ninja`) o sono
passi da eseguire con un tool esterno: una patch non li raggiunge.

| Passo | Cosa fa | Quando |
|---|---|---|
| `gn` | `v8_enable_sandbox=false` + pointer compression off (i tool V8 sotto qemu non possono riservare 1 TB / 4 GB di VA) e retrodata `CMakeLists.txt` perché cmake non rigeneri `args.gn` | dopo il configure, prima della build |
| `ninja` | accorcia i nomi dei `.rsp` (path di lavoro lungo → oltre NAME_MAX) e aggiunge `-Wl,--no-keep-memory` al link di WebEngineCore (.so da 1,3 GB, linker a 32 bit) | dopo ogni gn-regen |
| `snapshot` | esegue `v8_context_snapshot_generator` col qemu 10.x dell'host (col qemu 5.1 del target trappa) | solo se la build si ferma lì (~92%) |

Il path di lavoro resta `/home/RootGPT/Developing/SailfishOS/RooTitanium/`
per scelta esplicita dell'utente (20 lug 2026): il passo `ninja` è quindi
**strutturale**, non un ripiego temporaneo.

## C. Incognita nota

Nel riepilogo della build del 7-8 luglio compare un blocco **«permessi 000
qmlcachegen»** di cui non è rimasta la descrizione. Se si ripresenta va
ri-diagnosticato da zero e documentato qui.
