// Notification daemon: popups top right, newest on top. A click closes one;
// without a timeout from the sender they go after `defaultTimeout`, and
// critical ones stay until clicked. No history and no do-not-disturb.
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland

Scope {
    id: root

    readonly property int defaultTimeout: 5000

    NotificationServer {
        id: server

        bodySupported: true
        // tracked ones are kept until dismissed, which is what the popups show
        onNotification: n => n.tracked = true
    }

    LazyLoader {
        active: server.trackedNotifications.values.length > 0

        PanelWindow {
            anchors {
                top: true
                right: true
            }
            margins {
                top: 40
                right: 8
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            implicitWidth: 360
            implicitHeight: column.implicitHeight
            color: "transparent"

            Column {
                id: column

                width: parent.width
                spacing: 8

                Repeater {
                    model: ScriptModel {
                        values: [...server.trackedNotifications.values].reverse()
                    }

                    Rectangle {
                        id: popup

                        required property var modelData
                        readonly property bool critical: modelData.urgency === NotificationUrgency.Critical

                        width: column.width
                        height: content.implicitHeight + 16
                        color: Qt.alpha(Theme.base00, Theme.opacityPopups)
                        border.color: critical ? Theme.base08 : Theme.base03
                        border.width: 1

                        // expireTimeout is the sender's milliseconds (Quickshell 0.3.1
                        // documents seconds but passes D-Bus through), 0 means never,
                        // -1 the daemon's choice
                        Timer {
                            running: !popup.critical && popup.modelData.expireTimeout !== 0
                            interval: popup.modelData.expireTimeout > 0 ? popup.modelData.expireTimeout : root.defaultTimeout
                            onTriggered: popup.modelData.expire()
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: popup.modelData.dismiss()
                        }

                        Column {
                            id: content

                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                margins: 8
                            }
                            spacing: 2

                            Text {
                                width: parent.width
                                text: popup.modelData.appName ? popup.modelData.appName + ": " + popup.modelData.summary : popup.modelData.summary
                                elide: Text.ElideRight
                                color: Theme.base0D
                                font.family: Theme.fontMonospace
                                font.pointSize: Theme.sizePopups
                            }

                            Text {
                                width: parent.width
                                visible: popup.modelData.body !== ""
                                text: popup.modelData.body
                                wrapMode: Text.Wrap
                                maximumLineCount: 4
                                elide: Text.ElideRight
                                color: Theme.base05
                                font.family: Theme.fontMonospace
                                font.pointSize: Theme.sizePopups
                            }
                        }
                    }
                }
            }
        }
    }
}
