// Wifi menu: click a network to connect to it or, when it is the connected
// one, to disconnect. A network that is neither known nor open asks for its
// password first. The top line switches wifi off and on.
//
// Only passwords: a new network that wants a login (WPA-Enterprise) has to be
// set up with nmcli once. A wrong password shows as the network not
// connecting.
import QtQuick
import Quickshell.Networking

Menu {
    id: menu

    target: "wifimenu"

    Column {
        id: column

        readonly property var device: Networking.devices.values.find(d => d.type === DeviceType.Wifi)
        readonly property var networks: device ? [...device.networks.values].sort((a, b) => b.connected - a.connected || b.signalStrength - a.signalStrength) : []
        // the network a password is being asked for
        property var asking: null

        function open(n) {
            return n.security === WifiSecurityType.Open || n.security === WifiSecurityType.Owe;
        }

        function label(n) {
            const state = n.state === ConnectionState.Connecting ? "  connecting" : n.connected ? "  connected" : n.known ? "  known" : "";
            return n.name + "  " + Math.round(n.signalStrength * 100) + "%" + (open(n) ? "" : "  secured") + state;
        }

        spacing: 4

        // scan while the menu is open
        Component.onCompleted: if (device)
            device.scannerEnabled = true
        Component.onDestruction: if (device)
            device.scannerEnabled = false

        MenuRow {
            text: "Wifi: " + (Networking.wifiEnabled ? "on" : "off") + " (click to switch)"
            active: Networking.wifiEnabled
            onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
        }

        Repeater {
            model: column.networks

            MenuRow {
                required property var modelData

                text: column.label(modelData)
                active: modelData.connected
                onClicked: {
                    column.asking = null;
                    if (modelData.connected)
                        modelData.disconnect();
                    else if (modelData.known || column.open(modelData))
                        modelData.connect();
                    else
                        column.asking = modelData;
                }
            }
        }

        MenuRow {
            visible: column.asking !== null
            text: "Password for " + (column.asking?.name ?? "") + ":"
        }

        TextInput {
            id: password

            width: parent.width
            visible: column.asking !== null
            echoMode: TextInput.Password
            color: Theme.base05
            font.family: Theme.fontMonospace
            font.pointSize: Theme.sizePopups
            onVisibleChanged: {
                text = "";
                if (visible)
                    forceActiveFocus();
            }
            Keys.onReturnPressed: {
                column.asking.connectWithPsk(text);
                column.asking = null;
            }
            // Escape cancels the question first and closes the menu the second time
            Keys.onEscapePressed: event => {
                if (column.asking)
                    column.asking = null;
                else
                    event.accepted = false;
            }
        }
    }
}
