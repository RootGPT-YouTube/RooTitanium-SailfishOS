# nodejs-bin.spec - repack del binario prebuilt ufficiale Node.js per aarch64
# Fornisce /usr/bin/node come tool di SOLO build-time per soddisfare il
# BuildRequires "Node.js >= 14" di qt6-qtwebengine (>= 6.5, incl. 6.8.3).
#
# Non compila Node.js da sorgente: ripacchettizza il tarball ufficiale
# linux-arm64 da nodejs.org. Viene incluso solo il binario `node`; npm,
# corepack, header e doc sono esclusi perché non serve un runtime
# Node.js per applicazioni Sailfish, solo un tool di code-generation
# per il build di QtWebEngine/Chromium.
#
# SHA256 (da https://nodejs.org/dist/v22.23.1/SHASUMS256.txt, verificato
# il 5 lug 2026):
#   0294e8b915ab75f92c7513d2fcb830ae06e10684e6c603e99a87dbf8835389c1
#   node-v22.23.1-linux-arm64.tar.xz
#   c24dcdd3df032a34d1c858ddac9e514d3cac6fa655cc92cd4afe4e589c866a10
#   node-v22.23.1-linux-armv7l.tar.xz   (verificato l'8 ott 2026, build 32 bit)

%define nodever 22.23.1
# binario prebuilt: niente debuginfo (il tarball armv7l non ha la build-id e
# find-debuginfo --strict-build-id fallirebbe)
%global debug_package %{nil}
%ifarch armv7hl
%define nodearch armv7l
%else
%define nodearch arm64
%endif

Name:           nodejs-bin
Version:        %{nodever}
Release:        1
Summary:        Node.js prebuilt binary (solo build-time, per qt6-qtwebengine)
License:        MIT
URL:            https://nodejs.org
Source0:        https://nodejs.org/dist/v%{nodever}/node-v%{nodever}-linux-%{nodearch}.tar.xz

ExclusiveArch:  aarch64 armv7hl

BuildRequires:  xz

Provides:       nodejs = %{nodever}
Provides:       node(engine) = %{nodever}

%description
Repack del binario prebuilt ufficiale Node.js %{nodever} linux-%{nodearch}.
Fornisce esclusivamente /usr/bin/node, usato come tool host da
qt6-qtwebengine (e altri build system derivati da Chromium) per
eseguire script di generazione codice durante configure/build. Non è
pensato come runtime Node.js generico per applicazioni Sailfish.

%prep
%setup -q -n node-v%{nodever}-linux-%{nodearch}

%build
# nulla da compilare: binario prebuilt

%install
install -D -m 0755 bin/node %{buildroot}%{_bindir}/node

%files
%license LICENSE
%{_bindir}/node

%changelog
* Thu Oct 08 2026 RootGPT <emagiampa@gmail.com> - 22.23.1-1
- Anche armv7hl (tarball linux-armv7l), per il motore a 32 bit.

* Sun Jul 05 2026 RootGPT <emagiampa@gmail.com> - 22.23.1-1
- Repack iniziale del binario prebuilt Node.js linux-arm64 per
  soddisfare il BuildRequires di qt6-qtwebengine 6.8.3.
