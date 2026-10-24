# harbour-rootitanium.spec — RPM self-contained per SailfishOS (DRAFT, non ancora usato)
# Metodo = come il repack qtwebengine gia' collaudato: si impacchetta uno STAGING
# gia' pronto (nessuna compilazione qui). Build: sb2 -t <target> rpmbuild -bb.
#
# Payload grosso -> /home/rootitanium (partizione /home, 63G liberi).
# File piccoli   -> /usr/bin (launcher ELF) + /usr/share (.desktop + icone), rootfs.
# Launcher /usr/bin/harbour-rootitanium: sailjail rifiuta gli script e vuole il
# binario in /usr/bin. Il launcher imposta l'env del bundle ed esegue
# /home/rootitanium/webengine-smoke (argv[0] = /usr/bin/harbour-rootitanium, per lipstick).
# .desktop: [X-Sailjail] Sandboxing=Disabled (l'app gira fuori dal firejail).

%global _apphome   /home/rootitanium
%global debug_package %{nil}
%define __os_install_post %{nil}
%define __brp_strip %{nil}
%define __brp_strip_static_archive %{nil}
%define __brp_strip_comment_note %{nil}

Name:       harbour-rootitanium
Version:    2.9
Release:    3
Summary:    RooTitanium — browser Qt6 WebEngine per SailfishOS
License:    GPLv3+ and LGPLv3 and BSD
# Codice app (GPL-3.0-or-later) + Qt6/QtWebEngine bundled (LGPLv3) + Chromium (BSD).
# Vedi LICENSE (GPL-3.0) e NOTICE.md (terze parti) nel repo.
Group:      Applications/Internet
# aarch64 e armv7hl (dall'8 ott 2026): l'arch la decide il target sb2 di rpmbuild
ExclusiveArch: aarch64 armv7hl
AutoReqProv: no
# Librerie di SISTEMA che il bundle non porta con se' (AutoReqProv e' spento,
# quindi vanno dichiarate a mano). Elenco ricavato il 12 ott 2026 leggendo i
# NEEDED di ogni ELF del bundle meno i soname che il bundle contiene (glibc
# esclusa). Per soname, cosi' vale qualunque pacchetto le fornisca. Sono tutte
# di serie su Sailfish OS 5.1 tranne libgbm: sull'X10 III mancava, arriva da
# mesa-llvmpipe-libgbm (Chromium 140 la vuole); openssl 3 serve a QtNetwork 6.12.
# libopenjp2 solo su armv7hl: li' il motore si linka all'openjpeg di sistema.
%ifarch aarch64
Requires: libgbm.so.1()(64bit)
Requires: libssl.so.3()(64bit)
Requires: libEGL.so.1()(64bit)
Requires: libGLESv2.so.2()(64bit)
Requires: libdrm.so.2()(64bit)
Requires: libwayland-client.so.0()(64bit)
Requires: libwayland-cursor.so.0()(64bit)
Requires: libwayland-egl.so.1()(64bit)
Requires: libmtdev.so.1()(64bit)
Requires: libudev.so.1()(64bit)
Requires: libsystemd.so.0()(64bit)
Requires: libsqlite3.so.0()(64bit)
Requires: libasound.so.2()(64bit)
Requires: libstdc++.so.6()(64bit)
Requires: libgcc_s.so.1()(64bit)
%else
Requires: libgbm.so.1
Requires: libssl.so.3
Requires: libEGL.so.1
Requires: libGLESv2.so.2
Requires: libdrm.so.2
Requires: libwayland-client.so.0
Requires: libwayland-cursor.so.0
Requires: libwayland-egl.so.1
Requires: libmtdev.so.1
Requires: libudev.so.1
Requires: libsystemd.so.0
Requires: libsqlite3.so.0
Requires: libasound.so.2
Requires: libstdc++.so.6
Requires: libgcc_s.so.1
Requires: libopenjp2.so.7
%endif

%description
Browser sperimentale basato su Qt 6.12 e Qt WebEngine 6.140 (Chromium 140)
accelerato via
libhybris/EGL su SailfishOS 5.1 (aarch64 e armv7hl). Bundle self-contained in /home/rootitanium;
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
# 3) attivazione DBus: un link con l'app chiusa la fa partire (task 2.5 #3).
#    Con Sandboxing=Disabled sailjaild non lo genera da se': va spedito.
mkdir -p %{buildroot}%{_datadir}/dbus-1/services
install -m0644 %{stagingdir}/com.github.RootGPT_YouTube.rootitanium.service %{buildroot}%{_datadir}/dbus-1/services/com.github.RootGPT_YouTube.rootitanium.service
#    Web Push (task 2.8 #0): Foghorn sveglia l'app chiusa chiamando questo nome;
#    RT_PUSH_WAKE=1 = parti nascosta, recapita la push e richiuditi da sola.
#    Niente sailjail (Sandboxing=Disabled), quindi l'Exec e' libero.
install -m0644 %{stagingdir}/org.unifiedpush.Connector.rootitanium.service %{buildroot}%{_datadir}/dbus-1/services/org.unifiedpush.Connector.rootitanium.service
# 3) icone -> hicolor (le taglie disponibili nello staging)
for s in 86 108 128 172 256; do
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
%{_datadir}/dbus-1/services/com.github.RootGPT_YouTube.rootitanium.service
%{_datadir}/dbus-1/services/org.unifiedpush.Connector.rootitanium.service
%{_datadir}/icons/hicolor/*/apps/harbour-rootitanium.png

%changelog
* Sat Oct 24 2026 RootGPT <emagiampa@gmail.com> - 2.9-3
- "Blocca link nascosti e pubblicita' a sorpresa": il video coperto da
  uno strato invisibile ora parte al primo tocco anche quando il player
  sta in un riquadro di un altro sito (prima la pubblicita' era bloccata
  ma il video non partiva). Uno strato tolto viene segnalato una volta
  per pagina.

* Sat Oct 24 2026 RootGPT <emagiampa@gmail.com> - 2.9-2
- Notifiche push nel vecchio formato aesgcm (Firebase, per esempio
  avito.ru): RooTitanium le sa leggere, appena Foghorn inoltrera' le
  intestazioni di cifratura (richiesta fatta all'autore). Fino ad allora
  resta la notifica generica del sito.
- Iscrizione alle notifiche push piu' affidabile: se Foghorn in quel
  momento non e' collegato al server (rete appena cambiata, telefono
  appena svegliato) RooTitanium riprova invece di rinunciare, e non
  lascia registrazioni orfane in Foghorn.

* Sat Oct 24 2026 RootGPT <emagiampa@gmail.com> - 2.9-1
- Download: accanto ad "Apri" c'e' "Apri con...", che elenca le app
  adatte al tipo di file (la predefinita e' segnata).
- Notifiche dei siti: su Jolla Home si possono espandere e hanno il
  pulsante "Elimina", che le toglie dalla vista Eventi.
- Se un sito riceve una notifica push ma non mostra niente (succede con
  avito.ru), RooTitanium mostra comunque una notifica generica del sito;
  toccandola si apre il sito.
- mail.rambler.ru: la pagina di accesso non si ricarica piu' da sola ogni
  30 secondi, si riesce a scrivere utente e password.
- Incognito col tema chiaro: barra in basso ed elenco schede leggibili.
- Nuova opzione "Blocca link nascosti e pubblicita' a sorpresa" (spenta):
  un tocco apre un altro sito solo se hai toccato un link visibile verso
  quel sito. Niente popup o pagine pubblicitarie quando premi play su un
  video; se una pagina vuole portarti altrove dopo un tocco, chiede.

* Tue Oct 20 2026 RootGPT <emagiampa@gmail.com> - 2.8.1-1
- Toccando una notifica push ad app chiusa si apre la pagina che il
  sito voleva mostrare (prima si apriva la sua pagina principale), e
  RooTitanium resta aperto.
- La sveglia per una notifica push in arrivo dura pochi secondi invece
  di circa 25: l'app si richiude appena la notifica e' consegnata.

* Mon Oct 19 2026 RootGPT <emagiampa@gmail.com> - 2.8-2
- Le pagine non passano piu' da sole alla versione desktop. Quando il
  telefono chiudeva il processo di una pagina (scheda in background da
  tempo, poca memoria, crash), alla ricarica la pagina tornava senza lo
  zoom mobile e il sito mostrava il layout desktop, anche con "Versione
  desktop" spenta. Ora lo zoom viene rimesso a ogni caricamento.
- Notifiche push dei siti ora anche su armv7hl (motore a 32 bit
  aggiornato).

* Mon Oct 19 2026 RootGPT <emagiampa@gmail.com> - 2.8-1
- Notifiche push dei siti (BETA, spente di default): con Foghorn
  (UnifiedPush, OpenRepos) i siti mandano notifiche anche ad app chiusa,
  senza server Google. Il contenuto e' cifrato dal sito al telefono.
  Impostazioni → Notifiche push dei siti, con pagina Istruzioni. Solo
  aarch64: su armv7hl il motore non ha ancora il supporto.
- File picker: le cartelle non si aprivano piu' (Qt 6.12 ha cambiato il
  modello dei file) e non si potevano caricare file. Riparato.
- Segnalibri modificabili: nome e indirizzo (✎ nella pagina Segnalibri).
- Animazioni fluide per menu', dialoghi e pagine (Impostazioni → Tema,
  spente di default).
- Gli interruttori delle Impostazioni non riportano piu' la pagina in cima.
- Swipe Indietro/Avanti e protezioni privacy di nuovo attivi anche sulla
  prima pagina di ogni sito nuovo.

* Thu Oct 15 2026 RootGPT <emagiampa@gmail.com> - 2.7-2
- Yandex Maps: "Let's go" → "Open" lasciava una scheda bianca (il sito
  prova ad aprire l'app Android). Ora la scheda vuota si chiude e compare
  un avviso: la navigazione guidata richiede l'app Android, usare Pure Maps.
- Ignorati in silenzio i link ad app Android aperti da un sito senza tocco
  dell'utente (Yandex Maps li tenta al caricamento del percorso).

* Thu Oct 15 2026 RootGPT <emagiampa@gmail.com> - 2.7-1
- Notifiche dei siti: arrivano come notifiche di Sailfish (titolo, testo,
  icona e nome del sito, suono e vibrazione). Toccandole si torna alla
  scheda del sito; ad app chiusa RooTitanium si riapre sul sito.
- Le schede dei siti autorizzati alle notifiche restano attive in
  background (prima venivano congelate e non avrebbero potuto notificare).
- In incognito le notifiche sono negate, come in Chrome.
- L'interruttore Permessi App > Notifiche spento zittisce anche i siti
  gia' autorizzati.
- About: versione corretta (diceva ancora 2.5).

* Thu Oct 15 2026 RootGPT <emagiampa@gmail.com> - 2.6-1
- Pulsante Ricarica nella barra, fra Indietro e l'indirizzo.
- Opzione: il pulsante HOME apre la pagina iniziale in una nuova scheda.
- User agent e Client Hints dicono la versione vera del motore
  (Chrome 140, prima 122), letta dal motore stesso.
- Google Maps: Indicazioni funziona (i link intent:// delle app Android
  aprono l'indirizzo di riserva, come fa Chrome); «Avvia» mostra un avviso
  invece di finire sul Play Store.
- Barra nascosta scorrendo: ricompare su ogni pagina nuova e sulle pagine
  interne (prima da Permessi siti non si tornava indietro).
- Nuova icona in stile acciaio.

* Mon Oct 12 2026 RootGPT <emagiampa@gmail.com> - 2.5-1
- Nuovo motore: Chromium 140 (Qt WebEngine 6.140 su Qt 6.12), con le
  correzioni di sicurezza fino a Chromium 154. Prima era Chromium 122.
  Lo stack Qt e' compilato da noi e viaggia dentro l'app come prima.
- Accelerazione grafica: con Chromium 140 la pagina restava nera,
  perche' il motore non condivide piu' da solo la GPU con Qt. Ora la
  condivisione la fa l'app: provato su Mali (POCO M4 Pro) e Adreno
  (Xperia 10 III), con WebGL. Circa il 14%% di CPU in meno della 2.2
  sullo stesso video.
- Video con il decoder del telefono: niente piu' immagine a strisce
  diagonali. Alcuni chip dichiarano una larghezza di riga diversa da
  quella vera (sull'Xperia 10 III i WebM, su altri telefoni gli .mp4);
  ora la larghezza giusta si ricava dai pixel.
- Permessi: se l'interruttore generale «Permessi App» e' spento e un
  sito chiede il microfono o la posizione, un avviso lo dice invece di
  rifiutare in silenzio.
- Le Impostazioni non chiudono piu' l'app quando si tocca un
  interruttore.
- Cronologia: ora si puo' cancellare una voce sola (la X accanto a ogni
  riga), tutto un sito, o un periodo (ultima ora, oggi, ultimi 7 giorni,
  tutto). Ogni cancellazione di gruppo chiede conferma e dice quante voci
  spariranno. Con le voci se ne va anche il ricordo dei link visitati
  (il colore dei link gia' aperti).
- Barra degli indirizzi: sulle pagine interne (Cronologia, Segnalibri,
  Impostazioni...) mostrava ancora l'indirizzo del sito precedente; ora
  mostra quello della pagina aperta.
- Nuove dipendenze dichiarate: libgbm (mesa-llvmpipe-libgbm) e le altre
  librerie di sistema che il pacchetto usa; vengono installate da sole.

* Sat Oct 10 2026 RootGPT <emagiampa@gmail.com> - 2.2-1
- Link da altre app: con RooTitanium in background il link si apre in
  una scheda nuova e l'app torna in primo piano. Le schede gia' aperte
  restano. Anche toccando l'icona con l'app aperta, ora l'app torna
  avanti invece di ripartire.
- Nuova voce «Esci» nel menu': chiude davvero l'app, compresi i processi
  del motore.
- Se un avvio precedente era rimasto bloccato senza finestra, l'app lo
  chiude da sola e parte: prima toccando l'icona non succedeva nulla.
- Posizione per i siti: ora funziona, con il GPS del telefono e la
  posizione dalle celle quando il GPS non ha ancora agganciato i satelliti.
- Motori di ricerca: aggiunti Yandex, Ecosia, Brave Search e Qwant, e si
  possono aggiungere motori propri (Impostazioni › Motore di ricerca).
- Barra degli indirizzi in basso, con l'opzione «Nascondi scorrendo»
  (Impostazioni › Barra degli indirizzi).
- Permessi: con un interruttore di «Permessi App» spento, i siti non
  restano bloccati per sempre; riacceso, tornano a chiedere.
- Il menu' ⋮ si apre sotto la barra invece di coprirla.

* Tue Sep 29 2026 RootGPT <emagiampa@gmail.com> - 2.1-1
- x.com: scorrendo la timeline i post si caricano di nuovo, invece di
  fermarsi ai primi. La colpa era dell'opzione «Rifiuta cookie», che su
  ogni sito spostava lo scroll dalla finestra al corpo della pagina: i
  siti che caricano contenuti mentre si scorre non se ne accorgevano.
  Ora lo scroll viene sbloccato solo dove un banner dei cookie lo aveva
  davvero bloccato. Valeva per tutti i siti di questo tipo, non solo X.
- Dall'8 ottobre anche per telefoni a 32 bit (armv7hl): stesso browser,
  motore ricompilato per ARM a 32 bit, con lo stesso decoder video hardware
  droidmedia dell'aarch64. Dove il telefono non lo supporta, il video passa
  da solo alla decodifica software.

* Sat Sep 19 2026 RootGPT <emagiampa@gmail.com> - 2.0-1
- Decodifica video in hardware: i video VP9, il formato di YouTube, li
  decodifica il chip del telefono invece del processore. Misurato sul
  POCO M4 Pro con un 1080p: il 43%% di CPU del browser in meno, circa
  2 gradi in meno e da 0,2 a 0,3 W in meno, senza perdere fotogrammi.
  Dove la decodifica hardware non c'e' o il formato non e' supportato,
  il browser torna da solo a quella normale. Il pezzo di droidmedia che
  lo rende possibile e' incluso nel pacchetto: nessuna dipendenza nuova.
- Swipe per Indietro e Avanti: trascinando dal centro della pagina verso
  destra si torna indietro, verso sinistra si va avanti. Una freccia
  segue il dito e si accende oltre la soglia; rilasciando prima si
  annulla. Il gesto resta al sito quando il sito lo usa (caroselli,
  mappe, zone che scorrono di lato, pagina ingrandita). Acceso di
  default, si spegne da Impostazioni -> Pagine web.
- Pagina Informazioni: crediti per droidmedia e libhybris, che
  permettono di usare il decoder video del telefono.
- Questa versione sostituisce la 1.9-9, preparata ma mai pubblicata.

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
