// Shutdown menu: `quickshell ipc call powermenu toggle` opens it, click an
// action or press Escape. ACTIONS_JSON is replaced by modules/desktop/power.nix.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    readonly property var actions: ACTIONS_JSON
    property bool shown: false

    IpcHandler {
        target: "powermenu"

        function toggle(): void {
            root.shown = !root.shown;
        }
    }

    LazyLoader {
        active: root.shown

        PanelWindow {
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            implicitWidth: 240
            implicitHeight: 16 + 36 * root.actions.length
            color: Qt.alpha(Theme.base00, Theme.opacityPopups)

            Column {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4
                focus: true
                Keys.onEscapePressed: root.shown = false

                Repeater {
                    model: root.actions

                    Text {
                        required property var modelData

                        width: parent.width
                        height: 32
                        text: modelData.name
                        verticalAlignment: Text.AlignVCenter
                        color: Theme.base05
                        font.family: Theme.fontMonospace
                        font.pointSize: Theme.sizePopups

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                Quickshell.execDetached(modelData.exec);
                                root.shown = false;
                            }
                        }
                    }
                }
            }
        }
    }
}
