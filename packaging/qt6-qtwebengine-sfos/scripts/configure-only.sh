LANG=C
export LANG
unset DISPLAY
CFLAGS="-O2 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector --param=ssp-buffer-size=4 -Wformat -Wformat-security -march=armv8-a" ; export CFLAGS ; 
CXXFLAGS="${CXXFLAGS:--O2 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector --param=ssp-buffer-size=4 -Wformat -Wformat-security -march=armv8-a}" ; export CXXFLAGS ; 
FFLAGS="${FFLAGS:--O2 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector --param=ssp-buffer-size=4 -Wformat -Wformat-security -march=armv8-a -I/usr/lib64/gfortran/modules}" ; export FFLAGS ; 
LD_AS_NEEDED=1; export LD_AS_NEEDED ; 

export STRIP=strip
export NINJAFLAGS="-v -j16"
export NINJA_PATH=/usr/bin/ninja


 
  CFLAGS="${CFLAGS:--O2 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector --param=ssp-buffer-size=4 -Wformat -Wformat-security -march=armv8-a}" ; export CFLAGS ; 
  CXXFLAGS="${CXXFLAGS:--O2 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector --param=ssp-buffer-size=4 -Wformat -Wformat-security -march=armv8-a}" ; export CXXFLAGS ; 
  FFLAGS="${FFLAGS:--O2 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector --param=ssp-buffer-size=4 -Wformat -Wformat-security -march=armv8-a}" ; export FFLAGS ; 
  cmake \
         \
         \
        -DCMAKE_C_FLAGS_RELEASE:STRING="-DNDEBUG" \
        -DCMAKE_CXX_FLAGS_RELEASE:STRING="-DNDEBUG" \
        -DCMAKE_Fortran_FLAGS_RELEASE:STRING="-DNDEBUG" \
        -DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
        -DCMAKE_INSTALL_DO_STRIP:BOOL=OFF \
        -DCMAKE_INSTALL_PREFIX:PATH=/usr \
        -DINCLUDE_INSTALL_DIR:PATH=/usr/include \
        -DLIB_INSTALL_DIR:PATH=lib64 \
        -DSYSCONF_INSTALL_DIR:PATH=/etc \
        -DSHARE_INSTALL_PREFIX:PATH=/usr/share \
        -DLIB_SUFFIX=64 \
        -DBUILD_SHARED_LIBS:BOOL=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -GNinja \
         \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DINSTALL_ARCHDATADIR=/usr/lib64/qt6 \
        -DINSTALL_BINDIR=/usr/lib64/qt6/bin \
        -DINSTALL_LIBDIR=/usr/lib64 \
        -DINSTALL_LIBEXECDIR=/usr/lib64/qt6/libexec \
        -DINSTALL_DATADIR=/usr/share/qt6 \
        -DINSTALL_DOCDIR=/usr/share/doc/qt6 \
        -DINSTALL_INCLUDEDIR=/usr/include/qt6 \
        -DINSTALL_EXAMPLESDIR=/usr/lib64/qt6/examples \
        -DINSTALL_MKSPECSDIR=/usr/lib64/qt6/mkspecs \
        -DINSTALL_PLUGINSDIR=/usr/lib64/qt6/plugins \
        -DINSTALL_QMLDIR=/usr/lib64/qt6/qml \
        -DINSTALL_SYSCONFDIR=/etc/xdg \
        -DINSTALL_TRANSLATIONSDIR=/usr/share/qt6/translations \
        -DQT_GENERATE_SBOM=OFF \
        -DQT_DISABLE_RPATH=TRUE \
  -DCMAKE_TOOLCHAIN_FILE:STRING="/usr/lib64/cmake/Qt6/qt.toolchain.cmake" \
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
  -DQT_INSTALL_EXAMPLES_SOURCES=OFF
