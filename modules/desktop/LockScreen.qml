// Lock screen: `quickshell ipc call lock lock` locks the session
// (ext-session-lock, so the compositor itself keeps everything hidden), the
// password is checked by PAM as the current user (service "quickshell-lock",
// see modules/desktop/lock.nix).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland

Scope {
    id: root

    property bool failed: false

    IpcHandler {
        target: "lock"

        function lock(): void {
            sessionLock.locked = true;
        }
    }

    PamContext {
        id: pam

        config: "quickshell-lock"
        onCompleted: result => {
            if (result === PamResult.Success) {
                sessionLock.locked = false;
            } else {
                root.failed = true;
                pam.start();
            }
        }
    }

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    WlSessionLock {
        id: sessionLock

        onLockedChanged: {
            if (locked) {
                root.failed = false;
                pam.start();
            }
        }

        WlSessionLockSurface {
            color: Theme.base00

            Column {
                anchors.centerIn: parent
                spacing: 16

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(clock.date, "HH:mm")
                    color: Theme.base05
                    font.family: Theme.fontMonospace
                    font.pointSize: Theme.sizeDesktop * 4
                }

                TextInput {
                    id: password

                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 280
                    horizontalAlignment: TextInput.AlignHCenter
                    echoMode: TextInput.Password
                    enabled: pam.responseRequired
                    focus: true
                    color: Theme.base05
                    font.family: Theme.fontMonospace
                    font.pointSize: Theme.sizeDesktop
                    onAccepted: {
                        pam.respond(text);
                        text = "";
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.failed ? "Wrong password" : pam.message
                    color: root.failed ? Theme.base08 : Theme.base04
                    font.family: Theme.fontMonospace
                    font.pointSize: Theme.sizePopups
                }
            }
        }
    }
}
