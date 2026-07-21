# Task #3 — il display non deve spegnersi mentre un video è in play

Aperta il 21 lug 2026. Affianca la [#1 (1.3) hardening privacy](TASK-1.3-hardening.md)
e la [#2 isolamento bundle](TASK-2-isolamento-bundle.md); indipendente da entrambe.

Stato: **FATTA il 21 lug 2026** (commit 6212597, in RPM 1.3-1), collaudata sul
device. Implementata come previsto qui sotto, senza scostamenti.

Verifica eseguita con `dbus-monitor --system` **come root** (senza root non si
vede il traffico altrui: il primo test è risultato falsamente negativo):
con un media in play due `req_display_blanking_pause` in 40 s, alla pausa un
`req_display_cancel_blanking_pause` e nessun rinnovo successivo. Prova di
controllo con `dbus-send` manuale per validare il monitor stesso.

## Il difetto

Guardando un video in RooTitanium — **non solo su YouTube** — il display si spegne
da sé dopo il timeout di inattività di SailfishOS. È il comportamento normale del
sistema: senza tocchi sullo schermo, MCE spegne. Il browser però non gli sta
dicendo che c'è una riproduzione in corso, mentre ogni player nativo lo fa.

Requisito: **con un video in riproduzione, il display non si spegne mai da sé.**
Fuori dal play (pausa, fine, scheda cambiata, app in background) il timeout
normale deve tornare in vigore — non vogliamo un browser che tiene acceso lo
schermo per distrazione.

## Come si tiene acceso il display su SFOS

L'API pulita sarebbe `Nemo.KeepAlive` (`DisplayBlanking { preventBlanking: true }`),
ma è **Qt5/Silica**: per noi non esiste. Sotto, quel componente non fa altro che
chiamare MCE, e MCE possiamo chiamarlo direttamente:

| campo | valore |
|---|---|
| bus | **system** (non session: `main.cpp` oggi usa solo `sessionBus()`) |
| servizio | `com.nokia.mce` |
| oggetto | `/com/nokia/mce/request` |
| interfaccia | `com.nokia.mce.request` |
| metodo | `req_display_blanking_pause` (nessun argomento) |
| annulla | `req_display_cancel_blanking_pause` |

Proprietà importante: **la pausa scade da sé dopo ~60 s** e va rinnovata. È una
garanzia di sicurezza, non una scomodità: se l'app viene chiusa o va in crash
mentre il video è in play, il display torna al comportamento normale entro un
minuto da solo, senza lasciare il telefono acceso all'infinito. Rinnovo previsto
ogni **30 s**.

Nessun problema di permessi: il `.desktop` ha `[X-Sailjail] Sandboxing=Disabled`,
quindi il system bus è raggiungibile.

## Come sapere che c'è un video in play

Due segnali, complementari — nessuno dei due basta da solo.

1. **`WebEngineView.recentlyAudible`** (proprietà nativa QtWebEngine): copre tutto
   ciò che emette suono, a costo zero e senza iniettare niente. Non copre i video
   **muti** o con volume a zero, che sono comunissimi (autoplay, GIF-video).
2. **Sondaggio JS periodico** sulla sola scheda attiva, ogni ~20 s, via
   `runJavaScript` (il canale QML→JS già usato in `test.qml:793` e `test.qml:1035`):

   ```js
   (function(){
     var m = document.querySelectorAll('video,audio');
     for (var i = 0; i < m.length; i++)
       if (!m[i].paused && !m[i].ended && m[i].readyState > 2) return true;
     return false;
   })()
   ```

   20 s è ampiamente sotto il timeout di blanking più corto e il costo è
   trascurabile. Un `setInterval` iniettato che notifica solo sui cambi di stato
   sarebbe più elegante, ma il canale JS→QML in questo progetto è la parte scomoda
   (vedi il trucco `Image` per gli schemi custom): il polling ottiene lo stesso
   risultato con molto meno da mantenere.

`videoFS` (`test.qml:2178`, da `fullScreenRequested`) **non** è un segnale
sufficiente: la maggior parte dei video si guarda senza fullscreen. Va però usato
come terzo segnale immediato, perché in fullscreen l'intento è inequivocabile.

Condizione finale: `(recentlyAudible || pollJS || videoFS)` **e** applicazione
attiva in primo piano.

## Implementazione prevista

1. **`main.cpp`, in `NativeHelper`** (già esposto a QML come `rtNative`,
   `main.cpp:217`): aggiungere

   ```cpp
   Q_INVOKABLE void setKeepDisplayOn(bool on);
   ```

   con un `QTimer` interno a 30 s che rinnova `req_display_blanking_pause` su
   `QDBusConnection::systemBus()`, e che allo spegnimento ferma il timer e manda
   `req_display_cancel_blanking_pause`. Tutto lo stato sta in C++: il QML dice solo
   sì/no. Serve `#include <QTimer>`.
2. **`test.qml`**: una property `videoPlaying` calcolata dai tre segnali, un
   `Timer` a 20 s per il sondaggio, e `onVideoPlayingChanged: rtNative.setKeepDisplayOn(...)`.
   Spegnere anche su `Qt.application.state !== Qt.ApplicationActive` e al cambio
   scheda (`onCurrentTabChanged`, `test.qml:104`).
3. Nessuna impostazione utente in prima battuta: è un comportamento atteso, non una
   preferenza. Se emergesse il caso d'uso contrario, il toggle si aggiunge dopo.

## Collaudo

- Video **con audio**, non fullscreen, nessun tocco per 3-4 minuti → display acceso.
- Video **muto** nelle stesse condizioni → display acceso (è il caso che
  `recentlyAudible` da solo mancherebbe).
- Pagina **senza** video, nessun tocco → il display si spegne come sempre
  (regressione da verificare esplicitamente: è il modo in cui questo fix può fare
  danno).
- Video in play, poi **schermo bloccato a mano** con il tasto → deve spegnersi
  comunque: la pausa di blanking non deve vincere su una scelta esplicita.
- Video in play, poi **app in background** → display libero di spegnersi.
- **Kill dell'app** durante il play → entro ~60 s il comportamento torna normale.

Da collaudare lanciando **dall'icona**, non solo da ssh (vedi le trappole di
collaudo note: processo `run.sh` e non `webengine-smoke`).
