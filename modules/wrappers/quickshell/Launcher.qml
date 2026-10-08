// Launcher: `quickshell ipc call launcher toggle` opens it, typing filters,
// Up/Down select, Enter runs, Escape closes.
//
// It offers every desktop entry on the system (XDG_DATA_DIRS), so programs
// need not register anything, plus `desktop.launcher.entries` for what has no
// .desktop file (the power actions, for one). Entries that want a terminal
// are left out: Quickshell doesn't start one for them.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    readonly property int maxRows: 10
    property bool shown: false

    function entries() {
        const apps = DesktopEntries.applications.values.filter(e => !e.noDisplay && !e.runInTerminal).map(e => ({
                    name: e.name,
                    search: [e.name, e.genericName, ...e.keywords].join(" ").toLowerCase(),
                    run: () => e.execute()
                }));
        const extra = ShellData.launcherEntries.map(e => ({
                    name: e.name,
                    search: e.name.toLowerCase(),
                    run: () => Quickshell.execDetached(e.exec)
                }));
        return extra.concat(apps).sort((a, b) => a.name.localeCompare(b.name));
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            root.shown = !root.shown;
        }
    }

    LazyLoader {
        active: root.shown

        PanelWindow {
            id: window

            property int current: 0
            readonly property var matches: {
                const q = input.text.toLowerCase();
                return root.entries().filter(e => e.search.includes(q)).slice(0, root.maxRows);
            }

            function run() {
                if (matches.length === 0)
                    return;
                matches[Math.min(current, matches.length - 1)].run();
                root.shown = false;
            }

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            implicitWidth: 480
            implicitHeight: 48 + 28 * matches.length
            color: Qt.alpha(Theme.base00, Theme.opacityPopups)

            Column {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                TextInput {
                    id: input

                    width: parent.width
                    focus: true
                    color: Theme.base05
                    font.family: Theme.fontMonospace
                    font.pointSize: Theme.sizePopups
                    onTextChanged: window.current = 0
                    Keys.onEscapePressed: root.shown = false
                    Keys.onReturnPressed: window.run()
                    Keys.onDownPressed: window.current = Math.min(window.current + 1, window.matches.length - 1)
                    Keys.onUpPressed: window.current = Math.max(window.current - 1, 0)
                }

                Repeater {
                    model: window.matches

                    Text {
                        required property var modelData
                        required property int index

                        text: modelData.name
                        color: index === window.current ? Theme.base0D : Theme.base04
                        font.family: Theme.fontMonospace
                        font.pointSize: Theme.sizePopups
                    }
                }
            }
        }
    }
}
