// Launcher: `quickshell ipc call launcher toggle` opens it, typing filters
// `desktop.launcher.entries`, Enter runs the first match, Escape closes.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    property bool shown: false

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            root.shown = !root.shown;
        }
    }

    LazyLoader {
        active: root.shown

        PanelWindow {
            id: window

            function matches() {
                const q = input.text.toLowerCase();
                return ShellData.launcherEntries.filter(e => e.name.toLowerCase().includes(q));
            }

            function run(entry) {
                Quickshell.execDetached(entry.exec);
                root.shown = false;
            }

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            implicitWidth: 400
            implicitHeight: 40 + 28 * matches().length
            color: Qt.alpha(Theme.base00, Theme.opacityPopups)

            Column {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                TextInput {
                    id: input

                    width: parent.width
                    focus: true
                    color: Theme.base05
                    font.family: Theme.fontMonospace
                    font.pointSize: Theme.sizePopups
                    Keys.onEscapePressed: root.shown = false
                    Keys.onReturnPressed: {
                        const m = window.matches();
                        if (m.length > 0)
                            window.run(m[0]);
                    }
                }

                Repeater {
                    model: window.matches()

                    Text {
                        required property var modelData

                        text: modelData.name
                        color: Theme.base04
                        font.family: Theme.fontMonospace
                        font.pointSize: Theme.sizePopups
                    }
                }
            }
        }
    }
}
