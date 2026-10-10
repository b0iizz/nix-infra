// A line of a status menu (Menu): text that can be clicked and wraps.
import QtQuick

Text {
    signal clicked

    // highlighted: the connected network, the open adapter, ...
    property bool active: false

    width: parent.width
    height: implicitHeight + 8
    verticalAlignment: Text.AlignVCenter
    wrapMode: Text.Wrap
    color: active ? Theme.base0D : Theme.base05
    font.family: Theme.fontMonospace
    font.pointSize: Theme.sizePopups

    MouseArea {
        anchors.fill: parent
        onClicked: parent.clicked()
    }
}
