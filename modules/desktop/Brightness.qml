// Bar item: sun icon and screen brightness, scrolling changes it. (The icons
// of the bar items are Nerd Font glyphs, the theme's default font.) Hidden on a machine
// without a backlight. Polled, as nothing tells us when it changed.
import QtQuick
import Quickshell
import Quickshell.Io

Text {
    id: root

    property string percent: ""

    function refresh() {
        read.running = true;
    }

    visible: percent !== ""
    text: " " + percent + "%"
    color: Theme.base0A
    font.family: Theme.fontMonospace
    font.pointSize: Theme.sizeDesktop

    Process {
        id: read

        // machine-readable: name,class,current,percent,max
        command: ["brightnessctl", "-m", "-c", "backlight", "info"]
        stdout: StdioCollector {
            id: out

            onStreamFinished: {
                const fields = out.text.trim().split(",");
                root.percent = fields.length > 3 ? fields[3].replace("%", "") : "";
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    MouseArea {
        anchors.fill: parent
        onWheel: w => {
            Quickshell.execDetached(["brightnessctl", "-c", "backlight", "set", w.angleDelta.y > 0 ? "5%+" : "5%-"]);
            root.refresh();
        }
    }
}
