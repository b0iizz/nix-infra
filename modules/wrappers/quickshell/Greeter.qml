// Login screen for greetd. It runs as an ordinary fullscreen window inside a
// kiosk compositor (cage), asks greetd to authenticate the chosen user and
// starts `GreeterData.session` once that worked.
import QtQuick
import Quickshell
import Quickshell.Services.Greetd

FloatingWindow {
    id: window

    property string user: GreeterData.users[0] ?? ""
    property string message: ""
    property bool isError: false
    property bool failed: false

    function begin(name) {
        user = name;
        message = "";
        isError = false;
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
            password.echoMode = echoResponse ? TextInput.Normal : TextInput.Password;
            password.enabled = responseRequired;
            if (responseRequired)
                password.forceActiveFocus();
        }

        function onAuthFailure(text) {
            window.begin(window.user);
            window.failed = true;
        }

        function onReadyToLaunch() {
            Greetd.launch(GreeterData.session, ["XDG_SESSION_TYPE=wayland"]);
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 16

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 16

            Repeater {
                model: GreeterData.users

                Text {
                    required property string modelData

                    text: modelData
                    color: modelData === window.user ? Theme.base0D : Theme.base04
                    font.family: Theme.fontMonospace
                    font.pointSize: Theme.sizeDesktop

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            window.failed = false;
                            window.begin(parent.modelData);
                        }
                    }
                }
            }
        }

        TextInput {
            id: password

            anchors.horizontalCenter: parent.horizontalCenter
            width: 280
            horizontalAlignment: TextInput.AlignHCenter
            echoMode: TextInput.Password
            enabled: false
            focus: true
            color: Theme.base05
            font.family: Theme.fontMonospace
            font.pointSize: Theme.sizeDesktop
            onAccepted: {
                window.failed = false;
                Greetd.respond(text);
                text = "";
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: (window.failed ? "Login failed. " : "") + window.message
            color: window.isError || window.failed ? Theme.base08 : Theme.base04
            font.family: Theme.fontMonospace
            font.pointSize: Theme.sizePopups
        }
    }
}
