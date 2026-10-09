// Bar item registered by the sway wrapper: the workspaces sway has right now,
// the focused one highlighted, click to switch. Only shown inside sway
// (SWAYSOCK is set by sway itself), so it can sit in the bar next to the
// widgets of the other compositors.
import QtQuick
import Quickshell
import Quickshell.I3

Row {
    readonly property bool active: !!Quickshell.env("SWAYSOCK")

    visible: active
    spacing: 8

    Repeater {
        model: parent.active ? I3.workspaces : null

        Text {
            required property var modelData

            text: modelData.name
            color: modelData.focused ? Theme.base0D : Theme.base04
            font.family: Theme.fontMonospace
            font.pointSize: Theme.sizeDesktop

            MouseArea {
                anchors.fill: parent
                onClicked: parent.modelData.activate()
            }
        }
    }
}
