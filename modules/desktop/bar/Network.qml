// Bar item: whether any connection is up, and a lock while a VPN is; click
// opens NetworkMenu. NetworkManager's VPNs and WireGuard interfaces
// count; Quickshell.Networking doesn't know either, so they are polled.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

Text {
    id: root

    property bool vpn: false
    readonly property bool online: Networking.devices.values.some(d => d.connected)

    // a globe, green online and red offline, and a lock next to it with a VPN
    text: "" + (vpn ? " " : "")
    color: !online ? Theme.base08 : vpn ? Theme.base0C : Theme.base0B
    font.family: Theme.fontMonospace
    font.pointSize: Theme.sizeDesktop

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: Quickshell.execDetached(["quickshell", "ipc", "call", "networkmenu", "toggle"])
    }

    Process {
        id: probe

        command: ["sh", "-c", "ip -o link show type wireguard up; nmcli -t -f TYPE connection show --active | grep -E '^(vpn|wireguard)$'"]
        stdout: StdioCollector {
            id: out

            onStreamFinished: root.vpn = out.text.trim() !== ""
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: probe.running = true
    }
}
