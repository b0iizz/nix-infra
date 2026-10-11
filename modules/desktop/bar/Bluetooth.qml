// Bar item: bluetooth icon, colored by state; click opens BluetoothMenu, double
// click switches the adapter. Only on hosts with a bluetooth controller (modules/desktop/widgets.nix).
import QtQuick
import Quickshell
import Quickshell.Bluetooth

Text {
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property int connected: adapter ? adapter.devices.values.filter(d => d.connected).length : 0

    visible: adapter !== null
    // dim when off, white when on, blue while a device is connected
    text: ""
    color: !adapter?.enabled ? Theme.base03 : connected > 0 ? Theme.base0D : Theme.base05
    font.family: Theme.fontMonospace
    font.pointSize: Theme.sizeDesktop

    // A click opens a full screen menu that closes on the next click, so the
    // left one waits to see whether it is the first of a double click.
    Timer {
        id: openMenu

        interval: Qt.styleHints.mouseDoubleClickInterval
        onTriggered: Quickshell.execDetached(["quickshell", "ipc", "call", "bluetoothmenu", "toggle"])
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: e => e.button === Qt.RightButton ? openMenu.triggered() : openMenu.restart()
        onDoubleClicked: e => {
            openMenu.stop();
            if (e.button === Qt.LeftButton)
                adapter.enabled = !adapter.enabled;
        }
    }
}
