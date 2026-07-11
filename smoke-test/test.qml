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
        if (tabsModel.count === 0) { newTab(false); return }   // ultima scheda chiusa → HOME
        if (currentTab >= tabsModel.count) currentTab = tabsModel.count - 1
        Qt.callLater(refreshCurrent)
    }
    function switchTab(i) { currentTab = i; switcher.open = false; Qt.callLater(refreshCurrent) }
    function tabCount(priv) { var n = 0; for (var i=0;i<tabsModel.count;i++) if (tabsModel.get(i).priv === priv) n++; return n }

    // --- user agent per toggle Versione desktop ---
    property bool desktopMode: false
    readonly property string uaMobile: "Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
    readonly property string uaDesktop: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    function setDesktop(on) { desktopMode = on; if (currentView) currentView.reload() }

    function go(t) {
        t = t.trim()
        if (t.length === 0 || !currentView) return
        if (t === "probe") { currentView.loadHtml(probeHtml(), "https://probe.local/"); return }   // pagina diagnostica
        if (/^[a-z]+:\/\//i.test(t)) currentView.url = t
        else if (/^[^ ]+\.[^ ]+$/.test(t)) currentView.url = "https://" + t
        else currentView.url = "https://lite.duckduckgo.com/lite/?q=" + encodeURIComponent(t)
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
        else if (a === "pdf") { if (currentView) currentView.printToPdf("/home/defaultuser/pagina.pdf") }
        else if (a === "share") shareUrl()
        else if (a === "history") { if (currentView) currentView.loadHtml(historyHtml(), "https://history.local/") }
        else console.log("menu action (placeholder): " + a)
    }

    // Condividi = copia l'URL corrente negli appunti (wl_data_device_manager) + toast
    function shareUrl() {
        if (!currentView) return
        var u = "" + currentView.url
        if (u === "" || u === "about:blank") return
        clipHelper.text = u
        clipHelper.selectAll()
        clipHelper.copy()
        toast.show("Link copiato negli appunti")
    }
    TextInput { id: clipHelper; visible: false }

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

    // profilo NORMALE: persistente (cookie/login/cronologia salvati su disco)
    WebEngineProfile {
        id: normalProfile
        storageName: "rootitanium"
        persistentStoragePath: "/home/defaultuser/.rootitanium"
        httpUserAgent: win.desktopMode ? win.uaDesktop : win.uaMobile
        onDownloadRequested: function(download) { win.handleDownload(download) }
    }
    // profilo INCOGNITO: niente storageName → off-the-record (in memoria, isolato dal normale)
    WebEngineProfile {
        id: incognitoProfile
        httpUserAgent: win.desktopMode ? win.uaDesktop : win.uaMobile
        onDownloadRequested: function(download) { win.handleDownload(download) }
    }

    // senza questo handler i download (Salva link/immagine) muoiono in silenzio:
    // il profilo emette downloadRequested ma nessuno chiama accept()
    function handleDownload(download) {
        download.downloadDirectory = "/home/defaultuser/Downloads"
        download.accept()
        toast.show("Download avviato: " + download.downloadFileName)
        download.stateChanged.connect(function() {
            if (download.state === WebEngineDownloadRequest.DownloadCompleted)
                toast.show("Scaricato in Downloads: " + download.downloadFileName)
            else if (download.state === WebEngineDownloadRequest.DownloadInterrupted)
                toast.show("Download fallito: " + download.downloadFileName)
        })
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

    // pagina HOME / nuova scheda (Preferiti + Cronologia)
    function homeHtml() {
        var favs = [
            ["DuckDuckGo","https://lite.duckduckgo.com/lite/","#de5833","D"],
            ["Wikipedia","https://it.m.wikipedia.org","#636466","W"],
            ["YouTube","https://m.youtube.com","#ff0000","Y"],
            ["GitHub","https://github.com","#6e5494","G"],
            ["Reddit","https://www.reddit.com","#ff4500","R"],
            ["OpenStreetMap","https://www.openstreetmap.org","#7ebc6f","M"]
        ]
        var tiles = favs.map(function(f){ return `<a class="tile" href="${f[1]}"><span class="fav" style="background:${f[2]}">${f[3]}</span><span class="tl">${f[0]}</span></a>` }).join("")
        var hist = histRecent(8)
        var histSection = hist.length
            ? histRowsHtml(hist, false) + '<a class="hmore" href="https://history.local/">Tutta la cronologia →</a>'
            : '<div class="empty">La cronologia apparirà qui.</div>'
        if (_histErr.length) histSection += '<!-- histErr: ' + htmlEsc(_histErr) + ' -->'
        return `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Home</title><style>
*{box-sizing:border-box} body{background:#16161c;color:#e8eaed;font-family:sans-serif;margin:0;padding:26px}
h2{font-size:14px;color:#9aa0a6;font-weight:600;margin:28px 0 14px;text-transform:uppercase;letter-spacing:.6px}
.logo{text-align:center;font-size:30px;font-weight:700;margin:18px 0 6px;color:#f0f0f0}
.logo span{background:linear-gradient(180deg,#d3dbe3 0%,#9aa8b6 45%,#71808f 100%);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:18px}
.tile{display:flex;flex-direction:column;align-items:center;text-decoration:none;color:#c8c8d0;gap:9px}
.fav{width:58px;height:58px;border-radius:16px;display:flex;align-items:center;justify-content:center;color:#fff;font-size:25px;font-weight:700}
.tl{font-size:13px} .empty{color:#6a6a72;font-size:14px;padding:6px 2px}
${histCss}
</style></head><body>
<div class="logo">Roo<span>Titanium</span></div>
<h2>Preferiti</h2><div class="grid">${tiles}</div>
<h2>Cronologia</h2>${histSection}
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
        try { swapGet(Screen.prototype, 'width', 'height'); swapGet(Screen.prototype, 'availWidth', 'availHeight'); } catch(e){}
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

    function pushOrientation() {
        var land = orient !== 0
        for (var i = 0; i < tabsRepeater.count; i++) {
            var v = tabsRepeater.itemAt(i)
            if (v) v.runJavaScript("window.__rtSetLandscape && window.__rtSetLandscape(" + land + ")")
        }
    }
    onOrientChanged: pushOrientation()

    ListModel { id: tabsModel }
    Component.onCompleted: newTab(false)

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
                MouseArea { id: hma; anchors.fill: parent; onClicked: { urlbar.focus = false; if (win.currentView) win.currentView.url = "https://lite.duckduckgo.com/lite/" } }
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
                    profile: priv ? incognitoProfile : normalProfile
                    // zoom sul lato corto della FINESTRA (costante in landscape):
                    // viewport CSS ~412px in portrait, ~960px in landscape.
                    // NB: --force-device-scale-factor NON cambia il DSF della view
                    // (QtWebEngine usa il dpr della QQuickWindow = 1) ma corregge
                    // screen.* (in DIP) e le soglie gesture del display
                    zoomFactor: win.desktopMode ? 1.0 : Math.max(1.0, Math.min(win.width, win.height) / 412)
                    settings.fullScreenSupportEnabled: true
                    Component.onCompleted: {
                        userScripts.collection = [{
                            name: "rtScreenSpoof",
                            sourceCode: win.screenSpoofJs,
                            injectionPoint: WebEngineScript.DocumentCreation,
                            worldId: WebEngineScript.MainWorld,
                            runsOnSubFrames: true
                        }]
                        if (model.start === "incognito") loadHtml(win.incognitoHtml(), "about:blank")
                        else if (model.start === "home") loadHtml(win.homeHtml(), "about:blank")
                        else url = model.start
                        win.refreshCurrent()
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
                            loadHtml(win.historyHtml(), "https://history.local/")
                        }
                    }
                    onUrlChanged: tabsModel.setProperty(index, "murl", "" + url)
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
