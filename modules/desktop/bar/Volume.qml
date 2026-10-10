// Bar item: volume of the default output. Click mutes, scrolling changes it.
import QtQuick
import Quickshell.Services.Pipewire

Text {
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink?.audio

    visible: audio !== null && audio !== undefined
    // speaker icon with waves, or crossed out while muted, and the level
    text: !audio ? "" : audio.muted ? "" : (audio.volume < 0.5 ? " " : " ") + Math.round(audio.volume * 100) + "%"
    color: audio?.muted ? Theme.base08 : Theme.base0D
    font.family: Theme.fontMonospace
    font.pointSize: Theme.sizeDesktop

    // the node's volume is only readable and writable while it is tracked
    PwObjectTracker {
        objects: [sink]
    }

    WheelArea {
        anchors.fill: parent
        onClicked: audio.muted = !audio.muted
        onStepped: steps => audio.volume = Math.max(0, Math.min(1, audio.volume + steps * 0.05))
    }
}
