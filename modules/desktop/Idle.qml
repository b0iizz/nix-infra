// Idle daemon: dim, lock and suspend after the configured seconds without
// input (`desktop.idle.*`, modules/desktop/idle.nix). Each step is its own
// monitor on the compositor's idle notifications, which also honour the
// programs that inhibit idling.
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import Quickshell.Wayland

Scope {
    readonly property var cfg: ShellData.idle

    IdleMonitor {
        enabled: cfg.dim !== null
        timeout: cfg.dim ?? 0
        // ponytail: dims to 10% even when the screen is darker already
        onIsIdleChanged: Quickshell.execDetached(isIdle ? ["brightnessctl", "-c", "backlight", "-s", "set", "10%"] : ["brightnessctl", "-c", "backlight", "-r"])
    }

    IdleMonitor {
        enabled: cfg.lock !== null && cfg.lockCommand !== null
        timeout: cfg.lock ?? 0
        onIsIdleChanged: if (isIdle)
            Quickshell.execDetached(cfg.lockCommand)
    }

    IdleMonitor {
        // on AC the machine stays up: it is a desk, a build or a download
        enabled: cfg.suspend !== null && cfg.suspendCommand !== null && UPower.onBattery
        timeout: cfg.suspend ?? 0
        onIsIdleChanged: if (isIdle)
            Quickshell.execDetached(cfg.suspendCommand)
    }
}
