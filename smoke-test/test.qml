import QtQuick
import QtQuick.Window
import QtQuick.VirtualKeyboard
import QtWebEngine

Window {
    id: win
    visible: true
    visibility: Window.FullScreen
    color: "#101014"

    // scala UI in base alla larghezza reale (design a 540) → sizing "da telefono"
    readonly property real u: width / 540

    // --- user agent per toggle Versione desktop (backlog #2) ---
    property bool desktopMode: false
    readonly property string uaMobile: "Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
    readonly property string uaDesktop: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    function setDesktop(on) {
        desktopMode = on        // l'UA della profile è bindato a desktopMode
        view.reload()
    }

    function go(t) {
        t = t.trim()
        if (t.length === 0) return
        if (/^[a-z]+:\/\//i.test(t)) view.url = t
        else if (/^[^ ]+\.[^ ]+$/.test(t)) view.url = "https://" + t
        else view.url = "https://lite.duckduckgo.com/lite/?q=" + encodeURIComponent(t)
    }

    // URL colorato stile Chrome: schema verde, host chiaro, resto grigio
    function colorizeUrl(u) {
        u = "" + u
        var m = u.match(/^([a-z][a-z0-9+.-]*):\/\/([^\/]*)(.*)$/i)
        if (!m) return '<span style="color:#e8e8e8">' + u + '</span>'
        return '<span style="color:#4ea866">' + m[1] + '</span>'
             + '<span style="color:#6a6a72">://</span>'
             + '<span style="color:#f0f0f0">' + m[2] + '</span>'
             + '<span style="color:#8a8a92">' + m[3] + '</span>'
    }

    // voci del menu (stile Sailfish Browser)
    readonly property var menuModel: [
        { t: "item", ic: "newtab",   l: "Nuova scheda",          a: "newtab" },
        { t: "item", ic: "private",  l: "Scheda anonima",        a: "private" },
        { t: "sep" },
        { t: "item", ic: "search",   l: "Cerca nella pagina",    a: "find" },
        { t: "item", ic: "grid",     l: "Aggiungi alla griglia", a: "grid" },
        { t: "item", ic: "share",    l: "Condividi",             a: "share" },
        { t: "item", ic: "pdf",      l: "Salva pagina come PDF", a: "pdf" },
        { t: "sep" },
        { t: "item", ic: "desktop",  l: "Versione desktop",      a: "desktop", toggle: true },
        { t: "sep" },
        { t: "item", ic: "star",     l: "Segnalibri",            a: "bookmarks" },
        { t: "item", ic: "history",  l: "Cronologia",            a: "history" },
        { t: "item", ic: "download", l: "Download",              a: "downloads" },
        { t: "item", ic: "settings", l: "Impostazioni",          a: "settings" }
    ]

    function doAction(a) {
        menu.open = false
        if (a === "desktop") win.setDesktop(!win.desktopMode)
        else if (a === "pdf") view.printToPdf("/home/defaultuser/pagina.pdf")
        else console.log("menu action (placeholder): " + a)
    }

    Column {
        anchors.fill: parent

        // ===================== TOOLBAR stile Chrome mobile =====================
        Rectangle {
            id: toolbar
            width: parent.width
            height: 78 * win.u
            color: "#16161c"

            Item {
                id: homeBtn
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 6 * win.u
                width: 48 * win.u; height: parent.height
                Text { anchors.centerIn: parent; text: "⌂"; color: "#e6e6ea"; font.pixelSize: 30 * win.u }
                Rectangle { anchors.fill: parent; radius: width/2; color: "#ffffff"; opacity: hma.pressed ? 0.10 : 0 }
                MouseArea { id: hma; anchors.fill: parent; onClicked: { urlbar.focus = false; view.url = "https://lite.duckduckgo.com/lite/" } }
            }

            Item {
                id: menuBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: 6 * win.u
                width: 44 * win.u; height: parent.height
                Column {
                    anchors.centerIn: parent; spacing: 5 * win.u
                    Repeater { model: 3
                        Rectangle { width: 6*win.u; height: 6*win.u; radius: width/2; color: "#e6e6ea" } }
                }
                Rectangle { anchors.fill: parent; radius: width/2; color: "#ffffff"; opacity: mma.pressed ? 0.10 : 0 }
                MouseArea { id: mma; anchors.fill: parent; onClicked: menu.open = !menu.open }
            }

            Item {
                id: tabsBtn
                anchors.right: menuBtn.left
                anchors.verticalCenter: parent.verticalCenter
                width: 48 * win.u; height: parent.height
                Rectangle {
                    anchors.centerIn: parent
                    width: 30 * win.u; height: 30 * win.u; radius: 6 * win.u
                    color: "transparent"; border.color: "#c8c8d0"; border.width: 2 * win.u
                    Text { anchors.centerIn: parent; text: "1"; color: "#e6e6ea"; font.pixelSize: 18 * win.u; font.bold: true }
                }
                Rectangle { anchors.fill: parent; radius: width/2; color: "#ffffff"; opacity: tma.pressed ? 0.10 : 0 }
                MouseArea { id: tma; anchors.fill: parent; onClicked: {} }
            }

            Rectangle {
                id: pill
                anchors.left: homeBtn.right
                anchors.right: tabsBtn.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 4 * win.u
                anchors.rightMargin: 4 * win.u
                height: 54 * win.u
                radius: height / 2
                clip: true
                color: urlbar.activeFocus ? "#303039" : "#26262c"
                border.color: urlbar.activeFocus ? "#5a7fd0" : "#33333c"
                border.width: 1

                Item {
                    id: infoIcon
                    anchors.left: parent.left; anchors.leftMargin: 18 * win.u
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20 * win.u; height: 22 * win.u
                    Rectangle {
                        anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                        width: 20 * win.u; height: 13 * win.u; radius: 3 * win.u; color: "#9aa0a6"
                    }
                    Rectangle {
                        anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter
                        width: 12 * win.u; height: 14 * win.u; radius: 6 * win.u
                        color: "transparent"; border.color: "#9aa0a6"; border.width: 2.5 * win.u
                    }
                }

                Text {
                    anchors.left: infoIcon.right; anchors.right: parent.right
                    anchors.leftMargin: 12 * win.u; anchors.rightMargin: 20 * win.u
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !urlbar.activeFocus
                    text: win.colorizeUrl(view.url)
                    textFormat: Text.RichText
                    font.pixelSize: 22 * win.u
                }

                TextInput {
                    id: urlbar
                    anchors.left: infoIcon.right; anchors.right: parent.right
                    anchors.leftMargin: 12 * win.u; anchors.rightMargin: 20 * win.u
                    anchors.verticalCenter: parent.verticalCenter
                    visible: activeFocus
                    color: "white"; font.pixelSize: 22 * win.u; clip: true
                    inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                    text: view.url
                    selectByMouse: true
                    onActiveFocusChanged: if (activeFocus) { text = view.url; selectAll() }
                    onAccepted: { win.go(text); focus = false }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !urlbar.activeFocus
                    onClicked: { urlbar.forceActiveFocus() }
                }
            }
        }

        // ===================== PAGINA =====================
        WebEngineView {
            id: view
            width: parent.width
            height: win.height - toolbar.height - (inputPanel.active ? inputPanel.height : 0)
            // profile custom con UA bindato: Mobile di default, Desktop col toggle
            profile: WebEngineProfile {
                id: webProfile
                httpUserAgent: win.desktopMode ? win.uaDesktop : win.uaMobile
            }
            // in mobile riduce il viewport CSS a ~412px → media query mobile
            zoomFactor: win.desktopMode ? 1.0 : Math.max(1.0, width / 412)
            url: "https://lite.duckduckgo.com/lite/"
            onLoadingChanged: function(info) { console.log("LOAD status=" + info.status + " " + info.url) }
            Behavior on height { NumberAnimation { duration: 150 } }
        }
    }

    // ===================== MENU stile Sailfish Browser (⋮) =====================
    // overlay per chiudere toccando fuori
    MouseArea {
        anchors.fill: parent; z: 49
        enabled: menu.open
        onClicked: menu.open = false
    }

    Rectangle {
        id: menu
        property bool open: false
        anchors.right: parent.right; anchors.top: toolbar.bottom
        width: 340 * win.u
        height: menuCol.height + 16 * win.u
        color: "#2c2c31"
        border.color: "#3a3a42"; border.width: 1
        visible: open
        z: 50

        Column {
            id: menuCol
            width: parent.width; y: 8 * win.u
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

    // separatore
    Component {
        id: sepComp
        Item {
            height: 13 * win.u
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: 18 * win.u; anchors.rightMargin: 18 * win.u
                height: 1; color: "#43434c"
            }
        }
    }

    // riga voce (icona Canvas + etichetta)
    Component {
        id: rowComp
        Rectangle {
            property var entry
            height: 62 * win.u
            color: rma.pressed ? "#3a3a44" : "transparent"

            Canvas {
                id: ic
                anchors.left: parent.left; anchors.leftMargin: 22 * win.u
                anchors.verticalCenter: parent.verticalCenter
                width: 32 * win.u; height: 32 * win.u
                property string kind: entry ? entry.ic : ""
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

            Text {
                anchors.left: parent.left; anchors.leftMargin: 74 * win.u
                anchors.right: toggleDot.left; anchors.rightMargin: 8 * win.u
                anchors.verticalCenter: parent.verticalCenter
                text: entry ? entry.l : ""
                color: "#eaeaf0"; font.pixelSize: 21 * win.u
                elide: Text.ElideRight
            }

            // indicatore stato per "Versione desktop"
            Rectangle {
                id: toggleDot
                anchors.right: parent.right; anchors.rightMargin: 22 * win.u
                anchors.verticalCenter: parent.verticalCenter
                width: 16 * win.u; height: 16 * win.u; radius: width/2
                visible: entry && entry.toggle === true
                color: win.desktopMode ? "#4ea866" : "transparent"
                border.color: "#7a7a82"; border.width: 2 * win.u
            }

            MouseArea { id: rma; anchors.fill: parent; onClicked: win.doAction(entry.a) }
        }
    }

    // tastiera QtVirtualKeyboard in-app
    InputPanel {
        id: inputPanel
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: active
        z: 99
    }
}
