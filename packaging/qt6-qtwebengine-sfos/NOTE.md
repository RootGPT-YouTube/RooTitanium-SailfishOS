# qt6-qtwebengine-sfos — overlay dello spec chum

`rpm/qt6-qtwebengine.spec` è la copia **adattata per RooTitanium** dello spec di
`sailfishos-chum/qt6-qtwebengine` (clone in `../../qt6-qtwebengine/`, escluso da
git). Al momento del build va usata questa copia al posto dell'originale.

## Differenze rispetto allo spec chum (5 lug 2026)

1. **`qt6-srpm-macros` rimosso dai BR** — definiva solo `%qt6_qtwebengine_arches`,
   che lo spec non usa (`ExclusiveArch: aarch64 x86_64` è hardcoded). Il pacchetto
   non esiste in qt6sb2 e pacchettizzarlo sarebbe stato lavoro inutile.
2. **`qt6-qtquickcontrols2-devel` rimosso dai BR** — in Qt6 QuickControls2 è parte
   di qtdeclarative (già nei BR); il pacchetto separato non esiste in qt6sb2.
3. **`snappy-devel` commentato** — snappy non esiste in SFOS/chum; Chromium bundla
   comunque `third_party/snappy`. Da ripristinare (e pacchettizzare snappy) solo
   se il configure fallisce.

Il BR `nodejs` è soddisfatto da `nodejs-bin` (che ha `Provides: nodejs`);
`python3-html5lib` dal nostro pacchetto in `../python3-html5lib/`.

## Da verificare al primo configure (Fase 2)

- **Macro `%cmake_qt6`, `%_qt6_libdir`, `%_qt6_version` ecc.**: nello stack Fedora
  vengono da qt6-rpm-macros; da verificare se il `qt6-qtbase-devel` di piggz le
  fornisce. In caso contrario: inlinare le definizioni in testa allo spec.
- **`npm`/`npx`**: se il build li invoca oltre a `node`, estendere nodejs-bin.
- **kernel-headers**: lo spec chum indica che servono header recenti
  (`nemo:devel:hw:native-common` su build.sailfishos.org) — da installare nel
  target clonato prima del configure.
- **Tarball Source0**: lo spec fa `%setup -n %{name}-%{version}/upstream`; per il
  build locale va creato il tarball dal clone (~3,5 GB) o adattato il workflow
  (rpmbuild --build-in-place / mb2).
