// Lock screen: `quickshell ipc call lock lock` locks the session
// (ext-session-lock, so the compositor itself keeps everything hidden). It is
// the same AuthView as the login screen.
//
// The password and the fingerprint are checked by two PAM conversations at the
// same time, as the user running the shell: the password one answers to what
// is typed, the fingerprint one to the reader. Whichever succeeds unlocks.
// The PAM services are in modules/desktop/lock.nix.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland

Scope {
    id: root

    readonly property bool fingerprint: ShellData.fingerprint
    readonly property int maxFingerprintRetries: 5
    readonly property string user: Quickshell.env("USER") ?? ""
    property bool failed: false
    property int fingerprintRetries: 0
    property double fingerStarted: 0

    function startFinger() {
        fingerStarted = Date.now();
        finger.start();
    }

    function unlockOn(result) {
        if (result === PamResult.Success)
            sessionLock.locked = false;
        return result === PamResult.Success;
    }

    IpcHandler {
        target: "lock"

        function lock(): void {
            // lock-before-sleep also calls this on a locked screen
            if (sessionLock.locked)
                return;
            sessionLock.locked = true;
            // here, not in onLockedChanged: Quickshell 0.3.1 signals only the unlock
            if (!sessionLock.locked)
                return;
            root.failed = false;
            root.fingerprintRetries = 0;
            password.start();
            if (root.fingerprint)
                root.startFinger();
        }
    }

    PamContext {
        id: password

        config: "quickshell-lock"
        onCompleted: result => {
            // an abort after the unlock must not start a new conversation
            if (sessionLock.locked && !root.unlockOn(result)) {
                root.failed = true;
                // not at once: a PAM error that returns immediately would spin
                restartPassword.start();
            }
        }
    }

    Timer {
        id: restartPassword

        interval: 1000
        onTriggered: if (sessionLock.locked)
            password.start()
    }

    PamContext {
        id: finger

        config: "quickshell-lock-fingerprint"
        onCompleted: result => {
            // A reader that is missing or has no prints ends at once, so those
            // retries are limited. A timeout (30 s) is not one: the screen may
            // stay locked for hours.
            if (Date.now() - root.fingerStarted > 5000)
                root.fingerprintRetries = 0;
            if (!root.unlockOn(result) && root.fingerprintRetries++ < root.maxFingerprintRetries)
                retry.start();
        }
    }

    Timer {
        id: retry

        interval: 1500
        onTriggered: if (sessionLock.locked)
            root.startFinger()
    }

    WlSessionLock {
        id: sessionLock

        onLockedChanged: if (!locked) {
            retry.stop();
            restartPassword.stop();
            password.abort();
            finger.abort();
        }

        WlSessionLockSurface {
            AuthView {
                anchors.fill: parent
                // the copy of the current one (modules/desktop/wallpaper.nix)
                wallpaper: "file://" + ShellData.wallpaper.saved + "/" + root.user
                fallback: ShellData.wallpaper.default ? "file://" + ShellData.wallpaper.default : ""
                users: [root.user]
                user: root.user
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
