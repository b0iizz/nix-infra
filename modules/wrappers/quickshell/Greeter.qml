// Login screen for greetd. It runs as an ordinary fullscreen window inside a
// kiosk compositor (cage), asks greetd to authenticate the chosen user and
// starts `GreeterData.session` once that worked. What it shows is the AuthView
// of the lock screen.
//
// With a fingerprint reader greetd's PAM stack asks for the password first and
// the reader second (modules/wrappers/quickshell/greeter.nix): an empty answer
// moves on to the reader.
import QtQuick
import Quickshell
import Quickshell.Services.Greetd

FloatingWindow {
    id: window

    property string user: GreeterData.users[0] ?? ""
    property string message: ""
    property bool isError: false
    property bool failed: false
    property bool inputEnabled: false
    property bool echo: false

    function begin(name) {
        user = name;
        message = "";
        isError = false;
        inputEnabled = false;
        Greetd.cancelSession();
        Greetd.createSession(name);
    }

    visible: true
    color: Theme.base00
    Component.onCompleted: begin(user)

    Connections {
        target: Greetd

        function onAuthMessage(text, error, responseRequired, echoResponse) {
            window.message = text;
            window.isError = error;
            window.echo = echoResponse;
            window.inputEnabled = responseRequired;
        }

        function onAuthFailure(text) {
            window.begin(window.user);
            window.failed = true;
        }

        function onReadyToLaunch() {
            Greetd.launch(GreeterData.session, ["XDG_SESSION_TYPE=wayland"]);
        }
    }

    AuthView {
        anchors.fill: parent
        users: GreeterData.users
        user: window.user
        message: (window.failed ? "Login failed. " : "") + window.message
        isError: window.isError || window.failed
        echo: window.echo
        inputEnabled: window.inputEnabled
        hint: GreeterData.fingerprint ? "Password, or press Enter and use the fingerprint reader" : ""
        onSubmitted: text => {
            window.failed = false;
            Greetd.respond(text);
        }
        onUserChosen: name => {
            window.failed = false;
            window.begin(name);
        }
    }
}
