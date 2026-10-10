// The external drives and what can be done to them, for the Drives bar item and
// DrivesMenu (roles/removable-media.nix). `drives` lists the filesystems on
// hotplug disks, from lsblk; it is read again when udisks reports a change.
// Mounting and ejecting go through udisksctl, which polkit allows for the
// user at the seat.
import QtQuick
import Quickshell.Io

Item {
    id: root

    // { path, name, size, mountpoint ("" when not mounted), disk, mounted }
    property var drives: []
    readonly property int mountedCount: drives.filter(d => d.mounted).length
    // what the last action said when it failed
    property string error: ""

    function collect(node, disk, out) {
        const hotplug = node.hotplug === true || node.hotplug === "1";
        const top = disk ?? (hotplug ? node : null);
        if (!top)
            return;
        if (node.fstype && node.fstype !== "swap" && node.fstype !== "crypto_LUKS") {
            const mountpoint = (node.mountpoints ?? []).find(m => m) ?? "";
            out.push({
                path: node.path,
                name: node.label || (top.model ?? "").trim() || node.path,
                size: node.size,
                mountpoint: mountpoint,
                disk: top.path,
                mounted: mountpoint !== ""
            });
        }
        for (const child of node.children ?? [])
            collect(child, top, out);
    }

    function refresh() {
        list.running = true;
    }

    function toggle(drive) {
        error = "";
        act.command = ["udisksctl", drive.mounted ? "unmount" : "mount", "-b", drive.path];
        act.running = true;
    }

    // unmount everything on the disk of `drive`, then power it off
    function eject(drive) {
        error = "";
        const mounted = drives.filter(d => d.disk === drive.disk && d.mounted).map(d => d.path);
        act.command = ["sh", "-c", 'disk=$1; shift; for p in "$@"; do udisksctl unmount -b "$p" || exit; done; udisksctl power-off -b "$disk"', "sh", drive.disk].concat(mounted);
        act.running = true;
    }

    Component.onCompleted: refresh()

    Process {
        id: list

        command: ["lsblk", "--json", "--output", "PATH,LABEL,SIZE,FSTYPE,MOUNTPOINTS,HOTPLUG,MODEL"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                try {
                    for (const node of JSON.parse(text).blockdevices)
                        root.collect(node, null, out);
                } catch (e) {
                    return;
                }
                root.drives = out;
            }
        }
    }

    Process {
        id: act

        stderr: StdioCollector {
            id: problem
        }
        onExited: code => {
            if (code !== 0)
                root.error = problem.text.trim() || "Failed";
            root.refresh();
        }
    }

    // udisks talks about every change, mounting included; wait for it to settle
    Process {
        running: true
        command: ["udisksctl", "monitor"]
        stdout: SplitParser {
            onRead: settle.restart()
        }
    }

    Timer {
        id: settle

        interval: 500
        onTriggered: root.refresh()
    }
}
