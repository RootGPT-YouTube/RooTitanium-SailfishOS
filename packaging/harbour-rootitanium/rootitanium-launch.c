/* RooTitanium — launcher ELF per SailfishOS (sailjail richiede un ELF come Exec,
 * non uno script). Equivalente compilato di run.sh: imposta l'env del bundle e
 * fa execv di webengine-smoke con argv[0] forgiato = path del launcher, cosi'
 * la cover di jolla-home combacia (cmdline == riga Exec) e main.cpp risolve
 * test.qml da dirname(argv[0]).  RILASCIO: niente remote-debugging ne' log verbosi.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libgen.h>
#include <limits.h>

static char HERE[PATH_MAX];

/* setenv "name=HERE/suffix" (overwrite) */
static void set_here(const char *name, const char *suffix, int overwrite) {
    char buf[PATH_MAX * 2];
    snprintf(buf, sizeof(buf), "%s%s", HERE, suffix);
    setenv(name, buf, overwrite);
}

int main(int argc, char **argv) {
    /* Il launcher vive in /usr/bin/ (sailjail: "Legacy apps must be in /usr/bin/"),
     * ma il bundle e' installato dall'RPM in /home/rootitanium (path fisso). */
    strncpy(HERE, "/home/rootitanium", sizeof(HERE) - 1); HERE[sizeof(HERE)-1] = '\0';

    /* LD_LIBRARY_PATH = HERE/lib : path sistema/hybris : LD_LIBRARY_PATH esistente */
    {
        const char *old = getenv("LD_LIBRARY_PATH");
        char buf[PATH_MAX * 3];
        snprintf(buf, sizeof(buf),
                 "%s/lib:/usr/lib64:/usr/libexec/droid-hybris/system/lib64:/system/lib64:/vendor/lib64:/odm/lib64%s%s",
                 HERE, old && *old ? ":" : "", old ? old : "");
        setenv("LD_LIBRARY_PATH", buf, 1);
    }
    set_here("QT_PLUGIN_PATH", "/plugins", 1);
    set_here("QT_QPA_PLATFORM_PLUGIN_PATH", "/plugins/platforms", 1);
    set_here("QML2_IMPORT_PATH", "/qml", 1);
    set_here("QML_IMPORT_PATH", "/qml", 1);
    set_here("QTWEBENGINEPROCESS_PATH", "/libexec/QtWebEngineProcess", 1);
    set_here("QTWEBENGINE_RESOURCES_PATH", "/resources", 1);
    set_here("QTWEBENGINE_LOCALES_PATH", "/locales", 1);

    /* piattaforma grafica: solo se non gia' forniti (lipstick li passa) */
    setenv("QT_QPA_PLATFORM", "wayland-egl", 0);
    {
        const char *xrd = getenv("XDG_RUNTIME_DIR");
        if (!xrd || !*xrd) {
            char buf[64];
            snprintf(buf, sizeof(buf), "/run/user/%u", (unsigned)getuid());
            setenv("XDG_RUNTIME_DIR", buf, 1);
            xrd = getenv("XDG_RUNTIME_DIR");
        }
        setenv("WAYLAND_DISPLAY", "wayland-0", 0);
        const char *dbus = getenv("DBUS_SESSION_BUS_ADDRESS");
        if (!dbus || !*dbus) {
            char buf[PATH_MAX];
            snprintf(buf, sizeof(buf), "unix:path=%s/dbus/user_bus_socket", xrd);
            setenv("DBUS_SESSION_BUS_ADDRESS", buf, 1);
        }
    }

    /* tastiera QtVirtualKeyboard */
    setenv("QT_IM_MODULE", "qtvirtualkeyboard", 1);
    setenv("QT_VIRTUALKEYBOARD_STYLE", "rt", 0);
    set_here("QT_VIRTUALKEYBOARD_LAYOUT_PATH", "/kbd-layouts", 0);
    setenv("LANG", "it_IT.UTF-8", 0);

    /* Chromium: no sandbox (bundle non installato di sistema), EGL, fix touch */
    setenv("QTWEBENGINE_DISABLE_SANDBOX", "1", 1);
    setenv("QTWEBENGINE_CHROMIUM_FLAGS",
           "--no-sandbox --disable-gpu-sandbox --use-gl=egl --disable-seccomp-filter-sandbox "
           "--touch-events=enabled "
           "--blink-settings=availablePointerTypes=2,availableHoverTypes=1,primaryPointerType=2,primaryHoverType=1 "
           "--force-device-scale-factor=2.6214 --touch-slop-distance=28", 0);

    /* exec di webengine-smoke con argv[0] = suo path in /home/rootitanium, cosi'
     * main.cpp (base = dirname(argv[0])) trova /home/rootitanium/test.qml. */
    char bin[PATH_MAX];
    snprintf(bin, sizeof(bin), "%s/webengine-smoke", HERE);
    char **nargv = malloc(sizeof(char *) * (argc + 1));
    if (!nargv) return 1;
    nargv[0] = bin;                    /* argv[0] = /home/rootitanium/webengine-smoke */
    for (int i = 1; i < argc; i++) nargv[i] = argv[i];
    nargv[argc] = NULL;
    execv(bin, nargv);
    fprintf(stderr, "rootitanium-launch: execv %s fallita\n", bin);
    return 1;
}
