# TASK 4 — Messaggio a Steve: dati da raccogliere nei due boot (26 lug 2026)

Stato: ✅ **SUPERATA — archiviata il 14 ago 2026.** Questa era la raccolta dati
per diagnosticare la fascia nera; la fascia nera è stata risolta per altra via
nella 1.4.7-1 (soglia 15% in `rtGeomCheck`), quindi i dati chiesti a Steve non
servono più. Resta come storia dello scambio.

Riferimento: `TASK-4-fascia-nera-x10iii-lingua.md`.
Scopo: distinguere **race di avvio maliit-server ↔ prima finestra xdg-shell** da
**stato incastrato in dconf**. Le due domande decisive sono il diff di
`/sailfish/text_input/` fra i due boot e il punto 4 (restart di maliit ad app CHIUSA).

Testo inviato (inglese, così com'è):

```
Hi Steve,

your language-change finding is the best clue we've had so far — thank you.
Note that it can't be the Italian keyboard itself: English works too after you
switch back. What seems to matter is the *act* of changing the language, which
gives you exactly one good boot. The only thing that gesture moves at startup is
maliit-server (the system keyboard): changing language regenerates its layouts,
so on that one boot it either starts later or starts clean.

My working theory: it's a startup race between maliit-server and RooTitanium's
window. If the keyboard's input panel is already registered when the window is
created, the compositor permanently reserves the keyboard-sized strip at the
bottom (that's your black band); if maliit isn't ready yet, no reservation.

To tell that apart from "some stuck setting", I need the same four commands run
in TWO different boots. Please keep the outputs labelled A and B.

--- BOOT A = the GOOD one -------------------------------------------------
Change the system language (English -> Italian, or Italian -> English, either
direction), let the phone reboot, confirm RooTitanium is full screen, then run:

  1)  dconf dump /sailfish/text_input/ > ~/Documents/A-textinput.txt
  2)  systemctl --user show maliit-server -p ActiveState -p SubState \
        -p ActiveEnterTimestamp > ~/Documents/A-maliit.txt
  3)  open RooTitanium, use it for a few seconds, close it, then:
      cp /tmp/rootitanium.log ~/Documents/A-rootitanium.log

--- BOOT B = the BROKEN one -----------------------------------------------
Reboot again WITHOUT touching the language, confirm the black band is back,
then run exactly the same three commands, with B instead of A in the filenames.

--- ONE EXTRA TEST, only in boot B ----------------------------------------
While the phone is in the broken state:

  4)  close RooTitanium completely (swipe it away, not just minimise)
      systemctl --user restart maliit-server
      wait ~5 seconds, then open RooTitanium again

  Question: is it full screen now, or still 2/3?

That last answer is the important one. If restarting the keyboard *before*
opening the app fixes it, the race theory is confirmed and I know what to do.
(We already know restarting maliit *while* the app is open changes nothing.)

Then just send me the six files from ~/Documents plus the answer to question 4.

Thanks again — this is genuinely useful.
```

## Note di metodo

- `systemctl --user show maliit-server -p ActiveEnterTimestamp` al posto di
  `journalctl --user`: sul journal utente di SFOS spesso non c'è nulla, mentre il
  timestamp di attivazione è comunque confrontabile fra i due boot.
- Il restart di maliit **ad app aperta** era già stato provato il 23 lug e non
  cambia nulla: qui serve ad app CHIUSA, prima di riaprirla.
- Attese: boot A → `configure 1080x2520` fin dal primo nel log; boot B → il solito
  1660 e i `rtGeomCheck`.
- Se il punto 4 risolve → race confermata, workaround immediato documentabile;
  se il diff dconf mostra differenze → stato incastrato, cura diversa.
