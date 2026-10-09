// Bar item: the wifi network and its signal; right click opens WifiMenu. Only
// on hosts with a wifi interface (modules/desktop/widgets.nix).
import QtQuick
import Quickshell
import Quickshell.Networking

Text {
    readonly property var device: Networking.devices.values.find(d => d.type === DeviceType.Wifi)
    readonly property var network: device?.networks.values.find(n => n.connected)

    text: !Networking.wifiEnabled ? "wifi off" : network ? "wifi " + network.name + " " + Math.round(network.signalStrength * 100) + "%" : "wifi -"
    color: network ? Theme.base05 : Theme.base03
    font.family: Theme.fontMonospace
    font.pointSize: Theme.sizeDesktop

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: Quickshell.execDetached(["quickshell", "ipc", "call", "wifimenu", "toggle"])
    }
}
