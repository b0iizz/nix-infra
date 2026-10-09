// Frame of the status menus (network, wifi, bluetooth): a window in the middle
// of the screen, opened with `quickshell ipc call <target> toggle` (the bar
// item's right click) and closed with Escape. The child is its content and
// exists only while the menu is open.
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

        PanelWindow {
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            implicitWidth: root.menuWidth
            implicitHeight: content.implicitHeight + 32
            color: Qt.alpha(Theme.base00, Theme.opacityPopups)

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
