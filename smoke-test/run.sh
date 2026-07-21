#!/bin/bash
# RooTitanium — lancio smoke test WebEngine da bundle self-contained in /home.
# Nessuna installazione di sistema. Cancellabile con rm -rf della cartella.
# bash (non busybox sh): serve `exec -a` in fondo per il match cover di jolla-home.
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
# Modalità Lettura: test.qml legge Readability.js dal bundle via XHR file://,
# che Qt6 blocca di default senza questa variabile
export QML_XHR_ALLOW_FILE_READ=1

# --- piattaforma grafica: wayland+EGL (lipstick/hybris) ---
# Imposto, NON eredito: la sessione SFOS esporta QT_QPA_PLATFORM=wayland (plugin
# generico) e con "${VAR:-default}" vinceva lei. Stesso motivo per le due unset:
# variabili pensate per il Qt5 patchato di Sailfish che il nostro Qt6 upstream
# legge davvero (QT_WAYLAND_RESIZE_AFTER_SWAP e' dentro libQt6WaylandClient del
# bundle; e' quella che rinigus rimuove in qt-runner 0.4.0). Vedi il commento
# esteso in packaging/harbour-rootitanium/rootitanium-launch.c.
export QT_QPA_PLATFORM=wayland-egl
unset QT_WAYLAND_RESIZE_AFTER_SWAP
unset QMLSCENE_DEVICE
# niente decorazione: l'app e' fullscreen e la decorazione le mangia area utile
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
# session bus (Condividi via org.sailfishos.share): dall'icona lo passa lipstick,
# via ssh va indicato a mano (path standard del bus utente SFOS)
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/dbus/user_bus_socket}"

# --- tastiera: QtVirtualKeyboard (in-app, via InputPanel nel QML) ---
export QT_IM_MODULE=qtvirtualkeyboard
# stile tastiera custom (glifi armonizzati, look Sailfish/ItalianoX) + layout con "/"
export QT_VIRTUALKEYBOARD_STYLE="${QT_VIRTUALKEYBOARD_STYLE:-rt}"
export QT_VIRTUALKEYBOARD_LAYOUT_PATH="${QT_VIRTUALKEYBOARD_LAYOUT_PATH:-$HERE/kbd-layouts}"
# [Maliit: NON usato, ma l'assunzione storica era sbagliata su entrambi i punti —
#  qt6-sfos-maliit-platforminputcontext (Chum) esiste e parla via DBus, non via
#  wayland text-input. Vedi Documentation/TASK-2-isolamento-bundle.md, in fondo.]
# lingua device (un'app SFOS vera la eredita dalla sessione; qui via SSH la forziamo).
# Fallback neutro come nel launcher C: LANG pilota Qt.locale() e quindi
# l'Accept-Language, un default italiano darebbe pagine italiane a stranieri.
export LANG="${LANG:-en_US.UTF-8}"

# --- Chromium: niente sandbox (bundle non installato, no helper setuid); usa EGL ---
export QTWEBENGINE_DISABLE_SANDBOX=1
# --touch-events + --blink-settings: QtWebEngine (build non-embedded) forza
# hover:hover e pointer:fine → i siti (es. player YouTube) ci trattano da
# desktop col mouse e i controlli touch fanno toggle doppio (compaiono e
# spariscono subito). Valori bitfield mojom: PointerType coarse=2, HoverType
# none=1. ApplyCommandLineToSettings riapplica gli override DOPO ogni sync prefs.
# --force-device-scale-factor=2.6214 (=1080/412): SFOS forza DPI 96 → DSF 1 e
# Chromium riportava screen.* in px FISICI (2520x1080). Con la flag screen.*
# diventa nativamente in DIP=px CSS (412x961) come su Android — richiesto dal
# player YouTube (vedi spoof in test.qml). NB: NON cambia il DSF della view
# (QtWebEngine usa il dpr della QQuickWindow): il viewport resta gestito dallo
# zoomFactor 2.62 nel QML.
# --enable-viewport: accende la pipeline page-scale mobile (pinch zoom a due
# dita). NON cambia nessuna metrica vista dalle pagine (verificato via CDP:
# innerWidth/dpr/screen.* identici con e senza flag): lo zoom resta gestito
# dallo zoomFactor QML, la flag abilita solo il pinch sopra di esso.
# --touch-slop-distance=28: il gesture detector (aura) lavora in px della VIEW
# (=FISICI qui, DSF view 1): lo slop default ≈15px vale ~1,4mm su questo
# pannello ~450dpi → un dito che scivola di 2mm ANNULLA il click (pointercancel
# → scroll; verificato con tap iniettati da /dev/input: jitter 15px = niente
# click, tap fermo = ok). Android usa 8dp ≈ 21px fisici; 28px ≈ 2,6mm. Migliora
# anche longpress (stesso slop) e pinch (span_slop = 2x questo valore).
export QTWEBENGINE_CHROMIUM_FLAGS="${QTWEBENGINE_CHROMIUM_FLAGS:---no-sandbox --disable-gpu-sandbox --use-gl=egl --disable-seccomp-filter-sandbox --enable-logging=stderr --log-level=0 --touch-events=enabled --blink-settings=availablePointerTypes=2,availableHoverTypes=1,primaryPointerType=2,primaryHoverType=1 --force-device-scale-factor=2.6214 --touch-slop-distance=28 --enable-viewport --disable-features=WebBluetooth,WebUSB,WebNFC,IdleDetection,FedCm,WebOTP --force-webrtc-ip-handling-policy=default_public_interface_only --enable-features=BlockInsecurePrivateNetworkRequests}"

# log utile per diagnosi
export QT_LOGGING_RULES="qt.webengine*=true;qt.qpa*=true"
# senza questo i console.log/warning QML NON arrivano a stderr (journald/nulla)
# quando stderr non è una tty (log su file, lanci da icona): visto col probe DBus
export QT_FORCE_STDERR_LOGGING=1
# DevTools remoti (Chromium DevTools Protocol): dal PC via tunnel ssh
#   ssh -L 9222:localhost:9222 defaultuser@<phone> → http://localhost:9222
# Solo device di sviluppo: NON lasciare attivo su build di rilascio.
export QTWEBENGINE_REMOTE_DEBUGGING="${QTWEBENGINE_REMOTE_DEBUGGING:-9222}"

echo "== env =="; echo "QT_QPA_PLATFORM=$QT_QPA_PLATFORM  WAYLAND_DISPLAY=$WAYLAND_DISPLAY  XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
echo "== avvio webengine-smoke =="
# argv[0] forgiato = path di questo script: jolla-home (StartupWatcher.qml)
# aggancia la cover del launcher cercando un processo la cui cmdline combaci con
# la riga Exec del .desktop (JollaSystemInfo.matchingPidForCommand). Senza -a la
# cmdline diventerebbe .../webengine-smoke, il match fallirebbe e la cover
# segnaposto girerebbe a vuoto per ~30s ("cover fantasma").
# main.cpp risolve test.qml dalla dir di argv[0]: stessa cartella, quindi ok.
# log sempre su file: così anche i lanci dall'ICONA (lipstick) sono diagnosticabili
exec -a "$0" "$HERE/webengine-smoke" "$@" >/tmp/rootitanium.log 2>&1
