#!/usr/bin/env python3
"""Bundle RooTitanium per armv7hl, ricavato dal bundle aarch64 dello staging.

Il bundle aarch64 (scratch/pkg-staging/bundle) e' gia' trimmato e collaudato:
ne riprendiamo la STRUTTURA (stessi file, stessi nomi), e ogni ELF viene
sostituito col corrispettivo armv7hl:
  - motore (libQt6WebEngine*, QtWebEngineProcess, plugin QML QtWebEngine,
    resources/ e locales/): dall'install armv7hl del motore (--engine);
  - QtVirtualKeyboard patchata: da vkb-stage-armv7hl;
  - Qt6 e librerie di sistema: dal target SailfishOS-5.1.0.11-armv7hl;
  - ICU: 73 -> 70 (il Qt6 armv7hl di piggz e' compilato su SFOS 5.0);
  - webengine-smoke: dal build armv7hl (--smoke);
  - plugin Maliit: lo porta fetch-maliit-plugin.sh (ARCH=armv7hl).

Alla fine verifica:
  - che ogni ELF sia ARM 32 bit;
  - che i NEEDED non soddisfatti dal bundle siano gli stessi "di sistema"
    del bundle aarch64 (libc, EGL, wayland, ...), cosi' non manca niente.

Va lanciato DENTRO l'engine SDK (i target stanno in un volume docker):
  docker exec -u mersdk sailfish-sdk-build-engine_RootGPT python3 \
     <repo>/scratch/assembla-bundle-armv7hl.py --engine <stage> --smoke <bin>
"""
import argparse, os, shutil, subprocess, sys

def _radice_repo():
    # RT_REPO vince; altrimenti si risale dalla posizione dello script (che può
    # stare in packaging/harbour-rootitanium/ o copiato in scratch/) fino alla
    # cartella che contiene sia packaging/ sia smoke-test/.
    if os.environ.get("RT_REPO"):
        return os.environ["RT_REPO"]
    d = os.path.dirname(os.path.abspath(__file__))
    while d != "/":
        if os.path.isdir(f"{d}/packaging") and os.path.isdir(f"{d}/smoke-test"):
            return d
        d = os.path.dirname(d)
    sys.exit("radice del repo non trovata: impostare RT_REPO")

R = _radice_repo()
SRC = f"{R}/scratch/pkg-staging/bundle"
DST = f"{R}/scratch/pkg-staging-armv7hl/bundle"
TGT = "/srv/mer/targets/SailfishOS-5.1.0.11-armv7hl"
VKB = f"{R}/scratch/vkb-stage-armv7hl"
ENV = dict(os.environ, LC_ALL="C", LANG="C")

ap = argparse.ArgumentParser()
ap.add_argument("--engine", help="DESTDIR dell'install armv7hl del motore")
ap.add_argument("--smoke", help="webengine-smoke compilato per armv7hl")
a = ap.parse_args()


def is_elf(p):
    try:
        with open(p, "rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


def needed(p):
    out = subprocess.run(["readelf", "-d", p], capture_output=True, text=True, env=ENV).stdout
    return [l[l.index("[") + 1:l.index("]")] for l in out.splitlines() if "(NEEDED)" in l]


def elf_class(p):
    return subprocess.run(["file", "-b", p], capture_output=True, text=True, env=ENV).stdout


# motore: nel bundle aarch64 i file si chiamano .so.6.8.3 (il 6.8.4 e' stato
# copiato sopra i nomi vecchi); nell'install armv7hl hanno il nome vero
ENGINE_LIBS = ("libQt6WebEngineCore", "libQt6WebEngineQuick", "libQt6WebEngineQuickDelegatesQml")


def engine_src(rel):
    if not a.engine:
        return None
    E = a.engine + "/usr"
    base = os.path.basename(rel)
    if rel.startswith("lib/"):
        for l in ENGINE_LIBS:
            if base.startswith(l + ".so"):
                for cand in sorted(os.listdir(E + "/lib")):
                    p = f"{E}/lib/{cand}"
                    if cand.startswith(l + ".so.6.") and not os.path.islink(p):
                        return p
        return None
    if rel.startswith("libexec/"):
        return f"{E}/lib/qt6/{rel}"
    if rel.startswith("qml/QtWebEngine/"):
        return f"{E}/lib/qt6/{rel}"
    if rel.startswith("resources/"):
        return f"{E}/share/qt6/{rel}"
    if rel.startswith("locales/"):
        return f"{E}/share/qt6/translations/qtwebengine_{rel}"
    return None


def other_src(rel):
    cands = []
    if rel.startswith("lib/"):
        n = rel[4:]
        cands = [f"{VKB}/usr/lib/{n}", f"{TGT}/usr/lib/{n}", f"{TGT}/lib/{n}"]
    elif rel.startswith("plugins/"):
        cands = [f"{VKB}/usr/lib/qt6/{rel}", f"{TGT}/usr/lib/qt6/{rel}"]
    elif rel.startswith("qml/"):
        cands = [f"{VKB}/usr/lib/qt6/{rel}", f"{TGT}/usr/lib/qt6/{rel}"]
    for c in cands:
        if os.path.isfile(c):
            return c
    return None


# ── 1) copia della struttura ────────────────────────────────────────────────
if os.path.exists(DST):
    shutil.rmtree(DST)
shutil.copytree(SRC, DST, symlinks=True)

mancanti, sostituiti, rimossi = [], 0, []
for dp, dn, fn in os.walk(DST):
    for f in fn:
        p = os.path.join(dp, f)
        rel = os.path.relpath(p, DST)
        if os.path.islink(p):
            continue
        # ICU 73 -> 70 piu' sotto
        if rel.startswith("lib/libicu"):
            os.remove(p); rimossi.append(rel); continue
        if rel == "plugins/platforminputcontexts/libmaliitplatforminputcontextplugin.so":
            os.remove(p); rimossi.append(rel + " (lo rimette fetch-maliit-plugin.sh)"); continue
        if rel == "webengine-smoke":
            if a.smoke:
                shutil.copy2(a.smoke, p); sostituiti += 1
            else:
                os.remove(p); mancanti.append(rel)
            continue
        src = engine_src(rel)
        engine_owned = src is not None or rel.startswith(("resources/", "locales/", "libexec/", "qml/QtWebEngine/")) \
            or any(os.path.basename(rel).startswith(l + ".so") for l in ENGINE_LIBS)
        if engine_owned:
            if src and os.path.isfile(src):
                shutil.copy2(src, p); sostituiti += 1
            else:
                os.remove(p); mancanti.append(rel + " [motore]")
            continue
        if not is_elf(p):
            continue                      # qml, qmldir, js, png...: indipendenti dall'arch
        src = other_src(rel)
        if src:
            shutil.copy2(src, p); sostituiti += 1
        else:
            os.remove(p); mancanti.append(rel)

# symlink rimasti appesi (es. libicu*.so.73 -> .73.2 rimosso)
for dp, dn, fn in os.walk(DST):
    for f in fn:
        p = os.path.join(dp, f)
        if os.path.islink(p) and not os.path.exists(p):
            os.remove(p); rimossi.append(os.path.relpath(p, DST) + " (link appeso)")

for f in sorted(os.listdir(f"{TGT}/usr/lib")):
    if f.startswith(("libicudata.so.70", "libicui18n.so.70", "libicuuc.so.70")):
        s = f"{TGT}/usr/lib/{f}"
        d = f"{DST}/lib/{f}"
        if os.path.islink(s):
            os.symlink(os.readlink(s), d)
        else:
            shutil.copy2(s, d)

# run.sh di rilascio: path di sistema lib64 -> lib
rs = f"{DST}/run.sh"
t = open(rs).read()
t2 = t.replace("/usr/lib64:/usr/libexec/droid-hybris/system/lib64:/system/lib64:/vendor/lib64:/odm/lib64",
               "/usr/lib:/usr/libexec/droid-hybris/system/lib:/system/lib:/vendor/lib:/odm/lib")
open(rs, "w").write(t2)

# ── 2) verifiche ────────────────────────────────────────────────────────────
def scan(B):
    names = set()
    elfs = []
    for dp, dn, fn in os.walk(B):
        for f in fn:
            p = os.path.join(dp, f)
            if dp == os.path.join(B, "lib"):
                names.add(f)
            if not os.path.islink(p) and is_elf(p):
                elfs.append(p)
    unres = {}
    for p in elfs:
        for n in needed(p):
            if n not in names:
                unres.setdefault(n, []).append(os.path.relpath(p, B))
    return elfs, unres

elfs, unres32 = scan(DST)
_, unres64 = scan(SRC)
sys64 = set(unres64)
# Equivalenti a 32 bit di cio' che il device fornisce gia': il loader e le
# librerie glibc che su 5.1 aarch64 sono fuse in libc (il Qt armv7hl e' compilato
# su glibc 2.30, dove libdl/libpthread/librt erano separate e ci sono ancora
# come stub). libopenjp2.so.7: nel bundle aarch64 e' un link APPESO, quindi
# anche li' la fornisce il sistema (dipendenza di poppler, sempre presente).
sys64 |= {"ld-linux-armhf.so.3", "libdl.so.2", "libpthread.so.0", "librt.so.1", "libopenjp2.so.7"}
# i nomi "di sistema" del bundle 64 bit con suffissi diversi restano uguali
non32 = [p for p in elfs if "ELF 32-bit" not in elf_class(p) or "ARM" not in elf_class(p)]
extra = {n: v for n, v in unres32.items() if n not in sys64}

print(f"sostituiti: {sostituiti}")
print(f"rimossi: {len(rimossi)}")
for x in rimossi: print("   -", x)
print(f"MANCANTI ({len(mancanti)}):")
for x in mancanti: print("   !", x)
print(f"ELF non ARM32 ({len(non32)}):")
for x in non32: print("   !", os.path.relpath(x, DST))
print(f"NEEDED non soddisfatti e NON di sistema ({len(extra)}):")
for n, v in sorted(extra.items()): print(f"   ! {n}  <- {', '.join(v[:3])}")
print("di sistema attesi sul device:", " ".join(sorted(unres32)))
ok = not mancanti and not non32 and not extra
print("BUNDLE-OK" if ok else "BUNDLE-INCOMPLETO")
sys.exit(0 if ok else 1)
