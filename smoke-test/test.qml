import QtQuick
import QtQuick.Window
import QtWebEngine

Window {
    visible: true
    width: 540
    height: 960
    title: "RooTitanium browser"
    color: "#202030"

    Column {
        anchors.fill: parent

        // barra di pulsanti tappabili (niente tastiera necessaria)
        Row {
            width: parent.width
            height: 72
            spacing: 6
            padding: 6
            Repeater {
                model: [
                    { l: "chrome://gpu", u: "chrome://gpu" },
                    { l: "example", u: "http://example.com" },
                    { l: "wikipedia", u: "https://en.m.wikipedia.org/wiki/Sailfish_OS" }
                ]
                Rectangle {
                    width: 168
                    height: 60
                    radius: 8
                    color: ma.pressed ? "#5070c0" : "#3050a0"
                    Text { anchors.centerIn: parent; text: modelData.l; color: "white"; font.pixelSize: 20 }
                    MouseArea { id: ma; anchors.fill: parent; onClicked: view.url = modelData.u }
                }
            }
        }

        Text {
            width: parent.width
            height: 26
            leftPadding: 8
            color: "#8fef8f"
            font.pixelSize: 14
            elide: Text.ElideRight
            text: (view.loading ? "… " : "") + view.url
        }

        WebEngineView {
            id: view
            width: parent.width
            height: parent.height - 98
            url: "chrome://gpu"
            onLoadingChanged: function(info) {
                console.log("LOAD status=" + info.status + " url=" + info.url)
            }
        }
    }
}
