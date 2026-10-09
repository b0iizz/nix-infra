// Bar item: bluetooth state and the number of connected devices; left click
// switches the adapter, right click opens BluetoothMenu. Only on hosts with a
// bluetooth controller (modules/desktop/widgets.nix).
import QtQuick
import Quickshell
import Quickshell.Bluetooth

Text {
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property int connected: adapter ? adapter.devices.values.filter(d => d.connected).length : 0

    visible: adapter !== null
    text: !adapter?.enabled ? "bt off" : connected > 0 ? "bt " + connected : "bt"
    color: adapter?.enabled ? Theme.base05 : Theme.base03
    font.family: Theme.fontMonospace
    font.pointSize: Theme.sizeDesktop

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: e => {
            if (e.button === Qt.RightButton)
                Quickshell.execDetached(["quickshell", "ipc", "call", "bluetoothmenu", "toggle"]);
            else
                adapter.enabled = !adapter.enabled;
        }
    }
}
