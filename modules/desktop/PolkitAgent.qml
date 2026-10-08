// Polkit agent: shows a dialog whenever a program asks for authorization. The
// form is the one of the lock and login screen (AuthForm). Polkit's own helper
// talks to PAM.
import QtQuick
import Quickshell
import Quickshell.Services.Polkit
import Quickshell.Wayland

Scope {
    id: root

    readonly property bool fingerprint: ShellData.fingerprint

    function names(identities) {
        const out = [];
        for (let i = 0; i < identities.length; i++)
            out.push(identities[i].displayName);
        return out;
    }

    PolkitAgent {
        id: agent
    }

    LazyLoader {
        active: agent.isActive

        PanelWindow {
            readonly property var flow: agent.flow

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            implicitWidth: 460
            implicitHeight: column.implicitHeight + 48
            color: Qt.alpha(Theme.base00, Theme.opacityPopups)

            Column {
                id: column

                anchors.centerIn: parent
                spacing: 24

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 400
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: flow?.message ?? ""
                    color: Theme.base0D
                    font.family: Theme.fontMonospace
                    font.pointSize: Theme.sizePopups
                }

                AuthForm {
                    anchors.horizontalCenter: parent.horizontalCenter
                    users: flow ? root.names(flow.identities) : []
                    user: flow?.selectedIdentity?.displayName ?? ""
                    inputEnabled: flow?.isResponseRequired ?? false
                    echo: flow?.responseVisible ?? false
                    message: {
                        if (!flow)
                            return "";
                        return (flow.failed && !flow.supplementaryIsError ? "Authentication failed. " : "") + (flow.supplementaryMessage || flow.inputPrompt);
                    }
                    isError: flow ? flow.failed || flow.supplementaryIsError : false
                    hint: root.fingerprint ? "Password, or press Enter and use the fingerprint reader" : ""
                    onSubmitted: text => flow.submit(text)
                    onCancelled: flow.cancelAuthenticationRequest()
                    onUserChosen: name => {
                        for (let i = 0; i < flow.identities.length; i++) {
                            if (flow.identities[i].displayName === name)
                                flow.selectedIdentity = flow.identities[i];
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Escape to cancel"
                    color: Theme.base03
                    font.family: Theme.fontMonospace
                    font.pointSize: Theme.sizePopups

                    MouseArea {
                        anchors.fill: parent
                        onClicked: flow.cancelAuthenticationRequest()
                    }
                }
            }
        }
    }
}
