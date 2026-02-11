import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "claudeUsage"

    StyledText {
        width: parent.width
        text: "Claude Usage"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Monitor your Claude Pro/Max plan usage limits"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledRect {
        width: parent.width
        height: displayColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: displayColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Display"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            SelectionSetting {
                settingKey: "displayMode"
                label: "Bar Display"
                description: "Which usage window to show in the bar pill"
                options: [
                    {label: "5-Hour Window", value: "5h"},
                    {label: "Weekly Window", value: "7d"}
                ]
                defaultValue: "5h"
            }
        }
    }

    StyledRect {
        width: parent.width
        height: sectionsColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: sectionsColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Popout Sections"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            ToggleSetting {
                settingKey: "showFiveHour"
                label: "5-Hour Window"
                description: "Show the rolling 5-hour rate limit window"
                defaultValue: true
            }

            ToggleSetting {
                settingKey: "showSevenDay"
                label: "Weekly Window"
                description: "Show the 7-day usage window"
                defaultValue: true
            }

            ToggleSetting {
                settingKey: "showOpus"
                label: "Weekly Opus"
                description: "Show the Opus-specific weekly limit (when available)"
                defaultValue: true
            }

            ToggleSetting {
                settingKey: "showSonnet"
                label: "Weekly Sonnet"
                description: "Show the Sonnet-specific weekly limit (when available)"
                defaultValue: true
            }

            ToggleSetting {
                settingKey: "showExtraUsage"
                label: "Extra Usage"
                description: "Show the extra usage spending section"
                defaultValue: true
            }

            ToggleSetting {
                settingKey: "showPlanInfo"
                label: "Plan Info"
                description: "Show the plan type and tier card"
                defaultValue: true
            }
        }
    }

    StyledRect {
        width: parent.width
        height: refreshColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: refreshColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Refresh"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            StringSetting {
                settingKey: "refreshInterval"
                label: "Refresh Interval (minutes)"
                description: "How often to poll the usage API"
                placeholder: "2"
                defaultValue: "2"
            }
        }
    }

    StyledRect {
        width: parent.width
        height: infoColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surface

        Column {
            id: infoColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            Row {
                spacing: Theme.spacingM

                DankIcon {
                    name: "info"
                    size: Theme.iconSize
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: "About"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StyledText {
                text: "This widget fetches your real-time Claude plan usage from the Anthropic API using your Claude Code OAuth credentials (~/.claude/.credentials.json).\n\nUsage windows shown:\n\u2022 5-Hour — rolling rate limit window\n\u2022 Weekly — 7-day usage window\n\u2022 Weekly Opus — Opus-specific limit (if applicable)\n\nThe icon and percentage are color-coded:\n\u2022 Green: < 50% used\n\u2022 Yellow: 50-80% used\n\u2022 Red: > 80% used\n\nToken refresh is handled automatically."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                width: parent.width
                lineHeight: 1.4
            }
        }
    }
}
