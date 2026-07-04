import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "dankmailUnread"

    StyledText {
        width: parent.width
        text: "Dankmail Unread"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Live unread badge for dankmail. Left click toggles the triage window (starting the daemon if needed); right click triggers a sync. Requires the dmail daemon (https://github.com/arqueon/dankmail)."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "hideWhenZero"
        label: "Hide when inbox is clear"
        description: "Collapse the pill while there is no unread mail"
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "showDndDot"
        label: "Do-not-disturb indicator"
        description: "Show a small dot on the icon while dankmail's DND is active"
        defaultValue: true
    }
}
