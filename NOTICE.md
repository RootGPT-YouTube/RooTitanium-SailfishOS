# RooTitanium — License Notice

RooTitanium (the application code in this repository) is distributed under the
GNU General Public License v3.0 or later (GPL-3.0-or-later). The complete license
text is in [LICENSE](LICENSE) and at https://www.gnu.org/licenses/gpl-3.0.html

## What this means in practice
- You are free to use, study, modify, and redistribute this software.
- If you distribute modified versions, you must keep them under the same
  GPL-compatible terms and provide the corresponding source code.
- The software is provided without warranty, as described by the GPL.

## Third-party components

RooTitanium is a QML front-end around **Qt 6 QtWebEngine** (Chromium). To run on
SailfishOS 5.1 — where Qt 6 is not an official platform component — the app ships a
**self-contained bundle** of Qt 6 + QtWebEngine under `/home/rootitanium/` inside
the RPM, rather than depending on system libraries. Those bundled components are
owned by their respective authors and used under the terms of their licenses.

**Note on the bundled LGPL libraries and corresponding source.** The Qt 6 /
QtWebEngine shared objects are bundled (not linked against system libraries) and
are LGPL-3.0. They are distributed as separable `.so` files under
`/home/rootitanium/lib/` and `/home/rootitanium/libexec/`, so they can be replaced
by the user (LGPL §4 relinking). Their corresponding source is the upstream
project at the version listed below, built with the scripts and patches in
this repository (derived from `sailfishos-chum/qt6-qtwebengine`). The upstream source tree (`qt6-qtwebengine/`)
and the build trees are **not** kept in this repository (see `.gitignore`) to keep
it lean.

---

**RooTitanium** (this application)
- Role: browser UI (tabs, HOME, history, bookmarks, downloads, permissions,
  privacy toggles), written from scratch in QML — not a fork of another browser
- License: GPL-3.0-or-later — see [LICENSE](LICENSE)
- Source: https://github.com/RootGPT-YouTube/RooTitanium-SailfishOS

**Maliit input-context plugin for Qt 6** (`qt6-sfos-maliit-platforminputcontext` 1.0.1)
- Role: lets the app use the **system keyboard** of Sailfish OS instead of the
  in-app QtVirtualKeyboard. It is a Qt platform input context that talks to
  `maliit-server` over D-Bus; it needs no Maliit library of its own.
- License: LGPL-2.1 (`LGPLv2` per the RPM metadata)
- Distribution: **bundled** in the RPM as a single separable shared object,
  `/home/rootitanium/plugins/platforminputcontexts/libmaliitplatforminputcontextplugin.so`,
  so it can be replaced by the user (LGPL §4 relinking). It is bundled rather
  than required as a dependency because the package lives in `chum:testing`,
  which a stock device does not have enabled.
- Source: https://github.com/sailfishos-open/maliit-framework — the exact binary
  is taken from the published package, whose URL and SHA-256 are recorded in
  `packaging/harbour-rootitanium/fetch-maliit-plugin.sh` (that script is how the
  file enters the bundle; the binary itself is not kept in this repository)
- © The Maliit team and the sailfishos-open contributors

**Qt 6 / Qt WebEngine** (Qt 6.12.0, Qt WebEngine 6.140.0)
- Role: the browser engine (QtWebEngine + Chromium) and its Qt 6 runtime
  (QtCore/Gui/Qml/Quick/WebEngineQuick/WebEngineCore, QtVirtualKeyboard, plugins)
- Version: Qt 6.12.0 (`v6.12.0` tags of qtbase, qtdeclarative and the other
  modules) and Qt WebEngine from the `6.140.0` branch (commit `b711289`)
- License: LGPL-3.0-only (with parts under GPL-2.0-or-later / GPL-3.0-only)
- Distribution: **bundled** in the RPM under `/home/rootitanium/lib/`,
  `/home/rootitanium/libexec/`, `/home/rootitanium/qml/`, `/home/rootitanium/plugins/`;
  loaded via the launcher's `LD_LIBRARY_PATH` / `QML2_IMPORT_PATH`
- Source / corresponding source: https://code.qt.io/ (qtbase etc. at `v6.12.0`,
  qtwebengine at branch `6.140.0`); the build scripts are in
  `packaging/qt612/` and `packaging/qt6-qtwebengine-sfos/` of this repository
- © The Qt Company Ltd. and contributors — https://www.qt.io/licensing/
- The Sailfish OS patches used to build it (EGL/GL fixes, aarch64 fixes, …) come
  from `sailfishos-chum/qt6-qtwebengine` and the chum Qt 6 packaging,
  authored mainly by **Rinigus** and **Adam Pigg (piggz)**, with contributions
  from **Peter G. (nephros)**. RooTitanium adds its own patches on top
  (`packaging/qt6-qtwebengine-sfos/patches-6.140/`, e.g. sharing the GPU
  context with Qt, which Chromium 140 no longer does by itself).

**Chromium** (included inside Qt WebEngine as `src/3rdparty`)
- Role: the web rendering/JS engine (Chromium 140.0.7339.264) inside
  QtWebEngine, carrying the security fixes backported up to Chromium
  154.0.8037.93 (per the `CHROMIUM_VERSION` file of the source tree) — that
  backporting work is done by the Chromium project and by The Qt Company
- License: BSD-3-Clause, plus the licenses of its own `third_party` components
- Distribution: compiled into `libQt6WebEngineCore.so` and `QtWebEngineProcess`,
  with `icudtl.dat`, the `.pak` resources and `v8_context_snapshot.bin`, all
  bundled in the RPM
- Source: https://chromium.googlesource.com/chromium/src/ and the
  QtWebEngine 6.140.0 snapshot (`qtwebengine-chromium`)
- © The Chromium Authors

**Readability.js** (mozilla/readability 0.6.0)
- Role: article extraction for the browser's Reader Mode (injected into the page
  on demand, rendered in an internal reader page)
- License: Apache-2.0 — text bundled in `/home/rootitanium/LICENSES/Apache-2.0.txt`
- Distribution: **bundled** as `/home/rootitanium/Readability.js` (unmodified)
- Source: https://github.com/mozilla/readability (tag 0.6.0)
- © 2010 Arc90 Inc, Mozilla and contributors

**droidmedia** (Jolla Ltd.) — hardware video decoding
- Role: reaches the phone's Android MediaCodec video decoder through libhybris;
  RooTitanium's decoder puts it in front of Chromium's software decoders and
  falls back to them when it is unavailable
- License: Apache-2.0 — text bundled in `/home/rootitanium/LICENSES/Apache-2.0.txt`
- Distribution: the small loader shim (`libdroidmedia.a`, built from
  `hybris.c`, © 2014-2015 Jolla Ltd.) is **statically linked** into
  `libQt6WebEngineCore`; `libdroidmedia.so` itself is **not bundled**, it is
  loaded at runtime from the device's own adaptation packages
- Source: https://github.com/sailfishos/droidmedia

**libhybris** and the Android HAL (EGL / GPU)
- Role: GPU acceleration on SailfishOS — QtWebEngine renders through EGL over the
  device's Android graphics drivers via libhybris
- Distribution: **linked** against the on-device system libraries; not bundled
- Source: https://github.com/libhybris/libhybris

## Trademarks

"Chromium" and "Google Chrome" are trademarks of Google LLC. RooTitanium is an
independent project, **not affiliated with, sponsored by or endorsed by** Google
LLC; those names are used solely for identification (e.g. of the underlying engine
and of the Client-Hints user-agent the browser presents to sites). "Qt" is a
trademark of The Qt Company Ltd.
