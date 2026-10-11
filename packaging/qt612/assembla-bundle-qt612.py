#!/usr/bin/env python3
"""Bundle RooTitanium su Qt 6.12 + QtWebEngine 6.140 (Chromium 140) — task 2.5 #6.

Parte dal bundle 2.x dello staging (gia' trimmato e collaudato) e ne riprende
la forma, ma con tutto lo stack Qt preso dal target sb2 clonato (…-qt612), dove
sono installati i moduli 6.12 e il motore 6.140:
  - lib/: le librerie NON Qt restano quelle del bundle 2.x (stessa arch, stesse
    versioni di sistema); ogni libQt6* diventa la 6.12/6.140 del target, piu'
    quelle nuove che servono (chiusura sui NEEDED);
  - plugins/: stessi file del bundle 2.x quando esistono in 6.12; la
    piattaforma Wayland in 6.12 e' un solo plugin (libqwayland.so); restano
    nostri il plugin di posizione e quello Maliit (ricompilati per 6.12);
  - qml/: ogni modulo presente nel bundle 2.x viene copiato intero dal target;
  - motore: libexec/QtWebEngineProcess, resources/, locales/ dal target;
  - webengine-smoke: quello compilato contro 6.12 (--smoke).
Tutti gli ELF vengono strippati. Alla fine verifica che i NEEDED non
soddisfatti siano solo quelli "di sistema" gia' attesi dal bundle 2.x.

Da lanciare DENTRO l'engine SDK:
  docker exec -u mersdk sailfish-sdk-build-engine_RootGPT python3 \
    <repo>/packaging/qt612/assembla-bundle-qt612.py --arch aarch64 \
    --smoke <webengine-smoke> --position <plugin> --maliit <plugin>
"""
import argparse, os, shutil, subprocess, sys

ap = argparse.ArgumentParser()
ap.add_argument("--arch", default="aarch64", choices=["aarch64", "armv7hl"])
ap.add_argument("--smoke", required=True)
ap.add_argument("--position", required=True)
ap.add_argument("--maliit", required=True)
a = ap.parse_args()

R = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
L = "lib64" if a.arch == "aarch64" else "lib"
SRC = f"{R}/scratch/pkg-staging/bundle" if a.arch == "aarch64" else f"{R}/scratch/pkg-staging-armv7hl/bundle"
DST = f"{R}/scratch/pkg-staging-qt612-{a.arch}/bundle"
T = f"SailfishOS-5.1.0.11-{a.arch}-qt612"
TGT = f"/srv/mer/targets/{T}"
QT = f"{TGT}/usr/{L}/qt6"
ENV = dict(os.environ, LC_ALL="C", LANG="C")


def is_elf(p):
    try:
        with open(p, "rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


def needed(p):
    out = subprocess.run(["readelf", "-d", p], capture_output=True, text=True, env=ENV).stdout
    return [l[l.index("[") + 1:l.index("]")] for l in out.splitlines() if "(NEEDED)" in l]


def copia_lib_qt(stem):
    """stem = 'libQt6Core': copia il file vero e crea il link .so.6"""
    lib = f"{TGT}/usr/{L}"
    for f in sorted(os.listdir(lib)):
        p = f"{lib}/{f}"
        if f.startswith(stem + ".so.6.") and not os.path.islink(p):
            shutil.copy2(p, f"{DST}/lib/{f}")
            link = f"{DST}/lib/{stem}.so.6"
            if os.path.lexists(link):
                os.remove(link)
            os.symlink(f, link)
            return True
    return False


# ── 1) struttura ─────────────────────────────────────────────────────────────
if os.path.exists(DST):
    shutil.rmtree(DST)
os.makedirs(DST)
for e in os.listdir(SRC):
    if e in ("lib", "plugins", "qml", "libexec", "resources", "locales"):
        continue
    s = f"{SRC}/{e}"
    (shutil.copytree if os.path.isdir(s) and not os.path.islink(s) else shutil.copy2)(s, f"{DST}/{e}")
shutil.copy2(a.smoke, f"{DST}/webengine-smoke")

# lib/: non-Qt dal bundle 2.x, Qt dal target
os.makedirs(f"{DST}/lib")
stems, mancanti = set(), []
for f in sorted(os.listdir(f"{SRC}/lib")):
    s = f"{SRC}/lib/{f}"
    if f.startswith("libQt6"):
        stems.add(f.split(".so")[0])
        continue
    if os.path.islink(s):
        os.symlink(os.readlink(s), f"{DST}/lib/{f}")
    else:
        shutil.copy2(s, f"{DST}/lib/{f}")
for st in sorted(stems):
    if not copia_lib_qt(st):
        mancanti.append(f"lib/{st} (non esiste in 6.12)")

# plugins/
for dp, dn, fn in os.walk(f"{SRC}/plugins"):
    for f in fn:
        rel = os.path.relpath(f"{dp}/{f}", SRC)
        d = f"{DST}/{rel}"
        os.makedirs(os.path.dirname(d), exist_ok=True)
        if rel == "plugins/position/libqtposition_rtgeoclue1.so":
            shutil.copy2(a.position, d); continue
        if rel == "plugins/platforminputcontexts/libmaliitplatforminputcontextplugin.so":
            shutil.copy2(a.maliit, d); continue
        if rel in ("plugins/platforms/libqwayland-egl.so", "plugins/platforms/libqwayland-generic.so"):
            shutil.copy2(f"{QT}/plugins/platforms/libqwayland.so", f"{DST}/plugins/platforms/libqwayland.so"); continue
        s = f"{QT}/{rel}"
        if os.path.isfile(s):
            shutil.copy2(s, d)
        else:
            print("   (plugin non piu' in 6.12, tolto)", rel)

# qml/: moduli interi dal target. Un "modulo" = cartella con qmldir.
moduli = set()
for dp, dn, fn in os.walk(f"{SRC}/qml"):
    if "qmldir" in fn:
        moduli.add(os.path.relpath(dp, f"{SRC}/qml"))
for m in sorted(moduli):
    if any(m.startswith(x + "/") for x in moduli):
        continue   # sotto-modulo: arriva con il genitore
    s = f"{QT}/qml/{m}"
    if os.path.isdir(s):
        shutil.copytree(s, f"{DST}/qml/{m}", dirs_exist_ok=True)
    else:
        mancanti.append(f"qml/{m}")

# motore
os.makedirs(f"{DST}/libexec")
shutil.copy2(f"{QT}/libexec/QtWebEngineProcess", f"{DST}/libexec/QtWebEngineProcess")
shutil.copytree(f"{TGT}/usr/share/qt6/resources", f"{DST}/resources")
os.makedirs(f"{DST}/locales")
for f in os.listdir(f"{SRC}/locales"):   # stesse lingue del bundle 2.x
    s = f"{TGT}/usr/share/qt6/translations/qtwebengine_locales/{f}"
    if os.path.isfile(s):
        shutil.copy2(s, f"{DST}/locales/{f}")
    else:
        mancanti.append(f"locales/{f}")

# ── 2) chiusura sui NEEDED: libQt6* nuove richieste dalla 6.12 ───────────────
def copia_lib_soname(soname):
    """libicu*: la versione con cui e' linkata Qt 6.12 (su armv7hl il bundle 2.x
    portava ICU 70, Qt 6.12 vuole la 73). File vero + link col soname."""
    lib = f"{TGT}/usr/{L}"
    reale = os.path.realpath(f"{lib}/{soname}")
    if not os.path.isfile(reale):
        return False
    shutil.copy2(reale, f"{DST}/lib/{os.path.basename(reale)}")
    if os.path.basename(reale) != soname and not os.path.lexists(f"{DST}/lib/{soname}"):
        os.symlink(os.path.basename(reale), f"{DST}/lib/{soname}")
    return True


for giro in range(5):
    names = set(os.listdir(f"{DST}/lib"))
    nuove = set()
    for dp, dn, fn in os.walk(DST):
        for f in fn:
            p = f"{dp}/{f}"
            if not os.path.islink(p) and is_elf(p):
                for n in needed(p):
                    if n.startswith("libQt6") and n not in names:
                        nuove.add(n.split(".so")[0])
                    elif n.startswith("libicu") and n not in names:
                        print("   + ICU dal target:", n)
                        if not copia_lib_soname(n):
                            mancanti.append(f"lib/{n} (ICU assente nel target)")
                        names.add(n)
    if not nuove:
        break
    for st in sorted(nuove):
        print("   + libreria Qt nuova:", st)
        if not copia_lib_qt(st):
            mancanti.append(f"lib/{st} (richiesta ma assente)")

# ── 3) strip ─────────────────────────────────────────────────────────────────
elfs = []
for dp, dn, fn in os.walk(DST):
    for f in fn:
        p = f"{dp}/{f}"
        if not os.path.islink(p) and is_elf(p):
            elfs.append(p)
for i in range(0, len(elfs), 200):
    subprocess.run(["sb2", "-t", T, "strip", "--strip-unneeded"] + elfs[i:i + 200],
                   capture_output=True, env=ENV)


# ── 4) verifica ──────────────────────────────────────────────────────────────
def unresolved(B):
    names = set(os.listdir(f"{B}/lib"))
    out = {}
    for dp, dn, fn in os.walk(B):
        for f in fn:
            p = f"{dp}/{f}"
            if not os.path.islink(p) and is_elf(p):
                for n in needed(p):
                    if n not in names:
                        out.setdefault(n, []).append(os.path.relpath(p, B))
    return out

nuovo, vecchio = unresolved(DST), unresolved(SRC)
extra = {n: v for n, v in nuovo.items() if n not in vecchio}
dim = subprocess.run(["du", "-sh", DST], capture_output=True, text=True).stdout.split()[0]
print(f"bundle: {DST} ({dim}, {len(elfs)} ELF strippati)")
print(f"MANCANTI ({len(mancanti)}):")
for x in mancanti: print("   !", x)
print(f"NEEDED non soddisfatti e NON di sistema ({len(extra)}):")
for n, v in sorted(extra.items()): print(f"   ! {n}  <- {', '.join(v[:3])}")
ok = not mancanti and not extra
print("BUNDLE-OK" if ok else "BUNDLE-INCOMPLETO")
sys.exit(0 if ok else 1)
