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
project at the version listed below, built with the recipe from
`sailfishos-chum/qt6-qtwebengine`. The upstream source tree (`qt6-qtwebengine/`)
and the build trees are **not** kept in this repository (see `.gitignore`) to keep
it lean.

---

**RooTitanium** (this application)
- Role: browser UI (tabs, HOME, history, bookmarks, downloads, permissions,
  privacy toggles), written from scratch in QML — not a fork of another browser
- License: GPL-3.0-or-later — see [LICENSE](LICENSE)
- Source: https://github.com/RootGPT-YouTube/RooTitanium-SailfishOS

**Qt 6 / Qt WebEngine** (`qt6-qtwebengine` 6.8.3)
- Role: the browser engine (QtWebEngine + Chromium) and its Qt 6 runtime
  (QtCore/Gui/Qml/Quick/WebEngineQuick/WebEngineCore, QtVirtualKeyboard, plugins)
- Version: 6.8.3
- License: LGPL-3.0-only (with parts under GPL-2.0-or-later / GPL-3.0-only)
- Distribution: **bundled** in the RPM under `/home/rootitanium/lib/`,
  `/home/rootitanium/libexec/`, `/home/rootitanium/qml/`, `/home/rootitanium/plugins/`;
  loaded via the launcher's `LD_LIBRARY_PATH` / `QML2_IMPORT_PATH`
- Source / corresponding source: https://www.qt.io/ (6.8.3) built via
  https://github.com/sailfishos-chum/qt6-qtwebengine
- © The Qt Company Ltd. and contributors — https://www.qt.io/licensing/

**Chromium** (included inside Qt WebEngine as `src/3rdparty`)
- Role: the web rendering/JS engine (Chromium 122 base) inside QtWebEngine
- License: BSD-3-Clause, plus the licenses of its own `third_party` components
- Distribution: compiled into `libQt6WebEngineCore.so` and `QtWebEngineProcess`,
  with `icudtl.dat`, the `.pak` resources and `v8_context_snapshot.bin`, all
  bundled in the RPM
- Source: https://chromium.googlesource.com/chromium/src/ and the
  QtWebEngine 6.8.3 snapshot
- © The Chromium Authors

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
