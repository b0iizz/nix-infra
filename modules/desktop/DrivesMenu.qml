// Drives menu: a click on a drive mounts it or, when it is mounted, unmounts
// it. "Eject" under a drive unmounts everything on its disk and powers it
// off, after which it can be pulled out. What udisks says when it fails is
// shown at the top.
import QtQuick

Menu {
    target: "drivesmenu"

    Column {
        id: column

        spacing: 4

        DriveList {
            id: list
        }

        MenuRow {
            visible: list.drives.length === 0
            text: "No external drives"
        }

        MenuRow {
            visible: list.error !== ""
            text: list.error
            color: Theme.base08
        }

        Repeater {
            model: list.drives

            Column {
                required property var modelData

                width: column.width
                spacing: 4

                MenuRow {
                    text: modelData.name + "  " + modelData.size + (modelData.mounted ? "  " + modelData.mountpoint : "  not mounted")
                    active: modelData.mounted
                    onClicked: list.toggle(modelData)
                }

                // once per disk, under its last filesystem
                MenuRow {
                    visible: list.drives.filter(d => d.disk === modelData.disk).pop() === modelData
                    text: "    Eject"
                    onClicked: list.eject(modelData)
                }
            }
        }
    }
}
