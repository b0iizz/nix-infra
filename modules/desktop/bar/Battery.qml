// Bar item: battery icon and charge, green while charging, yellow below 30%
// and red below 15%. Only on hosts with a battery (modules/desktop/widgets.nix).
import QtQuick
import Quickshell.Services.UPower

Text {
    readonly property var battery: UPower.displayDevice
    readonly property bool charging: battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.FullyCharged
    readonly property int percent: Math.round(battery.percentage * 100)

    visible: battery.isPresent
    // a battery that empties with the charge (full, 3/4, half, 1/4, empty), a bolt while charging
    readonly property string icon: ["", "", "", "", ""][Math.min(4, Math.floor(percent / 20))]

    text: icon + " " + percent + "%" + (charging ? " " : "")
    color: charging ? Theme.base0B : percent <= 15 ? Theme.base08 : percent <= 30 ? Theme.base0A : Theme.base05
    font.family: Theme.fontMonospace
    font.pointSize: Theme.sizeDesktop
}
