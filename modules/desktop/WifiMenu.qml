// Wifi menu: the networks in range, a click connects to one or, on the
// connected one, disconnects. Connecting opens a view of its own with only
// what concerns that network: the password question (for a new secured
// network), the progress and, if it fails, why. Back returns to the list. The
// top line of the list switches wifi off and on.
//
// Only passwords: a new network that wants a login (WPA-Enterprise) has to be
// set up with nmcli once.
import QtQuick
import Quickshell.Networking

Menu {
    target: "wifimenu"

    Column {
        id: column

        readonly property var device: Networking.devices.values.find(d => d.type === DeviceType.Wifi)
        readonly property var networks: device ? [...device.networks.values].sort((a, b) => b.connected - a.connected || b.signalStrength - a.signalStrength) : []
        // the network of the connecting view, if it is open
        property var attempt: null
        // the password is still to be asked
        property bool needsPassword: false
        property string failure: ""
        readonly property bool listing: attempt === null

        function open(n) {
            return n.security === WifiSecurityType.Open || n.security === WifiSecurityType.Owe;
        }

        function label(n) {
            const state = n.state === ConnectionState.Connecting ? "  connecting" : n.connected ? "  connected" : n.known ? "  known" : "";
            return n.name + "  " + Math.round(n.signalStrength * 100) + "%" + (open(n) ? "" : "  secured") + state;
        }

        function why(reason) {
            switch (reason) {
            case ConnectionFailReason.NoSecrets:
                return "No password was given";
            case ConnectionFailReason.WifiAuthTimeout:
            case ConnectionFailReason.WifiClientFailed:
                return "Wrong password, or the network did not answer";
            case ConnectionFailReason.WifiNetworkLost:
                return "The network is out of range";
            default:
                return "Could not connect";
            }
        }

        function choose(n) {
            if (n.connected) {
                n.disconnect();
                return;
            }
            attempt = n;
            failure = "";
            needsPassword = !(n.known || open(n));
            if (!needsPassword)
                n.connect();
        }

        function retry() {
            failure = "";
            needsPassword = !(attempt.known || open(attempt));
            if (!needsPassword)
                attempt.connect();
        }

        function back() {
            if (attempt.state === ConnectionState.Connecting)
                attempt.disconnect();
            attempt = null;
        }

        spacing: 4

        // scan while the menu is open
        Component.onCompleted: if (device)
            device.scannerEnabled = true
        Component.onDestruction: if (device)
            device.scannerEnabled = false

        // the list closes again once the network is up or fails
        Connections {
            target: column.attempt

            function onConnectedChanged() {
                if (column.attempt.connected)
                    column.attempt = null;
            }

            function onConnectionFailed(reason) {
                column.failure = column.why(reason);
            }
        }

        MenuRow {
            visible: column.listing
            text: "Wifi: " + (Networking.wifiEnabled ? "on" : "off") + " (click to switch)"
            active: Networking.wifiEnabled
            onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
        }

        Repeater {
            model: column.networks

            MenuRow {
                required property var modelData

                visible: column.listing
                text: column.label(modelData)
                active: modelData.connected
                onClicked: column.choose(modelData)
            }
        }

        // the connecting view
        MenuRow {
            visible: !column.listing
            text: column.needsPassword ? "Password for " + (column.attempt?.name ?? "") + ":" : column.failure !== "" ? column.failure : "Connecting to " + (column.attempt?.name ?? "") + " ..."
            active: column.failure === ""
            color: column.failure !== "" ? Theme.base08 : Theme.base0D
        }

        TextInput {
            width: parent.width
            visible: column.needsPassword
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
                column.needsPassword = false;
                column.attempt.connectWithPsk(text);
            }
            // Escape goes back to the list first and closes the menu the second time
            Keys.onEscapePressed: event => {
                if (column.attempt)
                    column.back();
                else
                    event.accepted = false;
            }
        }

        MenuRow {
            visible: column.failure !== ""
            text: "Try again"
            onClicked: column.retry()
        }

        MenuRow {
            visible: !column.listing
            text: "Back"
            onClicked: column.back()
        }
    }
}
