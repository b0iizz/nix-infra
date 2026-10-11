// Bar item: wifi icon and signal strength; click opens WifiMenu. Only
// on hosts with a wifi interface (modules/desktop/widgets.nix).
import QtQuick
import Quickshell
import Quickshell.Networking

Text {
    readonly property var device: Networking.devices.values.find(d => d.type === DeviceType.Wifi)
    readonly property var network: device?.networks.values.find(n => n.connected)

    readonly property real strength: network?.signalStrength ?? 0

    // the icon is dim without a connection, else green, yellow or red by signal
    text: network ? " " + Math.round(strength * 100) + "%" : ""
    color: !network ? Theme.base03 : strength >= 0.6 ? Theme.base0B : strength >= 0.3 ? Theme.base0A : Theme.base08
    font.family: Theme.fontMonospace
    font.pointSize: Theme.sizeDesktop

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: Quickshell.execDetached(["quickshell", "ipc", "call", "wifimenu", "toggle"])
    }
}
