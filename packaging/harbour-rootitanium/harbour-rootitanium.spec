# harbour-rootitanium.spec — RPM self-contained per SailfishOS (DRAFT, non ancora usato)
# Metodo = come il repack qtwebengine gia' collaudato: si impacchetta uno STAGING
# gia' pronto (nessuna compilazione qui). Build: sb2 -t <target> rpmbuild -bb.
#
# Payload grosso -> /home/rootitanium (partizione /home, 63G liberi).
# File piccoli   -> /usr/bin (launcher ELF) + /usr/share (.desktop + icone), rootfs.
# Launcher /usr/bin/harbour-rootitanium: sailjail rifiuta gli script e vuole il
# binario in /usr/bin. Il launcher imposta l'env del bundle ed esegue
# /home/rootitanium/webengine-smoke (argv[0] = suo path, cosi' main.cpp trova test.qml).
# .desktop: [X-Sailjail] Sandboxing=Disabled (l'app gira fuori dal firejail).

%global _apphome   /home/rootitanium
%global debug_package %{nil}
%define __os_install_post %{nil}
%define __brp_strip %{nil}
%define __brp_strip_static_archive %{nil}
%define __brp_strip_comment_note %{nil}

Name:       harbour-rootitanium
Version:    1.0
Release:    1
Summary:    RooTitanium — browser Qt6 WebEngine per SailfishOS
License:    GPLv3+ and LGPLv3 and BSD
# Codice app (GPL-3.0-or-later) + Qt6/QtWebEngine bundled (LGPLv3) + Chromium (BSD).
# Vedi LICENSE (GPL-3.0) e NOTICE.md (terze parti) nel repo.
Group:      Applications/Internet
BuildArch:  aarch64
AutoReqProv: no

%description
Browser sperimentale basato su Qt6 WebEngine (Chromium 122) accelerato via
libhybris/EGL su SailfishOS 5.1 aarch64. Bundle self-contained in /home/rootitanium;
nessuna dipendenza Qt6 di sistema richiesta. Studio di fattibilita'.

%prep
# nulla: lo staging viene passato via --define 'stagingdir ...'

%install
rm -rf %{buildroot}
# 1) payload -> /home/rootitanium (staging gia' TRIMMATO a monte)
mkdir -p %{buildroot}%{_apphome}
cp -a %{stagingdir}/bundle/. %{buildroot}%{_apphome}/
# 2) launcher ELF -> /usr/bin (sailjail: Exec dev'essere un ELF in /usr/bin)
mkdir -p %{buildroot}%{_bindir}
install -m0755 %{stagingdir}/rootitanium-launch %{buildroot}%{_bindir}/harbour-rootitanium
# 3) .desktop -> /usr/share/applications
mkdir -p %{buildroot}%{_datadir}/applications
install -m0644 %{stagingdir}/harbour-rootitanium.desktop %{buildroot}%{_datadir}/applications/harbour-rootitanium.desktop
# 3) icone -> hicolor (le taglie disponibili nello staging)
for s in 86 108 128 172; do
  if [ -f %{stagingdir}/icons/${s}.png ]; then
    mkdir -p %{buildroot}%{_datadir}/icons/hicolor/${s}x${s}/apps
    install -m0644 %{stagingdir}/icons/${s}.png %{buildroot}%{_datadir}/icons/hicolor/${s}x${s}/apps/harbour-rootitanium.png
  fi
done

%files
%defattr(-,root,root,-)
%{_apphome}
%{_bindir}/harbour-rootitanium
%{_datadir}/applications/harbour-rootitanium.desktop
%{_datadir}/icons/hicolor/*/apps/harbour-rootitanium.png

%changelog
* Wed Jul 15 2026 RootGPT-YouTube <rootgpt@users.noreply.github.com> - 1.0-1
- Primo pacchetto: RPM self-contained (bundle Qt6 WebEngine in /home/rootitanium),
  launcher ELF /usr/bin/harbour-rootitanium, .desktop con [X-Sailjail] Sandboxing=Disabled.
