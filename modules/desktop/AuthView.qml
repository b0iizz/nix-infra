// The full screen of the lock screen and the login screen: background, clock
// and the AuthForm. Both use exactly this, nothing about them differs but the
// data they put in.
import QtQuick
import Quickshell

Rectangle {
    id: view

    property alias users: form.users
    property alias user: form.user
    property alias message: form.message
    property alias isError: form.isError
    property alias hint: form.hint
    property alias inputEnabled: form.inputEnabled
    property alias echo: form.echo
    // image behind everything, empty for none
    property url wallpaper

    signal submitted(string text)
    signal userChosen(string name)

    color: Theme.base00

    Image {
        anchors.fill: parent
        source: view.wallpaper
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize: Qt.size(view.width, view.height)
    }

    // keeps the clock and the form readable on any image
    Rectangle {
        anchors.fill: parent
        color: Theme.base00
        opacity: view.wallpaper.toString() === "" ? 0 : 0.45
    }

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    Column {
        anchors.centerIn: parent
        spacing: 32

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, "HH:mm")
            color: Theme.base05
            font.family: Theme.fontMonospace
            font.pointSize: Theme.sizeDesktop * 4
        }

        AuthForm {
            id: form

            anchors.horizontalCenter: parent.horizontalCenter
            onSubmitted: text => view.submitted(text)
            onUserChosen: name => view.userChosen(name)
        }
    }
}
