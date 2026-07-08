#!/bin/sh
# RooTitanium — lancio smoke test WebEngine da bundle self-contained in /home.
# Nessuna installazione di sistema. Cancellabile con rm -rf della cartella.
HERE=$(cd "$(dirname "$0")" && pwd)

# --- Qt6 + WebEngine dal bundle (le lib GPU/wayland/hybris restano quelle del device) ---
# bundle PRIMA (Qt6+WebEngine), poi sistema device (EGL/wayland/hybris) e path
# android della HAL grafica (senno' libhybris non trova libhardware/gralloc...)
export LD_LIBRARY_PATH="$HERE/lib:/usr/lib64:/usr/libexec/droid-hybris/system/lib64:/system/lib64:/vendor/lib64:/odm/lib64:$LD_LIBRARY_PATH"
export QT_PLUGIN_PATH="$HERE/plugins"
export QT_QPA_PLATFORM_PLUGIN_PATH="$HERE/plugins/platforms"
export QML2_IMPORT_PATH="$HERE/qml"
export QML_IMPORT_PATH="$HERE/qml"
export QTWEBENGINEPROCESS_PATH="$HERE/libexec/QtWebEngineProcess"
export QTWEBENGINE_RESOURCES_PATH="$HERE/resources"
export QTWEBENGINE_LOCALES_PATH="$HERE/locales"

# --- piattaforma grafica: wayland+EGL (lipstick/hybris) ---
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland-egl}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"

# --- tastiera: QtVirtualKeyboard (in-app, via InputPanel nel QML) ---
export QT_IM_MODULE=qtvirtualkeyboard
# [Alternativa in studio: Maliit nativo → NON impostare QT_IM_MODULE e provare
#  export QT_WAYLAND_TEXT_INPUT_PROTOCOL=v2 (maliit SFOS parla zwp_text_input_v2)]
# lingua device (un'app SFOS vera la eredita dalla sessione; qui via SSH la forziamo)
export LANG="${LANG:-it_IT.UTF-8}"

# --- Chromium: niente sandbox (bundle non installato, no helper setuid); usa EGL ---
export QTWEBENGINE_DISABLE_SANDBOX=1
export QTWEBENGINE_CHROMIUM_FLAGS="${QTWEBENGINE_CHROMIUM_FLAGS:---no-sandbox --disable-gpu-sandbox --use-gl=egl --disable-seccomp-filter-sandbox --enable-logging=stderr --log-level=0}"

# log utile per diagnosi
export QT_LOGGING_RULES="qt.webengine*=true;qt.qpa*=true"

echo "== env =="; echo "QT_QPA_PLATFORM=$QT_QPA_PLATFORM  WAYLAND_DISPLAY=$WAYLAND_DISPLAY  XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
echo "== avvio webengine-smoke =="
exec "$HERE/webengine-smoke" "$@"
