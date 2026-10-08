// Bar item registered by the hyprland wrapper: one label per workspace of
// `desktop.workspaces`, the focused one highlighted, click to switch.
//
// Hyprland answers `dispatch` in Lua now, so the switch is a Lua expression.
// Named (non-numeric) workspaces would need a "name:" prefix.
import QtQuick
import Quickshell
import Quickshell.Hyprland

Row {
    spacing: 8

    Repeater {
        model: ShellData.workspaces

        Text {
            required property var modelData
            readonly property bool focused: Hyprland.focusedWorkspace?.name === modelData.name

            text: modelData.name
            color: focused ? Theme.base0D : Theme.base04
            font.family: Theme.fontMonospace
            font.pointSize: Theme.sizeDesktop

            MouseArea {
                anchors.fill: parent
                onClicked: Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.focus({ workspace = ${modelData.name} })`])
            }
        }
    }
}
