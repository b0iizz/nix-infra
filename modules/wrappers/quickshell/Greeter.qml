// Login screen for greetd. It runs as an ordinary fullscreen window inside a
// kiosk compositor (cage), asks greetd to authenticate the chosen user and
// starts the chosen one of `GreeterData.sessions` once that worked. What it shows is the AuthView
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
    property int session: 0

    function begin(name) {
        restart.stop();
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
            window.failed = true;
            window.inputEnabled = false;
            // not at once: a PAM error that returns immediately would spin
            restart.start();
        }

        function onReadyToLaunch() {
            Greetd.launch(GreeterData.sessions[window.session].exec, ["XDG_SESSION_TYPE=wayland"]);
        }
    }

    Timer {
        id: restart

        interval: 1000
        onTriggered: window.begin(window.user)
    }

    AuthView {
        anchors.fill: parent
        wallpaper: GreeterData.wallpaper === "" ? "" : "file://" + GreeterData.wallpaper
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

    // only worth showing when there is a choice
    Row {
        visible: GreeterData.sessions.length > 1
        anchors {
            bottom: parent.bottom
            bottomMargin: 32
            horizontalCenter: parent.horizontalCenter
        }
        spacing: 16

        Repeater {
            model: GreeterData.sessions

            Text {
                required property var modelData
                required property int index

                text: modelData.name
                color: index === window.session ? Theme.base0D : Theme.base04
                font.family: Theme.fontMonospace
                font.pointSize: Theme.sizeDesktop

                MouseArea {
                    anchors.fill: parent
                    onClicked: window.session = parent.index
                }
            }
        }
    }
}
