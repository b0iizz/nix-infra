// Bar item registered by the niri wrapper: the workspaces niri has right now
// (they come and go), the focused one highlighted, click to switch. niri has
// no Quickshell module, so this follows `niri msg event-stream` and reads
// `niri msg workspaces` whenever a workspace event arrives. Only shown inside
// niri (NIRI_SOCKET is set by niri itself).
import QtQuick
import Quickshell
import Quickshell.Io

Row {
    id: root

    readonly property bool active: !!Quickshell.env("NIRI_SOCKET")
    property var workspaces: []

    visible: active
    spacing: 8

    Process {
        running: root.active
        command: ["niri", "msg", "--json", "event-stream"]
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith('{"Workspace'))
                    list.running = true;
            }
        }
    }

    Process {
        id: list

        command: ["niri", "msg", "--json", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: root.workspaces = JSON.parse(text).sort((a, b) => a.output === b.output ? a.idx - b.idx : a.output < b.output ? -1 : 1)
        }
    }

    // the stream may start with the state before anyone listens
    Component.onCompleted: if (active) list.running = true

    Repeater {
        model: root.workspaces

        Text {
            required property var modelData

            text: modelData.name ?? modelData.idx
            color: modelData.is_focused ? Theme.base0D : Theme.base04
            font.family: Theme.fontMonospace
            font.pointSize: Theme.sizeDesktop

            MouseArea {
                anchors.fill: parent
                onClicked: Quickshell.execDetached(["niri", "msg", "action", "focus-workspace", String(parent.modelData.idx)])
            }
        }
    }
}
