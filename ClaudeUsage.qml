import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "UsageUtils.js" as Utils

PluginComponent {
    id: root
    layerNamespacePlugin: "claude-usage"
    popoutWidth: 360
    popoutHeight: 520

    // === Settings ===
    property int refreshIntervalMinutes: parseInt(pluginData.refreshInterval) || 2
    property string displayMode: pluginData.displayMode || "5h"
    property bool showFiveHour: pluginData.showFiveHour !== false
    property bool showSevenDay: pluginData.showSevenDay !== false
    property bool showOpus: pluginData.showOpus !== false
    property bool showSonnet: pluginData.showSonnet !== false
    property bool showExtraUsage: pluginData.showExtraUsage !== false
    property bool showPlanInfo: pluginData.showPlanInfo !== false

    readonly property string credentialsPath: (Quickshell.env("HOME") || Qt.getenv("HOME")) + "/.claude/.credentials.json"

    // === Credentials state ===
    property string accessToken: ""
    property string refreshToken: ""
    property real expiresAt: 0
    property string subscriptionType: ""
    property string rateLimitTier: ""

    // === Usage data ===
    property bool dataAvailable: false
    property string errorMessage: ""
    property bool loading: false

    property real fiveHourUtil: 0
    property string fiveHourReset: ""
    property real sevenDayUtil: 0
    property string sevenDayReset: ""
    property real sevenDayOpusUtil: 0
    property string sevenDayOpusReset: ""
    property real sevenDaySonnetUtil: 0
    property string sevenDaySonnetReset: ""

    property bool extraUsageEnabled: false
    property real extraUsageLimit: 0
    property real extraUsageUsed: 0
    property real extraUsageUtil: 0

    // === Pill helpers ===
    readonly property real _pillPct: displayMode === "7d" ? sevenDayUtil : fiveHourUtil
    readonly property color _pillColor: dataAvailable ? Utils.utilizationColor(_pillPct, Theme) : Theme.surfaceVariantText
    readonly property string _pillReset: displayMode === "7d" ? sevenDayReset : fiveHourReset

    // === Tick timer (forces re-eval of reset time bindings) ===
    property int _tick: 0
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root._tick++
    }

    // === Error helper ===
    function setError(msg) {
        errorMessage = msg;
        dataAvailable = false;
        loading = false;
    }

    // === Credential loading ===
    Process {
        id: credLoader
        property string output: ""
        command: ["cat", root.credentialsPath]

        stdout: SplitParser {
            onRead: line => { credLoader.output += line; }
        }

        onExited: (exitCode) => {
            if (exitCode !== 0 || !output) {
                root.setError("No credentials file found\nRun 'claude' to log in");
                output = "";
                return;
            }

            try {
                var oauth = JSON.parse(output).claudeAiOauth;
                if (!oauth) {
                    root.setError("No OAuth credentials found");
                    output = "";
                    return;
                }

                root.accessToken = oauth.accessToken || "";
                root.refreshToken = oauth.refreshToken || "";
                root.expiresAt = oauth.expiresAt || 0;
                root.subscriptionType = oauth.subscriptionType || "";
                root.rateLimitTier = oauth.rateLimitTier || "";

                if (root.expiresAt > 0 && Date.now() > root.expiresAt)
                    root.refreshOAuthToken();
                else
                    root.fetchUsage();
            } catch (e) {
                root.setError("Failed to parse credentials");
            }
            output = "";
        }
    }

    // === Token refresh ===
    Process {
        id: tokenRefresher
        property string output: ""

        stdout: SplitParser {
            onRead: line => { tokenRefresher.output += line; }
        }

        onExited: (exitCode) => {
            if (exitCode !== 0 || !output) {
                root.setError("Token refresh failed\nRun 'claude' to re-login");
                output = "";
                return;
            }

            try {
                var resp = JSON.parse(output);
                if (!resp.access_token) {
                    root.setError("Token refresh failed");
                    output = "";
                    return;
                }

                root.accessToken = resp.access_token;
                root.refreshToken = resp.refresh_token || root.refreshToken;
                root.expiresAt = Date.now() + (resp.expires_in * 1000);
                root.saveCredentials();
                root.fetchUsage();
            } catch (e) {
                root.setError("Token refresh failed\nRun 'claude' to re-login");
            }
            output = "";
        }
    }

    function refreshOAuthToken() {
        if (!refreshToken) {
            setError("No refresh token available\nRun 'claude' to log in");
            return;
        }

        tokenRefresher.output = "";
        tokenRefresher.command = [
            "curl", "-sS", "--connect-timeout", "10", "--max-time", "15",
            "-X", "POST",
            "-H", "Content-Type: application/json",
            "-d", JSON.stringify({
                grant_type: "refresh_token",
                client_id: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
                refresh_token: refreshToken
            }),
            "https://console.anthropic.com/v1/oauth/token"
        ];
        tokenRefresher.running = true;
    }

    // === Save refreshed credentials ===
    Process {
        id: credSaver
        property string jsonData: ""
        command: ["tee", root.credentialsPath]
        stdinEnabled: true
        onStarted: { write(jsonData + "\n"); stdinClose(); }
    }

    function saveCredentials() {
        credSaver.jsonData = JSON.stringify({
            claudeAiOauth: {
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: expiresAt,
                scopes: ["user:inference", "user:mcp_servers", "user:profile", "user:sessions:claude_code"],
                subscriptionType: subscriptionType,
                rateLimitTier: rateLimitTier
            }
        });
        credSaver.running = true;
    }

    // === Usage API ===
    Process {
        id: usageFetcher
        property string output: ""

        stdout: SplitParser {
            onRead: line => { usageFetcher.output += line; }
        }

        onExited: (exitCode) => {
            root.loading = false;
            if (exitCode !== 0 || !output) {
                root.setError("Failed to fetch usage data");
                output = "";
                return;
            }

            try {
                var resp = JSON.parse(output);
                root.applyUsageData(resp);
            } catch (e) {
                if (output.indexOf("401") >= 0 || output.indexOf("Unauthorized") >= 0) {
                    root.refreshOAuthToken();
                } else {
                    root.setError("Failed to parse usage data");
                }
            }
            output = "";
        }
    }

    function applyUsageData(resp) {
        function extract(obj) {
            return obj ? { util: obj.utilization || 0, reset: obj.resets_at || "" }
                       : { util: 0, reset: "" };
        }

        var fh = extract(resp.five_hour);
        fiveHourUtil = fh.util;
        fiveHourReset = fh.reset;

        var sd = extract(resp.seven_day);
        sevenDayUtil = sd.util;
        sevenDayReset = sd.reset;

        var opus = extract(resp.seven_day_opus);
        sevenDayOpusUtil = opus.util;
        sevenDayOpusReset = opus.reset;

        var sonnet = extract(resp.seven_day_sonnet);
        sevenDaySonnetUtil = sonnet.util;
        sevenDaySonnetReset = sonnet.reset;

        if (resp.extra_usage) {
            extraUsageEnabled = resp.extra_usage.is_enabled || false;
            extraUsageLimit = resp.extra_usage.monthly_limit || 0;
            extraUsageUsed = resp.extra_usage.used_credits || 0;
            extraUsageUtil = resp.extra_usage.utilization || 0;
        } else {
            extraUsageEnabled = false;
        }

        dataAvailable = true;
        errorMessage = "";
    }

    function fetchUsage() {
        if (!accessToken) {
            setError("No access token");
            return;
        }

        usageFetcher.output = "";
        usageFetcher.command = [
            "curl", "-sS", "--connect-timeout", "10", "--max-time", "15",
            "-H", "Accept: application/json",
            "-H", "Content-Type: application/json",
            "-H", "Authorization: Bearer " + accessToken,
            "-H", "anthropic-beta: oauth-2025-04-20",
            "-H", "User-Agent: claude-code/2.0.32",
            "https://api.anthropic.com/api/oauth/usage"
        ];
        usageFetcher.running = true;
    }

    function loadUsage() {
        loading = true;
        credLoader.output = "";
        credLoader.running = true;
    }

    Timer {
        id: refreshTimer
        interval: root.refreshIntervalMinutes * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.loadUsage()
    }

    Component.onCompleted: root.loadUsage()

    // === Widget properties ===
    ccWidgetIcon: "smart_toy"
    ccWidgetPrimaryText: "Claude Usage"
    ccWidgetSecondaryText: {
        if (!dataAvailable) return errorMessage || "Loading...";
        return Math.round(fiveHourUtil) + "% (5h) \u2022 " + Math.round(sevenDayUtil) + "% (7d)";
    }
    ccWidgetIsActive: dataAvailable

    // === Bar pills ===
    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: "smart_toy"
                size: root.iconSize
                color: root._pillColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.dataAvailable ? Math.round(root._pillPct) + "%" : "--"
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale)
                font.weight: Font.Bold
                color: root._pillColor
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                visible: root.dataAvailable
                width: 1
                height: root.iconSize
                color: Theme.outline
                opacity: 0.3
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                visible: root.dataAvailable
                text: { root._tick; return Utils.formatResetTime(root._pillReset); }
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale)
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 2

            DankIcon {
                name: "smart_toy"
                size: root.iconSize
                color: root._pillColor
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.dataAvailable ? Math.round(root._pillPct) + "%" : "--"
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale)
                font.weight: Font.Bold
                color: root._pillColor
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // === Popout ===
    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "Claude " + Utils.planLabel(root.subscriptionType)
            detailsText: {
                if (!root.dataAvailable) return root.errorMessage || "Loading...";
                var tier = Utils.tierLabel(root.rateLimitTier);
                return tier || "Plan usage";
            }
            showCloseButton: false

            headerActions: Component {
                Row {
                    spacing: 4

                    DankActionButton {
                        iconName: "refresh"
                        iconColor: root.loading ? Theme.primary : Theme.surfaceVariantText
                        buttonSize: 28
                        tooltipText: "Refresh"
                        tooltipSide: "bottom"
                        onClicked: root.loadUsage()

                        RotationAnimation on rotation {
                            from: 0
                            to: 360
                            duration: 800
                            loops: Animation.Infinite
                            running: root.loading
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingM

                // Error state
                StyledRect {
                    visible: !root.dataAvailable
                    width: parent.width
                    height: errorCol.implicitHeight + Theme.spacingL * 2
                    radius: Theme.cornerRadius
                    color: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.1)

                    Column {
                        id: errorCol
                        anchors.centerIn: parent
                        width: parent.width - Theme.spacingL * 2
                        spacing: Theme.spacingM

                        DankIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: "cloud_off"
                            size: 40
                            color: Theme.error
                            opacity: 0.6
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.spacingXS

                            StyledText {
                                width: parent.width
                                text: "Unable to load usage"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.error
                                horizontalAlignment: Text.AlignHCenter
                            }

                            StyledText {
                                width: parent.width
                                text: root.errorMessage || "Check your credentials"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }

                // Usage cards
                UsageCard {
                    visible: root.dataAvailable && root.showFiveHour
                    iconName: "schedule"
                    title: "5-Hour Window"
                    subtitle: { root._tick; return Utils.formatResetTimeVerbose(root.fiveHourReset); }
                    utilization: root.fiveHourUtil
                }

                UsageCard {
                    visible: root.dataAvailable && root.showSevenDay
                    iconName: "date_range"
                    title: "Weekly Window"
                    subtitle: { root._tick; return Utils.formatResetDateTime(root.sevenDayReset); }
                    utilization: root.sevenDayUtil
                }

                UsageCard {
                    visible: root.dataAvailable && root.showOpus && root.sevenDayOpusUtil > 0
                    iconName: "auto_awesome"
                    title: "Weekly Opus"
                    subtitle: { root._tick; return Utils.formatResetDateTime(root.sevenDayOpusReset); }
                    utilization: root.sevenDayOpusUtil
                }

                UsageCard {
                    visible: root.dataAvailable && root.showSonnet && root.sevenDaySonnetUtil > 0
                    iconName: "bolt"
                    title: "Weekly Sonnet"
                    subtitle: { root._tick; return Utils.formatResetDateTime(root.sevenDaySonnetReset); }
                    utilization: root.sevenDaySonnetUtil
                }

                UsageCard {
                    visible: root.dataAvailable && root.showExtraUsage && root.extraUsageEnabled
                    iconName: "payments"
                    title: "Extra Usage"
                    subtitle: "$" + root.extraUsageUsed.toFixed(2) + " / $" + root.extraUsageLimit.toFixed(2)
                    utilization: root.extraUsageUtil
                }

                // Plan info
                StyledRect {
                    visible: root.dataAvailable && root.showPlanInfo
                    width: parent.width
                    height: planContent.implicitHeight + Theme.spacingL * 2
                    radius: Theme.cornerRadius
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)

                    Row {
                        id: planContent
                        anchors.fill: parent
                        anchors.margins: Theme.spacingL
                        spacing: Theme.spacingS

                        DankIcon {
                            name: "verified"
                            size: 18
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            spacing: 2
                            anchors.verticalCenter: parent.verticalCenter

                            StyledText {
                                text: "Claude " + Utils.planLabel(root.subscriptionType)
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }

                            StyledText {
                                visible: root.rateLimitTier !== ""
                                text: Utils.tierLabel(root.rateLimitTier)
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                        }
                    }
                }
            }
        }
    }

    // === Reusable components ===

    component UsageCard: StyledRect {
        property string iconName
        property string title
        property string subtitle
        property real utilization: 0

        readonly property color barColor: Utils.utilizationColor(utilization, Theme)

        width: parent.width
        height: cardCol.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: cardCol
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            Item {
                width: parent.width
                implicitHeight: titleCol.implicitHeight

                Row {
                    anchors.left: parent.left
                    anchors.right: pctText.left
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS

                    DankIcon {
                        name: iconName
                        size: 20
                        color: barColor
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: 0.8
                    }

                    Column {
                        id: titleCol
                        spacing: 2

                        StyledText {
                            text: title
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }

                        StyledText {
                            text: subtitle
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }
                }

                StyledText {
                    id: pctText
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(utilization) + "%"
                    font.pixelSize: 22
                    font.weight: Font.Bold
                    color: barColor
                }
            }

            UsageBar {
                width: parent.width
                utilization: parent.parent.utilization
            }
        }
    }

    component UsageBar: Item {
        property real utilization: 0
        readonly property color barColor: Utils.utilizationColor(utilization, Theme)
        height: 6

        StyledRect {
            anchors.fill: parent
            radius: 3
            color: Qt.rgba(barColor.r, barColor.g, barColor.b, 0.15)

            StyledRect {
                width: parent.width * Math.min(utilization, 100) / 100
                height: parent.height
                radius: 3
                color: barColor

                Behavior on width {
                    NumberAnimation {
                        duration: 400
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }
}
