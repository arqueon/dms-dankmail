import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

// Unread badge for dankmail (https://github.com/arqueon/dankmail).
// Live updates: subscribes to the dmail daemon's IPC socket (line-JSON
// protocol) instead of polling. Left click toggles the triage window
// (the daemon relaunches the UI if it was closed); right click syncs.
// If the daemon is down, the icon dims and a click starts the service.
PluginComponent {
    id: root

    property bool hideWhenZero: pluginData.hideWhenZero ?? false
    property bool showDndDot: pluginData.showDndDot ?? true

    property bool daemonConnected: false
    property int unread: 0
    property bool dnd: false
    property int _reqId: 0
    property int _statusReqId: -1

    readonly property string socketPath: {
        const rt = Quickshell.env("XDG_RUNTIME_DIR");
        return (rt && rt !== "" ? rt : "/tmp") + "/dankmail.sock";
    }

    readonly property bool pillHidden: hideWhenZero && daemonConnected && unread === 0

    function send(sock, obj) {
        sock.write(JSON.stringify(obj) + "\n");
        sock.flush();
    }

    function refreshStatus() {
        if (!cmdSocket.connected)
            return;
        root._reqId++;
        root._statusReqId = root._reqId;
        send(cmdSocket, {
            "id": root._statusReqId,
            "method": "system.status",
            "params": {}
        });
    }

    pillClickAction: () => {
        if (root.daemonConnected)
            Quickshell.execDetached(["dmail", "toggle"]);
        else
            Quickshell.execDetached(["systemctl", "--user", "start", "dmail"]);
    }

    pillRightClickAction: () => {
        if (!cmdSocket.connected)
            return;
        root._reqId++;
        root.send(cmdSocket, {
            "id": root._reqId,
            "method": "system.sync",
            "params": {}
        });
    }

    Component.onCompleted: cmdSocket.connected = true

    // Command connection: handshake line first, then request/response.
    Socket {
        id: cmdSocket

        path: root.socketPath
        connected: false

        onConnectionStateChanged: {
            root.daemonConnected = connected;
            if (connected) {
                subSocket.connected = true;
                root.refreshStatus();
            } else {
                subSocket.connected = false;
                root.unread = 0;
                retryTimer.restart();
            }
        }

        parser: SplitParser {
            onRead: line => {
                if (!line || line.length === 0)
                    return;
                let msg;
                try {
                    msg = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (msg.id !== undefined && msg.id === root._statusReqId && msg.result) {
                    root.unread = msg.result.unread || 0;
                    root.dnd = !!msg.result.dnd;
                }
            }
        }
    }

    // Subscription connection: daemon events push refreshes.
    Socket {
        id: subSocket

        path: root.socketPath
        connected: false

        onConnectionStateChanged: {
            if (connected)
                root.send(subSocket, {
                    "id": 1,
                    "method": "subscribe"
                });
        }

        parser: SplitParser {
            onRead: line => {
                if (!line || line.length === 0)
                    return;
                let ev;
                try {
                    ev = JSON.parse(line);
                } catch (e) {
                    return;
                }
                switch (ev.topic) {
                case "threads.changed":
                case "unread.changed":
                case "ops.applied":
                case "accounts.changed":
                case "snooze.woke":
                    refreshDebounce.restart();
                    break;
                case "dnd.changed":
                    root.dnd = !!(ev.payload && ev.payload.enabled);
                    break;
                }
            }
        }
    }

    Timer {
        id: retryTimer
        interval: 4000
        repeat: false
        onTriggered: {
            if (!cmdSocket.connected)
                cmdSocket.connected = true;
        }
    }

    Timer {
        id: refreshDebounce
        interval: 300
        repeat: false
        onTriggered: root.refreshStatus()
    }

    // Safety poll: cheap, and covers any missed event.
    Timer {
        interval: 60000
        running: root.daemonConnected
        repeat: true
        onTriggered: root.refreshStatus()
    }

    horizontalBarPill: Component {
        Item {
            implicitWidth: root.pillHidden ? 0 : hRow.implicitWidth
            implicitHeight: hRow.implicitHeight
            visible: !root.pillHidden

            Row {
                id: hRow
                spacing: Theme.spacingXS

                Item {
                    width: root.iconSize
                    height: root.iconSize
                    anchors.verticalCenter: parent.verticalCenter

                    DankIcon {
                        anchors.fill: parent
                        name: root.dnd ? "notifications_off" : "mail"
                        size: root.iconSize
                        color: {
                            if (!root.daemonConnected)
                                return Theme.surfaceVariantText;
                            return root.unread > 0 ? Theme.primary : Theme.surfaceText;
                        }
                    }

                    Rectangle {
                        visible: root.showDndDot && root.dnd && root.daemonConnected
                        width: 7
                        height: 7
                        radius: 3.5
                        color: Theme.warning
                        anchors.right: parent.right
                        anchors.top: parent.top
                    }
                }

                StyledText {
                    visible: root.daemonConnected && root.unread > 0
                    text: root.unread > 99 ? "99+" : String(root.unread)
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Bold
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: vCol.implicitWidth
            implicitHeight: root.pillHidden ? 0 : vCol.implicitHeight
            visible: !root.pillHidden

            Column {
                id: vCol
                spacing: 2

                DankIcon {
                    name: root.dnd ? "notifications_off" : "mail"
                    size: root.iconSize
                    color: {
                        if (!root.daemonConnected)
                            return Theme.surfaceVariantText;
                        return root.unread > 0 ? Theme.primary : Theme.surfaceText;
                    }
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    visible: root.daemonConnected && root.unread > 0
                    text: root.unread > 99 ? "99+" : String(root.unread)
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Bold
                    color: Theme.primary
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }
}
