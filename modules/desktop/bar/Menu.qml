// Frame of the menus (network, wifi, bluetooth, drives, power, wallpaper): a
// box in the middle of the screen, opened with `quickshell ipc call <target>
// toggle` (the bar item's right click) and closed with Escape or a click next
// to it. The child is its content and exists only while the menu is open.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    required property string target
    default property Component body
    property bool shown: false
    property int menuWidth: 420

    IpcHandler {
        target: root.target

        function toggle(): void {
            root.shown = !root.shown;
        }
    }

    LazyLoader {
        active: root.shown

        // the whole screen, so that the click next to the menu reaches it
        PanelWindow {
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: root.shown = false
            }

            Rectangle {
                anchors.centerIn: parent
                width: root.menuWidth
                height: content.implicitHeight + 32
                color: Qt.alpha(Theme.base00, Theme.opacityPopups)

                // a click on the menu itself does not close it
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                FocusScope {
                    anchors.fill: parent
                    focus: true
                    Keys.onEscapePressed: root.shown = false

                    Loader {
                        id: content

                        anchors.fill: parent
                        anchors.margins: 16
                        sourceComponent: root.body
                    }
                }
            }
        }
    }
}
