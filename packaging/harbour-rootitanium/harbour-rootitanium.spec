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
Version:    1.9
Release:    9
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
* Fri Sep 18 2026 RootGPT <emagiampa@gmail.com> - 1.9-9
- Decodifica video in hardware funzionante: i video VP9 (il formato di
  YouTube) vengono ora decodificati dal chip del telefono invece che dal
  processore. Sul POCO M4 Pro il consumo scende da 71%% a 57%% di un core
  su un 1080p, senza perdere un fotogramma.
- Rispetto alle prove precedenti sono stati corretti: il blocco del video
  quando riparte da capo o cambia segmento, i tempi dei fotogrammi
  (erano letti in un'unita' sbagliata), e un crash che chiudeva la pagina
  appena partiva un video.
- Dove la decodifica hardware non e' disponibile o il formato non e'
  supportato, il browser torna da solo a quella normale.

* Fri Sep 18 2026 RootGPT <emagiampa@gmail.com> - 1.9-4
- I video ora scorrono: il decoder leggeva il tempo di ogni fotogramma
  in un'unita' sbagliata (mille volte piu' grande), cosi' il video
  credeva di essere gia' finito e si fermava dopo pochi fotogrammi con
  l'immagine bloccata.

* Fri Sep 18 2026 RootGPT <emagiampa@gmail.com> - 1.9-3
- Terzo e decisivo difetto della serie: il decoder passava un puntatore
  nullo a droidmedia quando le consegnava i dati da decodificare, e
  droidmedia ci finiva sopra. E' questo che faceva morire la pagina, non
  la libreria mancante di ieri. Riprodotto fuori dal browser, in venti
  righe: con il puntatore nullo si schianta subito, con un riferimento
  valido i fotogrammi escono.
- Lo stesso riferimento tiene ora in vita i dati finche' il decoder del
  telefono non ha finito di usarli, cosa che prima non era garantita.
- Tolto anche un secondo ciclo di lettura che facevamo noi in parallelo a
  quello gia' avviato da droidmedia: due lettori sullo stesso decoder.

* Fri Sep 18 2026 RootGPT <emagiampa@gmail.com> - 1.9-2
- La 1.9-1 non riusciva a riprodurre i video: il decoder droidmedia si
  appoggiava a una libreria del produttore del telefono per convertire i
  fotogrammi, e su parecchi dispositivi (fra cui il POCO M4 Pro) quella
  libreria non esiste. Peggio: il decoder non se ne accorgeva e restava
  li' a non produrre nulla, senza lasciare che il browser tornasse al
  decoder normale. Da qui il video fermo.
- Ora la conversione la fa il browser stesso, con codice che ha gia'
  dentro: nessuna dipendenza dal produttore, quindi funziona uguale su
  tutti i telefoni. E se il formato dei fotogrammi non e' fra quelli che
  sappiamo trattare, il decoder si tira indietro subito e il video parte
  lo stesso, come prima, senza accelerazione.

* Fri Sep 18 2026 RootGPT <emagiampa@gmail.com> - 1.9-1
- Motore ricostruito con il decoder video droidmedia innestato: e' il
  primo pacchetto che lo contiene. Sotto c'e' MediaCodec di Android,
  raggiunto via droidmedia e libhybris, e il decoder si mette PRIMA dei
  tre software di Chromium. Se rifiuta -- device senza droidmedia, codec
  non supportato dal vendor -- si ripiega da solo sul software.
- Il shim droidmedia e' linkato STATICO: nessuna dipendenza nuova, un
  pacchetto solo per tutti i device, come le versioni precedenti.
- ATTENZIONE: prima prova sul campo della decodifica hardware. Se un
  video non parte o l'app si chiude riaprendo una pagina con video,
  e' qui che bisogna guardare; la 1.8-1 resta installabile a ritroso.

* Thu Sep 17 2026 RootGPT <emagiampa@gmail.com> - 1.8-1
- Selezione del testo: i due pallini ora si afferrano davvero. Non era
  colpa del motore: lo strato che chiude il menu' contestuale copre
  tutto lo schermo e si mangiava il tocco prima che Chromium lo
  vedesse. Il menu' inoltre stava 16 px sotto la selezione mentre i
  pallini ne sporgono 26, e ne copriva il 40%%.
- I pallini sono ora disegnati dall'app, a tema e con bordo chiaro per
  restare visibili su qualunque pagina. Serviva soprattutto per sapere
  dove sono: senza le loro coordinate, un tocco sul testo selezionato
  e' indistinguibile dalla presa di un pallino.
- Tocco fuori dalla selezione: un tocco solo per chiudere menu' e
  selezione, non piu' tre.
- Privacy, nuovi valori predefiniti: "Non tenere traccia" e "Blocca i
  cookie di terze parti" ora sono ACCESI di serie. Gli altri toggle
  della sezione Privacy non cambiano.

* Sat Sep 06 2026 RootGPT <emagiampa@gmail.com> - 1.7-1
- Tastiera di sistema (Maliit) al posto della QtVirtualKeyboard in-app:
  il plugin input-context Qt6 e' imbarcato nel bundle (LGPLv2), la
  QtVirtualKeyboard resta come ripiego dove maliit-server manca.
- La tastiera ruota anche in orizzontale: la rotazione passa al
  compositor (contentOrientation) e l'angolo arriva al server maliit
  tramite un container D-Bus interno all'app.
- Corretti due difetti latenti di dimensionamento: zoom della pagina e
  unita' della UI ora si basano sullo schermo, non sulla finestra, che
  si accorcia quando compare la tastiera.
- Grazie a Cristoffer (Imperador) per la segnalazione e le prove.

* Sat Sep 05 2026 RootGPT-YouTube <rootgpt@users.noreply.github.com> - 1.6-1
- YouTube, controlli del video: il tocco sul video torna a farli comparire.
  Un accorgimento aggiunto a luglio serviva a impedire che quel tocco mettesse
  in pausa il video per sbaglio; da allora YouTube ha cambiato il proprio
  lettore e quell'accorgimento era diventato lui il problema, mangiandosi il
  tocco. Ora l'app non intercetta piu' nulla: si limita a correggere la pausa
  indesiderata se e quando ricompare.
- YouTube, barra di avanzamento: si puo' toccare un punto qualsiasi della barra
  per saltare li'. Il lettore di YouTube si sposta solo se si trascina il dito;
  toccando e basta non succedeva nulla.
- Menu' a tendina delle pagine (le liste «a discesa» dei moduli): tornano a
  rispondere al tocco.

* Fri Aug 14 2026 RootGPT-YouTube <rootgpt@users.noreply.github.com> - 1.5-1
- Motore aggiornato a QtWebEngine 6.8.4: comprende le correzioni di sicurezza
  di Chromium fino alla 138.0.7204.96.
- Crediti rifatti di conseguenza nella schermata «Informazioni» e nel NOTICE.
* Sun Aug 09 2026 RootGPT-YouTube <rootgpt@users.noreply.github.com> - 1.4.7-1
- Corretto un difetto introdotto dalla 1.4.6 su alcuni telefoni (per esempio i
  porting con la fotocamera dentro lo schermo, come lo Xiaomi POCO M4 Pro 4G):
  l'app vedeva una striscia in alto riservata dal sistema, la scambiava per la
  tastiera e cercava di riprendersela, finendo per sporgere oltre il bordo
  inferiore dello schermo. Il risultato era una fascia nera in alto e la tastiera
  dell'app tagliata in basso.
- Ora l'app distingue le due cose: si riprende lo schermo solo quando l'area
  sottratta e' grande quanto una tastiera. Dove la striscia riservata e' piccola
  la lascia al sistema e il contenuto resta tutto visibile.
- Sui telefoni gia' a posto e su quelli con la fascia nera della 1.4.6 (Xperia
  10 III e simili) non cambia nulla: verificato su entrambi.

* Tue Jul 28 2026 RootGPT-YouTube <rootgpt@users.noreply.github.com> - 1.4.6-1
- Risolta la fascia nera in fondo allo schermo (Xperia 10 III e altri): non era un
  difetto di visualizzazione dell'app ma dell'ambiente. Quando la tastiera di
  sistema viene ricaricata (cambio di layout, per esempio il passaggio a Emoji con
  una pressione lunga sulla barra spazio, oppure un riavvio del servizio), il
  compositore continua a tenere riservata l'area della tastiera e la toglie a ogni
  finestra aperta da quel momento in poi, finche' il telefono non viene riavviato.
- L'app ora se ne accorge e si riprende lo schermo intero, ripetendo la richiesta
  anche se l'area viene tolta di nuovo mentre si naviga. Su un dispositivo che non
  ha il problema non cambia assolutamente nulla: nessuna richiesta viene inviata al
  compositore, quindi l'Xperia 10 II non e' toccato.
- Rimedio immediato senza aggiornare, per chi ha la fascia nera adesso: dal
  terminale «systemctl --user restart lipstick» (l'interfaccia si ricarica in pochi
  secondi, non serve riavviare il telefono).
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
