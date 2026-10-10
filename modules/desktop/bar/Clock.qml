// Bar item: date and time.
import QtQuick
import Quickshell

Text {
    text: Qt.formatDateTime(clock.date, "ddd d MMM HH:mm")
    color: Theme.base05
    font.family: Theme.fontMonospace
    font.pointSize: Theme.sizeDesktop

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }
}
