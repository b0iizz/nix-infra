// Lock screen: `quickshell ipc call lock lock` locks the session
// (ext-session-lock, so the compositor itself keeps everything hidden). It is
// the same AuthView as the login screen.
//
// The password and the fingerprint are checked by two PAM conversations at the
// same time, as the user running the shell: the password one answers to what
// is typed, the fingerprint one to the reader. Whichever succeeds unlocks.
// The PAM services are in modules/desktop/lock.nix, FINGERPRINT is replaced
// there as well.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland

Scope {
    id: root

    readonly property bool fingerprint: FINGERPRINT
    readonly property int maxFingerprintRetries: 5
    property bool failed: false
    property int fingerprintRetries: 0

    function unlockOn(result) {
        if (result === PamResult.Success)
            sessionLock.locked = false;
        return result === PamResult.Success;
    }

    IpcHandler {
        target: "lock"

        function lock(): void {
            sessionLock.locked = true;
        }
    }

    PamContext {
        id: password

        config: "quickshell-lock"
        onCompleted: result => {
            if (!root.unlockOn(result)) {
                root.failed = true;
                password.start();
            }
        }
    }

    PamContext {
        id: finger

        config: "quickshell-lock-fingerprint"
        onCompleted: result => {
            // a reader that is missing or has no prints ends at once, so the
            // retries are limited
            if (!root.unlockOn(result) && root.fingerprintRetries++ < root.maxFingerprintRetries)
                retry.start();
        }
    }

    Timer {
        id: retry

        interval: 1500
        onTriggered: if (sessionLock.locked)
            finger.start()
    }

    WlSessionLock {
        id: sessionLock

        onLockedChanged: {
            if (locked) {
                root.failed = false;
                root.fingerprintRetries = 0;
                password.start();
                if (root.fingerprint)
                    finger.start();
            } else {
                retry.stop();
                password.abort();
                finger.abort();
            }
        }

        WlSessionLockSurface {
            AuthView {
                anchors.fill: parent
                users: [Quickshell.env("USER") ?? ""]
                user: Quickshell.env("USER") ?? ""
                inputEnabled: password.responseRequired
                message: root.failed ? "Wrong password" : (finger.active ? finger.message : "")
                isError: root.failed || (finger.active && finger.messageIsError)
                hint: root.fingerprint ? "Password, or touch the fingerprint reader" : ""
                onSubmitted: text => {
                    root.failed = false;
                    password.respond(text);
                }
            }
        }
    }
}
