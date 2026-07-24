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
Version:    1.4.5
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
# 1b) qt.conf: SOSTITUISCE i path Qt compilati (qt_prfxpath=/usr) invece di
#     aggiungersi come fa QT_PLUGIN_PATH. Senza, il processo pesca anche in
#     /usr/lib64/qt6/plugins, che su chi ha (o ha avuto) Qt Runner e' pieno di
#     plugin Qt6 di sistema. Generato qui e non preso dallo staging: cosi' vale
#     anche per staging assemblati prima di questa modifica. Vedi
#     Documentation/TASK-2-isolamento-bundle.md e smoke-test/qt.conf.
cat > %{buildroot}%{_apphome}/qt.conf <<'RTQTCONF'
[Paths]
Prefix = .
Plugins = plugins
Imports = qml
Qml2Imports = qml
Libraries = lib
LibraryExecutables = libexec
RTQTCONF
chmod 0644 %{buildroot}%{_apphome}/qt.conf
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
# 4) licenze -> accompagnano il binario (obbligo GPL/LGPL). LICENSE = GPL-3.0 app;
#    NOTICE.md = terze parti (Qt6/QtWebEngine LGPLv3, Chromium BSD) con puntatori ai sorgenti.
mkdir -p %{buildroot}%{_defaultlicensedir}/%{name}
install -m0644 %{stagingdir}/LICENSE   %{buildroot}%{_defaultlicensedir}/%{name}/LICENSE
install -m0644 %{stagingdir}/NOTICE.md %{buildroot}%{_defaultlicensedir}/%{name}/NOTICE.md

%files
%defattr(-,root,root,-)
%license %{_defaultlicensedir}/%{name}/LICENSE
%license %{_defaultlicensedir}/%{name}/NOTICE.md
%{_apphome}
%{_bindir}/harbour-rootitanium
%{_datadir}/applications/harbour-rootitanium.desktop
%{_datadir}/icons/hicolor/*/apps/harbour-rootitanium.png

%changelog
* Fri Jul 24 2026 RootGPT-YouTube <rootgpt@users.noreply.github.com> - 1.4.5-1
- Corretto lo schermo nero su Xperia 10 II (e possibili altri device): la 1.4
  forzava il fullscreen reale per rimediare alla fascia nera dell'Xperia 10 III,
  ma su altre GPU faceva sparire la pagina web (nera dopo un istante). Ripristinato
  il comportamento di visualizzazione della 1.3 su tutti i dispositivi.
- Restano attive le migliorie 1.4 alle Impostazioni (scheda dedicata, niente
  scroll in cima al cambio di un'opzione). Nota: su alcuni Xperia 10 III puo'
  ricomparire la fascia nera in fondo (cosmetica); e' il compromesso per avere il
  browser di nuovo utilizzabile ovunque.

* Wed Jul 22 2026 RootGPT-YouTube <rootgpt@users.noreply.github.com> - 1.4-1
- Impostazioni: ora si aprono in una scheda dedicata, senza sovrascrivere la
  pagina su cui ti trovavi (torni indietro e la ritrovi).
- Cambiare un'impostazione (interruttore, motore di ricerca, cartella dei
  download) non riporta piu' la pagina in cima: resti sull'opzione toccata.
- Corretta la fascia nera in fondo allo schermo su Xperia 10 III: la finestra
  ora occupa tutto lo schermo (forzato il fullscreen reale sul compositore).

* Tue Jul 21 2026 RootGPT-YouTube <rootgpt@users.noreply.github.com> - 1.3-1
- Privacy (task 1.3): tre nuovi interruttori in Impostazioni, TUTTI SPENTI di
  default perche' possono rompere siti: "Blocca i cookie di terze parti",
  "Non inviare il referrer ai siti esterni", "Isola lo storage di terze parti"
  (quest'ultimo agisce al riavvio dell'app: e' un flag di Chromium).
- "Non tenere traccia" ora manda davvero gli header DNT: 1 e Sec-GPC: 1; prima
  era solo JavaScript e nessun segnale partiva sul filo.
- Spente le API che questo browser non usa e che allargano la superficie
  d'attacco: WebBluetooth, WebUSB, WebNFC, IdleDetection, FedCM, WebOTP. WebRTC
  non rivela piu' gli indirizzi della rete locale; le pagine pubbliche non
  possono sondare la rete di casa.
- Il display non si spegne piu' da solo mentre un video e' in riproduzione
  (task #3), nemmeno se il video e' muto. A video fermo il timeout torna quello
  di sistema.
- Correzione: gli interruttori con una cifra nel nome venivano ignorati in
  silenzio dalla pagina Impostazioni.
- Fascia nera in basso alta quanto una tastiera (X10 III): la finestra impone
  ora la propria geometria e non subisce piu' quella del compositor; il bundle
  non pesca piu' plugin Qt6 di sistema (qt.conf) e non eredita variabili Qt5 di
  Sailfish che gli spostavano la geometria sotto i piedi.
- Diagnostica: `touch /home/rootitanium/DEBUG` fa scrivere /tmp/rootitanium.log
  anche ai lanci dall'icona; `rm` per spegnerla.

* Tue Jul 21 2026 RootGPT-YouTube <rootgpt@users.noreply.github.com> - 1.2-2
- Fascia nera in basso alta quanto una tastiera (Xperia X10 III / SFOS 5.1.0.11,
  segnalata da due utenti, entrambi con Qt Runner installato o rimosso di recente).
  Due cure, su strati diversi dello stesso sintomo:
- qt.conf accanto al binario: i path Qt del bundle SOSTITUISCONO quelli compilati
  (qt_prfxpath=/usr), cosi' i plugin Qt6 di sistema lasciati in /usr/lib64/qt6 da
  Qt Runner non entrano piu' nel nostro processo. QT_PLUGIN_PATH da solo non basta:
  e' additivo.
- Finestra: geometria imposta da Screen invece che subita dal compositor, con
  diagnostica in /tmp/rootitanium.log se viene comunque rimpicciolita.

* Mon Jul 20 2026 RootGPT-YouTube <rootgpt@users.noreply.github.com> - 1.2-1
- Versione 1.2: i link tappati in altre app (RooTelegram & co.) ora si aprono
  anche quando RooTitanium e' gia' in esecuzione, sempre in una scheda NUOVA.
- .desktop: riga invoker scritta per esteso, senza «--single-instance» (che
  lipstick aggiungeva da se'): con l'app viva quel flag faceva uscire il
  processo prima di consegnare l'URL di %u.
- webengine-smoke: servizio di sessione com.github.RootGPT_YouTube.rootitanium
  (org.freedesktop.Application.openUrl); il processo lanciato per il link passa
  l'URL all'istanza viva e termina, mai una seconda finestra.

* Sun Jul 19 2026 RootGPT-YouTube <rootgpt@users.noreply.github.com> - 1.1-1
- Versione 1.1: file picker mobile per upload (<input type=file>), Modalita'
  Lettura (Readability.js 0.6.0 bundled, Apache-2.0 in NOTICE), Accept-Language
  dal locale reale, pinch zoom a due dita, fix tasto spazio tastiera.
- Launcher: QML_XHR_ALLOW_FILE_READ=1 (lettura Readability.js dal bundle).
- Trim bundle (~19 MB): rimossi Widgets/LabsPlatform/Pdf(+plugin qpdf)/
  PositioningQuick/Test/QuickTest/WaylandCompositor e moduli QML morti
  (QtTest, Qt/test, QtSensors, QtLocation, QtPositioning, Qt/labs/platform,
  Controls/Imagine, QtQuick/Pdf, QtWayland); strip launcher+webengine-smoke.

* Thu Jul 16 2026 RootGPT-YouTube <rootgpt@users.noreply.github.com> - 1.0-2
- Includo LICENSE (GPL-3.0) e NOTICE.md (terze parti) sotto %{_defaultlicensedir}
  (obbligo GPL/LGPL: il testo di licenza accompagna il binario distribuito).

* Wed Jul 15 2026 RootGPT-YouTube <rootgpt@users.noreply.github.com> - 1.0-1
- Primo pacchetto: RPM self-contained (bundle Qt6 WebEngine in /home/rootitanium),
  launcher ELF /usr/bin/harbour-rootitanium, .desktop con [X-Sailjail] Sandboxing=Disabled.
