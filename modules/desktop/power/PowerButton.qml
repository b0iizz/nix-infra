// Bar item: opens the shutdown menu (PowerMenu, registered by the same module).
import QtQuick
import Quickshell

Text {
    text: "⏻"
    color: Theme.base08
    font.family: Theme.fontMonospace
    font.pointSize: Theme.sizeDesktop

    MouseArea {
        anchors.fill: parent
        onClicked: Quickshell.execDetached(["quickshell", "ipc", "call", "powermenu", "toggle"])
    }
}
