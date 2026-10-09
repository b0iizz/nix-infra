// Wallpaper widget: `quickshell ipc call wallpaper toggle` opens a grid of the
// images in the wallpaper directory, a click hands one to `wallpaper-set` (awww
// with the transition of `desktop.wallpaper.transition`, or swaybg), Escape
// closes it.
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    readonly property string directory: ShellData.wallpaper.directory
    readonly property string setCommand: ShellData.wallpaper.set
    property bool shown: false

    function expand(path) {
        return path.startsWith("~") ? Quickshell.env("HOME") + path.slice(1) : path;
    }

    // a path with # or ? or % in it is not a URL as it stands
    function fileUrl(path) {
        return "file://" + encodeURI(path).replace(/#/g, "%23").replace(/\?/g, "%3F");
    }

    function set(file) {
        Quickshell.execDetached([setCommand, file]);
        shown = false;
    }

    IpcHandler {
        target: "wallpaper"

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
            implicitWidth: 920
            implicitHeight: 580
            color: Qt.alpha(Theme.base00, Theme.opacityPopups)

            GridView {
                id: grid

                anchors.fill: parent
                anchors.margins: 12
                cellWidth: 220
                cellHeight: 140
                focus: true
                clip: true
                Keys.onEscapePressed: root.shown = false

                model: FolderListModel {
                    folder: root.fileUrl(root.expand(root.directory))
                    nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.gif", "*.bmp"]
                    showDirs: false
                }

                delegate: Item {
                    required property string filePath
                    required property url fileUrl

                    width: grid.cellWidth
                    height: grid.cellHeight

                    Image {
                        anchors.fill: parent
                        anchors.margins: 4
                        source: parent.fileUrl
                        sourceSize.width: 440
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.set(parent.filePath)
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: grid.count === 0
                text: "No images in " + root.expand(root.directory)
                color: Theme.base04
                font.family: Theme.fontMonospace
                font.pointSize: Theme.sizePopups
            }
        }
    }
}
