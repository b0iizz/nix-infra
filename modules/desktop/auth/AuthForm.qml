// The form of every place that asks for a password: user names, the password
// field, a status line and a hint. The lock screen and the login screen show
// it in AuthView, polkit prompts put it in a dialog, so they all look alike.
// It only displays state and reports input, the caller talks to PAM.
import QtQuick
import Quickshell

Column {
    id: form

    property var users: []
    property string user: ""
    property string message: ""
    property bool isError: false
    property string hint: ""
    // the field takes input; it is emptied and focused whenever this turns on
    property bool inputEnabled: false
    property bool echo: false

    signal submitted(string text)
    signal userChosen(string name)
    signal cancelled

    spacing: 16
    onInputEnabledChanged: {
        field.text = "";
        if (inputEnabled)
            field.forceActiveFocus();
    }
    Component.onCompleted: field.forceActiveFocus()

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 16

        Repeater {
            model: form.users

            Text {
                required property string modelData

                text: modelData
                color: modelData === form.user ? Theme.base0D : Theme.base04
                font.family: Theme.fontMonospace
                font.pointSize: Theme.sizeDesktop

                MouseArea {
                    anchors.fill: parent
                    onClicked: form.userChosen(parent.modelData)
                }
            }
        }
    }

    TextInput {
        id: field

        anchors.horizontalCenter: parent.horizontalCenter
        width: 280
        horizontalAlignment: TextInput.AlignHCenter
        echoMode: form.echo ? TextInput.Normal : TextInput.Password
        enabled: form.inputEnabled
        color: Theme.base05
        font.family: Theme.fontMonospace
        font.pointSize: Theme.sizeDesktop
        // an empty answer is valid: it moves on to the fingerprint reader
        onAccepted: {
            form.submitted(text);
            text = "";
        }
        Keys.onEscapePressed: form.cancelled()

        Rectangle {
            anchors.top: parent.bottom
            width: parent.width
            height: 1
            color: Theme.base03
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: form.message
        color: form.isError ? Theme.base08 : Theme.base05
        font.family: Theme.fontMonospace
        font.pointSize: Theme.sizePopups
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: form.hint
        color: Theme.base03
        font.family: Theme.fontMonospace
        font.pointSize: Theme.sizePopups
    }
}
