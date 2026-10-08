# Configure qt6-qtwebengine per armv7hl (RooTitanium a 32 bit).
# Stessa riga di configure-only.sh (aarch64) con tre differenze volute:
#  1) flag del compilatore = %{optflags} del target 5.1 armv7hl
#     (-march=armv7-a -mfloat-abi=hard -mfpu=neon -mthumb), da cui QtWebEngine
#     ricava arm_version/arm_fpu/arm_float_abi/arm_use_neon per gn;
#  2) libdir /usr/lib (niente lib64 / LIB_SUFFIX);
#  3) CMAKE_BUILD_TYPE=Release e niente -g: senza simboli di debug la .so finale
#     resta molto sotto i ~4 GB che il linker (binutils a 32 bit) puo' indirizzare,
#     e la build e' piu' corta. Nell'RPM finiva comunque strippata.
# Si lancia, via sb2 nel target SailfishOS-5.1.0.11-armv7hl, dalla dir
# build-armv7hl/BUILD/qt6-qtwebengine-<ver>/upstream (configure in-place).
LANG=C
export LANG
unset DISPLAY
OPT="-O2 -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector --param=ssp-buffer-size=4 -Wformat -Wformat-security -fmessage-length=0 -march=armv7-a -mfloat-abi=hard -mfpu=neon -mthumb -Wno-psabi"
CFLAGS="$OPT"; export CFLAGS
CXXFLAGS="$OPT"; export CXXFLAGS
LD_AS_NEEDED=1; export LD_AS_NEEDED

export STRIP=strip
export NINJAFLAGS="-v -j16"
export NINJA_PATH=/usr/bin/ninja

cmake \
        -DCMAKE_C_FLAGS_RELEASE:STRING="-DNDEBUG" \
        -DCMAKE_CXX_FLAGS_RELEASE:STRING="-DNDEBUG" \
        -DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
        -DCMAKE_INSTALL_DO_STRIP:BOOL=OFF \
        -DCMAKE_INSTALL_PREFIX:PATH=/usr \
        -DINCLUDE_INSTALL_DIR:PATH=/usr/include \
        -DLIB_INSTALL_DIR:PATH=lib \
        -DSYSCONF_INSTALL_DIR:PATH=/etc \
        -DSHARE_INSTALL_PREFIX:PATH=/usr/share \
        -DBUILD_SHARED_LIBS:BOOL=ON -DCMAKE_BUILD_TYPE=Release \
        -GNinja \
        -DINSTALL_ARCHDATADIR=/usr/lib/qt6 \
        -DINSTALL_BINDIR=/usr/lib/qt6/bin \
        -DINSTALL_LIBDIR=/usr/lib \
        -DINSTALL_LIBEXECDIR=/usr/lib/qt6/libexec \
        -DINSTALL_DATADIR=/usr/share/qt6 \
        -DINSTALL_DOCDIR=/usr/share/doc/qt6 \
        -DINSTALL_INCLUDEDIR=/usr/include/qt6 \
        -DINSTALL_EXAMPLESDIR=/usr/lib/qt6/examples \
        -DINSTALL_MKSPECSDIR=/usr/lib/qt6/mkspecs \
        -DINSTALL_PLUGINSDIR=/usr/lib/qt6/plugins \
        -DINSTALL_QMLDIR=/usr/lib/qt6/qml \
        -DINSTALL_SYSCONFDIR=/etc/xdg \
        -DINSTALL_TRANSLATIONSDIR=/usr/share/qt6/translations \
        -DQT_GENERATE_SBOM=OFF \
        -DQT_DISABLE_RPATH=TRUE \
  -DCMAKE_TOOLCHAIN_FILE:STRING="/usr/lib/cmake/Qt6/qt.toolchain.cmake" \
  -DFEATURE_qtpdf_build:BOOL=ON \
  -DFEATURE_webengine_developer_build:BOOL=OFF \
  -DFEATURE_webengine_embedded_build:BOOL=OFF \
  -DFEATURE_webengine_extensions:BOOL=ON \
  -DFEATURE_webengine_kerberos:BOOL=OFF \
  -DFEATURE_webengine_native_spellchecker:BOOL=OFF \
  -DFEATURE_webengine_printing_and_pdf:BOOL=ON \
  -DFEATURE_webengine_proprietary_codecs:BOOL=ON \
  -DFEATURE_webengine_system_icu:BOOL=0 \
  -DFEATURE_webengine_system_libevent:BOOL=ON \
  -DFEATURE_webengine_system_ffmpeg:BOOL=OFF \
  -DFEATURE_webengine_webrtc:BOOL=ON \
  -DFEATURE_webengine_ozone_x11:BOOL=OFF \
  -DFEATURE_qtwebengine_widgets_build:BOOL=OFF \
  -DFEATURE_qtpdf_widgets_build:BOOL=OFF \
  -DQT_BUILD_EXAMPLES:BOOL=OFF \
  -DQT_INSTALL_EXAMPLES_SOURCES=OFF \
  "${SRCDIR:-.}"
