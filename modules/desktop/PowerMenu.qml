// Shutdown menu: `quickshell ipc call powermenu toggle` opens it, click an
// action, or press Escape or click next to it. An action that needs `confirm`
// takes a second click.
import QtQuick
import Quickshell

Menu {
    id: root

    readonly property var actions: ShellData.powerActions

    target: "powermenu"
    menuWidth: 240

    Column {
        spacing: 4

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
                        Quickshell.execDetached(parent.modelData.exec);
                        root.shown = false;
                    }
                }
            }
        }
    }
}
