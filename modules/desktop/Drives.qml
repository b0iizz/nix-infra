// Bar item: a drive icon while an external drive is connected, blue while one
// is mounted; a click opens DrivesMenu (modules/roles/removable-media.nix).
import QtQuick
import Quickshell

Text {
    DriveList {
        id: list
    }

    visible: list.drives.length > 0
    text: "" + (list.drives.length > 1 ? " " + list.mountedCount + "/" + list.drives.length : "")
    color: list.mountedCount > 0 ? Theme.base0D : Theme.base05
    font.family: Theme.fontMonospace
    font.pointSize: Theme.sizeDesktop

    MouseArea {
        anchors.fill: parent
        onClicked: Quickshell.execDetached(["quickshell", "ipc", "call", "drivesmenu", "toggle"])
    }
}
