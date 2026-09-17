# Selezione del testo touch — risolta il 17/09/2026

Segnalazione: dopo il long-press compaiono i due pallini di selezione, ma non si
agganciano al dito. «Seleziona tutto» funziona, quindi selezionare più di una
parola è possibile, ma non manualmente.

## Come funziona davvero (misurato, non dedotto)

I pallini non sono nostri: li disegna e li trascina Chromium.

- Il rettangolo di aggancio è la **dimensione dell'immagine**: misurato sul POCO
  `w=24 h=24` px della view (`touch_handle_drawable_qt.cpp`, `kSelectionHandlePadding = 0`).
- Il test di aggancio (`ui/touch_selection/touch_handle.cc:178-191`) usa
  `clamp(GetTouchMajor(), 1, 36) * 0.5` come raggio di tolleranza.
  `GetTouchMajor()` è `QEventPoint::ellipseDiameters()`
  (`render_widget_host_view_qt_delegate_client.cpp:138`).
- `selectionBounds` che arriva in `onTouchSelectionMenuRequested` **non**
  comprende i pallini: scendono altri 26 px sotto (24 di immagine + 2 di
  `kSelectionHandleVerticalVisualOffset`).
- Chromium ci notifica il «mostra menù» ma **mai** il «nascondi»:
  `hideTouchSelectionMenu()` nasconde solo il menù interno di Qt, al QML non
  arriva nessun segnale.

## Risolto

1. **Lo strato che chiude il menù si mangiava il tocco.** La `MouseArea` a `z:59`
   copre tutto lo schermo finché il menù è aperto: il press sul pallino moriva lì
   e Chromium non lo vedeva mai. Ora, col menù della selezione aperto, il press
   viene rifiutato (`mouse.accepted = false`) e prosegue verso la pagina.
2. **Il menù copriva i pallini.** Stava a 16 px sotto la selezione, contro i 26
   px di sporgenza dei pallini: ne copriva il 40%, e stando a `z:60` quel 40% si
   prendeva anche il tocco. Ora il franco è pieno (`touchHandleClearance`), e se
   sotto non c'è spazio il menù va sopra la selezione.
3. **Tocco fuori dalla selezione: servivano tre tocchi.** Il `touchUp` arriva
   prima che il renderer confermi la selezione sciolta, quindi Chromium chiede
   comunque il menù e questo rispuntava. Ora quel tocco lo riconosciamo al volo
   (cade fuori da `touchSelRect`) e la richiesta che segue si butta.

## 4. Il tap SUL testo selezionato riapriva il menù — risolto

Misurato il 17 set con tracce sul device, e le due ipotesi di partenza erano
entrambe sbagliate:

- il tap sulla selezione **non scioglie la selezione** su questo motore: subito
  dopo, `getSelection()` risponde `len=380 type=Range`. Quindi chiedere al
  renderer «c'è ancora una selezione?» non discrimina niente: risponde sì;
- la richiesta di menù che segue arriva **~1,6 s** dopo il tocco, fuori da
  qualunque finestra stretta.

La firma vera della richiesta spuria è un'altra: porta i **limiti di selezione
vecchi, identici**, mentre dopo un trascinamento vero cambiano sempre. È questa
che usiamo, con una finestra di 4 s.

Per sapere se il tocco era sul pallino o sul testo servono le coordinate vere dei
pallini, e si ottengono con un `touchHandleDelegate` nostro
(`QQuickWebEngineView::touchHandleDelegate`, REVISION 6.4, presente in 6.8): il
delegate riceve da Chromium `x/y/w/h` esatti di ciascun pallino via `setBounds`.
Ogni pallino si registra in `win.touchHandles` alla nascita e si cancella alla
distruzione; `win.onTouchHandle(x, y)` risponde con 18 px di slop (il rettangolo
è 24x24 px fisici, ~1,6 mm). Se il registro è vuoto risponde «sì», così il
comportamento degrada a quello di prima e mai a peggio.

Effetto collaterale: al posto dell'asset grigio di Chromium desktop disegniamo un
pallino a tema, che riempie **esattamente** il rettangolo afferrabile.

Collaudato sul POCO il 17 set: funziona.

## Leva rimasta, da misurare

`GetTouchMajor()` non è mai stato misurato: la sonda `PointHandler` non spara
perché la WebEngineView si prende l'evento prima. Se SailfishOS riporta
`ellipseDiameters` a zero, Chromium lavora con 0,5 px di tolleranza invece dei
~18 px di Android. Si corregge in `main.cpp` con un event filter che riscrive
`ellipseDiameters` sui `QTouchEvent`: `QMutableEventPoint::setEllipseDiameters`
è disponibile nel target (`qt6/QtGui/6.8.3/QtGui/private/qeventpoint_p.h`).
Per misurarlo serve una sonda dentro un delegate nostro, che sta sopra la view.
