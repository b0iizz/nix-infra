// Launcher: `quickshell ipc call launcher toggle` opens it, typing filters,
// Up/Down select, Enter runs, Escape or a click next to it closes.
//
// It offers every desktop entry on the system (XDG_DATA_DIRS), so programs
// need not register anything, plus `desktop.launcher.entries` for what has no
// .desktop file (the power actions, for one). Entries that want a terminal
// are started in `desktop.terminal` (Quickshell doesn't start one for them)
// and are left out when there is none.
//
// Typing a formula (`2 * (3 + 4)`, `sqrt(2) ^ 10`) adds its result on top;
// Enter copies it.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    readonly property int maxRows: 10
    property bool shown: false
    // sorted once and again only when the applications change, not per key
    readonly property var all: entries()

    // Arithmetic: + - * / % ^ (or **), parentheses, pi, e and the functions
    // below, as a number, or undefined for anything else so that the search
    // for an application is never taken for a sum. A lone number isn't one.
    function calc(text) {
        const tokens = text.toLowerCase().replace(/\*\*/g, "^").match(/(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?|[a-z]+|\S/g) ?? [];
        if (tokens.length < 2)
            return undefined;
        const fns = {
            sqrt: Math.sqrt,
            cbrt: Math.cbrt,
            sin: Math.sin,
            cos: Math.cos,
            tan: Math.tan,
            ln: Math.log,
            log: Math.log10,
            exp: Math.exp,
            abs: Math.abs,
            floor: Math.floor,
            ceil: Math.ceil,
            round: Math.round
        };
        const consts = {
            pi: Math.PI,
            e: Math.E
        };
        let i = 0;
        const fail = () => {
            throw new Error("not a formula");
        };
        const eat = t => tokens[i] === t ? (i++, true) : false;
        const expect = t => eat(t) || fail();
        const atom = () => {
            const t = tokens[i++];
            if (t === undefined)
                fail();
            if (/^[\d.]/.test(t))
                return parseFloat(t);
            if (t === "(") {
                const v = expr();
                expect(")");
                return v;
            }
            if (consts.hasOwnProperty(t))
                return consts[t];
            if (fns.hasOwnProperty(t)) {
                expect("(");
                const v = expr();
                expect(")");
                return fns[t](v);
            }
            return fail();
        };
        // the exponent binds to the right and takes a sign: 2 ^ -1, 2 ^ 3 ^ 2
        const power = () => {
            const base = atom();
            return eat("^") ? Math.pow(base, unary()) : base;
        };
        const unary = () => eat("-") ? -unary() : eat("+") ? unary() : power();
        const term = () => {
            let v = unary();
            for (; ; ) {
                if (eat("*"))
                    v *= unary();
                else if (eat("/"))
                    v /= unary();
                else if (eat("%"))
                    v %= unary();
                else
                    return v;
            }
        };
        const expr = () => {
            let v = term();
            for (; ; ) {
                if (eat("+"))
                    v += term();
                else if (eat("-"))
                    v -= term();
                else
                    return v;
            }
        };
        try {
            const v = expr();
            // toPrecision hides the float noise: 0.1 + 0.2
            return i === tokens.length && isFinite(v) ? Number(v.toPrecision(12)) : undefined;
        } catch (e) {
            return undefined;
        }
    }

    function entries() {
        const terminal = ShellData.terminal;
        const apps = DesktopEntries.applications.values.filter(e => !e.noDisplay && (terminal || !e.runInTerminal)).map(e => ({
                    name: e.name,
                    search: [e.name, e.genericName, ...e.keywords].join(" ").toLowerCase(),
                    run: () => e.runInTerminal ? Quickshell.execDetached({
                            command: [...terminal, ...e.command],
                            workingDirectory: e.workingDirectory
                        }) : e.execute()
                }));
        const extra = ShellData.launcherEntries.map(e => ({
                    name: e.name,
                    search: e.name.toLowerCase(),
                    confirm: e.confirm ?? false,
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
            // the entry that asked for a second Enter
            property string armed: ""
            readonly property var matches: {
                const q = input.text.toLowerCase();
                const found = root.all.filter(e => e.search.includes(q));
                const value = root.calc(input.text);
                const sum = value === undefined ? [] : [
                    {
                        name: "= " + value,
                        run: () => Quickshell.clipboardText = String(value)
                    }
                ];
                return sum.concat(found).slice(0, root.maxRows);
            }

            function run() {
                if (matches.length === 0)
                    return;
                const m = matches[Math.min(current, matches.length - 1)];
                if (m.confirm && armed !== m.name) {
                    armed = m.name;
                    return;
                }
                m.run();
                root.shown = false;
            }

            // the whole screen, so that a click next to the box closes it
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: root.shown = false
            }

            Rectangle {
                id: box

                anchors.centerIn: parent
                width: 480
                height: content.implicitHeight + 2 * content.anchors.margins
                color: Qt.alpha(Theme.base00, Theme.opacityPopups)

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }
            }

            Column {
                id: content

                anchors.fill: box
                anchors.margins: 8
                spacing: 4

                TextInput {
                    id: input

                    width: parent.width
                    focus: true
                    color: Theme.base05
                    font.family: Theme.fontMonospace
                    font.pointSize: Theme.sizePopups
                    onTextChanged: {
                        window.current = 0;
                        window.armed = "";
                    }
                    Keys.onEscapePressed: root.shown = false
                    Keys.onReturnPressed: window.run()
                    Keys.onDownPressed: {
                        window.current = Math.min(window.current + 1, window.matches.length - 1);
                        window.armed = "";
                    }
                    Keys.onUpPressed: {
                        window.current = Math.max(window.current - 1, 0);
                        window.armed = "";
                    }
                }

                Repeater {
                    model: window.matches

                    Text {
                        required property var modelData
                        required property int index

                        text: index === window.current && modelData.name === window.armed ? modelData.name + ": Enter again" : modelData.name
                        color: index === window.current ? Theme.base0D : Theme.base04
                        font.family: Theme.fontMonospace
                        font.pointSize: Theme.sizePopups
                    }
                }
            }
        }
    }
}
