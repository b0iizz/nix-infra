// Network menu: what every connection that is up looks like, nothing to click.
// NetworkManager's connections give the names, `ip` the addresses, so
// WireGuard interfaces NetworkManager doesn't know show up too.
import QtQuick
import Quickshell.Io

Menu {
    id: menu

    target: "networkmenu"
    menuWidth: 520

    Column {
        id: column

        property var connections: []

        spacing: 4

        Process {
            id: probe

            // NetworkManager's lines, a separator, then the interfaces that are up
            command: ["sh", "-c", "nmcli -t -f DEVICE,NAME,TYPE connection show --active; echo ---; ip -br addr show up"]
            stdout: StdioCollector {
                id: out

                onStreamFinished: {
                    const [named, up] = out.text.split("\n---\n");
                    const names = {};
                    for (const line of named.split("\n")) {
                        const [device, name, type] = line.split(":");
                        if (device)
                            names[device] = name + " (" + type + ")";
                    }
                    column.connections = (up ?? "").split("\n").map(l => l.trim().split(/\s+/)).filter(f => f[0] && f[0] !== "lo").map(f => ({
                                title: f[0] + "  " + (names[f[0]] ?? ""),
                                addresses: f.slice(2).join("  ")
                            }));
                }
            }
        }

        Timer {
            interval: 3000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: probe.running = true
        }

        MenuRow {
            text: column.connections.length === 0 ? "No connection is up" : "Connections that are up"
            active: true
        }

        Repeater {
            model: column.connections

            MenuRow {
                required property var modelData

                text: modelData.title + "\n    " + modelData.addresses
            }
        }
    }
}
