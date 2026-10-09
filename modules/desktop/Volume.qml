// Bar item: volume of the default output. Click mutes, scrolling changes it.
import QtQuick
import Quickshell.Services.Pipewire

Text {
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink?.audio

    visible: audio !== null && audio !== undefined
    text: audio ? (audio.muted ? "vol muted" : "vol " + Math.round(audio.volume * 100) + "%") : ""
    color: audio?.muted ? Theme.base03 : Theme.base05
    font.family: Theme.fontMonospace
    font.pointSize: Theme.sizeDesktop

    // the node's volume is only readable and writable while it is tracked
    PwObjectTracker {
        objects: [sink]
    }

    MouseArea {
        anchors.fill: parent
        onClicked: audio.muted = !audio.muted
        onWheel: w => audio.volume = Math.max(0, Math.min(1, audio.volume + (w.angleDelta.y > 0 ? 0.05 : -0.05)))
    }
}
