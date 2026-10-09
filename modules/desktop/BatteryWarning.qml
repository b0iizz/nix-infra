// Low battery warnings: a notification at `low` percent, an urgent one at
// `critical`, each once until the battery charges again
// (`desktop.batteryWarning.*`, modules/desktop/battery.nix).
import QtQuick
import Quickshell
import Quickshell.Services.UPower

Scope {
    id: root

    readonly property var cfg: ShellData.batteryWarning
    readonly property var battery: UPower.displayDevice
    readonly property int percent: Math.round(battery.percentage * 100)
    readonly property bool draining: battery.isPresent && UPower.onBattery
    // 0: fine, 1: low, 2: critical; what was warned about already
    property int warned: 0

    function check() {
        const level = !draining ? 0 : percent <= cfg.critical ? 2 : percent <= cfg.low ? 1 : 0;
        if (level > warned)
            Quickshell.execDetached(["notify-send", "-a", "Battery", "-u", level === 2 ? "critical" : "normal", level === 2 ? "Battery critical" : "Battery low", percent + "% left"]);
        // only charging resets it: a reading that wobbles around the limit warns once
        warned = draining ? Math.max(warned, level) : 0;
    }

    onPercentChanged: check()
    onDrainingChanged: check()
    Component.onCompleted: check()
}
