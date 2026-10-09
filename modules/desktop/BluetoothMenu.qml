// Bluetooth menu: click a device to connect to it or, when it is connected, to
// disconnect. A device not paired yet is paired. The top line switches the
// adapter, which scans while the menu is open.
//
// Pairing that asks for a PIN or a confirmation can't be answered here:
// Quickshell has no Bluetooth agent. Pair those once with bluetoothctl.
import QtQuick
import Quickshell.Bluetooth

Menu {
    id: menu

    target: "bluetoothmenu"

    Column {
        id: column

        readonly property var adapter: Bluetooth.defaultAdapter
        // devices without a name of their own are listed by address, which is noise
        readonly property var devices: adapter ? [...adapter.devices.values].filter(d => d.paired || d.connected || d.name !== d.address.replace(/:/g, "-")).sort((a, b) => b.connected - a.connected || b.paired - a.paired || a.name.localeCompare(b.name)) : []

        function label(d) {
            const state = d.connected ? "  connected" : d.paired ? "  paired" : "";
            return d.name + state + (d.batteryAvailable ? "  " + Math.round(d.battery * 100) + "%" : "");
        }

        spacing: 4

        Component.onCompleted: if (adapter)
            adapter.discovering = true
        Component.onDestruction: if (adapter)
            adapter.discovering = false

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
                        modelData.pair();
                }
            }
        }
    }
}
