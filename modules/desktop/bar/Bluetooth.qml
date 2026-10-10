// Bar item: bluetooth icon, colored by state; left click
// switches the adapter, right click opens BluetoothMenu. Only on hosts with a
// bluetooth controller (modules/desktop/widgets.nix).
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
