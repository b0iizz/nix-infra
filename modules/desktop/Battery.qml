// Bar item: charge of the battery, red when low and not charging. Only on
// hosts with a battery (modules/desktop/widgets.nix).
import QtQuick
import Quickshell.Services.UPower

Text {
    readonly property var battery: UPower.displayDevice
    readonly property bool charging: battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.FullyCharged
    readonly property int percent: Math.round(battery.percentage * 100)

    visible: battery.isPresent
    text: "bat " + percent + "%" + (charging ? " +" : "")
    color: !charging && percent <= 15 ? Theme.base08 : Theme.base05
    font.family: Theme.fontMonospace
    font.pointSize: Theme.sizeDesktop
}
