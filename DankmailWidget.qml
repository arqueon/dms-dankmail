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
    property var threads: []
    property int _reqId: 0
    property int _statusReqId: -1
    property int _threadsReqId: -1

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
        root._reqId++;
        root._threadsReqId = root._reqId;
        send(cmdSocket, {
            "id": root._threadsReqId,
            "method": "threads.list",
            "params": {
                "inbox": true,
                "limit": 20
            }
        });
    }

    // op fires a thread action from the popout; the daemon's optimistic
    // apply + our event subscription refresh the list right after.
    function op(method, threadId) {
        if (!cmdSocket.connected)
            return;
        root._reqId++;
        send(cmdSocket, {
            "id": root._reqId,
            "method": method,
            "params": {
                "ids": [threadId]
            }
        });
    }

    function uiCall(method, params) {
        if (!cmdSocket.connected)
            return;
        root._reqId++;
        send(cmdSocket, {
            "id": root._reqId,
            "method": method,
            "params": params || {}
        });
    }

    function senderOf(t) {
        const raw = (t.participants && t.participants.length > 0) ? t.participants[0] : "";
        const m = raw.match(/^\s*"?([^"<]*?)"?\s*<[^>]+>\s*$/);
        return m && m[1].trim() !== "" ? m[1].trim() : raw;
    }

    function timeOf(iso) {
        const d = new Date(iso);
        const now = new Date();
        if (d.toDateString() === now.toDateString())
            return Qt.formatTime(d, "HH:mm");
        return Qt.formatDate(d, "d MMM");
    }

    // Left click opens the popout (automatic when popoutContent is set);
    // right click syncs.
    pillRightClickAction: () => root.uiCall("system.sync", {})

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
                if (msg.id === undefined)
                    return;
                if (msg.id === root._statusReqId && msg.result) {
                    root.unread = msg.result.unread || 0;
                    root.dnd = !!msg.result.dnd;
                } else if (msg.id === root._threadsReqId) {
                    root.threads = msg.result || [];
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

    popoutWidth: 440
    popoutHeight: 520
    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "Dank Mail"
            detailsText: root.daemonConnected ? (root.unread > 0 ? root.unread + " sin leer" : "Bandeja en cero") : "daemon apagado"
            showCloseButton: true

            headerActions: Component {
                Row {
                    spacing: Theme.spacingXS

                    DankActionButton {
                        iconName: "edit_square"
                        visible: root.daemonConnected
                        onClicked: {
                            root.uiCall("ui.compose", {});
                            if (popout.closePopout)
                                popout.closePopout();
                        }
                    }

                    DankActionButton {
                        iconName: "sync"
                        visible: root.daemonConnected
                        onClicked: root.uiCall("system.sync", {})
                    }

                    DankActionButton {
                        iconName: root.dnd ? "notifications_off" : "notifications"
                        iconColor: root.dnd ? Theme.warning : Theme.surfaceText
                        visible: root.daemonConnected
                        onClicked: root.uiCall(root.dnd ? "dnd.off" : "dnd.on", {})
                    }

                    DankActionButton {
                        iconName: "open_in_new"
                        onClicked: {
                            if (root.daemonConnected)
                                Quickshell.execDetached(["dmail", "show"]);
                            else
                                Quickshell.execDetached(["systemctl", "--user", "start", "dmail"]);
                            if (popout.closePopout)
                                popout.closePopout();
                        }
                    }
                }
            }

            Item {
                width: parent.width
                // The list scrolls inside a fixed viewport when it grows
                // beyond the popout.
                readonly property real maxListHeight: 430
                implicitHeight: Math.min(threadColumn.implicitHeight + Theme.spacingM * 2, maxListHeight)

                DankFlickable {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingS
                    contentHeight: threadColumn.implicitHeight
                    clip: true

                    Column {
                        id: threadColumn
                        width: parent.width
                        spacing: 2

                    StyledText {
                        visible: !root.daemonConnected
                        width: parent.width
                        text: "El daemon de dankmail no está corriendo. Usa el botón ↗ para iniciarlo."
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                    }

                    StyledText {
                        visible: root.daemonConnected && root.threads.length === 0
                        width: parent.width
                        text: "Sin correos en la bandeja."
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    Repeater {
                        model: root.threads

                        delegate: Rectangle {
                            id: mailRow
                            required property var modelData

                            width: threadColumn.width
                            height: 56
                            radius: Theme.cornerRadiusSmall
                            color: rowHover.hovered ? Theme.surfaceContainerHigh : "transparent"

                            HoverHandler {
                                id: rowHover
                            }

                            // Row body: unread dot, sender/subject, time.
                            Row {
                                anchors.left: parent.left
                                anchors.right: rowActions.visible ? rowActions.left : parent.right
                                anchors.leftMargin: Theme.spacingS
                                anchors.rightMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingS

                                Rectangle {
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: mailRow.modelData.unread ? Theme.primary : "transparent"
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Column {
                                    width: parent.width - 8 - Theme.spacingS * 2 - timeLabel.implicitWidth
                                    spacing: 1

                                    StyledText {
                                        width: parent.width
                                        text: root.senderOf(mailRow.modelData)
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: mailRow.modelData.unread ? Font.Bold : Font.Normal
                                        color: mailRow.modelData.unread ? Theme.surfaceText : Theme.surfaceVariantText
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }

                                    StyledText {
                                        width: parent.width
                                        text: mailRow.modelData.subject || "(sin asunto)"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: mailRow.modelData.unread ? Theme.surfaceText : Theme.surfaceVariantText
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }
                                }

                                StyledText {
                                    id: timeLabel
                                    text: root.timeOf(mailRow.modelData.lastMessageAt)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            // Hover actions: the notification set, per row.
                            Row {
                                id: rowActions
                                visible: rowHover.hovered
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.spacingXS
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 0

                                DankActionButton {
                                    iconName: mailRow.modelData.unread ? "drafts" : "mark_email_unread"
                                    buttonSize: 26
                                    iconSize: 15
                                    onClicked: root.op(mailRow.modelData.unread ? "ops.markRead" : "ops.markUnread", mailRow.modelData.id)
                                }

                                DankActionButton {
                                    iconName: "archive"
                                    buttonSize: 26
                                    iconSize: 15
                                    onClicked: root.op("ops.archive", mailRow.modelData.id)
                                }

                                DankActionButton {
                                    iconName: "delete"
                                    buttonSize: 26
                                    iconSize: 15
                                    iconColor: Theme.error
                                    onClicked: root.op("ops.trash", mailRow.modelData.id)
                                }

                                DankActionButton {
                                    iconName: "snooze"
                                    buttonSize: 26
                                    iconSize: 15
                                    onClicked: root.op("ops.snoozePreset", mailRow.modelData.id)
                                }

                                DankActionButton {
                                    iconName: "open_in_new"
                                    buttonSize: 26
                                    iconSize: 15
                                    onClicked: root.uiCall("ui.openLink", {
                                        "id": mailRow.modelData.id
                                    })
                                }
                            }

                            // Click on the row body → open in the triage
                            // window (the action buttons' own MouseAreas
                            // take precedence over this handler).
                            TapHandler {
                                onTapped: {
                                    root.uiCall("ui.showThread", {
                                        "id": mailRow.modelData.id
                                    });
                                    if (popout.closePopout)
                                        popout.closePopout();
                                }
                            }
                        }
                    }
                    }
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
