// Bar item: bluetooth state and the number of connected devices; click
// switches the adapter. Only on hosts with a bluetooth controller
// (modules/desktop/widgets.nix).
import QtQuick
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
        onClicked: adapter.enabled = !adapter.enabled
    }
}
