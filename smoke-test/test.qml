import QtQuick
import QtQuick.Window
import QtQuick.VirtualKeyboard
import QtWebEngine
import QtQuick.LocalStorage

Window {
    id: win
    visible: true
    visibility: Window.FullScreen
    color: "#101014"

    // u basato sul lato corto: resta costante quando il contenuto ruota in landscape
    readonly property real u: Math.min(width, height) / 540

    // --- rotazione landscape ---
    // lipstick NON ruota le superfici wayland (le app SFOS si ruotano da sole):
    // ruotiamo il contenitore root (appRoot). Sensori non disponibili in Qt6 sul
    // device → landscape manuale dal menù + automatico per video a tutto schermo.
    // rotation 90 = si gira il telefono in senso antiorario (tacca in alto a sinistra)
    property bool videoFS: false
    property bool manualLandscape: false
    // diagnosi 11 lug: fullscreen+rotazione OK con <video> normali (probe);
    // il nero era solo su YouTube → auto-rotate riabilitato
    property bool autoRotateFS: true
    readonly property int orient: ((videoFS && autoRotateFS) || manualLandscape) ? 90 : 0

    // --- schede ---
    property int currentTab: 0
    // stato "Cerca nella pagina" (la barra findBar vive dentro appRoot)
    property int findCur: 0
    property int findTot: 0
    onCurrentTabChanged: closeFind()
    function closeFind() {
        if (!findBar.open) return
        findBar.open = false
        findInput.focus = false
        findInput.text = ""
        findCur = 0; findTot = 0
        if (currentView) currentView.findText("")
    }
    function findNextMatch(back) {
        if (!currentView || !findInput.text.length) return
        currentView.findText(findInput.text, back ? WebEngineView.FindBackward : 0)
    }
    property var currentView: null
    property bool currentPrivate: currentView ? currentView.priv : false

    function refreshCurrent() { currentView = tabsRepeater.itemAt(currentTab) }
    function newTab(priv) {
        menu.open = false
        tabsModel.append({ priv: priv, start: priv ? "incognito" : "home", murl: "", mtitle: priv ? "Incognito" : "Home" })
        currentTab = tabsModel.count - 1
        switcher.open = false
        Qt.callLater(refreshCurrent)
    }
    function closeTab(i) {
        tabsModel.remove(i)
        saveSession()
        if (tabsModel.count === 0) { newTab(false); return }   // ultima scheda chiusa → HOME
        if (currentTab >= tabsModel.count) currentTab = tabsModel.count - 1
        Qt.callLater(refreshCurrent)
    }
    function switchTab(i) { currentTab = i; switcher.open = false; Qt.callLater(refreshCurrent) }
    function tabCount(priv) { var n = 0; for (var i=0;i<tabsModel.count;i++) if (tabsModel.get(i).priv === priv) n++; return n }

    // --- user agent per toggle Versione desktop ---
    // #7 (login negato da x.com): lo UA vecchio ("Android 13; Mobile",
    // Chrome/124) CONTRADDICEVA i Client Hints veri (Sec-CH-UA: Chromium 122,
    // Platform "Linux", Mobile ?0, platformVersion = kernel 4.19) → fingerprint
    // da UA contraffatto, oro per l'anti-bot. Identità coerente scelta:
    // "Chromium 122 su Android, mobile" — UA nel formato RIDOTTO ufficiale di
    // Chrome Android (piattaforma congelata "Android 10; K", solo major
    // version) + Client Hints allineati in applyClientHints()
    property bool desktopMode: false
    readonly property string uaMobile: "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36"
    readonly property string uaDesktop: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    function setDesktop(on) { desktopMode = on; applyClientHints(); if (currentView) currentView.reload() }

    // ESPERIMENTO login X (#7) — ESITO NEGATIVO, toggle lasciato SPENTO.
    // Ipotesi: il browser NATIVO SailfishOS (Gecko/Firefox 91) accetta il login su
    // X dallo stesso device/IP, RooTitanium (Chromium) no → forse è l'identità.
    // firefoxMode ci fa presentare come il nativo: UA Firefox 91, niente API Chrome
    // lato JS (userAgentData/window.chrome rimossi). PROVATO 13 lug col login reale
    // dell'utente: STESSO blocco "non puoi accedere" su begin_login. Quindi
    // l'identità del browser NON è (da sola) il discriminante — anche perché con
    // username fittizio X procede sempre (il blocco è sul percorso account reale).
    // LIMITE tecnico emerso: da QML NON si può togliere l'header Sec-CH-UA
    // low-entropy (isAllClientHintsEnabled=false non basta) → la "Firefox" restava
    // un ibrido (UA Firefox + Sec-CH-UA Chromium). Codice tenuto come toggle per
    // futuri test; default false = identità Chromium coerente (giusta e onesta).
    property bool firefoxMode: false
    readonly property string uaFirefox: "Mozilla/5.0 (Mobile; rv:91.0) Gecko/91.0 Firefox/91.0"
    function effectiveUA() {
        if (firefoxMode) return uaFirefox
        return desktopMode ? uaDesktop : uaMobile
    }

    // Client Hints (Sec-CH-UA-*/navigator.userAgentData) coerenti con lo UA:
    // Chrome Android vero manda arch/bitness VUOTI e la versione Android reale
    // in platformVersion (lo UA ridotto resta "10; K"). API REVISION(6,8):
    // guardia try, l'app deve partire anche su runtime più vecchi
    function applyClientHints() {
        var m = !desktopMode
        var profs = [normalProfile, incognitoProfile]
        for (var i = 0; i < profs.length; i++) {
            try {
                var ch = profs[i].clientHints
                // firefoxMode: Gecko non manda ALCUN Client Hint → li spengo tutti
                // (niente header Sec-CH-UA*). isAllClientHintsEnabled è REV(6,8)
                if (firefoxMode) { ch.isAllClientHintsEnabled = false; continue }
                ch.isAllClientHintsEnabled = true
                ch.mobile = m
                ch.platform = m ? "Android" : "Linux"
                ch.platformVersion = m ? "13.0.0" : "6.5.0"
                ch.model = m ? "Pixel 7" : ""
                ch.arch = m ? "" : "x86"
                ch.bitness = m ? "" : "64"
                ch.wow64 = false
                // NB brand "Google Chrome": NON impostabile in modo coerente. Il
                // setter fullVersionList tocca solo la lista HIGH-entropy (via JS
                // getHighEntropyValues), mentre l'header Sec-CH-UA low-entropy è
                // gestito dallo stack di rete C++ e QtWebEngine non lo espone →
                // aggiungere Google Chrome creava un mismatch high/low. Restiamo
                // "Chromium 122" coerente ovunque (vendor "Google Inc." è normale
                // anche per Chromium vero: tutti i browser Blink lo riportano)
            } catch(e) { console.warn("clientHints non disponibili: " + e) }
        }
    }

    // ===================== IMPOSTAZIONI (persistite nella kv della SQLite) =====================
    property bool cfgJs: true               // Attiva JavaScript
    property bool cfgCookies: true          // conserva i cookies alla chiusura (#5)
    property bool cfgPopups: true           // consenti ai siti di aprire nuove schede (#6)
    property bool cfgDnt: false             // Non tenere traccia
    property bool cfgDark: false            // resa scura forzata (auto-dark Chromium)
    property bool cfgStartPrivate: false    // avvia in navigazione privata
    property bool cfgCloseTabs: true        // ON = chiudi tutte le schede all'uscita; OFF = ripristina sessione
    property bool cfgFarble: true           // anti-fingerprinting stile Brave/Cromite (rumore seedato)
    property bool cfgNoCookieBanner: true   // rifiuta/nascondi i banner cookie automaticamente
    property string cfgHome: ""             // vuoto = HOME interna RooTitanium
    property string cfgSearch: "duckduckgo"
    property string cfgDlDir: "downloads"   // destinazione download (token in dlDirs)
    // cartelle standard SFOS (inglesi anche con lingua italiana, verificato sul
    // device); scelta chiusa: niente path liberi = niente dir inesistenti
    readonly property var dlDirs: ({
        downloads: { n: "Downloads",  p: "/home/defaultuser/Downloads" },
        documents: { n: "Documenti",  p: "/home/defaultuser/Documents" },
        pictures:  { n: "Immagini",   p: "/home/defaultuser/Pictures" },
        videos:    { n: "Video",      p: "/home/defaultuser/Videos" },
        music:     { n: "Musica",     p: "/home/defaultuser/Music" }
    })
    function downloadDirPath() {
        // il default passa da rtNative: crea ~/Downloads se manca
        if (cfgDlDir === "downloads" && typeof rtNative !== "undefined") return rtNative.downloadsPath()
        return (dlDirs[cfgDlDir] || dlDirs.downloads).p
    }
    readonly property var searchEngines: ({
        duckduckgo: { n: "DuckDuckGo", q: "https://lite.duckduckgo.com/lite/?q=" },
        google:     { n: "Google",     q: "https://www.google.com/search?q=" },
        bing:       { n: "Bing",       q: "https://www.bing.com/search?q=" },
        startpage:  { n: "Startpage",  q: "https://www.startpage.com/sp/search?query=" }
    })
    function kvEnsure(tx) { tx.executeSql("CREATE TABLE IF NOT EXISTS kv(k TEXT PRIMARY KEY, v TEXT)") }
    function kvGet(k, def) {
        var v = def
        try { histDb().transaction(function(tx) { kvEnsure(tx)
            var rs = tx.executeSql("SELECT v FROM kv WHERE k=?", [k])
            if (rs.rows.length) v = rs.rows.item(0).v }) } catch(e) {}
        return v
    }
    function kvSet(k, v) {
        try { histDb().transaction(function(tx) { kvEnsure(tx)
            tx.executeSql("INSERT OR REPLACE INTO kv(k,v) VALUES(?,?)", [k, "" + v]) }) } catch(e) {}
    }
    function loadCfg() {
        cfgJs           = kvGet("set_js", "1") === "1"
        cfgCookies      = kvGet("set_cookies", "1") === "1"
        cfgPopups       = kvGet("set_popups", "1") === "1"
        cfgDnt          = kvGet("set_dnt", "0") === "1"
        cfgDark         = kvGet("set_dark", "0") === "1"
        cfgStartPrivate = kvGet("set_startprivate", "0") === "1"
        cfgCloseTabs    = kvGet("set_closetabs", "1") === "1"
        cfgFarble       = kvGet("set_farble", "1") === "1"
        cfgNoCookieBanner = kvGet("set_nocookie", "1") === "1"
        cfgHome         = kvGet("set_homepage", "")
        cfgSearch       = kvGet("set_search", "duckduckgo")
        if (!searchEngines[cfgSearch]) cfgSearch = "duckduckgo"
        cfgDlDir        = kvGet("set_dldir", "downloads")
        if (!dlDirs[cfgDlDir]) cfgDlDir = "downloads"
    }
    function applySetting(k, v) {
        if (k === "homepage") {
            v = v.trim()
            // senza schema: completa a https:// (come la barra indirizzi)
            if (v.length && !/^[a-z]+:\/\//i.test(v)) v = "https://" + v
            cfgHome = v; kvSet("set_homepage", cfgHome); return
        }
        if (k === "search")        { if (searchEngines[v]) { cfgSearch = v; kvSet("set_search", v) } return }
        if (k === "dldir")         { if (dlDirs[v]) { cfgDlDir = v; kvSet("set_dldir", v) } return }
        var on = v === "1"
        if (k === "js")            { cfgJs = on;        kvSet("set_js", v) }
        else if (k === "cookies")  { cfgCookies = on;   kvSet("set_cookies", v) }
        else if (k === "popups")   { cfgPopups = on;    kvSet("set_popups", v) }
        else if (k === "dnt")      { cfgDnt = on;       kvSet("set_dnt", v); applyViewPrefs() }
        else if (k === "dark")     { cfgDark = on;      kvSet("set_dark", v); applyViewPrefs() }
        else if (k === "startprivate") { cfgStartPrivate = on; kvSet("set_startprivate", v) }
        else if (k === "closetabs")    { cfgCloseTabs = on;    kvSet("set_closetabs", v)
                                         if (on) kvSet("session_tabs", "[]"); else saveSession() }
        else if (k === "farble")   { cfgFarble = on;   kvSet("set_farble", v); applyViewPrefs() }
        else if (k === "nocookie") { cfgNoCookieBanner = on; kvSet("set_nocookie", v); applyViewPrefs() }
    }
    // sessione (solo schede normali, mai incognito né pagine interne .local);
    // salvata a ogni navigazione/chiusura scheda: non esiste un "on exit"
    // affidabile (swipe-close di lipstick può uccidere il processo)
    function saveSession() {
        if (cfgCloseTabs) return
        var urls = []
        for (var i = 0; i < tabsModel.count; i++) {
            var t = tabsModel.get(i)
            if (!t.priv && /^https?:\/\//i.test(t.murl) && !/^https?:\/\/[^\/]*\.local(\/|$)/i.test(t.murl)) urls.push("" + t.murl)
        }
        kvSet("session_tabs", JSON.stringify(urls))
    }

    // HOME della scheda: pagina interna, o l'URL scelto in Impostazioni
    function goHome(view) {
        if (!view) return
        if (cfgHome.length) view.url = cfgHome
        else loadInternal(view, "home", homeHtml(), "about:blank")
    }

    // DNT solo lato JS (navigator.doNotTrack): l'header DNT: 1 vero
    // richiederebbe un interceptor C++ in rtNative → rimandato
    readonly property string dntJs: `(function(){
        try { Object.defineProperty(Navigator.prototype, 'doNotTrack', { configurable: true, get: function(){ return '1' } }); } catch(e) {}
        try { Object.defineProperty(Navigator.prototype, 'globalPrivacyControl', { configurable: true, get: function(){ return true } }); } catch(e) {}
    })();`

    // fingerprint fix (bug login #7): QtWebEngine crea window.chrome VUOTO (nessuna
    // chiave, niente runtime/loadTimes/csi) → firma classica di browser non-Chrome
    // usata dagli anti-bot. Ricostruisco un window.chrome minimale plausibile come
    // fa Chrome vero su una pagina normale (loadTimes/csi funzioni, app/runtime
    // oggetti; runtime SENZA id, come nelle pagine non-extension)
    readonly property string chromeStubJs: `(function(){
        if (window.__rtChrome) return; window.__rtChrome = true;
        try {
            var c = window.chrome = window.chrome || {};
            if (!c.app)  c.app  = { isInstalled: false, InstallState: { DISABLED: 'disabled', INSTALLED: 'installed', NOT_INSTALLED: 'not_installed' }, RunningState: { CANNOT_RUN: 'cannot_run', READY_TO_RUN: 'ready_to_run', RUNNING: 'running' } };
            if (!c.csi) c.csi = function(){ return { startE: Date.now(), onloadT: Date.now(), pageT: performance.now(), tran: 15 }; };
            if (!c.loadTimes) c.loadTimes = function(){ var t = performance.timing || {}; return {
                requestTime: (t.navigationStart||Date.now())/1000, startLoadTime: (t.navigationStart||Date.now())/1000,
                commitLoadTime: (t.responseStart||Date.now())/1000, finishDocumentLoadTime: (t.domContentLoadedEventEnd||Date.now())/1000,
                finishLoadTime: (t.loadEventEnd||Date.now())/1000, firstPaintTime: performance.now()/1000, firstPaintAfterLoadTime: 0,
                navigationType: 'Other', wasFetchedViaSpdy: true, wasNpnNegotiated: true, npnNegotiatedProtocol: 'h2', wasAlternateProtocolAvailable: false, connectionInfo: 'h2' }; };
            if (!c.runtime) c.runtime = { OnInstalledReason: {}, OnRestartRequiredReason: {}, PlatformArch: {}, PlatformNaclArch: {}, PlatformOs: {}, RequestUpdateCheckStatus: {}, connect: function(){}, sendMessage: function(){} };
        } catch(e){}
    })();`

    // firefoxMode (ESPERIMENTO #7): fa sparire lato JS le API che tradiscono
    // Chromium sotto UA Firefox — un vero Firefox non le ha. userAgentData e
    // window.chrome rimossi; vendor "" e productSub "20100101" come Gecko
    readonly property string firefoxJs: `(function(){
        try { delete Navigator.prototype.userAgentData; } catch(e){}
        try { Object.defineProperty(Navigator.prototype, 'userAgentData', { configurable: true, get: function(){ return undefined; } }); } catch(e){}
        try { delete window.chrome; } catch(e){}
        try { window.chrome = undefined; } catch(e){}
        try { Object.defineProperty(Navigator.prototype, 'vendor',     { configurable: true, get: function(){ return ''; } }); } catch(e){}
        try { Object.defineProperty(Navigator.prototype, 'productSub',  { configurable: true, get: function(){ return '20100101'; } }); } catch(e){}
        try { Object.defineProperty(Navigator.prototype, 'oscpu',       { configurable: true, get: function(){ return 'Linux aarch64'; } }); } catch(e){}
        try { Object.defineProperty(Navigator.prototype, 'buildID',     { configurable: true, get: function(){ return '20181001000000'; } }); } catch(e){}
    })();`

    // Anti-fingerprinting stile Brave/Cromite ("farbling"): rumore DETERMINISTICO
    // per-origine (stabile entro la pagina, diverso tra siti/sessioni) sui vettori
    // di fingerprint — canvas, WebGL readPixels, audio. Valori restano PLAUSIBILI
    // (non falsi evidenti), per questo non rompe l'anti-bot: Brave/Cromite girano
    // su X.com. NON tocca gli userscript di coerenza-Chrome: ci si aggiunge sopra.
    readonly property string farbleJs: `(function(){
  if (window.__rtFarble) return; window.__rtFarble = true;
  function h(s){var x=2166136261>>>0;for(var i=0;i<s.length;i++){x^=s.charCodeAt(i);x=Math.imul(x,16777619);}return x>>>0;}
  var seed=h((location.origin||'null')+'|rtfarble1');
  function mk(s){return function(){s|=0;s=s+0x6D2B79F5|0;var t=Math.imul(s^s>>>15,1|s);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296;};}
  try{
    var gID=CanvasRenderingContext2D.prototype.getImageData;
    var pID=CanvasRenderingContext2D.prototype.putImageData;
    // rumore DETERMINISTICO (seed fisso per-origine): due letture dello stesso
    // canvas danno lo STESSO risultato → stabile entro la pagina, non rilevabile
    function fb(img){var r=mk(seed^img.width^(img.height<<16));var d=img.data;for(var i=0;i<d.length;i+=4){if(r()<0.045){var n=(r()*3|0)-1;d[i]=(d[i]+n)&255;d[i+1]=(d[i+1]+n)&255;d[i+2]=(d[i+2]+n)&255;}}return img;}
    CanvasRenderingContext2D.prototype.getImageData=function(){var img=gID.apply(this,arguments);try{fb(img);}catch(e){}return img;};
    var tDU=HTMLCanvasElement.prototype.toDataURL;
    // legge i pixel PULITI (gID originale), farbla una COPIA su canvas temporaneo
    // e serializza quello — NON muta mai il canvas sorgente (evita drift cumulativo)
    HTMLCanvasElement.prototype.toDataURL=function(){try{var c=this.getContext('2d');if(c&&this.width&&this.height){var im=gID.call(c,0,0,this.width,this.height);fb(im);var t=document.createElement('canvas');t.width=this.width;t.height=this.height;pID.call(t.getContext('2d'),im,0,0);return tDU.apply(t,arguments);}}catch(e){}return tDU.apply(this,arguments);};
  }catch(e){}
  try{
    function pgl(P){if(!P)return;var rp=P.prototype.readPixels;P.prototype.readPixels=function(){var ret=rp.apply(this,arguments);try{var px=arguments[6];if(px&&px.length){var r=mk(seed^7);for(var i=0;i<px.length;i+=97){px[i]=(px[i]+(r()*2|0))&255;}}}catch(e){}return ret;};}
    pgl(window.WebGLRenderingContext);pgl(window.WebGL2RenderingContext);
  }catch(e){}
  try{
    var AN=window.AnalyserNode&&AnalyserNode.prototype;
    if(AN){var gf=AN.getFloatFrequencyData;AN.getFloatFrequencyData=function(a){gf.apply(this,arguments);try{var r=mk(seed^13);for(var i=0;i<a.length;i++)a[i]+=(r()-0.5)*0.002;}catch(e){}};}
  }catch(e){}
})();`

    // Rifiuta/nascondi i banner cookie automaticamente (stile "I don't care about
    // cookies"): nasconde i contenitori dei CMP più diffusi via CSS, clicca i
    // bottoni "rifiuta/solo necessari" noti (OneTrust/Cookiebot/Didomi/…) e per
    // testo, ripristina lo scroll. Best-effort e limitato: non copre ogni sito.
    readonly property string cookieBannerJs: `(function(){
  if (window.__rtNoCookie) return; window.__rtNoCookie = true;
  var HIDE=['#onetrust-banner-sdk','#onetrust-consent-sdk','#CybotCookiebotDialog','#didomi-host','#usercentrics-root','.qc-cmp2-container','#cmpbox','.cc-window','#cookie-banner','#cookieConsent','.cookie-consent','.cookie-notice','.fc-consent-root','.truste_overlay','#truste-consent-track','.osano-cm-window','.iubenda-cs-container','#iubenda-cs-banner'];
  var RIDS=['onetrust-reject-all-handler','CybotCookiebotDialogBodyButtonDecline','didomi-notice-disagree-button','truste-consent-required'];
  // bottoni "rifiuta" identificati per SELETTORE-classe nei vari CMP (anche <a>,
  // che il match per testo — solo button/[role=button] — non prenderebbe)
  var RSEL=['.iubenda-cs-reject-btn','.cc-btn.cc-deny','.osano-cm-denyAll','.cmp-reject-all','.fc-cta-do-not-consent','[data-role=reject-all]','[aria-label*="Rifiuta"]','[aria-label*="Reject"]'];
  function css(){try{if(document.getElementById('__rtNoCookieCss'))return;var s=document.createElement('style');s.id='__rtNoCookieCss';s.textContent=HIDE.join(',')+'{display:none!important;visibility:hidden!important;}html,body{overflow:auto!important;}';(document.head||document.documentElement).appendChild(s);}catch(e){}}
  var RE=/^(rifiuta|rifiuta tutto|rifiuta tutti|solo (i )?necessari|reject|reject all|decline|necessary only|only necessary|continua senza accettare|non accetto|no thanks)$/i;
  // clicca TUTTI i bottoni "rifiuta" non ancora gestiti (marcati con __rtDone,
  // così non si ri-cliccano e non bloccano la gestione di altri banner)
  function rej(){try{
    for(var i=0;i<RIDS.length;i++){var el=document.getElementById(RIDS[i]);if(el&&!el.__rtDone){el.__rtDone=1;el.click();}}
    for(var k=0;k<RSEL.length;k++){document.querySelectorAll(RSEL[k]).forEach(function(e){if(!e.__rtDone){e.__rtDone=1;e.click();}});}
    var b=document.querySelectorAll('button,a[role=button],[role=button]');
    for(var j=0;j<b.length;j++){var e2=b[j];if(e2.__rtDone)continue;var t=(e2.textContent||'').trim();if(t&&t.length<40&&RE.test(t)){e2.__rtDone=1;e2.click();}}
  }catch(e){}}
  css();
  var n=0;var iv=setInterval(function(){css();rej();if(++n>20)clearInterval(iv);},500);
  try{var mo=new MutationObserver(function(){css();rej();});mo.observe(document.documentElement,{childList:true,subtree:true});setTimeout(function(){try{mo.disconnect();}catch(e){}},12000);}catch(e){}
})();`

    function buildScripts() {
        var s = [{
            name: "rtScreenSpoof",
            sourceCode: screenSpoofJs,
            injectionPoint: WebEngineScript.DocumentCreation,
            worldId: WebEngineScript.MainWorld,
            runsOnSubFrames: true
        }, {
            name: "rtYtTapFix",
            sourceCode: ytTapFixJs,
            injectionPoint: WebEngineScript.DocumentCreation,
            worldId: WebEngineScript.MainWorld,
            runsOnSubFrames: true
        }]
        // identità JS: Firefox (rimuove API Chrome) OPPURE stub Chrome
        s.push(firefoxMode ? {
            name: "rtFirefox",
            sourceCode: firefoxJs,
            injectionPoint: WebEngineScript.DocumentCreation,
            worldId: WebEngineScript.MainWorld,
            runsOnSubFrames: true
        } : {
            name: "rtChromeStub",
            sourceCode: chromeStubJs,
            injectionPoint: WebEngineScript.DocumentCreation,
            worldId: WebEngineScript.MainWorld,
            runsOnSubFrames: true
        })
        if (cfgDnt) s.push({
            name: "rtDnt",
            sourceCode: dntJs,
            injectionPoint: WebEngineScript.DocumentCreation,
            worldId: WebEngineScript.MainWorld,
            runsOnSubFrames: true
        })
        if (cfgFarble) s.push({
            name: "rtFarble",
            sourceCode: farbleJs,
            injectionPoint: WebEngineScript.DocumentCreation,
            worldId: WebEngineScript.MainWorld,
            runsOnSubFrames: true
        })
        if (cfgNoCookieBanner) s.push({
            name: "rtCookieBanner",
            sourceCode: cookieBannerJs,
            injectionPoint: WebEngineScript.DocumentReady,
            worldId: WebEngineScript.MainWorld,
            runsOnSubFrames: false
        })
        return s
    }
    // riallinea le view esistenti dopo un cambio impostazione (dark subito,
    // DNT dal prossimo load). forceDarkMode è REVISION(6,7): assegnazione
    // imperativa con guardia, mai binding dichiarativo (se il runtime QML non
    // la espone, un binding romperebbe la creazione dell'intera view)
    function applyViewPrefs() {
        for (var i = 0; i < tabsRepeater.count; i++) {
            var v = tabsRepeater.itemAt(i)
            if (!v) continue
            try { v.settings.forceDarkMode = cfgDark } catch(e) {}
            v.userScripts.collection = buildScripts()
        }
    }

    // Pulisci dati navigazione: cronologia + download + cache HTTP + sessione.
    // I cookie NON si toccano da QML (niente cookie store): li governa il
    // toggle "conserva i cookies" via persistentCookiesPolicy (#5)
    function clearBrowsingData() {
        histClear()
        dlClear()
        kvSet("session_tabs", "[]")
        try { normalProfile.clearHttpCache() } catch(e) {}
        toast.show("Dati di navigazione puliti")
    }

    // carica una pagina interna su una view marcandola (localPage): loadHtml
    // non tocca la proprietà url, quindi timer/refresh Download e guardia
    // Condividi devono basarsi su questo, non su view.url
    function loadInternal(view, kind, html, base) {
        if (!view) return
        view.localPage = kind
        view.loadHtml(html, base)
    }

    function go(t) {
        t = t.trim()
        if (t.length === 0 || !currentView) return
        if (t === "probe") { loadInternal(currentView, "probe", probeHtml(), "https://probe.local/"); return }   // pagina diagnostica
        if (/^[a-z]+:\/\//i.test(t)) currentView.url = t
        else if (/^[^ ]+\.[^ ]+$/.test(t)) currentView.url = "https://" + t
        else currentView.url = searchEngines[cfgSearch].q + encodeURIComponent(t)
    }

    function colorizeUrl(u) {
        u = "" + u
        var m = u.match(/^([a-z][a-z0-9+.-]*):\/\/([^\/]*)(.*)$/i)
        if (!m) return '<span style="color:#e8e8e8">' + u + '</span>'
        return '<span style="color:#4ea866">' + m[1] + '</span>'
             + '<span style="color:#6a6a72">://</span>'
             + '<span style="color:#f0f0f0">' + m[2] + '</span>'
             + '<span style="color:#8a8a92">' + m[3] + '</span>'
    }

    readonly property var menuModel: [
        { t: "item", ic: "newtab",   l: "Nuova scheda",          a: "newtab" },
        { t: "item", ic: "private",  l: "Scheda anonima",        a: "private" },
        { t: "sep" },
        { t: "item", ic: "search",   l: "Cerca nella pagina",    a: "find" },
        { t: "item", ic: "share",    l: "Condividi",             a: "share" },
        { t: "item", ic: "pdf",      l: "Salva pagina come PDF", a: "pdf" },
        { t: "sep" },
        { t: "item", ic: "desktop",  l: "Versione desktop",      a: "desktop", toggle: true },
        { t: "item", ic: "rotate",   l: "Ruota in orizzontale",  a: "rotate",  toggle: true },
        { t: "sep" },
        { t: "item", ic: "staradd",  l: "Aggiungi ai segnalibri", a: "addbookmark" },
        { t: "item", ic: "star",     l: "Segnalibri",            a: "bookmarks" },
        { t: "item", ic: "history",  l: "Cronologia",            a: "history" },
        { t: "item", ic: "download", l: "Download",              a: "downloads" },
        { t: "item", ic: "settings", l: "Impostazioni",          a: "settings" }
    ]

    function doAction(a) {
        menu.open = false
        if (a === "newtab") newTab(false)
        else if (a === "private") newTab(true)
        else if (a === "desktop") setDesktop(!win.desktopMode)
        else if (a === "rotate") manualLandscape = !manualLandscape
        else if (a === "pdf") savePdf()
        else if (a === "share") shareUrl()
        else if (a === "history") loadInternal(currentView, "history", historyHtml(), "https://history.local/")
        else if (a === "addbookmark") { if (currentView) bmAdd(currentView.url, currentView.title) }
        else if (a === "bookmarks") loadInternal(currentView, "bookmarks", bookmarksHtml(), "https://bookmarks.local/")
        else if (a === "downloads") loadInternal(currentView, "downloads", downloadsHtml(), "https://downloads.local/")
        else if (a === "settings") openSettings(currentView)
        else if (a === "find") { if (currentView) { findBar.open = true; Qt.callLater(function(){ findInput.forceActiveFocus() }) } }
        else console.log("menu action (placeholder): " + a)
    }

    // Condividi = dialogo di condivisione DI SISTEMA (sailfish-share via DBus
    // org.sailfishos.share, helper rtNative in main.cpp — il plugin Qt5
    // Sailfish.Share non esiste in Qt6). Solo la scheda ATTIVA; pagine interne
    // (about:blank, *.local) escluse. Fallback: copia negli appunti se
    // l'helper manca (binario webengine-smoke vecchio).
    function shareUrl() {
        if (!currentView) return
        var u = "" + currentView.url
        // su pagina interna view.url resta quello della pagina PRECEDENTE
        // (loadHtml non lo aggiorna): localPage decide, mai condividerlo
        if (currentView.localPage !== "" || u === "" || u === "about:blank" || /^https?:\/\/[^\/]*\.local(\/|$)/i.test(u)) {
            toast.show("Questa pagina non si può condividere"); return
        }
        if (typeof rtNative !== "undefined" && rtNative.shareUrl(u, "" + currentView.title)) return
        clipHelper.text = u
        clipHelper.selectAll()
        clipHelper.copy()
        toast.show("Link copiato negli appunti")
    }
    TextInput { id: clipHelper; visible: false }

    // Salva pagina come PDF in ~/Documents (xdg-user-dirs), nome file dal
    // titolo pagina (sanificato + dedupe in rtNative); esito nel toast di
    // onPdfPrintingFinished della view
    function savePdf() {
        if (!currentView) return
        var p = (typeof rtNative !== "undefined")
            ? rtNative.pdfPathForTitle("" + currentView.title)
            : "/home/defaultuser/pagina.pdf"
        currentView.printToPdf(p)
        toast.show("Creazione PDF…")
    }

    // ===================== CONTEXT MENU (longpress) =====================
    // apre una scheda su un URL specifico (per "apri link in nuova scheda")
    function newTabUrl(priv, u) {
        menu.open = false
        tabsModel.append({ priv: priv, start: "" + u, murl: "" + u, mtitle: "…" })
        currentTab = tabsModel.count - 1
        switcher.open = false
        Qt.callLater(refreshCurrent)
    }

    property var ctxView: null
    property string ctxLink: ""
    property string ctxImg: ""
    property var ctxModel: []

    function showContext(view, req) {
        menu.open = false
        ctxView = view
        ctxLink = "" + (req.linkUrl || "")
        ctxImg  = (req.mediaType === ContextMenuRequest.MediaTypeImage) ? ("" + req.mediaUrl) : ""
        var sel = "" + (req.selectedText || "")
        var editable = req.isContentEditable === true

        var items = []
        if (ctxLink !== "") {
            items.push({ l: "Apri in nuova scheda",   a: "link_newtab" })
            items.push({ l: "Apri in scheda anonima",  a: "link_private" })
            items.push({ l: "Copia indirizzo link",    a: "link_copy" })
            items.push({ l: "Salva link",              a: "link_save" })
        }
        if (ctxImg !== "") {
            if (items.length) items.push({ sep: true })
            items.push({ l: "Apri immagine in nuova scheda", a: "img_newtab" })
            items.push({ l: "Copia immagine",                a: "img_copy" })
            items.push({ l: "Salva immagine",                a: "img_save" })
        }
        if (sel !== "") {
            if (items.length) items.push({ sep: true })
            items.push({ l: "Copia", a: "copy" })
            if (editable) items.push({ l: "Taglia", a: "cut" })
        }
        if (editable) {
            if (items.length) items.push({ sep: true })
            items.push({ l: "Incolla", a: "paste" })
            items.push({ l: "Seleziona tutto", a: "selall" })
        }
        if (items.length) items.push({ sep: true })
        items.push({ l: "Indietro", a: "back",    dis: !view.canGoBack })
        items.push({ l: "Avanti",   a: "forward", dis: !view.canGoForward })
        items.push({ l: "Ricarica", a: "reload" })
        ctxModel = items

        // req.position è relativo alla WebEngineView (che sta sotto la toolbar)
        ctxMenu.px = req.position.x
        ctxMenu.py = req.position.y + (toolbar.visible ? toolbar.height : 0)
        ctxMenu.open = true
    }

    // menù di selezione touch (sostituisce il quick-menu "Copy | …" di Chromium)
    function showTouchSelection(view, req) {
        menu.open = false
        ctxView = view
        ctxLink = ""; ctxImg = ""
        var f = req.touchSelectionCommandFlags
        var items = []
        if (f & TouchSelectionMenuRequest.Copy)  items.push({ l: "Copia",   a: "copy" })
        if (f & TouchSelectionMenuRequest.Cut)   items.push({ l: "Taglia",  a: "cut" })
        if (f & TouchSelectionMenuRequest.Paste) items.push({ l: "Incolla", a: "paste" })
        items.push({ l: "Seleziona tutto", a: "selall" })
        ctxModel = items
        // selectionBounds è relativo alla WebEngineView; il menù sotto la selezione
        ctxMenu.px = req.selectionBounds.x
        ctxMenu.py = req.selectionBounds.y + req.selectionBounds.height + (toolbar.visible ? toolbar.height : 0) + 8 * u
        ctxMenu.open = true
    }

    // dialoghi JS (alert/confirm/prompt/beforeunload) con UI scalata
    property var jsReq: null
    function showJsDialog(req) {
        jsReq = req
        jsDlg.dtype = req.type
        jsDlg.host = ("" + req.securityOrigin).replace(/^[a-z]+:\/\//i, "").replace(/\/.*$/, "")
        jsDlg.msg = req.type === JavaScriptDialogRequest.DialogTypeBeforeUnload
            ? "Uscire da questa pagina? Le modifiche potrebbero non essere salvate."
            : ("" + req.message)
        jsDlg.input = "" + (req.defaultText || "")
        jsDlg.open = true
    }
    function jsDialogDone(ok) {
        jsDlg.open = false
        if (!jsReq) return
        if (ok) jsReq.dialogAccept(jsDlg.dtype === JavaScriptDialogRequest.DialogTypePrompt ? jsDlg.input : "")
        else jsReq.dialogReject()
        jsReq = null
    }

    // menù longpress della barra indirizzi (TextInput QML, non WebEngine)
    function showUrlbarMenu() {
        menu.open = false
        ctxView = null
        ctxModel = [
            { l: "Seleziona tutto", a: "ub_selall" },
            { l: "Copia",           a: "ub_copy",  dis: urlbar.text.length === 0 },
            { l: "Incolla",         a: "ub_paste", dis: !urlbar.canPaste }
        ]
        ctxMenu.px = 60 * u
        ctxMenu.py = toolbar.height + 4 * u
        ctxMenu.open = true
    }

    function ctxAction(a) {
        ctxMenu.open = false
        if (a === "ub_selall") { urlbar.forceActiveFocus(); urlbar.selectAll(); return }
        if (a === "ub_copy")   { if (urlbar.selectedText.length === 0) urlbar.selectAll(); urlbar.copy(); toast.show("Copiato negli appunti"); return }
        if (a === "ub_paste")  { urlbar.forceActiveFocus(); urlbar.paste(); return }
        var v = ctxView
        if (!v) return
        if (a === "link_newtab")      newTabUrl(false, ctxLink)
        else if (a === "link_private") newTabUrl(true, ctxLink)
        else if (a === "link_copy")   { clipHelper.text = ctxLink; clipHelper.selectAll(); clipHelper.copy(); toast.show("Link copiato negli appunti") }
        else if (a === "link_save")   v.triggerWebAction(WebEngineView.DownloadLinkToDisk)
        else if (a === "img_newtab")  newTabUrl(v.priv, ctxImg)
        else if (a === "img_copy")    v.triggerWebAction(WebEngineView.CopyImageToClipboard)
        else if (a === "img_save")    v.triggerWebAction(WebEngineView.DownloadImageToDisk)
        else if (a === "copy")        v.triggerWebAction(WebEngineView.Copy)
        else if (a === "cut")         v.triggerWebAction(WebEngineView.Cut)
        else if (a === "paste")       v.triggerWebAction(WebEngineView.Paste)
        else if (a === "selall")      v.triggerWebAction(WebEngineView.SelectAll)
        else if (a === "back")        v.goBack()
        else if (a === "forward")     v.goForward()
        else if (a === "reload")      v.reload()
    }

    // profilo NORMALE: persistente (cookie/login/cronologia salvati su disco).
    // ⚠️ CAUSA del bug #5 "cookie non conservati": in QML il profilo nasce
    // off-the-record e storageName da solo NON lo commuta (ProfileAdapter:
    // setStorageName non tocca m_offTheRecord, verificato nei sorgenti 6.8.3)
    // → senza offTheRecord:false esplicito su disco esisteva solo OffTheRecord/
    WebEngineProfile {
        id: normalProfile
        storageName: "rootitanium"
        // NB: all'avvio QML applica offTheRecord prima di storageName → nel log
        // compare "Storage name is empty…" seguito da "Switching to disk-based
        // behavior": è il fallback previsto dal setter (SingleShotConnection su
        // storageNameChanged), benigno
        offTheRecord: false
        persistentStoragePath: "/home/defaultuser/.rootitanium"
        // toggle Impostazioni→Privacy (#5): OFF = cookie di sessione, spariscono
        // alla chiusura; il cambio vale da subito, non serve riavviare
        persistentCookiesPolicy: win.cfgCookies ? WebEngineProfile.AllowPersistentCookies
                                                : WebEngineProfile.NoPersistentCookies
        // permessi (#4 sezione Permessi): decisioni consenti/blocca salvate su
        // disco così sopravvivono al riavvio (REV 6,8). listAllPermissions()
        // alimenta la pagina di gestione permissions.local
        persistentPermissionsPolicy: WebEngineProfile.StoreOnDisk
        httpUserAgent: win.firefoxMode ? win.uaFirefox : (win.desktopMode ? win.uaDesktop : win.uaMobile)
        // senza, l'header Accept-Language MANCAVA del tutto (nessun browser
        // vero fa così: altro segnale bot per #7); pilota anche navigator.languages
        httpAcceptLanguage: "it-IT,it;q=0.9,en-US;q=0.8,en;q=0.7"
        onDownloadRequested: function(download) { win.handleDownload(download, false) }
        // installa (dal C++) l'interceptor header Sec-CH-UA. QQuickWebEngineProfile
        // espone setUrlRequestInterceptor come metodo C++ pubblico → rtNative lo
        // chiama passando questo profilo (non è raggiungibile da QML puro).
        Component.onCompleted: rtNative.setupProfile(this)
    }
    // profilo INCOGNITO: niente storageName → off-the-record (in memoria, isolato dal normale)
    WebEngineProfile {
        id: incognitoProfile
        // incognito: permessi solo in memoria, nessuna traccia su disco
        persistentPermissionsPolicy: WebEngineProfile.StoreInMemory
        httpUserAgent: win.firefoxMode ? win.uaFirefox : (win.desktopMode ? win.uaDesktop : win.uaMobile)
        httpAcceptLanguage: "it-IT,it;q=0.9,en-US;q=0.8,en;q=0.7"
        onDownloadRequested: function(download) { win.handleDownload(download, true) }
        // stesso interceptor header Sec-CH-UA anche in incognito
        Component.onCompleted: rtNative.setupProfile(this)
    }

    // ===================== DOWNLOAD =====================
    // dlItems = download della SESSIONE (array JS, nessun binding: la pagina
    // downloads.local si ri-renderizza a eventi + timer 1s per il progresso).
    // I download finiti (solo profilo normale, mai incognito) vanno anche
    // nella tabella downloads della SQLite → la pagina mostra pure lo storico.
    property var dlItems: []
    property int dlSeq: 0

    // senza accept() i download (Salva link/immagine, Content-Disposition,
    // blob/data) muoiono in silenzio: il profilo emette downloadRequested e
    // nessuno risponde. Qui: destinazione FORZATA alla cartella scelta in
    // Impostazioni (default ~/Downloads) per ogni tipo di download + tracking.
    function handleDownload(download, priv) {
        download.downloadDirectory = downloadDirPath()
        download.accept()
        // nome definitivo DOPO accept (Chromium deduplica "file (1).ext")
        var e = {
            did: Date.now() + "-" + (++dlSeq),
            item: download, priv: priv === true,
            name: "" + download.downloadFileName,
            path: download.downloadDirectory + "/" + download.downloadFileName,
            url: "" + download.url,
            state: "run", received: 0, total: download.totalBytes, ts: Date.now()
        }
        dlItems.unshift(e)
        toast.show("Download avviato: " + e.name)
        download.receivedBytesChanged.connect(function() { e.received = download.receivedBytes })
        download.totalBytesChanged.connect(function() { e.total = download.totalBytes })
        download.stateChanged.connect(function() {
            if (download.state === WebEngineDownloadRequest.DownloadCompleted) {
                e.state = "done"
                if (e.total > 0) e.received = e.total
                // cartella da e.path (quella vera del download, non la config
                // corrente: potrebbe essere cambiata a download in corso)
                toast.show("Scaricato in " + e.path.replace(/\/[^\/]*$/, "").replace(/^.*\//, "") + ": " + e.name)
            } else if (download.state === WebEngineDownloadRequest.DownloadCancelled) {
                e.state = "cancel"
            } else if (download.state === WebEngineDownloadRequest.DownloadInterrupted) {
                e.state = "fail"
                toast.show("Download fallito: " + e.name)
            } else return
            if (e.state !== "done" && typeof rtNative !== "undefined") {
                // Chromium lascia il parziale su disco (verificato): via anche il .download
                rtNative.removeFile(e.path)
                rtNative.removeFile(e.path + ".download")
            }
            e.item = null
            win.dlPersist(e)
            win.dlRefreshPage()
        })
        dlRefreshPage()
    }

    function dlEnsure(tx) { tx.executeSql("CREATE TABLE IF NOT EXISTS downloads(did TEXT PRIMARY KEY, name TEXT, path TEXT, url TEXT, state TEXT, size INTEGER, ts INTEGER)") }
    function dlPersist(e) {
        if (e.priv) return   // incognito: mai tracce su disco
        try { histDb().transaction(function(tx) { dlEnsure(tx)
            tx.executeSql("INSERT OR REPLACE INTO downloads(did,name,path,url,state,size,ts) VALUES(?,?,?,?,?,?,?)",
                          [e.did, e.name, e.path, e.url, e.state, e.received, e.ts]) }) } catch(err) {}
    }
    function dlHistory() {
        var out = []
        try { histDb().transaction(function(tx) { dlEnsure(tx)
            var rs = tx.executeSql("SELECT did,name,path,url,state,size,ts FROM downloads ORDER BY ts DESC LIMIT 100")
            for (var i = 0; i < rs.rows.length; i++) { var r = rs.rows.item(i)
                out.push({ did: r.did, name: r.name, path: r.path, url: r.url, state: r.state,
                           received: r.size, total: r.size, ts: r.ts, item: null, priv: false }) } }) } catch(err) {}
        return out
    }
    function dlFind(did) {
        for (var i = 0; i < dlItems.length; i++) if (dlItems[i].did === did) return dlItems[i]
        var hist = dlHistory()
        for (var j = 0; j < hist.length; j++) if (hist[j].did === did) return hist[j]
        return null
    }
    function dlCancel(did) {
        var e = dlFind(did)
        if (e && e.item) e.item.cancel()   // stateChanged fa persist+refresh
    }
    function dlClear() {
        try { histDb().transaction(function(tx) { dlEnsure(tx); tx.executeSql("DELETE FROM downloads") }) } catch(err) {}
        dlItems = dlItems.filter(function(e) { return e.state === "run" })
    }
    function dlRefreshPage() {
        if (currentView && currentView.localPage === "downloads")
            loadInternal(currentView, "downloads", downloadsHtml(), "https://downloads.local/")
    }

    function fmtBytes(n) {
        n = Number(n) || 0
        if (n < 1024) return n + " B"
        if (n < 1048576) return (n / 1024).toFixed(1) + " KB"
        if (n < 1073741824) return (n / 1048576).toFixed(1) + " MB"
        return (n / 1073741824).toFixed(2) + " GB"
    }
    function dlProgressText(e) {
        return e.total > 0 ? fmtBytes(e.received) + " di " + fmtBytes(e.total)
                           : fmtBytes(e.received)
    }

    // progresso live: aggiorna testo (#t<did>) e barra (#b<did>) via JS,
    // SENZA ricaricare la pagina (niente flicker/perdita scroll)
    function dlPushProgress() {
        if (!currentView) return
        var js = ""
        for (var i = 0; i < dlItems.length; i++) {
            var e = dlItems[i]
            if (e.state !== "run") continue
            var pct = e.total > 0 ? Math.round(e.received * 100 / e.total) : 0
            js += "(function(){var t=document.getElementById('t" + e.did + "');if(t)t.textContent=" + JSON.stringify(dlProgressText(e))
                + ";var b=document.getElementById('b" + e.did + "');if(b)b.style.width='" + pct + "%';})();"
        }
        if (js.length) currentView.runJavaScript(js)
    }
    Timer {
        interval: 1000; repeat: true
        running: (win.currentView ? win.currentView.localPage : "") === "downloads"
        onTriggered: win.dlPushProgress()
    }

    // pagina di gestione (menù ⋮ → Download): sessione + storico dalla SQLite,
    // dedupe per did. Azioni via link sentinella downloads.local/{open,cancel,clear}
    function downloadsHtml() {
        var rows = [], seen = {}
        for (var i = 0; i < dlItems.length; i++) { rows.push(dlItems[i]); seen[dlItems[i].did] = true }
        var hist = dlHistory()
        for (var j = 0; j < hist.length; j++) if (!seen[hist[j].did]) rows.push(hist[j])
        rows.sort(function(a, b) { return b.ts - a.ts })
        var body = rows.length ? rows.map(function(e) {
            var ico = e.state === "run" ? ["#3a5fc0", "↓"] : e.state === "done" ? ["#4ea866", "✓"] : ["#7a4a4a", "✕"]
            var when = Qt.formatDateTime(new Date(e.ts), "dd/MM hh:mm")
            var sub, act = ""
            if (e.state === "run") {
                sub = win.dlProgressText(e)
                act = '<a class="dact stop" href="https://downloads.local/cancel?id=' + e.did + '">Annulla</a>'
            } else if (e.state === "done") {
                sub = win.fmtBytes(e.received) + " · " + when
                act = '<a class="dact" href="https://downloads.local/open?id=' + e.did + '">Apri</a>'
            } else {
                sub = (e.state === "fail" ? "Non riuscito" : "Annullato") + " · " + when
            }
            var bar = (e.state === "run" && e.total > 0)
                ? '<span class="bar"><span class="fill" id="b' + e.did + '" style="width:' + Math.round(e.received * 100 / Math.max(e.total, 1)) + '%"></span></span>' : ''
            return '<div class="drow"><span class="hfav" style="background:' + ico[0] + '">' + ico[1] + '</span>'
                 + '<span class="hbody"><span class="ht">' + win.htmlEsc(e.name) + '</span>'
                 + '<span class="hu" id="t' + e.did + '">' + win.htmlEsc(sub) + '</span>' + bar + '</span>' + act + '</div>'
        }).join("") : '<div class="empty">Nessun download. I file scaricati finiscono in ' + win.dlDirs[win.cfgDlDir].n + '.</div>'
        var clear = rows.some(function(e) { return e.state !== "run" })
            ? '<a class="clear" href="https://downloads.local/clear">Svuota elenco</a>' : ''
        return `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Download</title><style>
*{box-sizing:border-box} body{background:#16161c;color:#e8eaed;font-family:sans-serif;margin:0;padding:22px}
h1{font-size:20px;font-weight:600;margin:6px 0 4px}
.empty{color:#6a6a72;font-size:14px;padding:14px 2px}
.clear{display:inline-block;color:#f28b82;font-size:14px;text-decoration:none;margin:6px 0 10px}
.drow{display:flex;align-items:center;gap:14px;padding:10px 2px;border-bottom:1px solid #24242c}
.dact{flex:none;color:#8ab4f8;font-size:14px;text-decoration:none;padding:10px 4px 10px 12px}
.dact.stop{color:#f28b82}
.bar{display:block;height:4px;background:#2e2e38;border-radius:2px;margin-top:6px;overflow:hidden}
.fill{display:block;height:100%;background:#5a7fd0;border-radius:2px}
${histCss}
</style></head><body>
<h1>Download</h1>${clear}
${body}
</body></html>`
    }

    // ===================== IMPOSTAZIONI (pagina interna) =====================
    // pagina modellata sul Browser SFOS (scelte utente 12 lug: Password e
    // Permessi placeholder, niente "Barra strumenti fissa"). Tutto HTML puro
    // (link sentinella https://settings.local/... + form GET per la homepage):
    // deve funzionare anche col toggle JavaScript spento
    property bool settingsClearArm: false   // "Pulisci dati" chiede conferma inline
    function openSettings(view) {
        settingsClearArm = false
        loadInternal(view, "settings", settingsHtml(), "https://settings.local/")
    }
    function sToggle(k, on, title, desc) {
        return '<a class="srow" href="https://settings.local/set?k=' + k + '&v=' + (on ? 0 : 1) + '">'
             + '<span class="sbody"><span class="st">' + title + '</span>'
             + (desc ? '<span class="sd">' + desc + '</span>' : '') + '</span>'
             + '<span class="sw' + (on ? ' on' : '') + '"></span></a>'
    }
    function settingsHtml() {
        var engines = ["duckduckgo", "google", "bing", "startpage"].map(function(k) {
            var on = cfgSearch === k
            return '<a class="srow" href="https://settings.local/set?k=search&v=' + k + '">'
                 + '<span class="rad' + (on ? ' on' : '') + '"></span>'
                 + '<span class="sbody"><span class="st">' + searchEngines[k].n + '</span></span></a>'
        }).join("")
        var dldirs = ["downloads", "documents", "pictures", "videos", "music"].map(function(k) {
            var on = cfgDlDir === k
            return '<a class="srow" href="https://settings.local/set?k=dldir&v=' + k + '">'
                 + '<span class="rad' + (on ? ' on' : '') + '"></span>'
                 + '<span class="sbody"><span class="st">' + dlDirs[k].n + '</span>'
                 + '<span class="sd">' + dlDirs[k].p.replace("/home/defaultuser", "~") + '</span></span></a>'
        }).join("")
        var clearRow = settingsClearArm
            ? '<div class="srow"><span class="sbody"><span class="st" style="color:#f28b82">Pulire i dati di navigazione?</span>'
              + '<span class="sd">Cronologia, elenco download, cache e sessione</span></span>'
              + '<a class="act red" href="https://settings.local/cleardata2">Pulisci</a>'
              + '<a class="act" href="https://settings.local/cancelclear">Annulla</a></div>'
            : '<a class="srow" href="https://settings.local/cleardata"><span class="sbody">'
              + '<span class="st">Pulisci dati navigazione</span>'
              + '<span class="sd">Cronologia, elenco download e cache</span></span></a>'
        return `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Impostazioni</title><style>
*{box-sizing:border-box} body{background:#16161c;color:#e8eaed;font-family:sans-serif;margin:0;padding:22px}
h1{font-size:20px;font-weight:600;margin:6px 0 4px}
h2{font-size:13px;color:#9aa0a6;font-weight:600;margin:26px 0 4px;text-transform:uppercase;letter-spacing:.6px}
.srow{display:flex;align-items:center;gap:14px;padding:13px 2px;border-bottom:1px solid #24242c;text-decoration:none;color:#e8eaed}
.sbody{flex:1;min-width:0;display:flex;flex-direction:column}
.st{font-size:15px}
.sd{font-size:12px;color:#8a8a92;margin-top:2px}
.sw{flex:none;width:46px;height:26px;border-radius:13px;background:#3a3a44;position:relative;transition:background .15s}
.sw.on{background:#3a5fc0}
.sw::after{content:"";position:absolute;top:3px;left:3px;width:20px;height:20px;border-radius:50%;background:#e8eaed;transition:left .15s}
.sw.on::after{left:23px}
.rad{flex:none;width:20px;height:20px;border-radius:50%;border:2px solid #6a6a72}
.rad.on{border-color:#3a5fc0;background:radial-gradient(circle,#8ab4f8 0 5px,transparent 6px)}
.dis .st{color:#6a6a72}
.badge{flex:none;font-size:11px;color:#9aa0a6;border:1px solid #3a3a44;border-radius:9px;padding:3px 9px}
.chev{flex:none;color:#6a6a72;font-size:22px;line-height:1}
.act{flex:none;color:#8ab4f8;font-size:14px;text-decoration:none;padding:10px 4px 10px 12px}
.act.red{color:#f28b82}
form{display:flex;gap:10px;padding:13px 2px;border-bottom:1px solid #24242c}
input{flex:1;min-width:0;background:#1c1c22;border:1px solid #3a3a44;border-radius:8px;color:#e8eaed;font-size:15px;padding:10px 12px;outline:none}
input:focus{border-color:#5a7fd0}
button{flex:none;background:#3a5fc0;border:0;border-radius:8px;color:#fff;font-size:14px;padding:10px 16px}
</style></head><body>
<h1>Impostazioni</h1>
<h2>Pagina iniziale</h2>
<form action="https://settings.local/sethome" method="get">
<input name="u" value="${htmlEsc(cfgHome)}" placeholder="HOME di RooTitanium" inputmode="url" autocapitalize="off" autocorrect="off">
<button>Salva</button>
</form>
<h2>Motore di ricerca</h2>
${engines}
<h2>Privacy</h2>
${sToggle("closetabs", cfgCloseTabs, "Chiudi tutte le schede all'uscita", "Spento: al riavvio ritrovi le schede aperte")}
${sToggle("startprivate", cfgStartPrivate, "Avvia in navigazione privata", "")}
${sToggle("dnt", cfgDnt, "Non tenere traccia", "Chiede ai siti di non tracciarti (DNT)")}
${sToggle("js", cfgJs, "Attiva JavaScript", "Consentito, raccomandato")}
${sToggle("cookies", cfgCookies, "Conserva i cookies alla chiusura", "Spento: i login non sopravvivono al riavvio")}
${sToggle("popups", cfgPopups, "Popup e nuove schede dai siti", "Spento: i link si aprono nella scheda corrente")}
${sToggle("farble", cfgFarble, "Disattiva fingerprint", "Anti-tracciamento stile Brave/Cromite: nasconde l'impronta del browser")}
${sToggle("nocookie", cfgNoCookieBanner, "Rifiuta i banner cookie", "Rifiuta o nasconde automaticamente gli avvisi sui cookie")}
<div class="srow dis"><span class="sbody"><span class="st">Password</span><span class="sd">Per sicurezza usa un gestore dedicato (Proton Pass, Bitwarden, KeePassXC)</span></span></div>
<a class="srow" href="https://permissions.local/"><span class="sbody"><span class="st">Permessi</span><span class="sd">Fotocamera, microfono, posizione, notifiche dei siti</span></span><span class="chev">›</span></a>
${clearRow}
<h2>Download — Destinazione</h2>
${dldirs}
<h2>Aspetto</h2>
${sToggle("dark", cfgDark, "Schema di colori scuro", "Forza la resa scura delle pagine")}
</body></html>`
    }

    // ===================== PERMESSI (#4) =====================
    // API WebEngine 6.8: la view emette permissionRequested(QWebEnginePermission);
    // il permesso ha origin/permissionType/state e i metodi grant()/deny()/reset().
    // Le decisioni sono persistite dal profilo (persistentPermissionsPolicy) e
    // rilette con listAllPermissions() per la pagina di gestione permissions.local.
    property var permPending: null          // permesso in attesa di decisione (tenuto vivo)
    function permLabel(t) {
        var T = WebEnginePermission.PermissionType
        if (t === T.Geolocation)             return "Conoscere la tua posizione"
        if (t === T.Notifications)           return "Inviarti notifiche"
        if (t === T.MediaAudioCapture)       return "Usare il microfono"
        if (t === T.MediaVideoCapture)       return "Usare la fotocamera"
        if (t === T.MediaAudioVideoCapture)  return "Usare fotocamera e microfono"
        if (t === T.DesktopVideoCapture)     return "Registrare lo schermo"
        if (t === T.DesktopAudioVideoCapture) return "Registrare schermo e audio"
        if (t === T.ClipboardReadWrite)      return "Leggere gli appunti"
        if (t === T.LocalFontsAccess)        return "Elencare i caratteri installati"
        if (t === T.MouseLock)               return "Bloccare il puntatore del mouse"
        return "Un permesso"
    }
    function permHost(p) { return ("" + p.origin).replace(/^[a-z]+:\/\//i, "").replace(/\/.*$/, "") }
    function showPermission(p) {
        permPending = p
        permDlg.host = permHost(p)
        permDlg.msg = permLabel(p.permissionType)
        permDlg.open = true
    }
    function permDecide(grant) {
        permDlg.open = false
        if (permPending) {
            if (grant) permPending.grant(); else permPending.deny()
            permPending = null
        }
        permRefreshPage()
    }
    // elenco permessi decisi (solo profilo normale: l'incognito è in memoria e
    // non ha una pagina di gestione persistente). Ordinati per origine.
    function permList() {
        var out = []
        try {
            var all = normalProfile.listAllPermissions()
            for (var i = 0; i < all.length; i++) {
                var p = all[i]
                var S = WebEnginePermission.State
                if (p.state !== S.Granted && p.state !== S.Denied) continue
                out.push({ origin: "" + p.origin, host: permHost(p), type: p.permissionType,
                           label: permLabel(p.permissionType), granted: p.state === S.Granted })
            }
        } catch(e) { console.warn("listAllPermissions non disponibile: " + e) }
        out.sort(function(a, b) { return a.host < b.host ? -1 : a.host > b.host ? 1 : a.type - b.type })
        return out
    }
    // revoca: reset() riporta il permesso a "chiedi" (il sito richiederà di nuovo)
    function permReset(origin, type) {
        try {
            var p = normalProfile.queryPermission(origin, type)
            if (p.isValid) p.reset()
        } catch(e) { console.warn("queryPermission/reset: " + e) }
    }
    function permRefreshPage() {
        if (currentView && currentView.localPage === "permissions")
            loadInternal(currentView, "permissions", permissionsHtml(), "https://permissions.local/")
    }
    function permissionsHtml() {
        var rows = permList()
        var body = rows.length ? rows.map(function(p) {
            var st = p.granted ? ["Consentito", "#4ea866"] : ["Bloccato", "#f28b82"]
            var enc = encodeURIComponent(p.origin) + "&t=" + p.type
            return '<div class="prow"><span class="pbody"><span class="pt">' + win.htmlEsc(p.host) + '</span>'
                 + '<span class="pu">' + win.htmlEsc(p.label) + '</span></span>'
                 + '<span class="pst" style="color:' + st[1] + '">' + st[0] + '</span>'
                 + '<a class="pact" href="https://permissions.local/reset?o=' + enc + '">Revoca</a></div>'
        }).join("") : '<div class="empty">Nessun permesso concesso o bloccato. Quando un sito chiede fotocamera, microfono, posizione o notifiche, la tua scelta comparirà qui.</div>'
        return `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Permessi</title><style>
*{box-sizing:border-box} body{background:#16161c;color:#e8eaed;font-family:sans-serif;margin:0;padding:22px}
h1{font-size:20px;font-weight:600;margin:6px 0 4px}
.hint{color:#6a6a72;font-size:12px;margin:2px 0 10px}
.empty{color:#6a6a72;font-size:14px;padding:14px 2px;line-height:1.5}
.prow{display:flex;align-items:center;gap:12px;padding:12px 2px;border-bottom:1px solid #24242c}
.pbody{flex:1;min-width:0;display:flex;flex-direction:column}
.pt{font-size:15px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.pu{font-size:12px;color:#8a8a92;margin-top:2px}
.pst{flex:none;font-size:12px}
.pact{flex:none;color:#8ab4f8;font-size:14px;text-decoration:none;padding:10px 2px 10px 10px}
</style></head><body>
<h1>Permessi</h1>
<div class="hint">Consenti o blocca l'accesso dei siti a fotocamera, microfono, posizione e notifiche. Revoca = il sito tornerà a chiedere.</div>
${body}
</body></html>`
    }

    // landing incognito (stile Chrome/Cromite)
    function incognitoHtml() {
        return `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Nuova scheda in incognito</title><style>
*{box-sizing:border-box} body{background:#202124;color:#e8eaed;font-family:sans-serif;margin:0;padding:28px}
.wrap{max-width:640px;margin:32px auto} .ico{width:76px;height:76px;border-radius:50%;background:#3c4043;
display:flex;align-items:center;justify-content:center;margin-bottom:22px}
h1{font-size:23px;font-weight:500;margin:0 0 14px} p{color:#9aa0a6;line-height:1.55;font-size:15px}
.box{background:#292a2d;border-radius:10px;padding:16px 20px;margin-top:18px}
.box b{color:#e8eaed;display:block;margin-bottom:6px} ul{margin:0;padding-left:20px;color:#9aa0a6;line-height:1.7;font-size:15px}
</style></head><body><div class="wrap">
<div class="ico"><svg width="42" height="42" viewBox="0 0 24 24" fill="none" stroke="#e8eaed" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="7" cy="15" r="3.1"/><circle cx="17" cy="15" r="3.1"/><path d="M10.1 14.6h3.8"/><path d="M3.8 12.2 5.3 7.6A2 2 0 0 1 7.2 6.2h9.6a2 2 0 0 1 1.9 1.4l1.5 4.6"/></svg></div>
<h1>Stai navigando in incognito</h1>
<p>Le altre persone che usano questo dispositivo non vedranno la tua attività, quindi puoi navigare in modo più privato.</p>
<div class="box"><b>RooTitanium non salverà:</b><ul><li>la cronologia di navigazione</li><li>i cookie e i dati dei siti</li><li>le informazioni inserite nei moduli</li></ul></div>
<div class="box"><b>La tua attività potrebbe comunque essere visibile a:</b><ul><li>i siti web che visiti</li><li>il tuo provider Internet</li></ul></div>
</div></body></html>`
    }

    // pagina DIAGNOSTICA (si apre digitando "probe" nella barra): mostra le media
    // query pointer/hover viste dalla pagina, logga gli eventi input per ogni tap
    // e ha un <video> H.264 con bottone fullscreen per isolare il nero da YouTube
    function probeHtml() {
        return `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>
body{background:#111;color:#eee;font-family:monospace;margin:0;padding:12px;font-size:14px}
#big{background:#274;padding:30px 0;text-align:center;font-size:20px;border-radius:10px;margin:10px 0;-webkit-user-select:none;user-select:none}
pre{white-space:pre-wrap;font-size:13px;color:#8f8;min-height:180px}
video{width:100%;background:#000}
button{font-size:18px;padding:12px 18px;margin:8px 0}
#mq{color:#ff8}
</style></head><body>
<div id="mq"></div>
<div id="cp"></div>
<div id="big">TAP QUI (test eventi)</div>
<pre id="log"></pre>
<p>H.264 (mp4):</p>
<video id="v1" controls preload="metadata" src="https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4"></video>
<button onclick="fs('v1')">FULLSCREEN H.264</button>
<p>VP9 (webm):</p>
<video id="v2" controls preload="metadata" src="https://test-videos.co.uk/vids/bigbuckbunny/webm/vp9/720/Big_Buck_Bunny_720_10s_1MB.webm"></video>
<button onclick="fs('v2')">FULLSCREEN VP9</button>
<script>
var t0=0;
function addl(s){var l=document.getElementById('log');l.textContent=(s+"\\n"+l.textContent).split("\\n").slice(0,22).join("\\n")}
function fs(id){document.getElementById(id).requestFullscreen().catch(function(e){addl('FS ERR: '+e)})}
function ev(e){var dt=(t0?Math.round(performance.now()-t0):0);if(e.type==='pointerdown'&&dt>500){t0=performance.now();dt=0;addl('---')}if(!t0){t0=performance.now()}addl('+'+dt+'ms '+e.type+(e.pointerType?' ('+e.pointerType+')':''))}
['pointerdown','pointerup','touchstart','touchend','mousedown','mouseup','click','contextmenu'].forEach(function(t){document.getElementById('big').addEventListener(t,ev)});
document.getElementById('mq').textContent='hover:none='+matchMedia('(hover: none)').matches+' pointer:coarse='+matchMedia('(pointer: coarse)').matches+' | ontouchstart='+('ontouchstart' in window)+' maxTouch='+navigator.maxTouchPoints;
var vt=document.createElement('video');
document.getElementById('cp').textContent='canPlay avc1='+vt.canPlayType('video/mp4; codecs="avc1.42E01E"')+' aac='+vt.canPlayType('audio/mp4; codecs="mp4a.40.2"')+' vp9='+vt.canPlayType('video/webm; codecs="vp9"')+' opus='+vt.canPlayType('audio/webm; codecs="opus"')+' av1='+vt.canPlayType('video/mp4; codecs="av01.0.05M.08"')+' | MSE='+(!!window.MediaSource);
document.addEventListener('fullscreenchange',function(){addl('fullscreenchange: '+(document.fullscreenElement?'ON':'OFF'))});
['v1','v2'].forEach(function(id){var v=document.getElementById(id);v.addEventListener('error',function(){addl(id+' ERR code='+(v.error&&v.error.code)+' msg='+(v.error&&v.error.message))});v.addEventListener('playing',function(){addl(id+' PLAYING '+v.videoWidth+'x'+v.videoHeight)})});
</script></body></html>`
    }

    // ===================== CRONOLOGIA (LocalStorage/SQLite, persistente) =====================
    // registra le visite delle schede NORMALI (mai incognito) su LoadSucceeded;
    // pagine interne (host *.local, about:blank) escluse. DB in OfflineStorage.
    // la cronologia non deve MAI impedire il load di HOME/pagine: ogni errore
    // SQL/LocalStorage viene ingoiato e riportato in _histErr (diagnosi)
    property string _histErr: ""
    function histDb() { return LocalStorage.openDatabaseSync("RooTitanium", "1.0", "Dati RooTitanium", 1000000) }
    function histAdd(url, title) {
        url = "" + url
        if (!/^https?:\/\//i.test(url) || /^https?:\/\/[^\/]*\.local(\/|$)/i.test(url)) return
        try {
            histDb().transaction(function(tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS history(url TEXT PRIMARY KEY, title TEXT, ts INTEGER, visits INTEGER DEFAULT 1)")
                var t = ("" + title) || url
                var r = tx.executeSql("UPDATE history SET title=?, ts=?, visits=visits+1 WHERE url=?", [t, Date.now(), url])
                if (r.rowsAffected === 0) tx.executeSql("INSERT INTO history(url,title,ts) VALUES(?,?,?)", [url, t, Date.now()])
            })
        } catch(e) { _histErr = "" + e; console.warn("cronologia add: " + e) }
    }
    // il titolo spesso arriva DOPO LoadSucceeded: aggiorna la riga esistente
    function histTitle(url, title) {
        url = "" + url; title = "" + title
        if (title.length === 0 || !/^https?:\/\//i.test(url)) return
        try {
            histDb().transaction(function(tx) {
                tx.executeSql("UPDATE history SET title=? WHERE url=?", [title, url])
            })
        } catch(e) {}
    }
    function histRecent(n) {
        var out = []
        try {
            histDb().transaction(function(tx) {
                tx.executeSql("CREATE TABLE IF NOT EXISTS history(url TEXT PRIMARY KEY, title TEXT, ts INTEGER, visits INTEGER DEFAULT 1)")
                var rs = tx.executeSql("SELECT url,title,ts FROM history ORDER BY ts DESC LIMIT ?", [n])
                for (var i = 0; i < rs.rows.length; i++) out.push(rs.rows.item(i))
            })
        } catch(e) { _histErr = "" + e; console.warn("cronologia read: " + e) }
        return out
    }
    function histClear() { try { histDb().transaction(function(tx) { tx.executeSql("DELETE FROM history") }) } catch(e) {} }

    // ===================== SEGNALIBRI (stessa SQLite della cronologia) =====================
    // DUE concetti separati (scelta utente 12 lug): la tabella bookmarks è la
    // RACCOLTA (si cancella solo dalla pagina Segnalibri, ✕); la colonna home=1
    // marca il sottoinsieme mostrato come Preferiti in HOME (toggle ⌂ nella
    // pagina Segnalibri; il ✕ della HOME fa solo home=0, il segnalibro resta).
    // I 6 preferiti storici sono il SEED, inserito una volta sola (flag kv
    // bmSeeded): se l'utente li rimuove non devono risorgere al riavvio.
    function bmEnsure(tx) {
        tx.executeSql("CREATE TABLE IF NOT EXISTS bookmarks(url TEXT PRIMARY KEY, title TEXT, color TEXT, letter TEXT, ts INTEGER, home INTEGER DEFAULT 0)")
        // migrazione DB pre-esistenti (senza colonna home): il DEFAULT 1 mette
        // in HOME le righe già presenti (erano i tile correnti), i nuovi
        // inserimenti passano home esplicito
        try { tx.executeSql("ALTER TABLE bookmarks ADD COLUMN home INTEGER DEFAULT 1") } catch(e) {}
        tx.executeSql("CREATE TABLE IF NOT EXISTS kv(k TEXT PRIMARY KEY, v TEXT)")
        if (tx.executeSql("SELECT v FROM kv WHERE k='bmSeeded'").rows.length === 0) {
            var seed = [
                ["DuckDuckGo","https://lite.duckduckgo.com/lite/","#de5833","D"],
                ["Wikipedia","https://it.m.wikipedia.org","#636466","W"],
                ["YouTube","https://m.youtube.com","#ff0000","Y"],
                ["GitHub","https://github.com","#6e5494","G"],
                ["Reddit","https://www.reddit.com","#ff4500","R"],
                ["OpenStreetMap","https://www.openstreetmap.org","#7ebc6f","M"]
            ]
            for (var i = 0; i < seed.length; i++)
                tx.executeSql("INSERT OR IGNORE INTO bookmarks(url,title,color,letter,ts,home) VALUES(?,?,?,?,?,1)",
                              [seed[i][1], seed[i][0], seed[i][2], seed[i][3], i])
            tx.executeSql("INSERT INTO kv(k,v) VALUES('bmSeeded','1')")
        }
    }
    function bmAll(homeOnly) {
        var out = []
        try {
            histDb().transaction(function(tx) {
                bmEnsure(tx)
                var rs = tx.executeSql("SELECT url,title,color,letter,home FROM bookmarks" + (homeOnly ? " WHERE home=1" : "") + " ORDER BY ts ASC")
                for (var i = 0; i < rs.rows.length; i++) out.push(rs.rows.item(i))
            })
        } catch(e) { _histErr = "" + e; console.warn("segnalibri read: " + e) }
        return out
    }
    function bmSetHome(url, v) {
        try { histDb().transaction(function(tx) { bmEnsure(tx); tx.executeSql("UPDATE bookmarks SET home=? WHERE url=?", [v ? 1 : 0, "" + url]) }) } catch(e) {}
    }
    // sposta su/giù nella lista: scambia i ts col vicino (l'ordine è ts ASC,
    // quindi si riordina di conseguenza anche la griglia della HOME)
    function bmMove(url, up) {
        try { histDb().transaction(function(tx) {
            bmEnsure(tx)
            var rs = tx.executeSql("SELECT url,ts FROM bookmarks ORDER BY ts ASC")
            var idx = -1
            for (var i = 0; i < rs.rows.length; i++) if (rs.rows.item(i).url === "" + url) { idx = i; break }
            var j = up ? idx - 1 : idx + 1
            if (idx < 0 || j < 0 || j >= rs.rows.length) return
            var a = rs.rows.item(idx), b = rs.rows.item(j)
            tx.executeSql("UPDATE bookmarks SET ts=? WHERE url=?", [b.ts, a.url])
            tx.executeSql("UPDATE bookmarks SET ts=? WHERE url=?", [a.ts, b.url])
        }) } catch(e) {}
    }
    function bmAdd(url, title) {
        url = "" + url
        if (!/^https?:\/\//i.test(url) || /^https?:\/\/[^\/]*\.local(\/|$)/i.test(url)) {
            toast.show("Questa pagina non si può aggiungere"); return
        }
        var host = histHost(url)
        var palette = ["#de5833","#4285f4","#0f9d58","#6e5494","#ff4500","#7ebc6f","#f4b400","#ab47bc","#00acc1","#ff7043"]
        var hsum = 0; for (var i = 0; i < host.length; i++) hsum = (hsum * 31 + host.charCodeAt(i)) % 9973
        var t = ("" + title).length ? "" + title : host
        try {
            histDb().transaction(function(tx) {
                bmEnsure(tx)
                if (tx.executeSql("SELECT url FROM bookmarks WHERE url=?", [url]).rows.length) {
                    toast.show("Già nei segnalibri")
                } else {
                    // home=0: in HOME ci va solo per scelta esplicita (⌂ nella pagina Segnalibri)
                    tx.executeSql("INSERT INTO bookmarks(url,title,color,letter,ts,home) VALUES(?,?,?,?,?,0)",
                                  [url, t, palette[hsum % palette.length], host.charAt(0).toUpperCase(), Date.now()])
                    toast.show("Aggiunto ai segnalibri")
                }
            })
        } catch(e) { _histErr = "" + e; console.warn("segnalibri add: " + e) }
    }
    function bmRemove(url) {
        try { histDb().transaction(function(tx) { bmEnsure(tx); tx.executeSql("DELETE FROM bookmarks WHERE url=?", ["" + url]) }) } catch(e) {}
    }

    // vista completa segnalibri (menù ⋮ → Segnalibri). Per riga: ⌂ = toggle
    // presenza in HOME (unico posto dove si AGGIUNGE ai preferiti HOME),
    // ✕ = cancella il segnalibro (unico posto dove si cancella davvero).
    // Sentinelle https://bookmarks.local/{home,del}?... in onNavigationRequested
    function bookmarksHtml() {
        var items = bmAll(false)
        var body = items.length
            ? items.map(function(b) {
                var host = win.histHost(b.url)
                var t = win.htmlEsc(b.title && ("" + b.title).length ? b.title : host)
                var inHome = b.home === 1 || b.home === "1"
                var enc = encodeURIComponent(b.url)
                return '<div class="brow"><a class="bmain" href="' + win.htmlEsc(b.url) + '"><span class="hfav" style="background:' + b.color + '">' + win.htmlEsc(b.letter) + '</span><span class="hbody"><span class="ht">' + t + '</span><span class="hu">' + win.htmlEsc(host) + '</span></span></a>'
                     + '<span class="bmov"><a class="bar" href="https://bookmarks.local/move?d=up&u=' + enc + '">▲</a><a class="bar" href="https://bookmarks.local/move?d=dn&u=' + enc + '">▼</a></span>'
                     + '<a class="bhome' + (inHome ? ' on' : '') + '" title="Mostra in HOME" href="https://bookmarks.local/home?v=' + (inHome ? 0 : 1) + '&u=' + enc + '">⌂</a>'
                     + '<a class="bdel" href="https://bookmarks.local/del?u=' + enc + '">✕</a></div>'
              }).join("")
            : '<div class="empty">Nessun segnalibro. Aggiungi la pagina che stai guardando dal menù ⋮ → “Aggiungi ai segnalibri”.</div>'
        var hint = items.length ? '<div class="hint">⌂ verde = mostrato nei Preferiti della HOME · ✕ = elimina il segnalibro</div>' : ''
        return `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Segnalibri</title><style>
*{box-sizing:border-box} body{background:#16161c;color:#e8eaed;font-family:sans-serif;margin:0;padding:22px}
h1{font-size:20px;font-weight:600;margin:6px 0 10px}
.empty{color:#6a6a72;font-size:14px;padding:14px 2px}
.hint{color:#6a6a72;font-size:12px;margin:2px 0 8px}
.brow{display:flex;align-items:center;border-bottom:1px solid #24242c}
.bmain{display:flex;align-items:center;gap:14px;flex:1;min-width:0;text-decoration:none;color:#c8c8d0;padding:10px 2px}
.bmov{flex:none;display:flex;flex-direction:column;gap:2px;margin-left:4px}
.bar{color:#5a5a64;font-size:12px;line-height:14px;text-decoration:none;padding:2px 8px}
.bhome{flex:none;color:#4a4a54;font-size:21px;text-decoration:none;padding:10px 8px}
.bhome.on{color:#4ea866}
.bdel{flex:none;color:#8a8a92;font-size:19px;text-decoration:none;padding:10px 4px 10px 14px}
${histCss}
</style></head><body>
<h1>Segnalibri</h1>${hint}
${body}
</body></html>`
    }

    function htmlEsc(s) { return ("" + s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;") }
    function histHost(u) { var m = ("" + u).match(/^[a-z]+:\/\/([^\/]+)/i); return m ? m[1].replace(/^www\./, "") : u }

    // righe cronologia condivise da HOME e vista completa
    function histRowsHtml(items, withTime) {
        return items.map(function(h) {
            var host = win.histHost(h.url)
            var t = win.htmlEsc(h.title && ("" + h.title).length ? h.title : host)
            var when = withTime ? '<span class="hw">' + Qt.formatDateTime(new Date(h.ts), "dd/MM hh:mm") + '</span>' : ''
            return '<a class="hrow" href="' + win.htmlEsc(h.url) + '"><span class="hfav">' + win.htmlEsc(host.charAt(0).toUpperCase()) + '</span><span class="hbody"><span class="ht">' + t + '</span><span class="hu">' + win.htmlEsc(host) + '</span></span>' + when + '</a>'
        }).join("")
    }
    readonly property string histCss: `
.hrow{display:flex;align-items:center;gap:14px;text-decoration:none;color:#c8c8d0;padding:10px 2px;border-bottom:1px solid #24242c}
.hfav{flex:none;width:38px;height:38px;border-radius:50%;background:#2e2e38;color:#e8eaed;display:flex;align-items:center;justify-content:center;font-size:18px;font-weight:700}
.hbody{display:flex;flex-direction:column;min-width:0;flex:1}
.ht{color:#e8eaed;font-size:15px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.hu{color:#8a8a92;font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.hw{flex:none;color:#6a6a72;font-size:12px;margin-left:8px}
.hmore{display:block;text-align:right;color:#8ab4f8;font-size:14px;text-decoration:none;padding:12px 2px}`

    // vista completa (menù ⋮ → Cronologia, o link dalla HOME); "svuota" =
    // link sentinella https://history.local/clear intercettato in onNavigationRequested
    function historyHtml() {
        var items = histRecent(200)
        var body = items.length
            ? histRowsHtml(items, true)
            : '<div class="empty">La cronologia è vuota.</div>'
        var clear = items.length
            ? '<a class="clear" href="https://history.local/clear">Svuota cronologia</a>'
            : ''
        return `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Cronologia</title><style>
*{box-sizing:border-box} body{background:#16161c;color:#e8eaed;font-family:sans-serif;margin:0;padding:22px}
h1{font-size:20px;font-weight:600;margin:6px 0 4px}
.empty{color:#6a6a72;font-size:14px;padding:14px 2px}
.clear{display:inline-block;color:#f28b82;font-size:14px;text-decoration:none;margin:6px 0 10px}
${histCss}
</style></head><body>
<h1>Cronologia</h1>${clear}
${body}
</body></html>`
    }

    // pagina HOME / nuova scheda (Preferiti = segnalibri con home=1 + Cronologia).
    // Long-press su un tile = modalità modifica (badge ✕ = togli dalla HOME, il
    // segnalibro RESTA nella raccolta): il contextmenu viene preventDefault-ato
    // in pagina, così il nostro menù QML non si apre sopra
    // quante voci di cronologia entrano nella HOME SENZA scrollbar verticale:
    // altezza viewport CSS (fisica/zoom, meno toolbar) meno le parti fisse
    // (logo, titoli, link, margini) e le righe della griglia preferiti;
    // stime in px CSS: riga cronologia ~60, riga griglia 82 + gap 18
    function homeHistCount(gridRows) {
        var zoom = desktopMode ? 1.0 : Math.max(1.0, Math.min(width, height) / 412)
        var viewH = (orient !== 0 ? Math.min(width, height) : Math.max(width, height)) - toolbar.height
        var vh = viewH / zoom
        var fixed = 26 + 60 + 58 + 58 + 40 + 50   // padding, logo, 2×h2, hmore, fondo+margine
        var grid = gridRows > 0 ? gridRows * 82 + (gridRows - 1) * 18 : 20
        // minimo 6 (scelta utente): con molti preferiti (3-4 righe di griglia)
        // può tornare la scrollbar, accettato — meglio della cronologia monca
        return Math.max(6, Math.min(8, Math.floor((vh - fixed - grid) / 60)))
    }

    function homeHtml() {
        var favs = bmAll(true)
        var tiles = favs.slice(0, 12).map(function(f) {
            var t = htmlEsc(f.title && ("" + f.title).length ? f.title : histHost(f.url))
            return '<a class="tile" href="' + htmlEsc(f.url) + '"><span class="bx" data-del="https://bookmarks.local/delhome?u=' + encodeURIComponent(f.url) + '">✕</span><span class="fav" style="background:' + f.color + '">' + htmlEsc(f.letter) + '</span><span class="tl">' + t + '</span></a>'
        }).join("")
        if (!favs.length) tiles = '<div class="empty" style="grid-column:1/-1">Nessun preferito. Scegli cosa mostrare qui col ⌂ nella pagina Segnalibri (menù ⋮).</div>'
        var favsMore = favs.length > 12 ? '<a class="hmore" href="https://bookmarks.local/">Tutti i segnalibri →</a>' : ''
        var gridRows = Math.ceil(Math.min(favs.length, 12) / 3)
        var hist = histRecent(homeHistCount(gridRows))
        var histSection = hist.length
            ? histRowsHtml(hist, false) + '<a class="hmore" href="https://history.local/">Tutta la cronologia →</a>'
            : '<div class="empty">La cronologia apparirà qui.</div>'
        if (_histErr.length) histSection += '<!-- histErr: ' + htmlEsc(_histErr) + ' -->'
        return `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Home</title><style>
*{box-sizing:border-box} body{background:#16161c;color:#e8eaed;font-family:sans-serif;margin:0;padding:26px}
h2{font-size:14px;color:#9aa0a6;font-weight:600;margin:28px 0 14px;text-transform:uppercase;letter-spacing:.6px}
.logo{text-align:center;font-size:30px;font-weight:700;margin:18px 0 6px;color:#f0f0f0}
.logo span{background:linear-gradient(180deg,#d3dbe3 0%,#9aa8b6 45%,#71808f 100%);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:18px}
.tile{display:flex;flex-direction:column;align-items:center;text-decoration:none;color:#c8c8d0;gap:9px;position:relative;min-width:0;max-width:100%}
.fav{width:58px;height:58px;border-radius:16px;display:flex;align-items:center;justify-content:center;color:#fff;font-size:25px;font-weight:700}
.tl{font-size:13px;max-width:100%;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.empty{color:#6a6a72;font-size:14px;padding:6px 2px}
.bx{display:none;position:absolute;top:-8px;left:calc(50% + 16px);width:26px;height:26px;border-radius:50%;background:#e35b5b;color:#fff;font-size:15px;line-height:26px;text-align:center;font-weight:700;z-index:2}
body.edit .bx{display:block}
body.edit .fav{opacity:.7}
${histCss}
</style></head><body>
<div class="logo">Roo<span>Titanium</span></div>
<h2>Preferiti</h2><div class="grid">${tiles}</div>${favsMore}
<h2>Cronologia</h2>${histSection}
<script>
(function(){
  var eb = document.body, armTs = 0;
  document.addEventListener('contextmenu', function(e){
    var t = e.target.closest ? e.target.closest('.tile') : null;
    if (t) { e.preventDefault(); eb.classList.add('edit'); armTs = Date.now(); }
    else if (eb.classList.contains('edit')) { e.preventDefault(); eb.classList.remove('edit'); }
  });
  // in modalità modifica i click non navigano: ✕ rimuove, altrove si esce.
  // il click sintetico che segue il long-press di ingresso va ignorato (armTs)
  document.addEventListener('click', function(e){
    if (!eb.classList.contains('edit')) return;
    e.preventDefault(); e.stopPropagation();
    var x = e.target.closest ? e.target.closest('.bx') : null;
    if (x) location.href = x.getAttribute('data-del');
    else if (Date.now() - armTs > 700) eb.classList.remove('edit');
  }, true);
})();
</script>
</body></html>`
    }

    // --- spoof metriche schermo per la rotazione interna ---
    // la rotazione è nostra (appRoot), quindi per Chromium lo SCHERMO resta
    // portrait 1080x2520: i player (YouTube!) dimensionano il fullscreen su
    // screen.width/height e orientation → video piazzato fuori viewport
    // (rect y=(2520-608)/2=956, verificato via CDP). Qui: getter di Screen/
    // ScreenOrientation scambiati quando siamo in landscape + evento
    // orientationchange, come una rotazione fisica vera.
    readonly property string screenSpoofJs: `(function(){
        if (window.__rtSpoof) return; window.__rtSpoof = true;
        var land = false;
        // NB: screen.* deve restare in px CSS come su Android Chrome (ora ci pensa
        // --force-device-scale-factor in run.sh: Chromium riporta già DIP=px CSS).
        // Il player YouTube (base.js pK()) confronta outerW*outerH (px CSS) col
        // max storico che include screen.w*screen.h — quando screen era in px
        // FISICI il rapporto ~0.14 → "player minimizzato" a ogni resize → hTq→F3
        // = exitFullscreen+pausa dopo ~200ms (verificato via CDP).
        function swapGet(proto, wName, hName) {
            var dw = Object.getOwnPropertyDescriptor(proto, wName), dh = Object.getOwnPropertyDescriptor(proto, hName);
            if (!dw || !dh || !dw.get || !dh.get) return;
            Object.defineProperty(proto, wName, { configurable: true, get: function(){ var w = dw.get.call(this), h = dh.get.call(this); return land ? Math.max(w,h) : Math.min(w,h); } });
            Object.defineProperty(proto, hName, { configurable: true, get: function(){ var w = dw.get.call(this), h = dh.get.call(this); return land ? Math.min(w,h) : Math.max(w,h); } });
        }
        try { swapGet(Screen.prototype, 'width', 'height'); } catch(e){}
        // availWidth/availHeight: Chromium con --force-device-scale-factor corregge
        // width/height in px CSS (412x961) ma NON avail*, che restano FISICI
        // (1080x2520) → availWidth(1080) > width(412), impossibile su un device
        // vero e segnale-bot lampante (l'anti-bot di X controlla availWidth<=width,
        // sospetta concausa del blocco login #7). Li allineo ai getter width/height
        // già spoofati (avail == dimensione piena, come una PWA mobile fullscreen)
        try {
            Object.defineProperty(Screen.prototype, 'availWidth',  { configurable: true, get: function(){ return this.width;  } });
            Object.defineProperty(Screen.prototype, 'availHeight', { configurable: true, get: function(){ return this.height; } });
            Object.defineProperty(Screen.prototype, 'availLeft',   { configurable: true, get: function(){ return 0; } });
            Object.defineProperty(Screen.prototype, 'availTop',    { configurable: true, get: function(){ return 0; } });
        } catch(e){}
        try {
            var ot = Object.getOwnPropertyDescriptor(ScreenOrientation.prototype, 'type');
            var oa = Object.getOwnPropertyDescriptor(ScreenOrientation.prototype, 'angle');
            Object.defineProperty(ScreenOrientation.prototype, 'type',  { configurable: true, get: function(){ return land ? 'landscape-primary' : ot.get.call(this); } });
            Object.defineProperty(ScreenOrientation.prototype, 'angle', { configurable: true, get: function(){ return land ? 90 : oa.get.call(this); } });
        } catch(e){}
        try { Object.defineProperty(window, 'orientation', { configurable: true, get: function(){ return land ? 90 : 0; } }); } catch(e){}
        // lock() qui NON esiste (NotSupportedError) ma YouTube ci CONTA: su
        // Android è il lock a ruotare lo schermo, e se fallisce esce dal
        // fullscreen (visto via CDP: lock RIFIUTATO → exitFullscreen da base.js).
        // Spoof: il lock landscape commuta subito lo spoof e risolve la promise.
        try {
            ScreenOrientation.prototype.lock = function(o){
                var L = ('' + o).indexOf('landscape') === 0;
                window.__rtSetLandscape(L);
                return Promise.resolve();
            };
            ScreenOrientation.prototype.unlock = function(){};
        } catch(e){}
        // su Android Chrome outer == inner (CSS px); qui di default sono px fisici
        try {
            Object.defineProperty(window, 'outerWidth',  { configurable: true, get: function(){ return window.innerWidth; } });
            Object.defineProperty(window, 'outerHeight', { configurable: true, get: function(){ return window.innerHeight; } });
        } catch(e){}
        // valori SUBITO, eventi DOPO: se orientationchange arriva durante la
        // transizione fullscreen (prima di fullscreenchange), il watchdog di
        // YouTube (base.js hTq→F3) esce dal fullscreen e PAUSA il video — visto
        // via CDP: exit a +23ms dall'evento, con fullscreenElement ancora null.
        // Con gli eventi a transizione assestata il layout nasce già coi valori
        // nuovi e l'orientationchange tardivo è solo una conferma innocua.
        var pend = null;
        window.__rtSetLandscape = function(v){
            v = !!v; if (v === land) return; land = v;
            if (pend) clearTimeout(pend);
            pend = setTimeout(function(){
                pend = null;
                try { screen.orientation.dispatchEvent(new Event('change')); } catch(e){}
                try { window.dispatchEvent(new Event('orientationchange')); } catch(e){}
            }, 600);
        };
    })();`

    // --- fix tap YouTube mobile: il tap che RIVELA i controlli non deve cliccare ---
    // QtWebEngine dopo il touchend sintetizza mousedown/mouseup/click (~20ms dopo);
    // su m.youtube.com il tap-catcher invisibile (player-controls-background,
    // opacity:0 + pointer-events:auto) mostra i controlli al touchstart e il click
    // di coda atterra sul bottone play/pausa appena comparso → pausa spuria +
    // controlli che appaiono/spariscono (verificato via CDP + tap kernel: ogni
    // tap a controlli nascosti diventava un play/pausa). Su Android Chrome quel
    // click viene assorbito da YT; qui lo inghiottiamo noi, SOLO quando il gesto
    // è iniziato sul player mweb (#player-control-container) coi controlli
    // nascosti (niente classe fadein sull'overlay) — i tap coi controlli visibili
    // passano intatti (play/pausa/seek legittimi), gli embed ytp non sono toccati.
    readonly property string ytTapFixJs: `(function(){
        if (window.__rtYtTapFix) return; window.__rtYtTapFix = true;
        var swallow = false, timer = 0;
        function fadein(){ var o = document.getElementById('player-control-overlay');
            return !!o && o.className.indexOf('fadein') >= 0; }
        window.addEventListener('touchstart', function(e){
            var p = e.target && e.target.closest && e.target.closest('#player-control-container');
            swallow = !!p && !fadein();
        }, {capture:true, passive:true});
        window.addEventListener('touchend', function(){
            if (!swallow) return;
            clearTimeout(timer); timer = setTimeout(function(){ swallow = false; }, 400);
        }, {capture:true, passive:true});
        function kill(e){ if (swallow) { e.stopImmediatePropagation(); e.preventDefault(); } }
        var evs = ['mousedown','mouseup','click'];
        for (var i = 0; i < evs.length; i++) window.addEventListener(evs[i], kill, {capture:true});
    })();`

    function pushOrientation() {
        var land = orient !== 0
        for (var i = 0; i < tabsRepeater.count; i++) {
            var v = tabsRepeater.itemAt(i)
            if (v) v.runJavaScript("window.__rtSetLandscape && window.__rtSetLandscape(" + land + ")")
        }
    }
    onOrientChanged: pushOrientation()

    ListModel { id: tabsModel }
    // avvio: config dalla kv PRIMA di creare la prima view (cfgJs/cfgCookies
    // sono binding, ma la homepage/incognito di partenza si decide qui);
    // ripristino sessione solo se "chiudi schede all'uscita" è spento
    Component.onCompleted: {
        loadCfg()
        applyClientHints()
        if (cfgStartPrivate) { newTab(true); return }
        var urls = []
        if (!cfgCloseTabs) { try { urls = JSON.parse(kvGet("session_tabs", "[]")) } catch(e) { urls = [] } }
        if (!urls || !urls.length) { newTab(false); return }
        for (var i = 0; i < urls.length; i++)
            tabsModel.append({ priv: false, start: "" + urls[i], murl: "" + urls[i], mtitle: "…" })
        currentTab = 0
        Qt.callLater(refreshCurrent)
    }

    // contenitore ruotabile: TUTTA la UI vive qui dentro; in landscape si
    // scambiano larghezza/altezza e si ruota attorno al centro della finestra
    Item {
        id: appRoot
        anchors.centerIn: parent
        rotation: win.orient
        width: win.orient % 180 === 0 ? win.width : win.height
        height: win.orient % 180 === 0 ? win.height : win.width

    Column {
        anchors.fill: parent

        // ===================== TOOLBAR =====================
        Rectangle {
            id: toolbar
            width: parent.width
            height: 78 * win.u
            visible: !win.videoFS     // video a tutto schermo → via la toolbar
            color: win.currentPrivate ? "#2a2233" : "#16161c"

            Item {
                id: homeBtn
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 6 * win.u
                width: 48 * win.u; height: parent.height
                Text { anchors.centerIn: parent; text: "⌂"; color: "#e6e6ea"; font.pixelSize: 30 * win.u }
                Rectangle { anchors.fill: parent; radius: width/2; color: "#ffffff"; opacity: hma.pressed ? 0.10 : 0 }
                MouseArea { id: hma; anchors.fill: parent; onClicked: { urlbar.focus = false; win.goHome(win.currentView) } }
            }

            // back button; durante il caricamento diventa cerchio con ✕ (stop)
            Item {
                id: backBtn
                anchors.left: homeBtn.right; anchors.verticalCenter: parent.verticalCenter
                width: 48 * win.u; height: parent.height
                readonly property bool loading: win.currentView ? win.currentView.loading === true : false
                readonly property bool canBack: win.currentView ? win.currentView.canGoBack === true : false
                opacity: (loading || canBack) ? 1.0 : 0.35
                onLoadingChanged: backIcon.requestPaint()
                Canvas {
                    id: backIcon
                    anchors.centerIn: parent
                    width: 30 * win.u; height: 30 * win.u
                    Component.onCompleted: requestPaint()
                    onPaint: {
                        var c = getContext("2d"); c.reset()
                        var s = width
                        c.strokeStyle = "#e6e6ea"; c.lineWidth = Math.max(1, s*0.09); c.lineCap = "round"; c.lineJoin = "round"
                        if (backBtn.loading) {
                            c.beginPath(); c.arc(s/2, s/2, s*0.44, 0, 2*Math.PI); c.stroke()
                            c.beginPath(); c.moveTo(s*0.34,s*0.34); c.lineTo(s*0.66,s*0.66)
                            c.moveTo(s*0.66,s*0.34); c.lineTo(s*0.34,s*0.66); c.stroke()
                        } else {
                            c.beginPath(); c.moveTo(s*0.80,s*0.5); c.lineTo(s*0.22,s*0.5)
                            c.moveTo(s*0.44,s*0.26); c.lineTo(s*0.20,s*0.5); c.lineTo(s*0.44,s*0.74); c.stroke()
                        }
                    }
                }
                Rectangle { anchors.fill: parent; radius: width/2; color: "#ffffff"; opacity: bma.pressed ? 0.10 : 0 }
                MouseArea {
                    id: bma; anchors.fill: parent
                    onClicked: {
                        if (!win.currentView) return
                        if (backBtn.loading) win.currentView.stop()
                        else if (backBtn.canBack) win.currentView.goBack()
                    }
                }
            }

            Item {
                id: menuBtn
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.rightMargin: 6 * win.u
                width: 44 * win.u; height: parent.height
                Column { anchors.centerIn: parent; spacing: 5 * win.u
                    Repeater { model: 3; Rectangle { width: 6*win.u; height: 6*win.u; radius: width/2; color: "#e6e6ea" } } }
                Rectangle { anchors.fill: parent; radius: width/2; color: "#ffffff"; opacity: mma.pressed ? 0.10 : 0 }
                MouseArea { id: mma; anchors.fill: parent; onClicked: menu.open = !menu.open }
            }

            // contatore schede → apre switcher
            Item {
                id: tabsBtn
                anchors.right: menuBtn.left; anchors.verticalCenter: parent.verticalCenter
                width: 48 * win.u; height: parent.height
                Rectangle {
                    anchors.centerIn: parent
                    width: 30 * win.u; height: 30 * win.u; radius: 6 * win.u
                    color: "transparent"; border.color: "#c8c8d0"; border.width: 2 * win.u
                    Text { anchors.centerIn: parent; text: tabsModel.count; color: "#e6e6ea"; font.pixelSize: 18 * win.u; font.bold: true }
                }
                Rectangle { anchors.fill: parent; radius: width/2; color: "#ffffff"; opacity: tma.pressed ? 0.10 : 0 }
                MouseArea { id: tma; anchors.fill: parent; onClicked: { urlbar.focus = false; switcher.showPrivate = win.currentPrivate; switcher.open = true } }
            }

            Rectangle {
                id: pill
                anchors.left: backBtn.right; anchors.right: tabsBtn.left; anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 4 * win.u; anchors.rightMargin: 4 * win.u
                height: 54 * win.u; radius: height / 2; clip: true
                color: urlbar.activeFocus ? "#303039" : (win.currentPrivate ? "#352b44" : "#26262c")
                border.color: urlbar.activeFocus ? "#5a7fd0" : "#33333c"; border.width: 1

                // icona: lucchetto (normale) o incognito (privata)
                Item {
                    id: infoIcon
                    anchors.left: parent.left; anchors.leftMargin: 18 * win.u; anchors.verticalCenter: parent.verticalCenter
                    width: 22 * win.u; height: 22 * win.u
                    // lucchetto
                    Item {
                        anchors.fill: parent; visible: !win.currentPrivate
                        Rectangle { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; width: 20*win.u; height: 13*win.u; radius: 3*win.u; color: "#9aa0a6" }
                        Rectangle { anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter; width: 12*win.u; height: 14*win.u; radius: 6*win.u; color: "transparent"; border.color: "#9aa0a6"; border.width: 2.5*win.u }
                    }
                    // incognito (occhiali) disegnato a Canvas
                    Canvas {
                        anchors.fill: parent; visible: win.currentPrivate
                        onPaint: { var c=getContext("2d"); c.reset(); var s=width; c.strokeStyle="#c9b8e0"; c.fillStyle="#c9b8e0"; c.lineWidth=s*0.09; c.lineCap="round"
                            c.beginPath(); c.arc(s*0.30,s*0.58,s*0.16,0,2*Math.PI); c.arc(s*0.70,s*0.58,s*0.16,0,2*Math.PI); c.stroke()
                            c.beginPath(); c.moveTo(s*0.44,s*0.55); c.lineTo(s*0.56,s*0.55); c.stroke()
                            c.beginPath(); c.arc(s*0.5,s*0.30,s*0.22,Math.PI*0.15,Math.PI*0.85); c.stroke() }
                    }
                }

                Text {
                    anchors.left: infoIcon.right; anchors.right: parent.right; anchors.leftMargin: 12*win.u; anchors.rightMargin: 20*win.u
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !urlbar.activeFocus
                    text: {
                        if (!win.currentView) return ""
                        var u = "" + win.currentView.url
                        if (u === "" || u === "about:blank") return '<span style="color:#6a6a72">Cerca o inserisci un indirizzo</span>'
                        return win.colorizeUrl(u)
                    }
                    textFormat: Text.RichText; font.pixelSize: 22 * win.u
                }

                TextInput {
                    id: urlbar
                    anchors.left: infoIcon.right; anchors.right: parent.right; anchors.leftMargin: 12*win.u; anchors.rightMargin: 20*win.u
                    anchors.verticalCenter: parent.verticalCenter
                    visible: activeFocus
                    color: "white"; font.pixelSize: 22 * win.u; clip: true
                    inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                    selectByMouse: true
                    onActiveFocusChanged: if (activeFocus && win.currentView) { var u = "" + win.currentView.url; text = (u === "about:blank" ? "" : u); selectAll() }
                    onAccepted: { win.go(text); focus = false }
                }

                // unica MouseArea sempre attiva su TUTTA la pillola: il TextInput da solo
                // è una striscia alta quanto il testo e il longpress mancava il bersaglio
                MouseArea {
                    anchors.fill: parent
                    onClicked: function(mouse) {
                        if (urlbar.activeFocus) {
                            var p = mapToItem(urlbar, mouse.x, mouse.y)
                            urlbar.cursorPosition = urlbar.positionAt(p.x, p.y)
                        } else urlbar.forceActiveFocus()
                    }
                    onPressAndHold: { urlbar.forceActiveFocus(); win.showUrlbarMenu() }
                }
            }
        }

        // ===================== AREA PAGINA (una WebEngineView per scheda) =====================
        Item {
            id: pageArea
            width: parent.width
            height: appRoot.height - (toolbar.visible ? toolbar.height : 0) - (inputPanel.active ? inputPanel.height : 0)
            // animazione SOLO per la tastiera: durante fullscreen/rotazione il
            // resize deve essere atomico — il viewport intermedio (larghezza già
            // ruotata, altezza ancora in animazione) faceva credere al watchdog
            // di YouTube di essere minimizzato → exitFullscreen + pausa (via CDP)
            Behavior on height { enabled: inputPanel.active; NumberAnimation { duration: 150 } }

            Repeater {
                id: tabsRepeater
                model: tabsModel
                WebEngineView {
                    anchors.fill: parent
                    visible: index === win.currentTab
                    property bool priv: model.priv
                    // pagina interna correntemente mostrata via loadHtml ("home",
                    // "downloads", "history", ...): loadHtml NON aggiorna la
                    // proprietà url (niente urlChanged, verificato su 6.8.3),
                    // quindi lo stato va tracciato a parte. "" = pagina web vera.
                    property string localPage: ""
                    profile: priv ? incognitoProfile : normalProfile
                    // zoom sul lato corto della FINESTRA (costante in landscape):
                    // viewport CSS ~412px in portrait, ~960px in landscape.
                    // NB: --force-device-scale-factor NON cambia il DSF della view
                    // (QtWebEngine usa il dpr della QQuickWindow = 1) ma corregge
                    // screen.* (in DIP) e le soglie gesture del display
                    zoomFactor: win.desktopMode ? 1.0 : Math.max(1.0, Math.min(win.width, win.height) / 412)
                    settings.fullScreenSupportEnabled: true
                    settings.javascriptEnabled: win.cfgJs
                    Component.onCompleted: {
                        userScripts.collection = win.buildScripts()
                        // REVISION(6,7): guardia come in applyViewPrefs
                        try { settings.forceDarkMode = win.cfgDark } catch(e) {}
                        if (model.start === "incognito") win.loadInternal(this, "incognito", win.incognitoHtml(), "about:blank")
                        else if (model.start === "home") win.goHome(this)
                        else url = model.start
                        win.refreshCurrent()
                    }
                    // popup/nuove schede dai siti (#6): window.open, target=_blank…
                    // niente request.openIn (le nostre view nascono dal Repeater):
                    // si apre l'URL richiesto in una scheda nuova, senza legame
                    // con l'opener — per un mini-browser basta. Toggle OFF: i
                    // gesti dell'utente restano nella scheda corrente, i popup
                    // spontanei (non user-initiated) muoiono con un toast
                    onNewWindowRequested: function(request) {
                        var u = "" + request.requestedUrl
                        if (u === "" || u === "about:blank") return
                        if (win.cfgPopups) win.newTabUrl(priv, u)
                        else if (request.userInitiated) url = u
                        else toast.show("Popup bloccato: " + win.histHost(u))
                    }
                    // pagine caricate mentre siamo già in landscape: sincronizza lo spoof
                    onLoadingChanged: function(li) {
                        if (li.status === WebEngineView.LoadSucceededStatus) {
                            if (win.orient !== 0)
                                runJavaScript("window.__rtSetLandscape && window.__rtSetLandscape(true)")
                            if (!priv) win.histAdd(url, title)   // cronologia: solo schede normali
                        }
                    }
                    // link interni cronologia (la HOME/vista sono loadHtml: host fittizio .local)
                    onNavigationRequested: function(request) {
                        var u = "" + request.url
                        if (u.indexOf("https://history.local/") === 0) {
                            request.action = WebEngineNavigationRequest.IgnoreRequest
                            if (u === "https://history.local/clear") win.histClear()
                            win.loadInternal(this, "history", win.historyHtml(), "https://history.local/")
                        } else if (u.indexOf("https://bookmarks.local/") === 0) {
                            request.action = WebEngineNavigationRequest.IgnoreRequest
                            // delhome = togli dalla HOME (il segnalibro resta);
                            // del = cancella dalla raccolta (solo pagina Segnalibri);
                            // home?v= = toggle presenza in HOME dalla pagina Segnalibri
                            var mDel = u.match(/^https:\/\/bookmarks\.local\/(del|delhome)\?u=(.*)$/)
                            var mHome = u.match(/^https:\/\/bookmarks\.local\/home\?v=([01])&u=(.*)$/)
                            var mMove = u.match(/^https:\/\/bookmarks\.local\/move\?d=(up|dn)&u=(.*)$/)
                            if (mDel && mDel[1] === "delhome") {
                                win.bmSetHome(decodeURIComponent(mDel[2]), 0)
                                win.loadInternal(this, "home", win.homeHtml(), "about:blank")
                            } else {
                                if (mDel) win.bmRemove(decodeURIComponent(mDel[2]))
                                else if (mHome) win.bmSetHome(decodeURIComponent(mHome[2]), mHome[1] === "1")
                                else if (mMove) win.bmMove(decodeURIComponent(mMove[2]), mMove[1] === "up")
                                win.loadInternal(this, "bookmarks", win.bookmarksHtml(), "https://bookmarks.local/")
                            }
                        } else if (u.indexOf("https://downloads.local/") === 0) {
                            request.action = WebEngineNavigationRequest.IgnoreRequest
                            var mOpen = u.match(/^https:\/\/downloads\.local\/open\?id=(.*)$/)
                            var mCanc = u.match(/^https:\/\/downloads\.local\/cancel\?id=(.*)$/)
                            if (mOpen) {
                                // niente reload: l'app handler si apre sopra la pagina
                                var de = win.dlFind(mOpen[1])
                                if (!(de && typeof rtNative !== "undefined" && rtNative.openFile(de.path)))
                                    toast.show("File non trovato (spostato o cancellato?)")
                            } else {
                                if (mCanc) win.dlCancel(mCanc[1])
                                else if (u === "https://downloads.local/clear") win.dlClear()
                                win.loadInternal(this, "downloads", win.downloadsHtml(), "https://downloads.local/")
                            }
                        } else if (u.indexOf("https://settings.local/") === 0) {
                            request.action = WebEngineNavigationRequest.IgnoreRequest
                            // set?k=&v= dai toggle/radio; sethome?u= dal form GET
                            // (spazi codificati come +); cleardata → conferma
                            // inline → cleardata2 esegue
                            var mSet   = u.match(/^https:\/\/settings\.local\/set\?k=([a-z]+)&v=([a-z0-9]*)$/)
                            var mSHome = u.match(/^https:\/\/settings\.local\/sethome\?u=(.*)$/)
                            win.settingsClearArm = (u === "https://settings.local/cleardata")
                            if (mSet) win.applySetting(mSet[1], mSet[2])
                            else if (mSHome) {
                                win.applySetting("homepage", decodeURIComponent(mSHome[1].replace(/\+/g, "%20")))
                                toast.show(win.cfgHome.length ? "Pagina iniziale salvata" : "Pagina iniziale: HOME di RooTitanium")
                            }
                            else if (u === "https://settings.local/cleardata2") win.clearBrowsingData()
                            win.loadInternal(this, "settings", win.settingsHtml(), "https://settings.local/")
                        } else if (u.indexOf("https://permissions.local/") === 0) {
                            request.action = WebEngineNavigationRequest.IgnoreRequest
                            // reset?o=<origin>&t=<type>: revoca (reset → il sito richiederà)
                            var mPerm = u.match(/^https:\/\/permissions\.local\/reset\?o=([^&]*)&t=(\d+)$/)
                            if (mPerm) win.permReset(decodeURIComponent(mPerm[1]), parseInt(mPerm[2]))
                            win.loadInternal(this, "permissions", win.permissionsHtml(), "https://permissions.local/")
                        }
                    }
                    // richiesta permesso di un sito (geoloc/notifiche/camera/mic/…):
                    // mostriamo il dialogo QML; grant()/deny() sul permesso, che il
                    // profilo persiste. Senza handler le richieste morivano in silenzio.
                    onPermissionRequested: function(permission) { win.showPermission(permission) }
                    onUrlChanged: { localPage = ""; tabsModel.setProperty(index, "murl", "" + url); win.saveSession() }
                    onTitleChanged: {
                        tabsModel.setProperty(index, "mtitle", title && title.length ? "" + title : "Nuova scheda")
                        if (!priv) win.histTitle(url, title)   // il titolo spesso arriva dopo il load
                    }
                    onContextMenuRequested: function(request) {
                        request.accepted = true          // sopprime il menù nativo (minuscolo, non scalato)
                        win.showContext(this, request)
                    }
                    // quick-menu di selezione touch di Chromium ("Copy | …"): canale
                    // separato da contextMenuRequested, va soppresso a parte
                    onTouchSelectionMenuRequested: function(request) {
                        request.accepted = true
                        win.showTouchSelection(this, request)
                    }
                    // alert/confirm/prompt nativi: minuscoli e non scalati → UI nostra
                    onJavaScriptDialogRequested: function(request) {
                        request.accepted = true
                        win.showJsDialog(request)
                    }
                    onTooltipRequested: function(request) { request.accepted = true }  // niente tooltip nativi minuscoli
                    onFindTextFinished: function(result) {
                        win.findCur = result.activeMatch
                        win.findTot = result.numberOfMatches
                    }
                    // esito di printToPdf (Salva pagina come PDF)
                    onPdfPrintingFinished: function(filePath, success) {
                        var name = ("" + filePath).replace(/^.*\//, "")
                        toast.show(success ? "PDF salvato in Documenti: " + name
                                           : "Salvataggio PDF fallito")
                    }
                    // video a tutto schermo: senza accept() la richiesta JS viene
                    // rifiutata e il player resta inline. Accettata → landscape auto
                    onFullScreenRequested: function(request) {
                        request.accept()
                        win.videoFS = request.toggleOn
                    }
                }
            }
        }
    }

    // ===================== CERCA NELLA PAGINA (UI) =====================
    // barra sotto la toolbar (overlay, non sposta la pagina); find-as-you-type
    // con findText(), contatore n/m da onFindTextFinished, ▲▼ prev/next.
    // findText("") a chiusura pulisce le evidenziazioni. NB: qui siamo dentro
    // appRoot (Item ruotabile): proprietà e funzioni stanno su win.
    Rectangle {
        id: findBar
        property bool open: false
        // stile Chrome mobile: la barra di ricerca SOSTITUISCE la toolbar
        // (overlay a tutta altezza sopra di essa, z sopra pagina e toolbar)
        anchors.top: parent.top
        width: parent.width; height: toolbar.height
        visible: open && !win.videoFS; z: 40
        color: "#1e1e26"
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#33333c" }

        MenuIcon { id: findIco; kind: "search"; anchors.left: parent.left; anchors.leftMargin: 18*win.u; anchors.verticalCenter: parent.verticalCenter; width: 26*win.u; height: 26*win.u }

        TextInput {
            id: findInput
            anchors.left: findIco.right; anchors.leftMargin: 14 * win.u
            anchors.right: findCount.left; anchors.rightMargin: 8 * win.u
            anchors.verticalCenter: parent.verticalCenter
            color: "white"; font.pixelSize: 22 * win.u; clip: true
            inputMethodHints: Qt.ImhNoAutoUppercase
            selectByMouse: true
            onTextChanged: {
                win.findCur = 0; win.findTot = 0
                if (win.currentView && findBar.open) win.currentView.findText(text)
            }
            onAccepted: win.findNextMatch(false)
            Text { anchors.verticalCenter: parent.verticalCenter; visible: findInput.text.length === 0
                   text: "Cerca nella pagina"; color: "#6a6a72"; font.pixelSize: 22 * win.u }
        }
        Text {
            id: findCount
            anchors.right: findPrev.left; anchors.rightMargin: 6 * win.u
            anchors.verticalCenter: parent.verticalCenter
            text: win.findTot ? (win.findCur + "/" + win.findTot) : (findInput.text.length ? "0/0" : "")
            color: "#8a8a92"; font.pixelSize: 18 * win.u
        }
        Item { id: findPrev; anchors.right: findNextB.left; width: 46*win.u; height: parent.height
            Text { anchors.centerIn: parent; text: "▲"; color: "#e6e6ea"; font.pixelSize: 20*win.u }
            Rectangle { anchors.fill: parent; radius: width/2; color: "#ffffff"; opacity: fpma.pressed ? 0.10 : 0 }
            MouseArea { id: fpma; anchors.fill: parent; onClicked: win.findNextMatch(true) } }
        Item { id: findNextB; anchors.right: findClose.left; width: 46*win.u; height: parent.height
            Text { anchors.centerIn: parent; text: "▼"; color: "#e6e6ea"; font.pixelSize: 20*win.u }
            Rectangle { anchors.fill: parent; radius: width/2; color: "#ffffff"; opacity: fnma.pressed ? 0.10 : 0 }
            MouseArea { id: fnma; anchors.fill: parent; onClicked: win.findNextMatch(false) } }
        Item { id: findClose; anchors.right: parent.right; anchors.rightMargin: 4*win.u; width: 46*win.u; height: parent.height
            Text { anchors.centerIn: parent; text: "✕"; color: "#e6e6ea"; font.pixelSize: 22*win.u }
            Rectangle { anchors.fill: parent; radius: width/2; color: "#ffffff"; opacity: fcma.pressed ? 0.10 : 0 }
            MouseArea { id: fcma; anchors.fill: parent; onClicked: win.closeFind() } }
    }

    // ===================== MENU (⋮) =====================
    // onPressAndHold: dopo un longpress il click NON viene emesso → senza questo
    // un longpress fuori dal menù lo lasciava aperto (e "mangiava" il gesto)
    MouseArea { anchors.fill: parent; z: 49; enabled: menu.open; onClicked: menu.open = false; onPressAndHold: menu.open = false }

    Rectangle {
        id: menu
        property bool open: false
        anchors.right: parent.right; anchors.top: toolbar.bottom
        width: 340 * win.u; height: menuCol.height + 16 * win.u
        color: "#2c2c31"; border.color: "#3a3a42"; border.width: 1
        visible: open; z: 50
        Column {
            id: menuCol; width: parent.width; y: 8 * win.u
            Repeater {
                model: win.menuModel
                delegate: Loader {
                    width: menuCol.width
                    sourceComponent: modelData.t === "sep" ? sepComp : rowComp
                    onLoaded: if (modelData.t !== "sep") { item.entry = modelData }
                }
            }
        }
    }

    Component {
        id: sepComp
        Item { height: 13 * win.u
            Rectangle { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: 18*win.u; anchors.rightMargin: 18*win.u; height: 1; color: "#43434c" } }
    }

    Component {
        id: rowComp
        Rectangle {
            property var entry
            height: 62 * win.u; color: rma.pressed ? "#3a3a44" : "transparent"
            MenuIcon { id: ic; anchors.left: parent.left; anchors.leftMargin: 22*win.u; anchors.verticalCenter: parent.verticalCenter
                width: 32*win.u; height: 32*win.u; kind: entry ? entry.ic : "" }
            Text { anchors.left: parent.left; anchors.leftMargin: 74*win.u; anchors.right: toggleDot.left; anchors.rightMargin: 8*win.u
                anchors.verticalCenter: parent.verticalCenter; text: entry ? entry.l : ""; color: "#eaeaf0"; font.pixelSize: 21*win.u; elide: Text.ElideRight }
            Rectangle { id: toggleDot; anchors.right: parent.right; anchors.rightMargin: 22*win.u; anchors.verticalCenter: parent.verticalCenter
                width: 16*win.u; height: 16*win.u; radius: width/2; visible: entry && entry.toggle === true
                color: (entry && entry.a === "rotate" ? win.manualLandscape : win.desktopMode) ? "#4ea866" : "transparent"
                border.color: "#7a7a82"; border.width: 2*win.u }
            MouseArea { id: rma; anchors.fill: parent; onClicked: win.doAction(entry.a) }
        }
    }

    // ===================== CONTEXT MENU (visuale) =====================
    MouseArea { anchors.fill: parent; z: 59; enabled: ctxMenu.open; onClicked: ctxMenu.open = false; onPressAndHold: ctxMenu.open = false }

    Rectangle {
        id: ctxMenu
        property bool open: false
        property real px: 0
        property real py: 0
        width: 320 * win.u
        height: ctxCol.height + 16 * win.u
        x: Math.max(8*win.u, Math.min(px, appRoot.width  - width  - 8*win.u))
        y: Math.max(8*win.u, Math.min(py, appRoot.height - height - 8*win.u))
        color: "#2c2c31"; border.color: "#3a3a42"; border.width: 1; radius: 6 * win.u
        visible: open; z: 60
        Column {
            id: ctxCol; width: parent.width; y: 8 * win.u
            Repeater {
                model: win.ctxModel
                delegate: Loader {
                    width: ctxCol.width
                    sourceComponent: modelData.sep === true ? sepComp : ctxRowComp
                    onLoaded: if (modelData.sep !== true) item.entry = modelData
                }
            }
        }
    }

    Component {
        id: ctxRowComp
        Rectangle {
            property var entry
            height: 58 * win.u
            color: (entry && entry.dis === true) ? "transparent" : (crma.pressed ? "#3a3a44" : "transparent")
            Text {
                anchors.left: parent.left; anchors.leftMargin: 24*win.u
                anchors.right: parent.right; anchors.rightMargin: 20*win.u
                anchors.verticalCenter: parent.verticalCenter
                text: entry ? entry.l : ""
                color: (entry && entry.dis === true) ? "#6a6a72" : "#eaeaf0"
                font.pixelSize: 21*win.u; elide: Text.ElideRight
            }
            MouseArea { id: crma; anchors.fill: parent
                enabled: !(entry && entry.dis === true)
                onClicked: win.ctxAction(entry.a) }
        }
    }

    // ===================== SWITCHER SCHEDE =====================
    Rectangle {
        id: switcher
        property bool open: false
        property bool showPrivate: false
        anchors.fill: parent
        color: showPrivate ? "#17121f" : "#0e0e12"
        visible: open; z: 80

        // barra superiore
        Rectangle {
            id: swBar
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            height: 84 * win.u; color: "transparent"

            // chiudi switcher
            Text { anchors.left: parent.left; anchors.leftMargin: 20*win.u; anchors.verticalCenter: parent.verticalCenter
                text: "✕"; color: "#e6e6ea"; font.pixelSize: 28*win.u
                MouseArea { anchors.fill: parent; anchors.margins: -14*win.u; onClicked: switcher.open = false } }

            // segmenti Normali / Incognito
            Row {
                anchors.centerIn: parent; spacing: 8 * win.u
                Rectangle {
                    width: 130*win.u; height: 50*win.u; radius: 25*win.u
                    color: !switcher.showPrivate ? "#33333e" : "transparent"
                    Text { anchors.centerIn: parent; text: "Schede " + win.tabCount(false); color: "#e6e6ea"; font.pixelSize: 18*win.u }
                    MouseArea { anchors.fill: parent; onClicked: switcher.showPrivate = false }
                }
                Rectangle {
                    width: 150*win.u; height: 50*win.u; radius: 25*win.u
                    color: switcher.showPrivate ? "#3a3050" : "transparent"
                    Text { anchors.centerIn: parent; text: "Incognito " + win.tabCount(true); color: "#c9b8e0"; font.pixelSize: 18*win.u }
                    MouseArea { anchors.fill: parent; onClicked: switcher.showPrivate = true }
                }
            }

            // nuova scheda (nel filtro corrente)
            Rectangle {
                anchors.right: parent.right; anchors.rightMargin: 18*win.u; anchors.verticalCenter: parent.verticalCenter
                width: 50*win.u; height: 50*win.u; radius: 12*win.u; color: pma.pressed ? "#4a6fd0" : "#3a5fc0"
                Text { anchors.centerIn: parent; text: "+"; color: "white"; font.pixelSize: 32*win.u }
                MouseArea { id: pma; anchors.fill: parent; onClicked: win.newTab(switcher.showPrivate) }
            }
        }

        // griglia card
        Flickable {
            anchors.top: swBar.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.margins: 16 * win.u
            contentHeight: cardsFlow.height; clip: true
            Flow {
                id: cardsFlow
                width: parent.width; spacing: 16 * win.u
                Repeater {
                    model: tabsModel
                    delegate: Rectangle {
                        visible: model.priv === switcher.showPrivate
                        width: (cardsFlow.width - 16*win.u) / 2
                        height: width * 1.35
                        radius: 12 * win.u
                        color: "#1c1c24"
                        border.color: index === win.currentTab ? "#5a7fd0" : "#2e2e38"; border.width: index === win.currentTab ? 3*win.u : 1

                        // header: titolo + chiudi
                        Rectangle {
                            id: cardHead
                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                            height: 46 * win.u; radius: 12 * win.u
                            color: model.priv ? "#2c2440" : "#26262f"
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 12*win.u; color: parent.color }  // squadra il basso
                            Text { anchors.left: parent.left; anchors.leftMargin: 12*win.u; anchors.right: closeX.left; anchors.rightMargin: 6*win.u
                                anchors.verticalCenter: parent.verticalCenter; text: model.mtitle; color: "#e6e6ea"; font.pixelSize: 16*win.u; elide: Text.ElideRight }
                            Text { id: closeX; anchors.right: parent.right; anchors.rightMargin: 12*win.u; anchors.verticalCenter: parent.verticalCenter
                                text: "✕"; color: "#b0b0b8"; font.pixelSize: 20*win.u
                                MouseArea { anchors.fill: parent; anchors.margins: -10*win.u; onClicked: win.closeTab(index) } }
                        }
                        // corpo: url (placeholder anteprima)
                        Text {
                            anchors.top: cardHead.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 12*win.u
                            text: ("" + model.murl).replace(/^https?:\/\//, ""); color: "#8a8a94"; font.pixelSize: 14*win.u
                            wrapMode: Text.WrapAnywhere; maximumLineCount: 3; elide: Text.ElideRight
                        }
                        MouseArea { anchors.fill: parent; anchors.topMargin: 46*win.u; onClicked: win.switchTab(index) }
                    }
                }
            }
        }
    }

    // ===================== ICONE MENU (Canvas) =====================
    component MenuIcon: Canvas {
        property string kind: ""
        onKindChanged: requestPaint()
        Component.onCompleted: requestPaint()
        onPaint: {
            var ctx = getContext("2d"); ctx.reset()
            var s = width, m = s * 0.14, cx = s/2, cy = s/2
            ctx.strokeStyle = "#dcdce2"; ctx.fillStyle = "#dcdce2"
            ctx.lineWidth = Math.max(1, s * 0.07); ctx.lineCap = "round"; ctx.lineJoin = "round"
            function rrect(x,y,w,h,r){ ctx.beginPath(); ctx.moveTo(x+r,y); ctx.arcTo(x+w,y,x+w,y+h,r); ctx.arcTo(x+w,y+h,x,y+h,r); ctx.arcTo(x,y+h,x,y,r); ctx.arcTo(x,y,x+w,y,r); ctx.closePath() }
            var k = kind
            if (k === "newtab" || k === "private") {
                rrect(m,m,s-2*m,s-2*m,s*0.14); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(cx,cy-s*0.16); ctx.lineTo(cx,cy+s*0.16); ctx.moveTo(cx-s*0.16,cy); ctx.lineTo(cx+s*0.16,cy); ctx.stroke()
                if (k === "private") { ctx.beginPath(); rrect(m,m,s-2*m,s*0.20,s*0.08); ctx.fill() }
            } else if (k === "search") {
                ctx.beginPath(); ctx.arc(s*0.42,s*0.42,s*0.24,0,2*Math.PI); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(s*0.60,s*0.60); ctx.lineTo(s*0.84,s*0.84); ctx.stroke()
            } else if (k === "grid") {
                var d = s*0.13, g = s*0.11, x0 = s*0.22, y0 = s*0.22
                for (var i=0;i<3;i++) for (var j=0;j<3;j++){ ctx.beginPath(); ctx.rect(x0+i*(d+g), y0+j*(d+g), d, d); ctx.fill() }
            } else if (k === "share") {
                var r = s*0.09
                var p1x=s*0.72,p1y=s*0.22, p2x=s*0.28,p2y=s*0.5, p3x=s*0.72,p3y=s*0.78
                ctx.beginPath(); ctx.moveTo(p2x,p2y); ctx.lineTo(p1x,p1y); ctx.moveTo(p2x,p2y); ctx.lineTo(p3x,p3y); ctx.stroke()
                ctx.beginPath(); ctx.arc(p1x,p1y,r,0,2*Math.PI); ctx.arc(p2x,p2y,r,0,2*Math.PI); ctx.arc(p3x,p3y,r,0,2*Math.PI); ctx.fill()
            } else if (k === "pdf") {
                rrect(s*0.24,m,s*0.5,s-2*m,s*0.05); ctx.stroke()
                for (var li=0; li<3; li++){ ctx.beginPath(); ctx.moveTo(s*0.33, s*0.36+li*s*0.14); ctx.lineTo(s*0.65, s*0.36+li*s*0.14); ctx.stroke() }
            } else if (k === "desktop") {
                rrect(s*0.16,s*0.22,s*0.68,s*0.42,s*0.05); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(s*0.08,s*0.76); ctx.lineTo(s*0.92,s*0.76); ctx.stroke()
            } else if (k === "rotate") {
                rrect(s*0.32,s*0.14,s*0.36,s*0.62,s*0.07); ctx.stroke()
                ctx.beginPath(); ctx.arc(cx,cy+s*0.06,s*0.42,Math.PI*0.25,Math.PI*0.75); ctx.stroke()
                var axr=cx+Math.cos(Math.PI*0.25)*s*0.42, ayr=cy+s*0.06+Math.sin(Math.PI*0.25)*s*0.42
                ctx.beginPath(); ctx.moveTo(axr,ayr); ctx.lineTo(axr-s*0.11,ayr+s*0.01); ctx.moveTo(axr,ayr); ctx.lineTo(axr-s*0.01,ayr-s*0.11); ctx.stroke()
            } else if (k === "star") {
                ctx.beginPath()
                for (var t=0;t<10;t++){ var rad = (t%2===0)? s*0.34 : s*0.15; var an = -Math.PI/2 + t*Math.PI/5; var px=cx+rad*Math.cos(an), py=cy+rad*Math.sin(an); if(t===0) ctx.moveTo(px,py); else ctx.lineTo(px,py) }
                ctx.closePath(); ctx.fill()
            } else if (k === "staradd") {
                ctx.beginPath()
                for (var t2=0;t2<10;t2++){ var rad2=(t2%2===0)?s*0.30:s*0.13; var an2=-Math.PI/2+t2*Math.PI/5; var px2=cx-s*0.06+rad2*Math.cos(an2), py2=cy+s*0.04+rad2*Math.sin(an2); if(t2===0) ctx.moveTo(px2,py2); else ctx.lineTo(px2,py2) }
                ctx.closePath(); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(s*0.78,s*0.14); ctx.lineTo(s*0.78,s*0.38); ctx.moveTo(s*0.66,s*0.26); ctx.lineTo(s*0.90,s*0.26); ctx.stroke()
            } else if (k === "history") {
                ctx.beginPath(); ctx.arc(cx,cy,s*0.30,0,2*Math.PI); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(cx,cy); ctx.lineTo(cx,cy-s*0.18); ctx.moveTo(cx,cy); ctx.lineTo(cx+s*0.15,cy+s*0.05); ctx.stroke()
            } else if (k === "download") {
                ctx.beginPath(); ctx.moveTo(cx,s*0.18); ctx.lineTo(cx,s*0.60); ctx.moveTo(cx-s*0.15,s*0.44); ctx.lineTo(cx,s*0.62); ctx.lineTo(cx+s*0.15,s*0.44); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(s*0.22,s*0.80); ctx.lineTo(s*0.78,s*0.80); ctx.stroke()
            } else if (k === "settings") {
                ctx.beginPath(); ctx.arc(cx,cy,s*0.16,0,2*Math.PI); ctx.stroke()
                for (var g2=0; g2<8; g2++){ var a2 = g2*Math.PI/4; ctx.beginPath(); ctx.moveTo(cx+Math.cos(a2)*s*0.22, cy+Math.sin(a2)*s*0.22); ctx.lineTo(cx+Math.cos(a2)*s*0.32, cy+Math.sin(a2)*s*0.32); ctx.stroke() }
            }
        }
    }

    // ===================== DIALOGO JS (alert/confirm/prompt) =====================
    Rectangle {
        id: jsDlg
        property bool open: false
        property int dtype: 0
        property string host: ""
        property string msg: ""
        property alias input: jsInput.text
        readonly property bool isPrompt: dtype === JavaScriptDialogRequest.DialogTypePrompt
        anchors.fill: parent
        color: "#99000000"
        visible: open; z: 90
        onOpenChanged: if (open && isPrompt) jsInput.forceActiveFocus()
        MouseArea { anchors.fill: parent; onPressAndHold: {} }   // modale: blocca i gesti sotto

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(jsDlg.width - 48*win.u, 460*win.u)
            height: dlgCol.height + 36*win.u
            radius: 14*win.u; color: "#2c2c31"; border.color: "#3a3a42"; border.width: 1
            Column {
                id: dlgCol
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top; anchors.topMargin: 18*win.u
                width: parent.width - 44*win.u
                spacing: 14*win.u
                Text { width: parent.width; text: jsDlg.host; visible: jsDlg.host.length > 0
                    color: "#9aa0a6"; font.pixelSize: 17*win.u; elide: Text.ElideRight }
                Text { width: parent.width; text: jsDlg.msg; color: "#eaeaf0"; font.pixelSize: 21*win.u; wrapMode: Text.Wrap }
                Rectangle {
                    width: parent.width; height: 54*win.u; radius: 8*win.u
                    visible: jsDlg.isPrompt
                    color: "#1c1c22"; border.color: jsInput.activeFocus ? "#5a7fd0" : "#3a3a42"; border.width: 1
                    TextInput { id: jsInput; anchors.fill: parent; anchors.leftMargin: 14*win.u; anchors.rightMargin: 14*win.u
                        verticalAlignment: TextInput.AlignVCenter; color: "white"; font.pixelSize: 20*win.u; clip: true
                        onAccepted: win.jsDialogDone(true) }
                }
                Row {
                    anchors.right: parent.right; spacing: 10*win.u
                    Rectangle {
                        width: annullaTxt.paintedWidth + 40*win.u; height: 56*win.u; radius: 28*win.u
                        visible: jsDlg.dtype !== JavaScriptDialogRequest.DialogTypeAlert
                        color: jcma.pressed ? "#3a3a44" : "transparent"
                        Text { id: annullaTxt; anchors.centerIn: parent; text: "Annulla"; color: "#8ab4f8"; font.pixelSize: 20*win.u }
                        MouseArea { id: jcma; anchors.fill: parent; onClicked: win.jsDialogDone(false) }
                    }
                    Rectangle {
                        width: okTxt.paintedWidth + 40*win.u; height: 56*win.u; radius: 28*win.u
                        color: joma.pressed ? "#4a6fd0" : "#3a5fc0"
                        Text { id: okTxt; anchors.centerIn: parent; text: "OK"; color: "white"; font.pixelSize: 20*win.u }
                        MouseArea { id: joma; anchors.fill: parent; onClicked: win.jsDialogDone(true) }
                    }
                }
            }
        }
    }

    // ===================== DIALOGO PERMESSI (#4) =====================
    // "<host> vuole: <azione>" con Blocca/Consenti. Stessa UI del dialogo JS.
    Rectangle {
        id: permDlg
        property bool open: false
        property string host: ""
        property string msg: ""
        anchors.fill: parent
        color: "#99000000"
        visible: open; z: 90
        MouseArea { anchors.fill: parent; onPressAndHold: {} }   // modale

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(permDlg.width - 48*win.u, 460*win.u)
            height: permCol.height + 36*win.u
            radius: 14*win.u; color: "#2c2c31"; border.color: "#3a3a42"; border.width: 1
            Column {
                id: permCol
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top; anchors.topMargin: 18*win.u
                width: parent.width - 44*win.u
                spacing: 14*win.u
                Text { width: parent.width; text: permDlg.host; visible: permDlg.host.length > 0
                    color: "#9aa0a6"; font.pixelSize: 17*win.u; elide: Text.ElideRight }
                Text { width: parent.width; text: "Vuole: " + permDlg.msg; color: "#eaeaf0"; font.pixelSize: 21*win.u; wrapMode: Text.Wrap }
                Row {
                    anchors.right: parent.right; spacing: 10*win.u
                    Rectangle {
                        width: permNoTxt.paintedWidth + 40*win.u; height: 56*win.u; radius: 28*win.u
                        color: pnma.pressed ? "#3a3a44" : "transparent"
                        Text { id: permNoTxt; anchors.centerIn: parent; text: "Blocca"; color: "#8ab4f8"; font.pixelSize: 20*win.u }
                        MouseArea { id: pnma; anchors.fill: parent; onClicked: win.permDecide(false) }
                    }
                    Rectangle {
                        width: permYesTxt.paintedWidth + 40*win.u; height: 56*win.u; radius: 28*win.u
                        color: pyma.pressed ? "#4a6fd0" : "#3a5fc0"
                        Text { id: permYesTxt; anchors.centerIn: parent; text: "Consenti"; color: "white"; font.pixelSize: 20*win.u }
                        MouseArea { id: pyma; anchors.fill: parent; onClicked: win.permDecide(true) }
                    }
                }
            }
        }
    }

    // toast (conferme brevi)
    Rectangle {
        id: toast
        property string msg: ""
        function show(m) { msg = m; opacity = 1; toastTimer.restart() }
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 44 * win.u
        width: tt.paintedWidth + 44 * win.u; height: 60 * win.u; radius: 30 * win.u
        color: "#e6000000"; opacity: 0; visible: opacity > 0; z: 200
        Behavior on opacity { NumberAnimation { duration: 250 } }
        Text { id: tt; anchors.centerIn: parent; text: toast.msg; color: "white"; font.pixelSize: 18 * win.u }
        Timer { id: toastTimer; interval: 1900; onTriggered: toast.opacity = 0 }
    }

    // tastiera QtVirtualKeyboard in-app; in landscape resta larga come il lato
    // corto (a tutta larghezza scalerebbe fino a coprire l'intero schermo)
    InputPanel {
        id: inputPanel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: Math.min(parent.width, win.width)
        visible: active
        z: 99
    }

    }   // fine appRoot
}
