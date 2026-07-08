import QtQuick
import QtQuick.Window
import QtQuick.VirtualKeyboard
import QtWebEngine

Window {
    id: win
    visible: true
    visibility: Window.FullScreen
    color: "#202030"

    // scala UI custom in base alla larghezza reale (design a 540) → sizing "da telefono"
    readonly property real u: width / 540

    function go(t) {
        t = t.trim()
        if (t.length === 0) return
        if (/^[a-z]+:\/\//i.test(t)) view.url = t
        else if (/^[^ ]+\.[^ ]+$/.test(t)) view.url = "https://" + t
        else view.url = "https://lite.duckduckgo.com/lite/?q=" + encodeURIComponent(t)
    }

    Column {
        anchors.fill: parent

        // --- barra indirizzi ---
        Rectangle {
            width: parent.width; height: 64 * win.u; color: "#151525"
            Rectangle {
                anchors.fill: parent; anchors.margins: 8 * win.u; radius: 8 * win.u
                color: urlbar.activeFocus ? "#2a2a45" : "#22223a"
                border.color: urlbar.activeFocus ? "#5070c0" : "#333"
                TextInput {
                    id: urlbar
                    anchors.fill: parent; anchors.leftMargin: 14 * win.u; anchors.rightMargin: 14 * win.u
                    verticalAlignment: TextInput.AlignVCenter
                    color: "white"; font.pixelSize: 22 * win.u; clip: true
                    inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                    text: view.url
                    onAccepted: { win.go(text); focus = false }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "tocca per scrivere un URL o una ricerca…"
                        color: "#888"; font.pixelSize: 18 * win.u
                        visible: urlbar.text.length === 0 && !urlbar.activeFocus
                    }
                }
            }
        }

        // --- pulsanti rapidi ---
        Row {
            width: parent.width; height: 54 * win.u; spacing: 6 * win.u; leftPadding: 6 * win.u
            Repeater {
                model: [
                    { l: "◄" }, { l: "►" }, { l: "⟳" },
                    { l: "gpu", u: "chrome://gpu" }, { l: "wiki", u: "https://en.m.wikipedia.org" }
                ]
                Rectangle {
                    width: 100 * win.u; height: 46 * win.u; radius: 6 * win.u
                    color: bma.pressed ? "#5070c0" : "#3050a0"
                    Text { anchors.centerIn: parent; text: modelData.l; color: "white"; font.pixelSize: 20 * win.u }
                    MouseArea { id: bma; anchors.fill: parent; onClicked: {
                        if (modelData.l === "◄") view.goBack()
                        else if (modelData.l === "►") view.goForward()
                        else if (modelData.l === "⟳") view.reload()
                        else view.url = modelData.u
                    } }
                }
            }
        }

        // --- pagina ---
        WebEngineView {
            id: view
            width: parent.width
            height: win.height - 64 * win.u - 54 * win.u - (inputPanel.active ? inputPanel.height : 0)
            url: "https://lite.duckduckgo.com/lite/"
            onLoadingChanged: function(info) { console.log("LOAD status=" + info.status + " " + info.url) }
            Behavior on height { NumberAnimation { duration: 150 } }
        }
    }

    // tastiera QtVirtualKeyboard in-app (funzionante). [Alternativa in studio:
    // Maliit nativo via wayland text-input v2 — vedi memoria.]
    InputPanel {
        id: inputPanel
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: active
        z: 99
    }
}
