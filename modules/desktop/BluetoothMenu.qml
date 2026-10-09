// Bluetooth menu: click a device to connect to it or, when it is connected, to
// disconnect. A device not paired yet is paired through bluetoothctl, as
// Quickshell has no Bluetooth agent: the menu answers its questions (confirm
// a passkey, type a PIN) and shows the code a device wants typed on its side.
// A paired device is trusted and connected right away. The top line switches
// the adapter, which scans while the menu is open.
//
// bluetoothctl is talked to in plain text, so a BlueZ that words its prompts
// differently needs the patterns in `parse` adjusted.
import QtQuick
import Quickshell.Bluetooth
import Quickshell.Io

Menu {
    id: menu

    target: "bluetoothmenu"

    Column {
        id: column

        readonly property var adapter: Bluetooth.defaultAdapter
        // devices without a name of their own are listed by address, which is noise
        readonly property var devices: adapter ? [...adapter.devices.values].filter(d => d.paired || d.connected || d.name !== d.address.replace(/:/g, "-")).sort((a, b) => b.connected - a.connected || b.paired - a.paired || a.name.localeCompare(b.name)) : []
        // the device being paired, what the pairing says and what it waits for
        // ("confirm" a passkey, "input" a PIN, or "")
        property var pairing: null
        property string message: ""
        property string waitingFor: ""

        function label(d) {
            const state = d.connected ? "  connected" : d.paired ? "  paired" : "";
            return d.name + state + (d.batteryAvailable ? "  " + Math.round(d.battery * 100) + "%" : "");
        }

        function startPairing(d) {
            pairing = d;
            waitingFor = "";
            message = "Pairing with " + d.name + " ...";
            pair.log = "";
            pair.running = true;
        }

        function answer(text) {
            pair.write(text + "\n");
            waitingFor = "";
            message = "Pairing with " + pairing.name + " ...";
        }

        spacing: 4

        Component.onCompleted: if (adapter)
            adapter.discovering = true
        Component.onDestruction: if (adapter)
            adapter.discovering = false

        // an interactive bluetoothctl, kept open for the questions of the pairing
        Process {
            id: pair

            // what it said since the last question we took, without its colours
            property string log: ""

            function parse(chunk) {
                // it still talks while it connects and quits after a success
                if (!column.pairing)
                    return;
                log += chunk.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "").replace(/\r/g, "");
                const address = column.pairing.address;
                let m;
                if ((m = /Confirm passkey (\d+)/.exec(log))) {
                    column.message = "Does " + column.pairing.name + " show " + m[1] + "?";
                    column.waitingFor = "confirm";
                } else if (/Enter (PIN code|passkey)/.test(log)) {
                    column.message = "Enter the code of " + column.pairing.name + ":";
                    column.waitingFor = "input";
                } else if ((m = /\[agent\] (?:PIN code|Passkey): (\d+)/.exec(log))) {
                    column.message = "Type " + m[1] + " on " + column.pairing.name;
                } else if (/Pairing successful/.test(log)) {
                    write("trust " + address + "\nconnect " + address + "\nquit\n");
                    column.pairing = null;
                } else if (/Failed to pair|Authentication (Failed|Canceled|Rejected|Timeout)/.test(log)) {
                    write("quit\n");
                    column.message = "Pairing with " + column.pairing.name + " failed";
                    column.waitingFor = "";
                } else {
                    return;
                }
                log = "";
            }

            command: ["stdbuf", "-oL", "bluetoothctl"]
            stdinEnabled: true
            stdout: SplitParser {
                // the questions have no line break, so read whatever arrives
                splitMarker: ""
                onRead: chunk => pair.parse(chunk)
            }
            onStarted: write("agent KeyboardDisplay\ndefault-agent\npair " + column.pairing.address + "\n")
            onExited: if (column.pairing) {
                column.message = "bluetoothctl stopped";
                column.waitingFor = "";
            }
        }

        MenuRow {
            text: "Bluetooth: " + (column.adapter?.enabled ? "on" : "off") + " (click to switch)"
            active: column.adapter?.enabled ?? false
            onClicked: column.adapter.enabled = !column.adapter.enabled
        }

        Repeater {
            model: column.devices

            MenuRow {
                required property var modelData

                text: column.label(modelData)
                active: modelData.connected
                onClicked: {
                    if (modelData.connected)
                        modelData.disconnect();
                    else if (modelData.paired)
                        modelData.connect();
                    else
                        column.startPairing(modelData);
                }
            }
        }

        MenuRow {
            visible: column.pairing !== null
            text: column.message
            active: true
        }

        MenuRow {
            visible: column.waitingFor === "confirm"
            text: "Yes, it does"
            onClicked: column.answer("yes")
        }

        TextInput {
            width: parent.width
            visible: column.waitingFor === "input"
            color: Theme.base05
            font.family: Theme.fontMonospace
            font.pointSize: Theme.sizePopups
            onVisibleChanged: {
                text = "";
                if (visible)
                    forceActiveFocus();
            }
            Keys.onReturnPressed: column.answer(text)
        }

        MenuRow {
            visible: column.pairing !== null
            text: "Cancel"
            onClicked: {
                pair.running = false;
                column.pairing = null;
            }
        }
    }
}
