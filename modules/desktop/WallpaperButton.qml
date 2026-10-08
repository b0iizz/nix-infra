// Bar item: opens the wallpaper picker (WallpaperPicker, registered by the
// same module). The glyph is a nerd font "picture".
import QtQuick
import Quickshell

Text {
    text: ""
    color: Theme.base0E
    font.family: Theme.fontMonospace
    font.pointSize: Theme.sizeDesktop

    MouseArea {
        anchors.fill: parent
        onClicked: Quickshell.execDetached(["quickshell", "ipc", "call", "wallpaper", "toggle"])
    }
}
