// Shutdown menu: `quickshell ipc call powermenu toggle` opens it, click an
// action or press Escape. An action that needs `confirm` takes a second click.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    readonly property var actions: ShellData.powerActions
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

                        property bool armed: false

                        width: parent.width
                        height: 32
                        text: armed ? modelData.name + ": click again" : modelData.name
                        verticalAlignment: Text.AlignVCenter
                        color: armed ? Theme.base08 : Theme.base05
                        font.family: Theme.fontMonospace
                        font.pointSize: Theme.sizePopups

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onExited: parent.armed = false
                            onClicked: {
                                if (parent.modelData.confirm && !parent.armed) {
                                    parent.armed = true;
                                    return;
                                }
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
